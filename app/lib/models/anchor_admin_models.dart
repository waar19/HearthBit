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
    this.freeHeap,
    this.minFreeHeap,
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
      freeHeap: (value['freeHeap'] as num?)?.toInt(),
      minFreeHeap: (value['minFreeHeap'] as num?)?.toInt(),
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
  final int? freeHeap;
  final int? minFreeHeap;
}

class AnchorActivitySample {
  const AnchorActivitySample({
    required this.sampledAt,
    required this.received,
    required this.forwarded,
    required this.deduplicated,
    required this.rejected,
    required this.mailboxPercent,
    required this.freeHeap,
    required this.minFreeHeap,
  });

  final DateTime sampledAt;
  final int received;
  final int forwarded;
  final int deduplicated;
  final int rejected;
  final double mailboxPercent;
  final int? freeHeap;
  final int? minFreeHeap;
}

class AnchorActivityHistory {
  AnchorActivityHistory({this.capacity = 60}) : assert(capacity > 0);

  final int capacity;
  final List<AnchorActivitySample> _samples = [];
  AnchorAdminStatus? _previous;

  List<AnchorActivitySample> get samples =>
      List<AnchorActivitySample>.unmodifiable(_samples);

  void add(AnchorAdminStatus status, {DateTime? sampledAt}) {
    final previous = _previous;
    final sample = AnchorActivitySample(
      sampledAt: sampledAt ?? DateTime.now(),
      received: _delta(status.packetsReceived, previous?.packetsReceived),
      forwarded: _delta(status.packetsForwarded, previous?.packetsForwarded),
      deduplicated: _delta(
        status.packetsDeduplicated,
        previous?.packetsDeduplicated,
      ),
      rejected: _delta(status.packetsRejected, previous?.packetsRejected),
      mailboxPercent: status.mailboxCapacity > 0
          ? (status.mailboxUsed / status.mailboxCapacity * 100)
                .clamp(0.0, 100.0)
                .toDouble()
          : 0.0,
      freeHeap: status.freeHeap,
      minFreeHeap: status.minFreeHeap,
    );
    _previous = status;
    _samples.add(sample);
    if (_samples.length > capacity) {
      _samples.removeRange(0, _samples.length - capacity);
    }
  }

  static int _delta(int current, int? previous) {
    if (previous == null || current < previous) return 0;
    return current - previous;
  }
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
