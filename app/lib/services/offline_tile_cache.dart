import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const osmTileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const hearthBitMapUserAgent =
    'HearthBit/1.0 (emergency offline map; https://github.com/waar19/HearthBit)';

@immutable
class OfflineTileCoordinate {
  const OfflineTileCoordinate(this.x, this.y, this.zoom);

  final int x;
  final int y;
  final int zoom;

  @override
  bool operator ==(Object other) =>
      other is OfflineTileCoordinate &&
      x == other.x &&
      y == other.y &&
      zoom == other.zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);
}

@immutable
class GeographicBounds {
  const GeographicBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}

class TileDownloadLimitException implements Exception {
  const TileDownloadLimitException(this.requested, this.maximum);

  final int requested;
  final int maximum;

  @override
  String toString() => 'Tile download requires $requested tiles; max $maximum';
}

class TileDownloadPlanner {
  const TileDownloadPlanner({
    this.minimumZoom = 3,
    this.maximumZoom = 17,
    this.maximumTiles = 200,
  });

  final int minimumZoom;
  final int maximumZoom;
  final int maximumTiles;

  List<OfflineTileCoordinate> plan({
    required GeographicBounds bounds,
    required int fromZoom,
    required int toZoom,
  }) {
    if (!_validBounds(bounds) ||
        fromZoom < minimumZoom ||
        toZoom > maximumZoom ||
        fromZoom > toZoom) {
      throw ArgumentError('Invalid map bounds or zoom range');
    }
    final tiles = <OfflineTileCoordinate>[];
    for (var zoom = fromZoom; zoom <= toZoom; zoom++) {
      final northY = _latitudeToTileY(bounds.north, zoom);
      final southY = _latitudeToTileY(bounds.south, zoom);
      final westX = _longitudeToTileX(bounds.west, zoom);
      final eastX = _longitudeToTileX(bounds.east, zoom);
      final xRanges = bounds.west <= bounds.east
          ? [(westX, eastX)]
          : [(westX, (1 << zoom) - 1), (0, eastX)];
      for (final (startX, endX) in xRanges) {
        for (var x = startX; x <= endX; x++) {
          for (var y = northY; y <= southY; y++) {
            tiles.add(OfflineTileCoordinate(x, y, zoom));
            if (tiles.length > maximumTiles) {
              throw TileDownloadLimitException(tiles.length, maximumTiles);
            }
          }
        }
      }
    }
    return List.unmodifiable(tiles);
  }

  bool _validBounds(GeographicBounds bounds) =>
      bounds.south.isFinite &&
      bounds.west.isFinite &&
      bounds.north.isFinite &&
      bounds.east.isFinite &&
      bounds.south >= -85.05112878 &&
      bounds.north <= 85.05112878 &&
      bounds.south <= bounds.north &&
      bounds.west >= -180 &&
      bounds.west <= 180 &&
      bounds.east >= -180 &&
      bounds.east <= 180;

  int _longitudeToTileX(double longitude, int zoom) {
    final count = 1 << zoom;
    return (((longitude + 180) / 360) * count).floor().clamp(0, count - 1);
  }

  int _latitudeToTileY(double latitude, int zoom) {
    final count = 1 << zoom;
    final radians = latitude * math.pi / 180;
    final tangent = math.tan(radians);
    final inverseHyperbolicSine = math.log(
      tangent + math.sqrt(tangent * tangent + 1),
    );
    final projected = (1 - inverseHyperbolicSine / math.pi) / 2 * count;
    return projected.floor().clamp(0, count - 1);
  }
}

typedef TileDownloadProgress = void Function(int completed, int total);

class OfflineTileCache {
  OfflineTileCache._({
    required this._root,
    required this._client,
    required this._ownsClient,
  });

  static const int maximumTileBytes = 1024 * 1024;
  static const int maximumCacheBytes = 250 * 1024 * 1024;

  final Directory _root;
  final http.Client _client;
  final bool _ownsClient;
  final Map<OfflineTileCoordinate, Future<Uint8List>> _loads = {};

