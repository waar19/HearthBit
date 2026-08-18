import 'dart:typed_data';

enum RescueRosterRole {
  leader(0),
  responder(1),
  medic(2),
  search(3),
  logistics(4),
  communications(5),
  authority(6);

  const RescueRosterRole(this.wireCode);

  final int wireCode;

  static RescueRosterRole? fromWireCode(int value) {
    for (final role in values) {
      if (role.wireCode == value) return role;
    }
    return null;
  }
}

class RescueRosterMember {
  const RescueRosterMember({
    required this.peerId,
    required this.callsign,
    required this.role,
    required this.signingPublicKey,
  });

  final String peerId;
  final String callsign;
  final RescueRosterRole role;
  final Uint8List signingPublicKey;
}

class RescueTeamRoster {
  const RescueTeamRoster({
    required this.teamId,
    required this.name,
    required this.createdAt,
    required this.leaderPeerId,
    required this.members,
    required this.signature,
  });

  final String teamId;
  final String name;
  final DateTime createdAt;
  final String leaderPeerId;
  final List<RescueRosterMember> members;
  final Uint8List signature;

  RescueRosterMember get leader =>
      members.firstWhere((member) => member.peerId == leaderPeerId);
}
