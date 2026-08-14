import 'dart:convert';
import 'dart:typed_data';

import 'voice_note.dart';

enum MeshNodeRole {
  phoneRelay('PHONE_RELAY'),
  phoneBeacon('PHONE_BEACON'),
  infraRelay('INFRA_RELAY'),
  infraDataAnchor('INFRA_DATA_ANCHOR');

  const MeshNodeRole(this.wireName);

  final String wireName;

  static MeshNodeRole fromWire(Object? value) {
    return switch (value) {
      'PHONE_BEACON' => MeshNodeRole.phoneBeacon,
      'INFRA_RELAY' => MeshNodeRole.infraRelay,
      'INFRA_DATA_ANCHOR' => MeshNodeRole.infraDataAnchor,
      _ => MeshNodeRole.phoneRelay,
    };
  }

  bool get canChat => this == MeshNodeRole.phoneRelay;
}

bool isDefaultMeshNickname(String value) =>
    RegExp(r'^SOS-[0-9a-fA-F]{4}$').hasMatch(value.trim());

enum MeshPowerProfile {
  performance('performance'),
  balanced('balanced'),
  powerSaver('powerSaver'),
  critical('critical'),
  survival('survival');

  const MeshPowerProfile(this.wireName);

  final String wireName;

  static MeshPowerProfile fromWire(Object? value) {
    return switch (value) {
      'performance' => MeshPowerProfile.performance,
      'powerSaver' => MeshPowerProfile.powerSaver,
      'critical' => MeshPowerProfile.critical,
      'survival' => MeshPowerProfile.survival,
      _ => MeshPowerProfile.balanced,
    };
  }

  bool get savesPower =>
      this != MeshPowerProfile.performance && this != MeshPowerProfile.balanced;
}

enum CheckInStatus {
  ok('OK'),
  needsHelp('HELP'),
  injured('INJURED');

  const CheckInStatus(this.wireCode);

  final String wireCode;

  static CheckInStatus? fromWire(String value) {
    for (final status in values) {
      if (status.wireCode == value) return status;
    }
    return null;
  }
}

class DrillCheckIn {
  const DrillCheckIn({
    required this.version,
    required this.status,
    required this.timestamp,
    required this.readableMessage,
  });

  static const marker = '[HB-DRILL|';
  static const currentVersion = 1;
  static const _kind = 'CHECKIN';

  final int version;
  final CheckInStatus status;
  final DateTime timestamp;
  final String readableMessage;

  static String encode({
    required CheckInStatus status,
    required String readableMessage,
    required String safetyNotice,
    required DateTime timestamp,
  }) {
    final notice = safetyNotice.trim();
    final message = readableMessage.trim();
    return '$notice${message.isEmpty ? '' : ': $message'}\n'
        '$marker$currentVersion|$_kind|${status.wireCode}|'
        '${timestamp.millisecondsSinceEpoch}]';
  }

  static DrillCheckIn? tryParse(String content) {
    final markerStart = content.lastIndexOf(marker);
    if (markerStart < 0 || !content.endsWith(']')) return null;
    final fields = content
        .substring(markerStart + marker.length, content.length - 1)
        .split('|');
    if (fields.length != 4) return null;
    final version = int.tryParse(fields[0]);
    final status = CheckInStatus.fromWire(fields[2]);
    final timestampMs = int.tryParse(fields[3]);
    if (version != currentVersion ||
        fields[1] != _kind ||
        status == null ||
        timestampMs == null ||
        timestampMs <= 0) {
      return null;
    }
    final readable = content.substring(0, markerStart).trim();
    if (readable.isEmpty) return null;
    return DrillCheckIn(
      version: version!,
      status: status,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      readableMessage: readable,
    );
  }
}

class EmergencyCheckIn {
  const EmergencyCheckIn({
    required this.status,
    required this.peerId,
    required this.sender,
    required this.timestamp,
    required this.message,
    this.latitude,
    this.longitude,
  });

  static const marker = '[HB-CHECKIN|';

