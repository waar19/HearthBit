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

class MeshPeer {
  const MeshPeer({
    required this.id,
    required this.nickname,
    required this.lastSeen,
    required this.secure,
    this.supportsTransfers = false,
    this.role = MeshNodeRole.phoneRelay,
    this.radarAllowedUntil,
    this.radarConsentSource,
  });

  factory MeshPeer.fromMap(Map<Object?, Object?> map) {
    return MeshPeer(
      id: map['id']! as String,
      nickname: map['nickname']! as String,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['lastSeen']! as int),
      secure: map['secure'] as bool? ?? false,
      supportsTransfers: map['supportsTransfers'] as bool? ?? false,
      role: MeshNodeRole.fromWire(map['role']),
      radarAllowedUntil: switch (map['radarAllowedUntil']) {
        final int value when value > 0 => DateTime.fromMillisecondsSinceEpoch(
          value,
        ),
        _ => null,
      },
      radarConsentSource: map['radarConsentSource'] as String?,
    );
  }

  final String id;
  final String nickname;
  final DateTime lastSeen;
  final bool secure;
  final bool supportsTransfers;
  final MeshNodeRole role;
  final DateTime? radarAllowedUntil;
  final String? radarConsentSource;

  bool get radarAllowed => radarAllowedUntil?.isAfter(DateTime.now()) ?? false;

  factory MeshPeer.fromDatabase(Map<String, Object?> map) {
    return MeshPeer(
      id: map['id']! as String,
      nickname: map['nickname']! as String,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen']! as int),
      secure: false,
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

class MeshMessage {
  const MeshMessage({
    required this.id,
    required this.sender,
    required this.content,
    required this.senderPeerId,
    required this.isPrivate,
    required this.isMine,
    required this.timestamp,
    this.channel,
  });

  factory MeshMessage.fromMap(Map<Object?, Object?> map) {
    return MeshMessage(
      id: map['id']! as String,
      sender: map['sender']! as String,
      content: map['content']! as String,
      senderPeerId: map['senderPeerId']! as String,
      isPrivate: map['private'] as bool? ?? false,
      isMine: map['mine'] as bool? ?? false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']! as int),
      channel: map['channel'] as String?,
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

  bool get isSos => channel == 'sos' || content.startsWith('SOS|');

  bool get isCheckIn =>
      channel == 'checkin' || content.contains(EmergencyCheckIn.marker);

  bool get isVoiceNote =>
      isPrivate &&
      RegExp(r'^\[HB-VOICE\|[0-9a-f]{32}\|\d+\]$').hasMatch(content);

  String? get voiceTransferId => isVoiceNote ? content.split('|')[1] : null;

  int? get voiceDurationSeconds => isVoiceNote
      ? int.tryParse(content.split('|')[2].replaceAll(']', ''))
      : null;

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
