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
}

RescueCase _case(
  String hash,
  double latitude,
  double longitude, {
  SosTriage? triage,
}) => RescueCase(
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
