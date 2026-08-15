import 'dart:math';
import 'dart:typed_data';

enum RangingControlAction {
  capabilities,
  request,
  accept,
  acousticReady,
  acousticChirp,
  acousticObservation,
  result,
  stop,
  error,
  oobData,
}

enum RangingTechnology {
  none,
  bluetoothChannelSounding,
  wifiNanRtt,
  bleRssi,
  acoustic,
}

class RangingControlMessage {
  const RangingControlMessage({
    required this.action,
    required this.technology,
    required this.sessionNonce,
    required this.round,
    required this.value,
    required this.errorMeters,
    required this.confidence,
    required this.opaqueData,
  });

  final RangingControlAction action;
  final RangingTechnology technology;
  final Uint8List sessionNonce;
  final int round;
  final double value;
  final double errorMeters;
  final double confidence;
  final Uint8List opaqueData;
}

class RangingControlProtocol {
  const RangingControlProtocol._();

  static const int version = 1;
  static const int errorMicrophonePermission = 1;
  static const int errorRoundFailed = 2;
  static const int errorSelfChirpMissing = 3;
  static const int nonceSize = 16;
  static const int fixedSize = 38;
  static const int maximumOpaqueBytes = 1024;

  static Uint8List encode({
    required RangingControlAction action,
    required RangingTechnology technology,
    Uint8List? sessionNonce,
    int round = 0,
    double value = 0,
    double errorMeters = 0,
    double confidence = 0,
    Uint8List? opaqueData,
  }) {
    final nonce = sessionNonce ?? randomNonce();
    final opaque = opaqueData ?? Uint8List(0);
    if (nonce.length != nonceSize ||
        round < 0 ||
        round > 255 ||
        opaque.length > maximumOpaqueBytes ||
        !value.isFinite ||
        !errorMeters.isFinite ||
        !confidence.isFinite ||
        errorMeters < 0 ||
        confidence < 0 ||
        confidence > 1) {
      throw ArgumentError('Invalid ranging control fields');
    }
    final output = Uint8List(fixedSize + opaque.length);
    final data = ByteData.sublistView(output);
    output[0] = version;
    output[1] = action.index + 1;
    output[2] = technology.index;
    output[3] = round;
    output.setRange(4, 4 + nonceSize, nonce);
    data
      ..setFloat64(20, value, Endian.big)
      ..setFloat32(28, errorMeters, Endian.big)
      ..setFloat32(32, confidence, Endian.big)
      ..setUint16(36, opaque.length, Endian.big);
    output.setRange(fixedSize, output.length, opaque);
    return output;
  }

  static RangingControlMessage? decode(Uint8List payload) {
    if (payload.length < fixedSize || payload[0] != version) return null;
    final actionIndex = payload[1] - 1;
    final technologyIndex = payload[2];
    if (actionIndex < 0 ||
        actionIndex >= RangingControlAction.values.length ||
        technologyIndex < 0 ||
        technologyIndex >= RangingTechnology.values.length) {
      return null;
    }
    final data = ByteData.sublistView(payload);
    final opaqueLength = data.getUint16(36, Endian.big);
    if (opaqueLength > maximumOpaqueBytes ||
        payload.length != fixedSize + opaqueLength) {
      return null;
    }
    final value = data.getFloat64(20, Endian.big);
    final error = data.getFloat32(28, Endian.big);
    final confidence = data.getFloat32(32, Endian.big);
    if (!value.isFinite ||
        !error.isFinite ||
        !confidence.isFinite ||
        error < 0 ||
        confidence < 0 ||
        confidence > 1) {
      return null;
    }
    return RangingControlMessage(
      action: RangingControlAction.values[actionIndex],
      technology: RangingTechnology.values[technologyIndex],
      sessionNonce: Uint8List.fromList(payload.sublist(4, 4 + nonceSize)),
      round: payload[3],
      value: value,
      errorMeters: error,
      confidence: confidence,
      opaqueData: Uint8List.fromList(payload.sublist(fixedSize)),
    );
  }

  static Uint8List randomNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(nonceSize, (_) => random.nextInt(256)),
    );
  }
}
