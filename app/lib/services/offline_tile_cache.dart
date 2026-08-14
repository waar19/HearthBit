import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostics_log.dart';

const osmTileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const osmAttribution = '© OpenStreetMap contributors';
const osmAttributionUrl = 'https://www.openstreetmap.org/copyright';
const osmTilePolicyUrl = 'https://operations.osmfoundation.org/policies/tiles/';
const hearthBitMapUserAgent =
    'HearthBit/1.0 (+https://github.com/waar19/HearthBit; '
    'contact: https://github.com/waar19/HearthBit/issues)';
const hearthBitApplicationId = 'com.hearthbit.app';
const _minimumFallbackCacheTtl = Duration(days: 7);

@immutable
class MapTileSource {
  const MapTileSource._({
    required this.urlTemplate,
    required this.attribution,
    required this.attributionUrl,
    required this.bulkDownloadConfigured,
  });

  factory MapTileSource.configured({
    required String urlTemplate,
    required String attribution,
    required String attributionUrl,
    required bool allowsBulkDownload,
  }) {
    final templateUri = _parseTemplate(urlTemplate);
    final attributionUri = Uri.tryParse(attributionUrl);
    if (templateUri == null ||
        attributionUri == null ||
        (attributionUri.scheme != 'https' && attributionUri.scheme != 'http') ||
        !attributionUri.hasAuthority) {
      return MapTileSource.openStreetMap;
    }
    if (templateUri.host.toLowerCase() == 'tile.openstreetmap.org') {
      return MapTileSource.openStreetMap;
    }
    return MapTileSource._(
      urlTemplate: urlTemplate,
      attribution: attribution.trim().isEmpty ? templateUri.host : attribution,
      attributionUrl: attributionUrl,
      bulkDownloadConfigured: allowsBulkDownload,
    );
  }

  factory MapTileSource.fromEnvironment() {
    const urlTemplate = String.fromEnvironment(
      'MAP_TILE_URL_TEMPLATE',
      defaultValue: osmTileUrlTemplate,
    );
    const attribution = String.fromEnvironment(
      'MAP_TILE_ATTRIBUTION',
      defaultValue: osmAttribution,
    );
    const attributionUrl = String.fromEnvironment(
      'MAP_TILE_ATTRIBUTION_URL',
      defaultValue: osmAttributionUrl,
    );
    const allowsBulkDownload = bool.fromEnvironment(
      'MAP_TILE_ALLOWS_BULK_DOWNLOAD',
    );
    return MapTileSource.configured(
      urlTemplate: urlTemplate,
      attribution: attribution,
      attributionUrl: attributionUrl,
      allowsBulkDownload: allowsBulkDownload,
    );
  }

  static const openStreetMap = MapTileSource._(
    urlTemplate: osmTileUrlTemplate,
    attribution: osmAttribution,
    attributionUrl: osmAttributionUrl,
    bulkDownloadConfigured: false,
  );

  final String urlTemplate;
  final String attribution;
  final String attributionUrl;
  final bool bulkDownloadConfigured;

  Uri get _templateUri => _parseTemplate(urlTemplate)!;

  bool get isPublicOpenStreetMap =>
      _templateUri.host.toLowerCase() == 'tile.openstreetmap.org';

  bool get allowsBulkDownload =>
      bulkDownloadConfigured && !isPublicOpenStreetMap;

  Uri get attributionUri => Uri.parse(attributionUrl);

  String get cacheDirectoryName {
    if (isPublicOpenStreetMap) return 'osm-policy-v2';
    return _templateUri.host.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9.-]'),
      '_',
    );
  }

  Uri tileUri(OfflineTileCoordinate tile) => Uri.parse(
    urlTemplate
        .replaceAll('{z}', '${tile.zoom}')
        .replaceAll('{x}', '${tile.x}')
        .replaceAll('{y}', '${tile.y}'),
  );

  static Uri? _parseTemplate(String value) {
    if (!value.contains('{z}') ||
        !value.contains('{x}') ||
        !value.contains('{y}')) {
      return null;
    }
    final parsed = Uri.tryParse(
      value
          .replaceAll('{z}', '0')
          .replaceAll('{x}', '0')
          .replaceAll('{y}', '0'),
    );
    if (parsed == null ||
        (parsed.scheme != 'https' && parsed.scheme != 'http') ||
        !parsed.hasAuthority) {
      return null;
    }
    return parsed;
  }
}

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

class TileBulkDownloadNotAllowedException implements Exception {
  const TileBulkDownloadNotAllowedException(this.host);

  final String host;

  @override
  String toString() => 'Bulk tile download is not allowed for $host';
}

class TileAccessBlockedException implements Exception {
  const TileAccessBlockedException(this.statusCode, this.host);

  final int statusCode;
  final String host;

  @override
  String toString() => 'Tile access blocked by $host ($statusCode)';
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

class OfflineTileCacheStats {
  const OfflineTileCacheStats({required this.tileCount, required this.bytes});