  factory EmergencyCheckIn.fromMessage(MeshMessage message) {
    final markerStart = message.content.lastIndexOf(marker);
    if (markerStart < 0 || !message.content.endsWith(']')) {
      throw const FormatException('Not a HearthBit check-in');
    }
    final readable = message.content.substring(0, markerStart).trim();
    final fields = message.content
        .substring(markerStart + marker.length, message.content.length - 1)
        .split('|');
    if (fields.length != 5) {
      throw const FormatException('Invalid HearthBit check-in');
    }
    final status = CheckInStatus.fromWire(fields[0]);
    final timestampMs = int.tryParse(fields[1]);
    if (status == null || timestampMs == null) {
      throw const FormatException('Invalid HearthBit check-in fields');
    }
    return EmergencyCheckIn(
      status: status,
      peerId: message.senderPeerId,
      sender: message.sender,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      message: readable,
      latitude: double.tryParse(fields[2]),
      longitude: double.tryParse(fields[3]),
    );
  }

  final CheckInStatus status;
  final String peerId;
  final String sender;
  final DateTime timestamp;
  final String message;
  final double? latitude;
  final double? longitude;

  static String encode({
    required CheckInStatus status,
    required String readableMessage,
    required DateTime timestamp,
    double? latitude,
    double? longitude,
  }) {
    final lat = latitude?.toStringAsFixed(6) ?? '';
    final lon = longitude?.toStringAsFixed(6) ?? '';
    return '${readableMessage.trim()}\n'
        '$marker${status.wireCode}|${timestamp.millisecondsSinceEpoch}|'
        '$lat|$lon|1]';
  }
}

class RadarLocationUpdate {
  const RadarLocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  static const marker = '[HB-LOC|';

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;

  static String encode({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime timestamp,
  }) =>
      '$marker${latitude.toStringAsFixed(6)}|'
      '${longitude.toStringAsFixed(6)}|'
      '${accuracyMeters.toStringAsFixed(1)}|'
      '${timestamp.millisecondsSinceEpoch}]';

  static RadarLocationUpdate? tryParse(String content) {
    if (!content.startsWith(marker) || !content.endsWith(']')) return null;
    final fields = content
        .substring(marker.length, content.length - 1)
        .split('|');
    if (fields.length != 4) return null;
    final latitude = double.tryParse(fields[0]);
    final longitude = double.tryParse(fields[1]);
    final accuracy = double.tryParse(fields[2]);
    final timestampMs = int.tryParse(fields[3]);
    if (latitude == null ||
        longitude == null ||
        accuracy == null ||
        timestampMs == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        !accuracy.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        accuracy < 0 ||
        accuracy > 10000 ||
        timestampMs <= 0) {
      return null;
    }
    return RadarLocationUpdate(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }
}

enum EmergencyDeliveryKind {
  sos('sos'),
  checkIn('checkIn');

  const EmergencyDeliveryKind(this.wireName);

  final String wireName;

  static EmergencyDeliveryKind fromWire(Object? value) => value == 'checkIn'
      ? EmergencyDeliveryKind.checkIn
      : EmergencyDeliveryKind.sos;
}

enum EmergencyDeliveryState {
  pending('pending'),
  relayed('relayed'),
  acknowledged('acknowledged'),
  expired('expired');

  const EmergencyDeliveryState(this.wireName);

  final String wireName;

  static EmergencyDeliveryState fromWire(Object? value) {
    return switch (value) {
      'relayed' => EmergencyDeliveryState.relayed,
      'acknowledged' => EmergencyDeliveryState.acknowledged,
      'expired' => EmergencyDeliveryState.expired,
      _ => EmergencyDeliveryState.pending,
    };
  }
}

class EmergencyDelivery {
  const EmergencyDelivery({
    required this.localId,
    required this.kind,
    required this.content,
    required this.createdAt,
    required this.expiresAt,
    required this.nextAttemptAt,
    required this.state,
    this.attempts = 0,
    this.lastAttemptAt,
    this.canonicalHash,
    this.lastError,
    this.acknowledgedBy = const {},
  });

