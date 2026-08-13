import 'dart:typed_data';

class FamilyGroup {
  const FamilyGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FamilyGroup.fromDatabase(Map<String, Object?> map) => FamilyGroup(
    id: map['id']! as int,
    name: map['name']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
  );

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.groupId,
    required this.peerId,
    required this.nickname,
    required this.signingPublicKey,
    required this.fingerprint,
    required this.verifiedAt,
  });

  factory FamilyMember.fromDatabase(Map<String, Object?> map) => FamilyMember(
    id: map['id']! as int,
    groupId: map['group_id']! as int,
    peerId: map['peer_id']! as String,
    nickname: map['nickname']! as String,
    signingPublicKey: Uint8List.fromList(
      map['signing_public_key']! as List<int>,
    ),
    fingerprint: map['fingerprint']! as String,
    verifiedAt: DateTime.fromMillisecondsSinceEpoch(map['verified_at']! as int),
  );

  final int id;
  final int groupId;
  final String peerId;
  final String nickname;
  final Uint8List signingPublicKey;
  final String fingerprint;
  final DateTime verifiedAt;
}

class FamilyQrIdentity {
  const FamilyQrIdentity({
    required this.peerId,
    required this.nickname,
    required this.signingPublicKey,
    required this.fingerprint,
  });

  final String peerId;
  final String nickname;
  final Uint8List signingPublicKey;
  final String fingerprint;
}