  final int tileCount;
  final int bytes;
}

class OfflineTileCache {
  OfflineTileCache._({
    required this._root,
    required this._client,
    required this._ownsClient,
    required this.source,
    required this._now,
  });

  static const int maximumTileBytes = 1024 * 1024;
  static const int maximumCacheBytes = 250 * 1024 * 1024;

  final Directory _root;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final MapTileSource source;
  final Map<OfflineTileCoordinate, Future<Uint8List>> _loads = {};
  DateTime? _lastPassiveTrimAt;
  int _writesSinceTrim = 0;
  bool _trimming = false;

  static Future<OfflineTileCache> create({
    http.Client? client,
    MapTileSource? source,
  }) async {
    final effectiveSource = source ?? MapTileSource.fromEnvironment();
    final support = await getApplicationSupportDirectory();
    final mapRoot = Directory(p.join(support.path, 'map_tiles'));
    if (effectiveSource.isPublicOpenStreetMap) {
      final legacyRoot = Directory(p.join(mapRoot.path, 'osm'));
      if (await legacyRoot.exists()) {
        // Versiones anteriores podían persistir el PNG de bloqueo 403 como si
        // fuera un mapa válido. No se reutiliza esa caché no verificable.
        try {
          await legacyRoot.delete(recursive: true);
        } on FileSystemException {
          // La nueva generación usa otro directorio incluso si el SO mantiene
          // temporalmente un archivo antiguo abierto.
        }
      }
    }
    final root = Directory(
      p.join(mapRoot.path, effectiveSource.cacheDirectoryName),
    );
    await root.create(recursive: true);
    return OfflineTileCache._(
      root: root,
      client: client ?? http.Client(),
      ownsClient: client == null,
      source: effectiveSource,
      now: DateTime.now,
    );
  }

  @visibleForTesting
  static OfflineTileCache forTesting({
    required Directory root,
    required http.Client client,
    MapTileSource source = MapTileSource.openStreetMap,
    DateTime Function()? now,
  }) => OfflineTileCache._(
    root: root,
    client: client,
    ownsClient: false,
    source: source,
    now: now ?? DateTime.now,
  );

  File fileFor(OfflineTileCoordinate tile) =>
      File(p.join(_root.path, '${tile.zoom}', '${tile.x}', '${tile.y}.png'));