  factory EmergencyDelivery.fromDatabase(
    Map<String, Object?> row, {
    Set<String> acknowledgedBy = const {},
  }) {
    DateTime? optionalDate(String key) {
      final value = row[key] as int?;
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    }

    return EmergencyDelivery(
      localId: row['local_id']! as String,
      kind: EmergencyDeliveryKind.fromWire(row['kind']),
      content: row['content']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ).toLocal(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        row['expires_at']! as int,
        isUtc: true,
      ).toLocal(),
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
        row['next_attempt_at']! as int,
        isUtc: true,
      ).toLocal(),
      state: EmergencyDeliveryState.fromWire(row['state']),
      attempts: row['attempts']! as int,
      lastAttemptAt: optionalDate('last_attempt_at'),
      canonicalHash: row['canonical_hash'] as String?,
      lastError: row['last_error'] as String?,
      acknowledgedBy: Set.unmodifiable(acknowledgedBy),
    );
  }

  final String localId;
  final EmergencyDeliveryKind kind;
  final String content;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime nextAttemptAt;
  final EmergencyDeliveryState state;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? canonicalHash;
  final String? lastError;
  final Set<String> acknowledgedBy;

  int get confirmationCount => acknowledgedBy.length;
  bool get isTerminal =>
      state == EmergencyDeliveryState.acknowledged ||
      state == EmergencyDeliveryState.expired;

  Map<String, Object?> toDatabase() => {
    'local_id': localId,
    'kind': kind.wireName,
    'content': content,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
    'next_attempt_at': nextAttemptAt.toUtc().millisecondsSinceEpoch,
    'state': state.wireName,
    'attempts': attempts,
    'last_attempt_at': lastAttemptAt?.toUtc().millisecondsSinceEpoch,
    'canonical_hash': canonicalHash,
    'last_error': lastError,
  };

  EmergencyDelivery copyWith({
    EmergencyDeliveryState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    DateTime? lastAttemptAt,
    String? canonicalHash,
    String? lastError,
    Set<String>? acknowledgedBy,
    bool clearLastError = false,
  }) {
    return EmergencyDelivery(
      localId: localId,
      kind: kind,
      content: content,
      createdAt: createdAt,
      expiresAt: expiresAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      canonicalHash: canonicalHash ?? this.canonicalHash,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
    );
  }
}

class MeshPeer {
  const MeshPeer({
    required this.id,
    required this.nickname,
    required this.lastSeen,
    required this.secure,
    this.online = true,
    this.supportsTransfers = false,
    this.supportsEmergencyAck = false,
    this.role = MeshNodeRole.phoneRelay,
    this.hasLongRangeTrunk = false,
    this.radarAllowedUntil,
    this.radarConsentSource,
    this.signingPublicKey,
  });

  factory MeshPeer.fromMap(Map<Object?, Object?> map) {
    final parsed = tryParse(map);
    if (parsed == null) throw const FormatException('Invalid mesh peer');
    return parsed;
  }

