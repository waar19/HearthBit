import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Códigos fountain LT (Luby Transform) con distribución robust soliton.
///
/// El emisor genera símbolos "rateless": puede producir tantos como haga
/// falta y el receptor reconstruye el archivo con cualquier subconjunto
/// suficiente, sin canal de retorno. Es la base del modo óptico por QR.
///
/// Emisor y receptor derivan el mismo conjunto de vecinos de cada símbolo a
/// partir de (seed, symbolIndex), por lo que solo viajan índice y payload.
class Xorshift32 {
  Xorshift32(int seed)
    : _state = (seed & 0xffffffff) == 0 ? 0x9e3779b9 : seed & 0xffffffff;

  int _state;

  int next() {
    var x = _state;
    x = (x ^ (x << 13)) & 0xffffffff;
    x ^= x >>> 17;
    x = (x ^ (x << 5)) & 0xffffffff;
    _state = x;
    return x;
  }

  double nextDouble() => next() / 4294967296;

  int nextInt(int max) => max <= 1 ? 0 : next() % max;
}

/// Distribución robust soliton: casi todos los símbolos tienen grado bajo
/// (rápidos de "pelar") con una espiga que garantiza cubrir todos los chunks.
class RobustSoliton {
  RobustSoliton(this.chunkCount, {double c = 0.03, double delta = 0.5}) {
    final k = chunkCount;
    if (k <= 1) {
      _cdf = const [1.0];
      return;
    }
    final r = c * math.log(k / delta) * math.sqrt(k.toDouble());
    final spike = math.max(1, math.min(k, (k / r).round()));
    final weights = List<double>.filled(k, 0);
    for (var degree = 1; degree <= k; degree++) {
      final rho = degree == 1 ? 1 / k : 1 / (degree * (degree - 1));
      double tau;
      if (degree < spike) {
        tau = r / (degree * k);
      } else if (degree == spike) {
        tau = r * math.log(r / delta) / k;
      } else {
        tau = 0;
      }
      weights[degree - 1] = rho + math.max(0, tau);
    }
    final total = weights.fold<double>(0, (sum, w) => sum + w);
    var cumulative = 0.0;
    _cdf = List<double>.generate(k, (i) {
      cumulative += weights[i] / total;
      return cumulative;
    });
  }

  final int chunkCount;
  late final List<double> _cdf;

  int sample(Xorshift32 rng) {
    final value = rng.nextDouble();
    var low = 0;
    var high = _cdf.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_cdf[mid] < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low + 1;
  }
}

/// Vecinos (índices de chunk) de un símbolo, idénticos en ambos extremos.
List<int> symbolNeighbors({
  required int seed,
  required int symbolIndex,
  required int chunkCount,
  required RobustSoliton soliton,
}) {
  final rng = Xorshift32((seed ^ (symbolIndex * 0x9e3779b1)) & 0xffffffff);
  final degree = math.min(soliton.sample(rng), chunkCount);
  final neighbors = <int>{};
  while (neighbors.length < degree) {
    neighbors.add(rng.nextInt(chunkCount));
  }
  return neighbors.toList();
}

void _xorInto(Uint8List target, Uint8List source) {
  for (var i = 0; i < target.length; i++) {
    target[i] ^= source[i];
  }
}

int _validatedEncoderChunkCount(Uint8List data, int chunkSize) {
  if (data.isEmpty) throw ArgumentError.value(data.length, 'data');
  if (chunkSize <= 0 || chunkSize > 4096) {
    throw ArgumentError.value(chunkSize, 'chunkSize');
  }
  final count = (data.length + chunkSize - 1) ~/ chunkSize;
  if (count > 262144) throw ArgumentError.value(count, 'chunkCount');
  return count;
}

class FountainEncoder {
  FountainEncoder({
    required Uint8List data,
    required this.chunkSize,
    required this.seed,
  }) : chunkCount = _validatedEncoderChunkCount(data, chunkSize) {
    _soliton = RobustSoliton(chunkCount);
    _chunks = List.generate(chunkCount, (index) {
      final chunk = Uint8List(chunkSize);
      final start = index * chunkSize;
      final end = math.min(start + chunkSize, data.length);
      chunk.setRange(0, end - start, data, start);
      return chunk;
    });
  }

  final int chunkSize;
  final int seed;
  final int chunkCount;
  late final RobustSoliton _soliton;
  late final List<Uint8List> _chunks;

  Uint8List encodeSymbol(int symbolIndex) {
    final payload = Uint8List(chunkSize);
    for (final neighbor in neighborsOf(symbolIndex)) {
      _xorInto(payload, _chunks[neighbor]);
    }
    return payload;
  }

