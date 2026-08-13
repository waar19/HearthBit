import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/mesh_models.dart';
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
    ];

    final csv = RescueCsv.build(RescueIncidentList.fromMessages(messages));

    expect(csv, contains('"Ana, sector 2"'));
    expect(csv, contains('"Herida ""leve""\nconsciente"'));
    expect(csv, contains('INJURED'));
    expect(csv, isNot(contains('9.999999')));
    expect(csv, isNot(contains(RadarLocationUpdate.marker)));
  });
}