  static MeshPeer? tryParse(Map<Object?, Object?> map) {
    final id = map['id'];
    final nickname = map['nickname'];
    final lastSeen = map['lastSeen'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        nickname is! String ||
        nickname.trim().isEmpty ||
        nickname.length > 80 ||
        lastSeen is! num ||
        !lastSeen.isFinite ||
        lastSeen <= 0 ||
        lastSeen > 8640000000000000) {
      return null;
    }
    final online = map['online'] is bool ? map['online']! as bool : true;
    final radarConsentSource = map['radarConsentSource'];
    if (radarConsentSource != null &&
        (radarConsentSource is! String || radarConsentSource.length > 64)) {
      return null;
    }
    return MeshPeer(
      id: id,
      nickname: nickname,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeen.toInt()),
      secure: online && map['secure'] == true,
      online: online,
      supportsTransfers: map['supportsTransfers'] == true,
      supportsEmergencyAck: map['supportsEmergencyAck'] == true,
      role: MeshNodeRole.fromWire(map['role']),
      hasLongRangeTrunk: map['hasLongRangeTrunk'] == true,
      radarAllowedUntil: switch (map['radarAllowedUntil']) {
        final num value
            when value.isFinite && value > 0 && value <= 8640000000000000 =>
          DateTime.fromMillisecondsSinceEpoch(value.toInt()),
        _ => null,
      },
      radarConsentSource: radarConsentSource as String?,
      signingPublicKey: switch (map['signingPublicKey']) {
        final Uint8List value when value.length == 32 => value,
        final List<int> value when value.length == 32 => Uint8List.fromList(
          value,
        ),
        _ => null,
      },
    );
  }

  final String id;
  final String nickname;
  final DateTime lastSeen;
  final bool secure;
  final bool online;
  final bool supportsTransfers;
  final bool supportsEmergencyAck;
  final MeshNodeRole role;
  final bool hasLongRangeTrunk;
  final DateTime? radarAllowedUntil;
  final String? radarConsentSource;

  /// Clave Ed25519 autenticada por el ANNOUNCE. Nunca contiene material privado.
  final Uint8List? signingPublicKey;

  bool get radarAllowed => radarAllowedUntil?.isAfter(DateTime.now()) ?? false;

  bool isOnlineAt(DateTime now, {required Duration freshnessWindow}) =>
      online && !lastSeen.isBefore(now.subtract(freshnessWindow));

  factory MeshPeer.fromDatabase(Map<String, Object?> map) {
    return MeshPeer(
      id: map['id']! as String,
      nickname: map['nickname']! as String,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen']! as int),
      secure: false,
      online: false,
    );
  }

  Map<String, Object?> toDatabase() => {
    'id': id,
    'nickname': nickname,
    'last_seen': lastSeen.millisecondsSinceEpoch,
  };
}

class GenericBlePresence {
  const GenericBlePresence({
    required this.id,
    required this.role,
    required this.kind,
    required this.chatAvailable,
    required this.rssi,
    required this.lastSeen,
  });

  factory GenericBlePresence.fromMap(Map<Object?, Object?> map) {
    return GenericBlePresence(
      id: map['id']! as String,
      role: MeshNodeRole.fromWire(map['role']),
      kind: map['kind'] as String? ?? 'genericBle',
      chatAvailable: map['chatAvailable'] as bool? ?? false,
      rssi: (map['rssi']! as num).toInt(),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        (map['lastSeen']! as num).toInt(),
      ),
    );
  }

  /// Identificador efímero, local a esta ejecución y rotado por Android.
  final String id;
  final MeshNodeRole role;
  final String kind;
  final bool chatAvailable;
  final int rssi;
  final DateTime lastSeen;
}

/// Regla única para ofrecer archivos desde cualquier vista de la aplicación.
bool canOfferFileToPeer(MeshPeer peer, {required bool isOnline}) =>
    isOnline && peer.supportsTransfers;

enum MeshMessageDeliveryStatus { transmitted, pending, expired }

class MeshMessage {
  static const int maximumIdLength = 128;
  static const int maximumNicknameLength = 80;
  static const int maximumContentBytes = 64 * 1024;
  static const int maximumChannelLength = 32;

  const MeshMessage({
    required this.id,
    required this.sender,
    required this.content,
    required this.senderPeerId,
    required this.isPrivate,
    required this.isMine,
    required this.timestamp,
    this.channel,
    this.deliveryStatus = MeshMessageDeliveryStatus.transmitted,
  });

  factory MeshMessage.fromMap(Map<Object?, Object?> map) {
    final parsed = tryParse(map);
    if (parsed == null) throw const FormatException('Invalid mesh message');
    return parsed;
  }

