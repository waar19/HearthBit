import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/models/swept_zone_models.dart';

void main() {
  test('codifica y recupera una zona compacta versionada', () {
    final zone = _zone();
    final encoded = SweptZoneCodec.encode(zone);
    final decoded = SweptZoneCodec.tryDecode(encoded);

    expect(encoded, startsWith('[HB-ZONE|1|'));
    expect(decoded?.zoneId, zone.zoneId);
    expect(decoded?.teamId, zone.teamId);
    expect(decoded?.actorPeerId, zone.actorPeerId);
    expect(decoded?.points, hasLength(2));
    expect(decoded?.points.last.latitude, closeTo(4.7001, 0.00001));
  });

  test('rechaza payloads malformados, versiones y tamaños inválidos', () {
    expect(SweptZoneCodec.tryDecode('[HB-ZONE|2|e30]'), isNull);
    expect(SweptZoneCodec.tryDecode('[HB-ZONE|1|%%%]'), isNull);
    expect(
      SweptZoneCodec.tryDecode(
        '[HB-ZONE|1|${'a' * SweptZoneCodec.maximumPayloadBytes}]',
      ),
      isNull,
    );
    expect(
      () => SweptZoneCodec.encode(
        _zone(
          points: List.generate(
            SweptZoneCodec.maximumPoints + 1,
            (index) => SweptZonePoint(
              latitude: 4.7,
              longitude: -74.1,
              recordedAt: DateTime.fromMillisecondsSinceEpoch(
                1000 + index * 1000,
                isUtc: true,
              ),
            ),
          ),
          endedAt: DateTime.fromMillisecondsSinceEpoch(
            (SweptZoneCodec.maximumPoints + 2) * 1000,
            isUtc: true,
          ),
        ),
      ),
      throwsFormatException,
    );
  });
}

SweptZone _zone({List<SweptZonePoint>? points, DateTime? endedAt}) => SweptZone(
  version: SweptZoneCodec.version,
  zoneId: '00112233445566778899aabbccddeeff',
  teamId: 'ffeeddccbbaa99887766554433221100',
  actorPeerId: '0011223344556677',
  callsign: 'Águila',
  startedAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
  endedAt: endedAt ?? DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
  points:
      points ??
      [
        SweptZonePoint(
          latitude: 4.7,
          longitude: -74.1,
          recordedAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        ),
        SweptZonePoint(
          latitude: 4.7001,
          longitude: -74.1001,
          recordedAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
        ),
      ],
);
