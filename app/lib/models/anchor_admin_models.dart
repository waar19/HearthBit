class AnchorAdminStatus {
  const AnchorAdminStatus({
    required this.claimed,
    required this.firmwareVersion,
    required this.protocolVersion,
    required this.uptimeMs,
    required this.bootCount,
    required this.packetsReceived,
    required this.packetsForwarded,
    required this.packetsStored,
    required this.packetsDelivered,
    required this.packetsDeduplicated,
    required this.packetsExpired,
    required this.packetsRejected,
    required this.lastActivityUptimeMs,
    required this.mailboxUsed,
    required this.mailboxCapacity,
    required this.mailboxAvailable,
    required this.clockValid,
    required this.clockAuthoritative,
    required this.nickname,
  });

  factory AnchorAdminStatus.fromMap(Map<Object?, Object?> value) {
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    return AnchorAdminStatus(
      claimed: value['claimed'] == true,
      firmwareVersion: number('firmwareVersion'),
      protocolVersion: number('protocolVersion'),
      uptimeMs: number('uptimeMs'),
      bootCount: number('bootCount'),
      packetsReceived: number('packetsReceived'),
      packetsForwarded: number('packetsForwarded'),
      packetsStored: number('packetsStored'),
      packetsDelivered: number('packetsDelivered'),
      packetsDeduplicated: number('packetsDeduplicated'),
      packetsExpired: number('packetsExpired'),
      packetsRejected: number('packetsRejected'),
      lastActivityUptimeMs: number('lastActivityUptimeMs'),
      mailboxUsed: number('mailboxUsed'),
      mailboxCapacity: number('mailboxCapacity'),
      mailboxAvailable: value['mailboxAvailable'] == true,
      clockValid: value['clockValid'] == true,
      clockAuthoritative: value['clockAuthoritative'] == true,
      nickname: value['nickname'] as String? ?? '',
    );
  }

  final bool claimed;
  final int firmwareVersion;
  final int protocolVersion;
  final int uptimeMs;
  final int bootCount;
  final int packetsReceived;
  final int packetsForwarded;
  final int packetsStored;
  final int packetsDelivered;
  final int packetsDeduplicated;
  final int packetsExpired;
  final int packetsRejected;
  final int lastActivityUptimeMs;
  final int mailboxUsed;
  final int mailboxCapacity;
  final bool mailboxAvailable;
  final bool clockValid;
  final bool clockAuthoritative;
  final String nickname;
}

class AnchorAdminResult {
  const AnchorAdminResult({
    required this.requestId,
    required this.command,
    required this.statusCode,
    this.status,
    this.retryAfterSeconds = 0,
    this.error,
  });

  factory AnchorAdminResult.fromMap(Map<Object?, Object?> value) {
    final command = value['command'] as String? ?? '';
    return AnchorAdminResult(
      requestId: value['requestId'] as String? ?? '',
      command: command,
      statusCode: (value['statusCode'] as num?)?.toInt() ?? -1,
      status: command == 'status' && (value['statusCode'] as num?)?.toInt() == 0
          ? AnchorAdminStatus.fromMap(value)
          : null,
      retryAfterSeconds: (value['retryAfterSeconds'] as num?)?.toInt() ?? 0,
      error: value['error'] as String?,
    );
  }

  final String requestId;
  final String command;
  final int statusCode;
  final AnchorAdminStatus? status;
  final int retryAfterSeconds;
  final String? error;

  bool get succeeded => statusCode == 0;
}
