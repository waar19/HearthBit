import 'dart:convert';
import 'dart:typed_data';

import '../models/rescue_roster_models.dart';

typedef RescueRosterPayloadSigner =
    Future<Uint8List> Function(Uint8List payload);
typedef RescueRosterSignatureVerifier =
    Future<bool> Function(
      String peerId,
      Uint8List signingPublicKey,
      Uint8List payload,
      Uint8List signature,
    );

class RescueRosterCodec {
  const RescueRosterCodec();

  static const String prefix = 'HBRT1:';
  static const int version = 1;
  static const int rosterType = 0x52;
  static const int peerIdBytes = 8;
  static const int publicKeyBytes = 32;
  static const int signatureBytes = 64;
  static const int maximumMembers = 512;
  static const int maximumTeamNameBytes = 80;
  static const int maximumCallsignBytes = 63;
  static const int maximumEncodedCharacters = 100000;
  static const int maximumTimestampMilliseconds = 253402300799999;

  Future<RescueTeamRoster> sign(
    RescueTeamRoster roster,
    RescueRosterPayloadSigner signer,
  ) async {
    final canonical = canonicalPayload(roster);
    final signature = await signer(canonical);
    if (signature.length != signatureBytes) {
      throw const FormatException('Invalid Ed25519 signature length');
    }
    return RescueTeamRoster(
      teamId: roster.teamId,
      name: roster.name.trim(),
      createdAt: roster.createdAt,
      leaderPeerId: roster.leaderPeerId.toLowerCase(),
      members: _copyMembers(roster.members),
      signature: Uint8List.fromList(signature),
    );
  }

  String encode(RescueTeamRoster roster) {
    final canonical = canonicalPayload(roster);
    if (roster.signature.length != signatureBytes) {
      throw const FormatException('Invalid Ed25519 signature length');
    }
    final body = base64Url
        .encode([...canonical, ...roster.signature])
        .replaceAll('=', '');
    if (body.length > maximumEncodedCharacters) {
      throw const FormatException('Rescue roster is too large');
    }
    return '$prefix$body';
  }

  Future<RescueTeamRoster> decodeAndVerify(
    String encoded, {
    required RescueRosterSignatureVerifier verify,
  }) async {
    final clean = encoded.trim();
    if (!clean.startsWith(prefix) ||
        clean.length - prefix.length > maximumEncodedCharacters) {
      throw const FormatException('Invalid rescue roster type');
    }
    final bytes = _decodeBase64(clean.substring(prefix.length));
    if (bytes.length < _minimumCanonicalBytes + signatureBytes) {
      throw const FormatException('Truncated rescue roster');
    }
    final signatureOffset = bytes.length - signatureBytes;
    final canonical = Uint8List.sublistView(bytes, 0, signatureOffset);
    final signature = Uint8List.sublistView(bytes, signatureOffset);
    final reader = _RosterReader(canonical);
    if (reader.readUint8() != version || reader.readUint8() != rosterType) {
      throw const FormatException('Unsupported rescue roster version');
    }
    final teamId = _hex(reader.readBytes(16));
    final createdAtMs = reader.readUint64();
    if (createdAtMs > maximumTimestampMilliseconds) {
      throw const FormatException('Invalid rescue roster timestamp');
    }
    final teamName = reader.readString(
      reader.readUint8(),
      maximum: maximumTeamNameBytes,
    );
    final leaderIndex = reader.readUint16();
    final memberCount = reader.readUint16();
    if (memberCount == 0 ||
        memberCount > maximumMembers ||
        leaderIndex >= memberCount) {
      throw const FormatException('Invalid rescue roster member count');
    }
    final members = <RescueRosterMember>[];
    for (var index = 0; index < memberCount; index++) {
      final role = RescueRosterRole.fromWireCode(reader.readUint8());
      if (role == null) {
        throw const FormatException('Invalid rescue roster role');
      }
      final peerId = _hex(reader.readBytes(peerIdBytes));
      final callsign = reader.readString(
        reader.readUint8(),
        maximum: maximumCallsignBytes,
      );
      final key = reader.readBytes(publicKeyBytes);
      members.add(
        RescueRosterMember(
          peerId: peerId,
          callsign: callsign,
          role: role,
          signingPublicKey: key,
        ),
      );
    }
    if (!reader.isDone) {
      throw const FormatException('Unexpected rescue roster data');
    }
    final roster = RescueTeamRoster(
      teamId: teamId,
      name: teamName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      leaderPeerId: members[leaderIndex].peerId,
      members: members,
      signature: Uint8List.fromList(signature),
    );
    _validate(roster);
    final leader = roster.leader;
    final valid = await verify(
      leader.peerId,
      leader.signingPublicKey,
      canonical,
      roster.signature,
    );
    if (!valid) {
      throw const FormatException('Invalid rescue roster signature');
    }
    return roster;
  }