  File _metadataFileFor(OfflineTileCoordinate tile) =>
      File('${fileFor(tile).path}.json');

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
    final metadataFile = _metadataFileFor(tile);
    Uint8List? staleBytes;
    _TileCacheMetadata? metadata;
    if (await file.exists()) {
      try {
        final cached = await file.readAsBytes();
        if (_looksLikePng(cached)) {
          staleBytes = cached;
          metadata = await _readMetadata(metadataFile);
          final expiresAt =
              metadata?.expiresAt ??
              (await file.stat()).modified.add(_minimumFallbackCacheTtl);
          if (_now().isBefore(expiresAt)) return cached;
        } else {
          await file.delete();
          if (await metadataFile.exists()) await metadataFile.delete();
        }
      } on FileSystemException {
        // Continue with the network path when a stale cache entry is unreadable.
      }
    }
    final uri = source.tileUri(tile);
    final headers = <String, String>{
      HttpHeaders.userAgentHeader: hearthBitMapUserAgent,
      'X-Requested-With': hearthBitApplicationId,
      HttpHeaders.acceptHeader: 'image/png,image/*;q=0.8',
      HttpHeaders.ifNoneMatchHeader: ?metadata?.eTag,
      HttpHeaders.ifModifiedSinceHeader: ?metadata?.lastModified,
    };
    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      final decision = _cacheDecision(response.headers, _now());
      if (response.statusCode == HttpStatus.notModified && staleBytes != null) {
        if (!decision.store) {
          if (await file.exists()) await file.delete();
          if (await metadataFile.exists()) await metadataFile.delete();
          return staleBytes;
        }
        await _writeMetadata(
          metadataFile,
          _TileCacheMetadata(
            expiresAt: decision.expiresAt,
            eTag: response.headers[HttpHeaders.etagHeader] ?? metadata?.eTag,
            lastModified:
                response.headers[HttpHeaders.lastModifiedHeader] ??
                metadata?.lastModified,
          ),
        );
        await file.setLastModified(_now());
        return staleBytes;
      }
      if (response.statusCode == HttpStatus.forbidden ||
          response.statusCode == HttpStatus.tooManyRequests) {
        throw TileAccessBlockedException(response.statusCode, uri.host);
      }
      final bytes = response.bodyBytes;
      if (response.statusCode != HttpStatus.ok ||
          bytes.length > maximumTileBytes ||
          !_looksLikePng(bytes)) {
        throw HttpException(
          'Invalid tile response (${response.statusCode})',
          uri: uri,
        );
      }
      if (!decision.store) {
        if (await file.exists()) await file.delete();
        if (await metadataFile.exists()) await metadataFile.delete();
        return bytes;
      }
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      await _writeMetadata(
        metadataFile,
        _TileCacheMetadata(
          expiresAt: decision.expiresAt,
          eTag: response.headers[HttpHeaders.etagHeader],
          lastModified: response.headers[HttpHeaders.lastModifiedHeader],
        ),
      );
      _schedulePassiveTrim();
      return bytes;
    } catch (_) {
      if (staleBytes != null) return staleBytes;
      rethrow;
    }
  }

  Future<void> download(
    Iterable<OfflineTileCoordinate> tiles, {
    TileDownloadProgress? onProgress,
  }) async {
    if (!source.allowsBulkDownload) {
      throw TileBulkDownloadNotAllowedException(
        source.tileUri(const OfflineTileCoordinate(0, 0, 0)).host,
      );
    }
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
    try {
      await for (final entity in _root.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.png')) continue;
        final stat = await entity.stat();
        total += stat.size;
        files.add((file: entity, length: stat.size, modified: stat.modified));
      }
    } on FileSystemException {
      // El borrado de pánico (o un tearDown de test) puede eliminar el
      // directorio mientras el trim pasivo aún lista archivos; en ese caso ya
      // no queda nada que recortar.
      return;
    }
    if (total <= maximumCacheBytes) return;
    files.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in files) {
      try {
        await entry.file.delete();
        final metadata = File('${entry.file.path}.json');
        if (await metadata.exists()) await metadata.delete();
      } on FileSystemException {
        // Si otro proceso borró la entrada primero, el espacio ya quedó libre.
      }
      total -= entry.length;
      if (total <= maximumCacheBytes) break;
    }
  }

  Future<OfflineTileCacheStats> stats() async {
    if (!await _root.exists()) {
      return const OfflineTileCacheStats(tileCount: 0, bytes: 0);
    }
    var count = 0;
    var bytes = 0;
    await for (final entity in _root.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      final stat = await entity.stat();
      count += 1;
      bytes += stat.size;
    }
    return OfflineTileCacheStats(tileCount: count, bytes: bytes);
  }

  void _schedulePassiveTrim() {
    _writesSinceTrim += 1;
    final now = _now();
    final dueByTime =
        _lastPassiveTrimAt == null ||
        now.difference(_lastPassiveTrimAt!) >= const Duration(minutes: 5);
    if (_trimming || (_writesSinceTrim < 50 && !dueByTime)) return;
    _trimming = true;
    _writesSinceTrim = 0;
    _lastPassiveTrimAt = now;
    unawaited(
      trim().whenComplete(() {
        _trimming = false;
      }),
    );
  }

  Future<void> close() async {
    await trim();
    final current = await stats();
    DiagnosticsLog.instance.info(
      'map.cache.stats',
      data: {'tileCount': current.tileCount, 'bytes': current.bytes},
    );
    dispose();
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<_TileCacheMetadata?> _readMetadata(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return _TileCacheMetadata.fromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeMetadata(File file, _TileCacheMetadata metadata) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(metadata.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static _CacheDecision _cacheDecision(
    Map<String, String> headers,
    DateTime now,
  ) {
    final cacheControl = headers[HttpHeaders.cacheControlHeader]?.toLowerCase();
    if (cacheControl != null) {
      final directives = cacheControl
          .split(',')
          .map((value) => value.trim())
          .toList(growable: false);
      if (directives.contains('no-store')) {
        return _CacheDecision(store: false, expiresAt: now);
      }
      if (directives.contains('no-cache')) {
        return _CacheDecision(store: true, expiresAt: now);
      }
      for (final directive in directives) {
        final match = RegExp(r'^max-age=(\d+)$').firstMatch(directive);
        final seconds = int.tryParse(match?.group(1) ?? '');
        if (seconds != null) {
          return _CacheDecision(
            store: true,
            expiresAt: now.add(Duration(seconds: seconds)),
          );
        }
      }
    }
    final expires = headers[HttpHeaders.expiresHeader];
    if (expires != null) {
      try {
        return _CacheDecision(store: true, expiresAt: HttpDate.parse(expires));
      } on HttpException {
        // Use the policy-safe fallback below for an invalid Expires value.
      }
    }
    return _CacheDecision(
      store: true,
      expiresAt: now.add(_minimumFallbackCacheTtl),
    );
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

class _TileCacheMetadata {
  const _TileCacheMetadata({
    required this.expiresAt,
    this.eTag,
    this.lastModified,
  });

  factory _TileCacheMetadata.fromJson(Map<String, dynamic> json) {
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (expiresAt == null) throw const FormatException('Invalid expiration');
    return _TileCacheMetadata(
      expiresAt: expiresAt,
      eTag: json['eTag'] as String?,
      lastModified: json['lastModified'] as String?,
    );
  }

  final DateTime expiresAt;
  final String? eTag;
  final String? lastModified;

  Map<String, Object?> toJson() => {
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'eTag': eTag,
    'lastModified': lastModified,
  };
}

class _CacheDecision {
  const _CacheDecision({required this.store, required this.expiresAt});

  final bool store;
  final DateTime expiresAt;
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
