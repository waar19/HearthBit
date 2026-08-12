class MeshPeer {
  const MeshPeer({
    required this.id,
    required this.nickname,
    required this.lastSeen,
    required this.secure,
    this.supportsTransfers = false,
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
