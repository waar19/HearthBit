import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/offline_tile_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const pngBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  const tile = OfflineTileCoordinate(1, 2, 3);
  const bogotaBounds = GeographicBounds(
    south: 4.58,
    west: -74.11,
    north: 4.64,
    east: -74.05,
  );

  test('planifica teselas únicas dentro del zoom solicitado', () {
    const planner = TileDownloadPlanner(maximumTiles: 200);

    final tiles = planner.plan(bounds: bogotaBounds, fromZoom: 12, toZoom: 13);

    expect(tiles, isNotEmpty);
    expect(tiles.toSet(), hasLength(tiles.length));
    expect(tiles.every((tile) => tile.zoom == 12 || tile.zoom == 13), isTrue);
    expect(tiles.every((tile) => tile.x >= 0 && tile.y >= 0), isTrue);
  });

  test('rechaza descargas que exceden el límite seguro', () {
    const planner = TileDownloadPlanner(maximumTiles: 2);

    expect(
      () => planner.plan(bounds: bogotaBounds, fromZoom: 15, toZoom: 16),
      throwsA(isA<TileDownloadLimitException>()),
    );
  });

  test('rechaza zooms fuera del rango offline permitido', () {
    const planner = TileDownloadPlanner();

    expect(
      () => planner.plan(bounds: bogotaBounds, fromZoom: 2, toZoom: 3),
      throwsArgumentError,
    );
  });

  group('política de fuentes', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'hearthbit_tiles_',
      );
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test('bloquea bulk de OSM aunque la configuración lo habilite', () async {
      final source = MapTileSource.configured(
        urlTemplate: osmTileUrlTemplate,
        attribution: 'Incorrect attribution',
        attributionUrl: 'https://example.org',
        allowsBulkDownload: true,
      );
      var requests = 0;
      final cache = OfflineTileCache.forTesting(
        root: temporaryDirectory,
        source: source,
        client: MockClient((_) async {
          requests += 1;
          return http.Response.bytes(pngBytes, HttpStatus.ok);
        }),
      );

      expect(source, same(MapTileSource.openStreetMap));
      expect(source.allowsBulkDownload, isFalse);
      expect(source.cacheDirectoryName, 'osm-policy-v2');
      await expectLater(
        cache.download(const [tile]),
        throwsA(isA<TileBulkDownloadNotAllowedException>()),
      );
      expect(requests, 0);
    });

    test('habilita bulk para una fuente personalizada autorizada', () async {
      final source = MapTileSource.configured(
        urlTemplate: 'https://maps.example.org/{z}/{x}/{y}.png',
        attribution: 'Example Maps',
        attributionUrl: 'https://maps.example.org/terms',
        allowsBulkDownload: true,
      );
      var requests = 0;
      final cache = OfflineTileCache.forTesting(
        root: temporaryDirectory,
        source: source,
        client: MockClient((request) async {
          requests += 1;
          expect(request.url.host, 'maps.example.org');
          return http.Response.bytes(pngBytes, HttpStatus.ok);
        }),
      );

      expect(source.allowsBulkDownload, isTrue);
      await cache.download(const [tile]);
      expect(requests, 1);
    });

    test(
      'identifica HearthBit sin usar el User-Agent de la librería',
      () async {
        final cache = OfflineTileCache.forTesting(
          root: temporaryDirectory,
          client: MockClient((request) async {
            expect(
              request.headers[HttpHeaders.userAgentHeader],
              hearthBitMapUserAgent,
            );
            expect(request.headers['X-Requested-With'], hearthBitApplicationId);
            expect(
              request.headers[HttpHeaders.acceptHeader],
              'image/png,image/*;q=0.8',
            );
            return http.Response.bytes(
              pngBytes,
              HttpStatus.ok,
              headers: const {HttpHeaders.cacheControlHeader: 'max-age=604800'},
            );
          }),
        );

        expect(await cache.load(tile), pngBytes);
      },
    );

    test('un PNG 403 nunca se guarda como tesela de mapa', () async {
      final cache = OfflineTileCache.forTesting(
        root: temporaryDirectory,
        client: MockClient(
          (_) async => http.Response.bytes(pngBytes, HttpStatus.forbidden),
        ),
      );

      await expectLater(
        cache.load(tile),
        throwsA(
          isA<TileAccessBlockedException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.forbidden,
          ),
        ),
      );
      expect(await cache.fileFor(tile).exists(), isFalse);
    });

    test('expone cantidad y bytes sin datos de ubicación', () async {
      final cache = OfflineTileCache.forTesting(
        root: temporaryDirectory,
        client: MockClient(
          (_) async => http.Response.bytes(
            pngBytes,
            HttpStatus.ok,
            headers: const {HttpHeaders.cacheControlHeader: 'max-age=3600'},
          ),
        ),
      );

      await cache.load(tile);
      final stats = await cache.stats();

      expect(stats.tileCount, 1);
      expect(stats.bytes, pngBytes.length);
    });
  });

  group('caducidad de caché pasiva', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'hearthbit_cache_ttl_',
      );
    });

    tearDown(() async {
      await temporaryDirectory.delete(recursive: true);
    });

    test('no solicita de nuevo una tesela antes del max-age', () async {
      var now = DateTime.utc(2026, 8, 13, 12);
      var requests = 0;
      final seenRequests = <http.Request>[];
      final cache = OfflineTileCache.forTesting(
        root: temporaryDirectory,
        now: () => now,
        client: MockClient((request) async {
          requests += 1;
          seenRequests.add(request);
          if (requests == 1) {
            return http.Response.bytes(
              pngBytes,
              HttpStatus.ok,
              headers: const {
                HttpHeaders.cacheControlHeader: 'max-age=3600',
                HttpHeaders.etagHeader: '"tile-v1"',
              },
            );
          }
          return http.Response.bytes(
            const [],
            HttpStatus.notModified,
            headers: const {HttpHeaders.cacheControlHeader: 'max-age=3600'},
          );
        }),
      );

      await cache.load(tile);
      now = now.add(const Duration(minutes: 30));
      await cache.load(tile);
      expect(requests, 1);

      now = now.add(const Duration(hours: 1));
      await cache.load(tile);
      expect(requests, 2);
      expect(
        seenRequests.last.headers[HttpHeaders.ifNoneMatchHeader],
        '"tile-v1"',
      );

      now = now.add(const Duration(minutes: 30));
      await cache.load(tile);
      expect(requests, 2);
    });

    test('usa siete días para entradas existentes sin metadata', () async {
      final now = DateTime.utc(2026, 8, 13, 12);
      var requests = 0;
      final cache = OfflineTileCache.forTesting(
        root: temporaryDirectory,
        now: () => now,
        client: MockClient((_) async {
          requests += 1;
          return http.Response.bytes(pngBytes, HttpStatus.ok);
        }),
      );
      final file = cache.fileFor(tile);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pngBytes);
      await file.setLastModified(now.subtract(const Duration(days: 6)));

      expect(await cache.load(tile), pngBytes);
      expect(requests, 0);
    });
  });
}