  static Uint8List canonicalPayload(RescueTeamRoster roster) {
    _validate(roster);
    final leaderIndex = roster.members.indexWhere(
      (member) => member.peerId == roster.leaderPeerId,
    );
    final output = BytesBuilder(copy: false)
      ..add([version, rosterType])
      ..add(_unhex(roster.teamId.toLowerCase()))
      ..add(_uint64(roster.createdAt.millisecondsSinceEpoch));
    final teamName = utf8.encode(roster.name.trim());
    output
      ..add([teamName.length])
      ..add(teamName)
      ..add(_uint16(leaderIndex))
      ..add(_uint16(roster.members.length));
    for (final member in roster.members) {
      final callsign = utf8.encode(member.callsign.trim());
      output
        ..add([member.role.wireCode])
        ..add(_unhex(member.peerId.toLowerCase()))
        ..add([callsign.length])
        ..add(callsign)
        ..add(member.signingPublicKey);
    }
    return output.takeBytes();
  }

  static void _validate(RescueTeamRoster roster) {
    final teamId = roster.teamId.trim().toLowerCase();
    final name = roster.name.trim();
    final nameBytes = utf8.encode(name);
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(teamId)) {
      throw const FormatException('Invalid rescue team ID');
    }
    if (name.isEmpty ||
        name != roster.name ||
        nameBytes.length > maximumTeamNameBytes) {
      throw const FormatException('Invalid rescue team name');
    }
    final timestamp = roster.createdAt.millisecondsSinceEpoch;
    if (timestamp <= 0 || timestamp > maximumTimestampMilliseconds) {
      throw const FormatException('Invalid rescue roster timestamp');
    }
    if (roster.members.isEmpty || roster.members.length > maximumMembers) {
      throw const FormatException('Invalid rescue roster member count');
    }
    final normalizedLeader = roster.leaderPeerId.trim().toLowerCase();
    final peerIds = <String>{};
    final signingKeys = <String>{};
    var leaderCount = 0;
    for (final member in roster.members) {
      final peerId = member.peerId.trim().toLowerCase();
      final callsign = member.callsign.trim();
      final callsignBytes = utf8.encode(callsign);
      if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(peerId) ||
          peerId != member.peerId ||
          !peerIds.add(peerId)) {
        throw const FormatException('Invalid or duplicate rescue peer ID');
      }
      if (callsign.isEmpty ||
          callsign != member.callsign ||
          callsignBytes.length > maximumCallsignBytes) {
        throw const FormatException('Invalid rescue callsign');
      }
      if (member.signingPublicKey.length != publicKeyBytes ||
          member.signingPublicKey.every((byte) => byte == 0) ||
          !signingKeys.add(base64Url.encode(member.signingPublicKey))) {
        throw const FormatException('Invalid or duplicate rescue signing key');
      }
      if (member.role == RescueRosterRole.leader) leaderCount += 1;
    }
    if (leaderCount != 1 ||
        roster.members
                .where((member) => member.role == RescueRosterRole.leader)
                .single
                .peerId !=
            normalizedLeader) {
      throw const FormatException('Invalid rescue roster leader');
    }
  }

  static List<RescueRosterMember> _copyMembers(
    Iterable<RescueRosterMember> members,
  ) => members
      .map(
        (member) => RescueRosterMember(
          peerId: member.peerId,
          callsign: member.callsign,
          role: member.role,
          signingPublicKey: Uint8List.fromList(member.signingPublicKey),
        ),
      )
      .toList(growable: false);

  static Uint8List _decodeBase64(String value) {
    if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Invalid rescue roster encoding');
    }
    try {
      final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
      return base64Url.decode(padded);
    } on FormatException {
      throw const FormatException('Invalid rescue roster encoding');
    }
  }

  static Uint8List _uint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static Uint8List _uint64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String value) => Uint8List.fromList([
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);

  static const int _minimumCanonicalBytes =
      2 + 16 + 8 + 1 + 1 + 2 + 2 + 1 + peerIdBytes + 1 + 1 + publicKeyBytes;
}

class _RosterReader {
  _RosterReader(this.bytes);

  final Uint8List bytes;
  int _offset = 0;

  bool get isDone => _offset == bytes.length;

  int readUint8() {
    _require(1);
    return bytes[_offset++];
  }

  int readUint16() {
    _require(2);
    final value = ByteData.sublistView(
      bytes,
      _offset,
      _offset + 2,
    ).getUint16(0, Endian.big);
    _offset += 2;
    return value;
  }

  int readUint64() {
    _require(8);
    final value = ByteData.sublistView(
      bytes,
      _offset,
      _offset + 8,
    ).getUint64(0, Endian.big);
    _offset += 8;
    return value;
  }

  Uint8List readBytes(int length) {
    _require(length);
    final value = Uint8List.fromList(bytes.sublist(_offset, _offset + length));
    _offset += length;
    return value;
  }

  String readString(int length, {required int maximum}) {
    if (length == 0 || length > maximum) {
      throw const FormatException('Invalid rescue roster text length');
    }
    final value = utf8.decode(readBytes(length), allowMalformed: false);
    if (value.trim().isEmpty || value != value.trim()) {
      throw const FormatException('Invalid rescue roster text');
    }
    return value;
  }

  void _require(int length) {
    if (length < 0 || _offset + length > bytes.length) {
      throw const FormatException('Truncated rescue roster');
    }
  }
}
