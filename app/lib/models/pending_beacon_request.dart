import '../services/beacon_control_protocol.dart';

class PendingBeaconRequest {
  const PendingBeaconRequest({
    required this.requestId,
    required this.peerId,
    required this.nickname,
    required this.expiresAt,
    required this.flags,
  });

  final String requestId;
  final String peerId;
  final String nickname;
  final DateTime expiresAt;
  final int flags;

  bool get wantsFlash => flags & BeaconControlFlags.flash != 0;
  bool get wantsSound => flags & BeaconControlFlags.sound != 0;
  bool get wantsVibration => flags & BeaconControlFlags.vibrate != 0;
}
