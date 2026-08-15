import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/mesh_native_event.dart';

void main() {
  test('parsea RSSI y ranging con tipos nativos estables', () {
    final rssi = MeshNativeEvent.parse({
      'type': 'rssi',
      'peerId': 'AABB',
      'rssi': -61,
      'at': 1234,
      'remote': true,
      'tentative': false,
    });
    expect(rssi, isA<MeshRssiEvent>());
    expect((rssi as MeshRssiEvent).peerId, 'AABB');
    expect(rssi.rssi, -61);
    expect(rssi.remote, isTrue);

    final control = MeshNativeEvent.parse({
      'type': 'rangingControl',
      'peerId': 'AABB',
      'payload': <int>[1, 2, 3],
    });
    expect(control, isA<MeshRangingControlEvent>());
    expect(
      (control as MeshRangingControlEvent).payload,
      Uint8List.fromList([1, 2, 3]),
    );
  });

  test('tipos incorrectos fallan cerrados sin lanzar', () {
    final event = MeshNativeEvent.parse({
      'type': 'rangingMeasurement',
      'peerId': 7,
      'meters': 'near',
      'confidence': <int>[],
    });

    expect(event, isA<MeshRangingMeasurementEvent>());
    final measurement = event as MeshRangingMeasurementEvent;
    expect(measurement.peerId, isNull);
    expect(measurement.meters, isNull);
    expect(measurement.confidence, isNull);
  });

  test('conserva eventos desconocidos para compatibilidad futura', () {
    final event = MeshNativeEvent.parse({
      'type': 'futureCapability',
      'version': 2,
    });

    expect(event, isA<MeshUnknownEvent>());
    expect((event as MeshUnknownEvent).type, 'futureCapability');
    expect(event.raw['version'], 2);
  });
}