  /// Precalcula un lote fuera del isolate UI. El grafo transferido contiene
  /// únicamente enteros, listas Dart y TypedData.
  Future<List<Uint8List>> encodeSymbolsInIsolate({
    required int startIndex,
    required int count,
  }) {
    if (startIndex < 0 || count <= 0 || count > 64) {
      throw ArgumentError('Invalid fountain symbol batch');
    }
    return Isolate.run(
      () => List<Uint8List>.generate(
        count,
        (offset) => encodeSymbol(startIndex + offset),
        growable: false,
      ),
    );
  }

  List<int> neighborsOf(int symbolIndex) => symbolNeighbors(
    seed: seed,
    symbolIndex: symbolIndex,
    chunkCount: chunkCount,
    soliton: _soliton,
  );
}

class _PendingSymbol {
  _PendingSymbol(this.neighbors, this.payload);

  final Set<int> neighbors;
  final Uint8List payload;
}

class FountainDecoder {
  static const int maximumTrackedSymbols = 65536;
  static const int maximumPendingSymbols = 8192;

  FountainDecoder({
    required this.chunkCount,
    required this.chunkSize,
    required this.seed,
  }) : _soliton = RobustSoliton(_validateChunkCount(chunkCount)),
       _chunks = List<Uint8List?>.filled(
         _validateChunkCount(chunkCount),
         null,
       ) {
    if (chunkSize <= 0 || chunkSize > 4096) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
  }

  static int _validateChunkCount(int value) {
    if (value <= 0 || value > 262144) {
      throw ArgumentError.value(value, 'chunkCount');
    }
    return value;
  }

  final int chunkCount;
  final int chunkSize;
  final int seed;
  final RobustSoliton _soliton;
  final List<Uint8List?> _chunks;
  final List<_PendingSymbol> _pending = [];
  final Set<int> _seenSymbols = {};

  int _decodedCount = 0;
  int symbolsReceived = 0;

  int get decodedCount => _decodedCount;

  bool get isComplete => _decodedCount == chunkCount;

  /// Procesa un símbolo; devuelve true si aportó información nueva.
  bool addSymbol(int symbolIndex, Uint8List payload) {
    if (isComplete ||
        symbolIndex < 0 ||
        symbolIndex > 0x7fffffff ||
        payload.length != chunkSize ||
        _seenSymbols.length >= maximumTrackedSymbols) {
      return false;
    }
    if (!_seenSymbols.add(symbolIndex)) return false;
    symbolsReceived += 1;

    final reduced = Uint8List.fromList(payload);
    final remaining = <int>{};
    for (final neighbor in symbolNeighbors(
      seed: seed,
      symbolIndex: symbolIndex,
      chunkCount: chunkCount,
      soliton: _soliton,
    )) {
      final known = _chunks[neighbor];
      if (known != null) {
        _xorInto(reduced, known);
      } else {
        remaining.add(neighbor);
      }
    }
    if (remaining.isEmpty) return false;
    if (remaining.length == 1) {
      _resolve(remaining.first, reduced);
      return true;
    }
    if (_pending.length >= maximumPendingSymbols) return false;
    _pending.add(_PendingSymbol(remaining, reduced));
    return true;
  }

  /// Aplica un lote en un isolate y devuelve la copia ya mutada del decoder.
  static Future<FountainDecoder> addSymbolsInIsolate(
    FountainDecoder decoder,
    List<(int, Uint8List)> symbols,
  ) {
    if (symbols.length > 256) {
      throw ArgumentError.value(symbols.length, 'symbols');
    }
    return Isolate.run(() {
      for (final (index, payload) in symbols) {
        decoder.addSymbol(index, payload);
        if (decoder.isComplete) break;
      }
      return decoder;
    });
  }

  /// Peeling: resolver un chunk puede degradar símbolos pendientes a grado 1
  /// y desencadenar nuevas resoluciones en cascada.
  void _resolve(int chunkIndex, Uint8List value) {
    final queue = <(int, Uint8List)>[(chunkIndex, value)];
    while (queue.isNotEmpty) {
      final (index, chunk) = queue.removeLast();
      if (_chunks[index] != null) continue;
      _chunks[index] = chunk;
      _decodedCount += 1;
      final stillPending = <_PendingSymbol>[];
      for (final symbol in _pending) {
        if (symbol.neighbors.remove(index)) {
          _xorInto(symbol.payload, chunk);
        }
        if (symbol.neighbors.length == 1) {
          queue.add((symbol.neighbors.single, symbol.payload));
        } else if (symbol.neighbors.isNotEmpty) {
          stillPending.add(symbol);
        }
      }
      _pending
        ..clear()
        ..addAll(stillPending);
    }
  }

  Uint8List assemble(int fileSize) {
    if (!isComplete) {
      throw StateError('${chunkCount - _decodedCount} chunks missing');
    }
    final output = Uint8List(fileSize);
    for (var i = 0; i < chunkCount; i++) {
      final start = i * chunkSize;
      final end = math.min(start + chunkSize, fileSize);
      if (start >= fileSize) break;
      output.setRange(start, end, _chunks[i]!);
    }
    return output;
  }
}
