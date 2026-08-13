import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/services/beacon_control_protocol.dart';

void main() {
  final nonce = Uint8List.fromList(List<int>.generate(16, (index) => index));

  test('codec de baliza conserva acciones flags expiración y nonce', () {
    final now = DateTime.utc(2026, 8, 13, 12);
    final expiresAt = now.add(const Duration(minutes: 5));
    final payload = BeaconControlProtocol.encode(
      action: BeaconControlAction.request,
      expiresAt: expiresAt,
      flags: BeaconControlFlags.flash | BeaconControlFlags.vibrate,
      nonce: nonce,
    );
    final decoded = BeaconControlProtocol.decode(payload);

    expect(payload, hasLength(BeaconControlProtocol.payloadSize));
    expect(decoded?.action, BeaconControlAction.request);
    expect(decoded?.expiresAt, expiresAt);
    expect(decoded?.nonce, orderedEquals(nonce));
    expect(
      BeaconControlProtocol.isValid(decoded!, packetTimestamp: now, now: now),
      isTrue,
    );
  });

  test('rechaza longitud flags y expiración mayores de cinco minutos', () {
    final now = DateTime.utc(2026, 8, 13, 12);
    final payload = BeaconControlProtocol.encode(
      action: BeaconControlAction.grant,
      expiresAt: now.add(const Duration(minutes: 5)),
      flags: BeaconControlFlags.sound,
      nonce: nonce,
    );

    expect(
      BeaconControlProtocol.decode(Uint8List.sublistView(payload, 0, 26)),
      isNull,
    );
    expect(
      BeaconControlProtocol.decode(
        Uint8List.fromList(payload)..[payload.length - 1] = 0x08,
      ),
      isNull,
    );
    final decoded = BeaconControlProtocol.decode(payload)!;
    expect(
      BeaconControlProtocol.isValid(
        BeaconControlMessage(
          action: decoded.action,
          expiresAt: now.add(const Duration(minutes: 5, milliseconds: 1)),
          nonce: nonce,
          flags: decoded.flags,
        ),
        packetTimestamp: now,
        now: now,
      ),
      isFalse,
    );
  });

  test('revoke y stop no admiten expiración ni actuadores', () {
    for (final action in [
      BeaconControlAction.revoke,
      BeaconControlAction.stop,
    ]) {
      final payload = BeaconControlProtocol.encode(
        action: action,
        expiresAt: null,
        flags: 0,
        nonce: nonce,
      );
      final decoded = BeaconControlProtocol.decode(payload);
      expect(decoded?.action, action);
      expect(decoded?.expiresAt, isNull);
      expect(decoded?.flags, 0);
    }
  });
}