  static Future<OfflineTileCache> create({http.Client? client}) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'map_tiles', 'osm'));
    await root.create(recursive: true);
    return OfflineTileCache._(
      root: root,
      client: client ?? http.Client(),
      ownsClient: client == null,
    );
  }

  @visibleForTesting
  static OfflineTileCache forTesting({
    required Directory root,
    required http.Client client,
  }) => OfflineTileCache._(root: root, client: client, ownsClient: false);

  File fileFor(OfflineTileCoordinate tile) =>
      File(p.join(_root.path, '${tile.zoom}', '${tile.x}', '${tile.y}.png'));

  Future<Uint8List> load(OfflineTileCoordinate tile) {
    final active = _loads[tile];
    if (active != null) return active;
    late final Future<Uint8List> tracked;
    tracked = _load(tile).whenComplete(() {
      if (identical(_loads[tile], tracked)) _loads.remove(tile);
    });
    _loads[tile] = tracked;
    return tracked;
  }

  Future<Uint8List> _load(OfflineTileCoordinate tile) async {
    final file = fileFor(tile);
    if (await file.exists()) {
      try {
        final cached = await file.readAsBytes();
        if (_looksLikePng(cached)) return cached;
        await file.delete();
      } on FileSystemException {
        // Continue with the network path when a stale cache entry is unreadable.
      }
    }
    final uri = Uri.https(
      'tile.openstreetmap.org',
      '/${tile.zoom}/${tile.x}/${tile.y}.png',
    );
    final response = await _client
        .get(
          uri,
          headers: const {
            HttpHeaders.userAgentHeader: hearthBitMapUserAgent,
            HttpHeaders.acceptHeader: 'image/png',
          },
        )
        .timeout(const Duration(seconds: 12));
    final bytes = response.bodyBytes;
    if (response.statusCode != HttpStatus.ok ||
        bytes.length > maximumTileBytes ||
        !_looksLikePng(bytes)) {
      throw HttpException(
        'Invalid tile response (${response.statusCode})',
        uri: uri,
      );
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    return bytes;
  }

  Future<void> download(
    Iterable<OfflineTileCoordinate> tiles, {
    TileDownloadProgress? onProgress,
  }) async {
    final requested = tiles.toList(growable: false);
    var completed = 0;
    for (final tile in requested) {
      await load(tile);
      completed += 1;
      onProgress?.call(completed, requested.length);
      if (completed < requested.length) {
        await Future<void>.delayed(const Duration(milliseconds: 75));
      }
    }
    await trim();
  }

  Future<void> trim() async {
    if (!await _root.exists()) return;
    final files = <({File file, int length, DateTime modified})>[];
    var total = 0;
    await for (final entity in _root.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      final stat = await entity.stat();
      total += stat.size;
      files.add((file: entity, length: stat.size, modified: stat.modified));
    }
    if (total <= maximumCacheBytes) return;
    files.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in files) {
      await entry.file.delete();
      total -= entry.length;
      if (total <= maximumCacheBytes) break;
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static bool _looksLikePng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;
}

class OfflineTileProvider extends TileProvider {
  OfflineTileProvider(this.cache);

  final OfflineTileCache cache;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return OfflineTileImageProvider(
      cache: cache,
      tile: OfflineTileCoordinate(coordinates.x, coordinates.y, coordinates.z),
    );
  }
}

@immutable
class OfflineTileImageProvider extends ImageProvider<OfflineTileImageProvider> {
  const OfflineTileImageProvider({required this.cache, required this.tile});

  final OfflineTileCache cache;
  final OfflineTileCoordinate tile;

  @override
  Future<OfflineTileImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    OfflineTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1,
      debugLabel: '${tile.zoom}/${tile.x}/${tile.y}',
    );
  }

  Future<ui.Codec> _load(
    OfflineTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await key.cache.load(key.tile);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is OfflineTileImageProvider &&
      identical(cache, other.cache) &&
      tile == other.tile;

  @override
  int get hashCode => Object.hash(identityHashCode(cache), tile);
}
