import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract final class KeyRotationProtocol {
  static const int typeId = 0x2c;
  static const int version = 1;
  static const int payloadSize = 153;
  static const Duration clockWindow = Duration(minutes: 10);
  static final Uint8List _domain = Uint8List.fromList(
    'HearthBitKeyRotationV1'.codeUnits,
  );

  static KeyRotationPayload? decode(Uint8List payload) {
    if (payload.length != payloadSize || payload[0] != version) return null;
    final oldPeerId = Uint8List.fromList(payload.sublist(1, 9));
    final noise = Uint8List.fromList(payload.sublist(9, 41));
    final signing = Uint8List.fromList(payload.sublist(41, 73));
    final timestamp = _u64(payload, 73);
    final sequence = _u64(payload, 81);
    final signature = Uint8List.fromList(payload.sublist(89, 153));
    if (sequence <= 0 ||
        noise.every((byte) => byte == 0) ||
        signing.every((byte) => byte == 0)) {
      return null;
    }
    return KeyRotationPayload(
      oldPeerId: oldPeerId,
      newNoisePublicKey: noise,
      newSigningPublicKey: signing,
      timestampMilliseconds: timestamp,
      sequence: sequence,
      authorizationSignature: signature,
    );
  }

  static Uint8List authorizationBytes(KeyRotationPayload rotation) =>
      Uint8List.fromList([..._domain, ...rotation.unsignedBytes]);

  static String peerIdForNoiseKey(Uint8List key) =>
      sha256.convert(key).bytes.take(8).map(_hexByte).join();

  static int _u64(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 8).getUint64(0);

  static String _hexByte(int value) => value.toRadixString(16).padLeft(2, '0');
}

class KeyRotationPayload {
  const KeyRotationPayload({
    required this.oldPeerId,
    required this.newNoisePublicKey,
    required this.newSigningPublicKey,
    required this.timestampMilliseconds,
    required this.sequence,
    required this.authorizationSignature,
  });

  final Uint8List oldPeerId;
  final Uint8List newNoisePublicKey;
  final Uint8List newSigningPublicKey;
  final int timestampMilliseconds;
  final int sequence;
  final Uint8List authorizationSignature;

  String get oldPeerIdHex =>
      oldPeerId.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  String get newPeerIdHex =>
      KeyRotationProtocol.peerIdForNoiseKey(newNoisePublicKey);

  Uint8List get unsignedBytes {
    final output = BytesBuilder(copy: false)
      ..addByte(KeyRotationProtocol.version)
      ..add(oldPeerId)
      ..add(newNoisePublicKey)
      ..add(newSigningPublicKey);
    final numbers = ByteData(16)
      ..setUint64(0, timestampMilliseconds)
      ..setUint64(8, sequence);
    output.add(numbers.buffer.asUint8List());
    return output.takeBytes();
  }
}
