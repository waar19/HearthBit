class MeshPeer {
  const MeshPeer({
    required this.id,
    required this.nickname,
    required this.lastSeen,
    required this.secure,
  });

  factory MeshPeer.fromMap(Map<Object?, Object?> map) {
    return MeshPeer(
      id: map['id']! as String,
      nickname: map['nickname']! as String,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['lastSeen']! as int),
      secure: map['secure'] as bool? ?? false,
    );
  }

  final String id;
  final String nickname;
  final DateTime lastSeen;
  final bool secure;
}

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