  static MeshMessage? tryParse(Map<Object?, Object?> map) {
    final id = map['id'];
    final sender = map['sender'];
    final content = map['content'];
    final senderPeerId = map['senderPeerId'];
    final timestamp = map['timestamp'];
    final channel = map['channel'];
    if (id is! String ||
        id.isEmpty ||
        id.length > maximumIdLength ||
        sender is! String ||
        sender.length > maximumNicknameLength ||
        content is! String ||
        utf8.encode(content).length > maximumContentBytes ||
        senderPeerId is! String ||
        senderPeerId.isEmpty ||
        senderPeerId.length > maximumIdLength ||
        timestamp is! num ||
        !timestamp.isFinite ||
        timestamp <= 0 ||
        timestamp > 8640000000000000 ||
        (channel != null &&
            (channel is! String || channel.length > maximumChannelLength))) {
      return null;
    }
    return MeshMessage(
      id: id,
      sender: sender,
      content: content,
      senderPeerId: senderPeerId,
      isPrivate: map['private'] == true,
      isMine: map['mine'] == true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()),
      channel: channel as String?,
    );
  }

  factory MeshMessage.fromDatabase(Map<String, Object?> map) {
    return MeshMessage(
      id: map['id']! as String,
      sender: map['sender']! as String,
      content: map['content']! as String,
      senderPeerId: map['sender_peer_id']! as String,
      isPrivate: map['is_private'] == 1,
      isMine: map['is_mine'] == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']! as int),
      channel: map['channel'] as String?,
    );
  }

  final String id;
  final String sender;
  final String content;
  final String senderPeerId;
  final bool isPrivate;
  final bool isMine;
  final DateTime timestamp;
  final String? channel;
  final MeshMessageDeliveryStatus deliveryStatus;

  bool get isDrill =>
      channel?.trim().toLowerCase() == 'drill' ||
      content.contains(DrillCheckIn.marker);

  DrillCheckIn? get drill {
    if (!isDrill || isPrivate) return null;
    return DrillCheckIn.tryParse(content);
  }

  bool get isSos =>
      !isDrill && (channel == 'sos' || content.startsWith('SOS|'));

  bool get isPending => deliveryStatus == MeshMessageDeliveryStatus.pending;

  bool get isExpired => deliveryStatus == MeshMessageDeliveryStatus.expired;

  bool get isCheckIn =>
      !isDrill &&
      (channel == 'checkin' || content.contains(EmergencyCheckIn.marker));

  VoiceNoteEnvelope? get voiceNote =>
      isPrivate ? VoiceNoteEnvelope.tryParse(content) : null;

  bool get isVoiceNote => voiceNote != null;

  String? get voiceTransferId => voiceNote?.transferId;

  int? get voiceDurationSeconds => voiceNote?.durationSeconds;

  List<double> get voiceWaveform => voiceNote?.waveform ?? const [];

  bool get isRadarLocation => isPrivate && radarLocation != null;

  RadarLocationUpdate? get radarLocation =>
      isPrivate ? RadarLocationUpdate.tryParse(content) : null;

  EmergencyCheckIn? get checkIn {
    if (!isCheckIn) return null;
    try {
      return EmergencyCheckIn.fromMessage(this);
    } on FormatException {
      return null;
    }
  }

  /// Las alertas viajan como 'SOS|descripción|lat|lon' (lat/lon vacíos si no
  /// hubo GPS). Estos helpers separan las partes para la UI y el radar.
  String get sosDescription {
    if (!content.startsWith('SOS|')) return content;
    final parts = content.split('|');
    if (parts.length < 4) return parts.skip(1).join('|');
    return parts.sublist(1, parts.length - 2).join('|');
  }

  double? get sosLatitude => _sosCoordinate(2);

  double? get sosLongitude => _sosCoordinate(1);

  double? _sosCoordinate(int fromEnd) {
    if (!content.startsWith('SOS|')) return null;
    final parts = content.split('|');
    if (parts.length < 4) return null;
    return double.tryParse(parts[parts.length - fromEnd]);
  }

  Map<String, Object?> toDatabase() => {
    'id': id,
    'sender': sender,
    'content': content,
    'sender_peer_id': senderPeerId,
    'is_private': isPrivate ? 1 : 0,
    'is_mine': isMine ? 1 : 0,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'channel': channel,
  };
}

enum MeshConnectionStatus { stopped, starting, active, degraded, error }

class MeshConversation {
  const MeshConversation({
    required this.peer,
    required this.lastMessage,
    required this.isOnline,
  });

  final MeshPeer peer;
  final MeshMessage lastMessage;
  final bool isOnline;
}
