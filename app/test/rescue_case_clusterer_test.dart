import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/models/rescue_case_models.dart';
import 'package:hearth_bit/services/rescue_case_clusterer.dart';

void main() {
  test('agrupa de forma determinista según el zoom', () {
    final cases = [
      _case('b' * 64, 4.7000, -74.1000),
      _case('a' * 64, 4.7010, -74.1010),
    ];

    final distant = RescueCaseClusterer.cluster(cases, zoom: 8);
    final close = RescueCaseClusterer.cluster(cases, zoom: 18);

    expect(distant, hasLength(1));
    expect(distant.single.cases.map((item) => item.caseHash), [
      'a' * 64,
      'b' * 64,
    ]);
    expect(close, hasLength(2));
  });

  test('el clúster conserva la prioridad máxima', () {
    final cases = [
      _case('a' * 64, 4.7000, -74.1000),
      _case(
        'b' * 64,
        4.7001,
        -74.1001,
        triage: const SosTriage(
          peopleCount: 2,
          injuryStatus: SosInjuryStatus.injured,
          injuredCount: 1,
          trappedStatus: SosTrappedStatus.yes,
          primaryNeed: SosPrimaryNeed.medical,
        ),
      ),
    ];

    final cluster = RescueCaseClusterer.cluster(cases, zoom: 12).single;
    expect(cluster.maximumPriority, RescuePriority.critical);
  });

  test('agrupa puntos cercanos a ambos lados de una celda', () {
    final clusters = RescueCaseClusterer.cluster([
      _case('a' * 64, 0, -0.0000001),
      _case('b' * 64, 0, 0.0000001),
    ], zoom: 18);

    expect(clusters, hasLength(1));
    expect(clusters.single.cases, hasLength(2));
  });

  test('agrupa sobre el antimeridiano con centro circular', () {
    final cluster = RescueCaseClusterer.cluster([
      _case('a' * 64, 0, 179.99999),
      _case('b' * 64, 0, -179.99999),
    ], zoom: 18).single;

    expect(cluster.cases, hasLength(2));
    expect(cluster.longitude.abs(), closeTo(180, 0.00001));
  });

  test('no agrupa puntos más lejanos que el radio', () {
    final clusters = RescueCaseClusterer.cluster([
      _case('a' * 64, 0, 0),
      _case('b' * 64, 0, 0.0002),
    ], zoom: 18);

    expect(clusters, hasLength(2));
  });

  test('produce el mismo resultado con entrada invertida', () {
    final cases = [
      _case('c' * 64, 0, 0.0002),
      _case('b' * 64, 0, 0.0000001),
      _case('a' * 64, 0, -0.0000001),
    ];
    final forward = RescueCaseClusterer.cluster(cases, zoom: 18);
    final reverse = RescueCaseClusterer.cluster(cases.reversed, zoom: 18);

    expect(
      reverse.map((cluster) => cluster.id),
      forward.map((cluster) => cluster.id),
    );
    expect(
      reverse.map(
        (cluster) => cluster.cases.map((rescueCase) => rescueCase.caseHash),
      ),
      forward.map(
        (cluster) => cluster.cases.map((rescueCase) => rescueCase.caseHash),
      ),
    );
    expect(
      reverse.map((cluster) => (cluster.latitude, cluster.longitude)),
      forward.map((cluster) => (cluster.latitude, cluster.longitude)),
    );
  });

  test('agrupa 2000 casos concentrados sin comparar cada pareja', () {
    final cases = List.generate(
      2000,
      (index) => _case(index.toRadixString(16).padLeft(64, '0'), 4.7, -74.1),
    );

    final clusters = RescueCaseClusterer.cluster(cases, zoom: 18);

    expect(clusters, hasLength(1));
    expect(clusters.single.cases, hasLength(2000));
  });
}

RescueCase _case(
  String hash,
  double latitude,
  double longitude, {
  SosTriage? triage,
}) => RescueCase(
  teamId: '0' * 32,
  caseHash: hash,
  victimPeerId: '0011223344556677',
  victim: 'Persona',
  message: 'Ayuda',
  triage: triage,
  latitude: latitude,
  longitude: longitude,
  state: RescueCaseState.newCase,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  lastActorPeerId: '0011223344556677',
);
