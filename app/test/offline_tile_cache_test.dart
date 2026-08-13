import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/offline_tile_cache.dart';

void main() {
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
}
