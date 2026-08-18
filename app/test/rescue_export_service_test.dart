import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/models/rescue_case_models.dart';
import 'package:hearth_bit/models/swept_zone_models.dart';
import 'package:hearth_bit/services/rescue_export_service.dart';

MeshMessage _message({
  required String id,
  required String content,
  required DateTime timestamp,
  String peerId = 'peer',
  String sender = 'Persona',
  bool isPrivate = false,
  String? channel,
}) => MeshMessage(
  id: id,
  sender: sender,
  content: content,
  senderPeerId: peerId,
  isPrivate: isPrivate,
  isMine: false,
  timestamp: timestamp,
  channel: channel,
);

void main() {
  test('ordena incidentes con ubicación por distancia y luego antigüedad', () {
    final newer = DateTime.utc(2026, 8, 13, 12);
    final older = DateTime.utc(2026, 8, 13, 10);
    final incidents = RescueIncidentList.fromMessages(
      [
        _message(
          id: 'far',
          content: 'SOS|Lejos|4.700000|-74.080000',
          timestamp: newer,
          channel: 'sos',
        ),
        _message(
          id: 'near',
          content: 'SOS|Cerca|4.601000|-74.080000',
          timestamp: older,
          channel: 'sos',
        ),
        _message(
          id: 'without-location',
          content: 'SOS|Sin GPS||',
          timestamp: newer.add(const Duration(hours: 1)),
          channel: 'sos',
        ),
      ],
      originLatitude: 4.6,
      originLongitude: -74.08,
    );

    expect(incidents.map((incident) => incident.id), [
      'near',
      'far',
      'without-location',
    ]);
    expect(incidents.first.distanceMeters, lessThan(200));
  });

  test('CSV escapa texto y excluye por completo HB-LOC', () {
    final timestamp = DateTime.utc(2026, 8, 13, 12);
    final messages = [
      _message(
        id: 'checkin',
        sender: 'Ana, sector 2',
        content: EmergencyCheckIn.encode(
          status: CheckInStatus.injured,
          readableMessage: 'Herida "leve"\nconsciente',
          timestamp: timestamp,
          latitude: 4.61,
          longitude: -74.07,
        ),
        timestamp: timestamp,
        channel: 'checkin',
      ),
      _message(
        id: 'live-secret',
        content: RadarLocationUpdate.encode(
          latitude: 9.999999,
          longitude: -70,
          accuracyMeters: 1,
          timestamp: timestamp,
        ),
        timestamp: timestamp,
        isPrivate: true,
      ),
      _message(
        id: 'triage-sos',
        content: SosMessageCodec.encode(
          description: 'Rescate',
          triage: const SosTriage(
            peopleCount: 4,
            injuryStatus: SosInjuryStatus.injured,
            injuredCount: 2,
            trappedStatus: SosTrappedStatus.yes,
            primaryNeed: SosPrimaryNeed.extraction,
          ),
        ),
        timestamp: timestamp,
        channel: 'sos',
      ),
      _message(
        id: 'drill',
        content:
            'SIMULACRO - no solicita rescate\n'
            '[HB-DRILL|1|CHECKIN|HELP|1700000000000]',
        timestamp: timestamp,
        channel: 'drill',
      ),
    ];

    final csv = RescueCsv.build(RescueIncidentList.fromMessages(messages));

    expect(csv, contains('"Ana, sector 2"'));
    expect(csv, contains('"Herida ""leve""\nconsciente"'));
    expect(csv, contains('INJURED'));
    expect(
      csv,
      contains(
        'people_count,injury_status,injured_count,trapped_status,primary_need',
      ),
    );
    expect(
      csv,
      contains(
        'Rescate,2026-08-13T12:00:00.000Z,,,,4,injured,2,yes,extraction',
      ),
    );
    expect(csv, isNot(contains('9.999999')));
    expect(csv, isNot(contains(RadarLocationUpdate.marker)));
    expect(csv, isNot(contains(DrillCheckIn.marker)));
    expect(csv, isNot(contains('SIMULACRO')));
  });

  test('CSV neutraliza fórmulas y conserva números negativos internos', () {
    final now = DateTime.utc(2026, 8, 18, 12);
    final incidentCsv = RescueCsv.build([
      RescueIncident(
        id: 'formula',
        kind: RescueIncidentKind.sos,
        sender: '=HYPERLINK("https://invalid")',
        peerId: '+SUM(1,1)',
        message: '   @comando',
        timestamp: now,
        latitude: 4.61,
        longitude: -74.07,
      ),
      RescueIncident(
        id: 'controls',
        kind: RescueIncidentKind.sos,
        sender: '\tpeligro',
        peerId: 'normal',
        message: '\rpeligro',
        timestamp: now,
      ),
    ]);
    final operationalCsv = RescueOperationalCsv.build([
      _case(
        hash: _repeat('a', 64),
        latitude: 4.61,
        longitude: -74.07,
        now: now,
        victim: '-1+1',
        message: 'Mensaje normal',
      ),
    ], teamId: _repeat('2', 32));

    expect(incidentCsv, contains("'=HYPERLINK"));
    expect(incidentCsv, contains("'+SUM"));
    expect(incidentCsv, contains("'   @comando"));
    expect(incidentCsv, contains("'\tpeligro"));
    expect(incidentCsv, contains("'\rpeligro"));
    expect(incidentCsv, contains('normal'));
    expect(incidentCsv, contains('-74.070000'));
    expect(incidentCsv, isNot(contains("'-74.070000")));
    expect(operationalCsv, contains("'-1+1"));
    expect(operationalCsv, contains('Mensaje normal'));
    expect(operationalCsv, contains('-74.070000'));
    expect(operationalCsv, isNot(contains("'-74.070000")));
  });

  test('GeoJSON RFC 7946 es determinista y limpia geometrías inválidas', () {
    final now = DateTime.utc(2026, 8, 18, 12);
    final first = _case(
      hash: _repeat('a', 64),
      latitude: 4.61,
      longitude: -74.07,
      now: now,
    );
    final second = _case(
      hash: _repeat('b', 64),
      latitude: double.nan,
      longitude: 200,
      now: now,
    );
    final otherTeamCase = _case(
      hash: _repeat('c', 64),
      latitude: 1,
      longitude: 1,
      now: now,
      teamId: _repeat('9', 32),
    );
    final validZone = SweptZone(
      version: 1,
      zoneId: _repeat('1', 32),
      teamId: _repeat('2', 32),
      actorPeerId: _repeat('3', 16),
      callsign: 'Cóndor',
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 2)),
      points: [
        SweptZonePoint(latitude: 4.6, longitude: -74.1, recordedAt: now),
        SweptZonePoint(
          latitude: double.infinity,
          longitude: -74.09,
          recordedAt: now.add(const Duration(minutes: 1)),
        ),
        SweptZonePoint(
          latitude: 4.62,
          longitude: -74.08,
          recordedAt: now.add(const Duration(minutes: 2)),
        ),
      ],
    );
    final invalidZone = SweptZone(
      version: 1,
      zoneId: _repeat('4', 32),
      teamId: _repeat('2', 32),
      actorPeerId: _repeat('3', 16),
      callsign: 'Cóndor',
      startedAt: now,
      endedAt: now,
      points: [
        SweptZonePoint(latitude: 95, longitude: 0, recordedAt: now),
        SweptZonePoint(latitude: 4.6, longitude: -74, recordedAt: now),
      ],
    );
    final otherTeamZone = SweptZone(
      version: 1,
      zoneId: _repeat('5', 32),
      teamId: _repeat('9', 32),
      actorPeerId: _repeat('3', 16),
      callsign: 'Cóndor',
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 1)),
      points: [
        SweptZonePoint(latitude: 1, longitude: 1, recordedAt: now),
        SweptZonePoint(
          latitude: 1.1,
          longitude: 1.1,
          recordedAt: now.add(const Duration(minutes: 1)),
        ),
      ],
    );

    final encoded = RescueGeoJson.build(
      teamId: _repeat('2', 32),
      cases: [second, otherTeamCase, first],
      zones: [invalidZone, otherTeamZone, validZone],
    );
    final repeated = RescueGeoJson.build(
      teamId: _repeat('2', 32),
      cases: [first, second],
      zones: [validZone, invalidZone],
    );
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final features = decoded['features']! as List<dynamic>;

    expect(encoded, repeated);
    expect(decoded['type'], 'FeatureCollection');
    expect(features, hasLength(3));
    expect(
      (features[0] as Map<String, dynamic>)['id'],
      'case:${_repeat('a', 64)}',
    );
    expect(
      ((features[0] as Map<String, dynamic>)['geometry']
          as Map<String, dynamic>)['coordinates'],
      [-74.07, 4.61],
    );
    expect((features[1] as Map<String, dynamic>)['geometry'], isNull);
    final zoneGeometry =
        (features[2] as Map<String, dynamic>)['geometry']
            as Map<String, dynamic>;
    expect(zoneGeometry['type'], 'LineString');
    expect(zoneGeometry['coordinates'], [
      [-74.1, 4.6],
      [-74.08, 4.62],
    ]);
    final properties =
        (features[0] as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
    expect(properties['schema'], RescueGeoJson.schema);
    expect(properties['version'], RescueGeoJson.version);
    expect(properties['priority'], 'critical');
    expect(properties['triage'], isA<Map<String, dynamic>>());
    expect(
      features.every(
        (feature) =>
            ((feature as Map<String, dynamic>)['properties']
                as Map<String, dynamic>)['teamId'] ==
            _repeat('2', 32),
      ),
      isTrue,
    );
  });

  test('contrato de extensión y MIME distingue CSV de GeoJSON', () {
    expect(RescueExportFormat.csv.extension, 'csv');
    expect(RescueExportFormat.csv.mimeType, 'text/csv');
    expect(RescueExportFormat.geoJson.extension, 'geojson');
    expect(RescueExportFormat.geoJson.mimeType, 'application/geo+json');
  });

  test('política operativa exporta todos los casos excepto cerrados', () {
    final now = DateTime.utc(2026, 8, 18);
    final active = _case(
      hash: _repeat('a', 64),
      latitude: 1,
      longitude: 1,
      now: now,
    );
    final closed = active.copyWith(
      state: RescueCaseState.closed,
      assigneePeerId: active.assigneePeerId,
    );

    expect(
      RescueExportPolicy.operationalCases([
        closed,
        active,
      ], teamId: active.teamId),
      [same(active)],
    );
  });
}

RescueCase _case({
  required String hash,
  required double latitude,
  required double longitude,
  required DateTime now,
  String victim = 'Víctima',
  String message = 'Necesita extracción',
  String? teamId,
}) => RescueCase(
  teamId: teamId ?? _repeat('2', 32),
  caseHash: hash,
  victimPeerId: _repeat('0', 16),
  victim: victim,
  message: message,
  triage: const SosTriage(
    peopleCount: 2,
    injuryStatus: SosInjuryStatus.injured,
    injuredCount: 1,
    trappedStatus: SosTrappedStatus.yes,
    primaryNeed: SosPrimaryNeed.medical,
  ),
  latitude: latitude,
  longitude: longitude,
  state: RescueCaseState.assigned,
  assigneePeerId: _repeat('9', 16),
  createdAt: now,
  updatedAt: now,
  lastActorPeerId: _repeat('9', 16),
);

String _repeat(String value, int count) => List.filled(count, value).join();
