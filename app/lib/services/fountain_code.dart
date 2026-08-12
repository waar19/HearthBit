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

class FountainEncoder {
  FountainEncoder({
    required Uint8List data,
    required this.chunkSize,
    required this.seed,
  }) : chunkCount = data.isEmpty
           ? 0
           : (data.length + chunkSize - 1) ~/ chunkSize {
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
  FountainDecoder({
    required this.chunkCount,
    required this.chunkSize,
    required this.seed,
  }) : _soliton = RobustSoliton(chunkCount),
       _chunks = List<Uint8List?>.filled(chunkCount, null);

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
    if (isComplete || payload.length != chunkSize) return false;
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
    _pending.add(_PendingSymbol(remaining, reduced));
    return true;
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
