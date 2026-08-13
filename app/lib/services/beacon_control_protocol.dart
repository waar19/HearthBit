import 'dart:math';
import 'dart:typed_data';

enum BeaconControlAction { request, grant, revoke, stop }

class BeaconControlFlags {
  const BeaconControlFlags._();

  static const int flash = 0x01;
  static const int sound = 0x02;
  static const int vibrate = 0x04;
  static const int all = flash | sound | vibrate;
}

class BeaconControlMessage {
  const BeaconControlMessage({
    required this.action,
    required this.expiresAt,
    required this.nonce,
    required this.flags,
  });

  final BeaconControlAction action;
  final DateTime? expiresAt;
  final Uint8List nonce;
  final int flags;
}

class BeaconControlProtocol {
  const BeaconControlProtocol._();

  static const int version = 1;
  static const int nonceSize = 16;
  static const int payloadSize = 27;
  static const Duration maximumDuration = Duration(minutes: 5);
  static const Duration clockSkew = Duration(minutes: 2);

  static Uint8List encode({
    required BeaconControlAction action,
    required DateTime? expiresAt,
    required int flags,
    Uint8List? nonce,
  }) {
    final terminal =
        action == BeaconControlAction.revoke ||
        action == BeaconControlAction.stop;
    if (flags & ~BeaconControlFlags.all != 0 ||
        (terminal && (expiresAt != null || flags != 0)) ||
        (!terminal && (expiresAt == null || flags == 0))) {
      throw ArgumentError('Invalid beacon control fields');
    }
    final actualNonce = nonce ?? _randomNonce();
    if (actualNonce.length != nonceSize) {
      throw ArgumentError.value(actualNonce.length, 'nonce.length');
    }
    final output = Uint8List(payloadSize);
    final data = ByteData.sublistView(output);
    output[0] = version;
    output[1] = switch (action) {
      BeaconControlAction.request => 1,
      BeaconControlAction.grant => 2,
      BeaconControlAction.revoke => 3,
      BeaconControlAction.stop => 4,
    };
    data.setUint64(2, expiresAt?.millisecondsSinceEpoch ?? 0, Endian.big);
    output.setRange(10, 10 + nonceSize, actualNonce);
    output[payloadSize - 1] = flags;
    return output;
  }

  static BeaconControlMessage? decode(Uint8List payload) {
    if (payload.length != payloadSize || payload[0] != version) return null;
    final action = switch (payload[1]) {
      1 => BeaconControlAction.request,
      2 => BeaconControlAction.grant,
      3 => BeaconControlAction.revoke,
      4 => BeaconControlAction.stop,
      _ => null,
    };
    if (action == null) return null;
    final millis = ByteData.sublistView(payload).getUint64(2, Endian.big);
    final flags = payload.last;
    if (flags & ~BeaconControlFlags.all != 0) return null;
    final terminal =
        action == BeaconControlAction.revoke ||
        action == BeaconControlAction.stop;
    if ((terminal && (millis != 0 || flags != 0)) ||
        (!terminal && (millis == 0 || flags == 0))) {
      return null;
    }
    return BeaconControlMessage(
      action: action,
      expiresAt: millis == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      nonce: Uint8List.fromList(payload.sublist(10, 10 + nonceSize)),
      flags: flags,
    );
  }

  static bool isValid(
    BeaconControlMessage message, {
    required DateTime packetTimestamp,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final difference = packetTimestamp.difference(current).abs();
    if (difference > clockSkew) return false;
    return switch (message.action) {
      BeaconControlAction.request || BeaconControlAction.grant =>
        message.expiresAt != null &&
            message.expiresAt!.isAfter(current) &&
            !message.expiresAt!.isAfter(current.add(maximumDuration)),
      BeaconControlAction.revoke || BeaconControlAction.stop =>
        message.expiresAt == null && message.flags == 0,
    };
  }

  static Uint8List _randomNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(nonceSize, (_) => random.nextInt(256)),
    );
  }
}
