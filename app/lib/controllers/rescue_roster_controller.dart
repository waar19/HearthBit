import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/rescue_roster_models.dart';
import '../services/mesh_platform_service.dart';
import '../services/rescue_roster_codec.dart';
import '../services/rescue_roster_repository.dart';
import '../utils/utf8_text.dart';
import 'mesh_controller.dart';

class RescueRosterController extends ChangeNotifier {
  RescueRosterController({
    required this.mesh,
    MeshPlatformService? platform,
    RescueRosterRepository? repository,
    RescueRosterCodec? codec,
    Random? secureRandom,
    DateTime Function()? now,
  }) : _platform = platform ?? MeshPlatformService(),
       _repository = repository ?? RescueRosterRepository(),
       _codec = codec ?? const RescueRosterCodec(),
       _random = secureRandom ?? Random.secure(),
       _now = now ?? DateTime.now;

  static const Duration maximumFutureSkew = Duration(minutes: 5);

  final MeshController mesh;
  final MeshPlatformService _platform;
  final RescueRosterRepository _repository;
  final RescueRosterCodec _codec;
  final Random _random;
  final DateTime Function() _now;
  RescueTeamRoster? _activeRoster;
  bool _disposed = false;
  bool loading = true;

  RescueTeamRoster? get activeRoster => _activeRoster;
  List<RescueRosterMember> get members =>
      _activeRoster?.members ?? const <RescueRosterMember>[];
  bool get canEdit {
    final roster = _activeRoster;
    final localKey = mesh.signingPublicKey;
    return roster != null &&
        localKey != null &&
        roster.leaderPeerId == mesh.peerId.toLowerCase() &&
        _sameBytes(roster.leader.signingPublicKey, localKey);
  }

  Future<void> initialize() async {
    try {
      _activeRoster = await _repository.loadActiveRoster();
      await _platform.importRescueRosterPins(members);
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<RescueTeamRoster> createRoster({
    required String teamName,
    required String leaderCallsign,
    Iterable<RescueRosterMember> members = const [],
  }) async {
    validateTeamName(teamName);
    validateCallsign(leaderCallsign);
    final localKey = mesh.signingPublicKey;
    if (mesh.peerId.isEmpty || localKey?.length != 32) {
      throw StateError('Local signing identity is not available');
    }
    final otherMembers = members.toList(growable: false);
    if (otherMembers.any((member) => member.role == RescueRosterRole.leader)) {
      throw const FormatException(
        'Only the local identity can lead the roster',
      );
    }
    final unsigned = RescueTeamRoster(
      teamId: _randomHex(16),
      name: teamName.trim(),
      createdAt: _now().toUtc(),
      leaderPeerId: mesh.peerId.toLowerCase(),
      members: [
        RescueRosterMember(
          peerId: mesh.peerId.toLowerCase(),
          callsign: leaderCallsign.trim(),
          role: RescueRosterRole.leader,
          signingPublicKey: Uint8List.fromList(localKey!),
        ),
        ...otherMembers,
      ],
      signature: Uint8List(0),
    );
    final signed = await _codec.sign(unsigned, mesh.signPayload);
    await _activate(signed);
    return signed;
  }

  Future<RescueTeamRoster> importRoster(String encoded) async {
    final roster = await _codec.decodeAndVerify(
      encoded,
      verify: (peerId, signingPublicKey, payload, signature) =>
          _platform.verifySignatureWithPublicKey(
            signingPublicKey: signingPublicKey,
            data: payload,
            signature: signature,
          ),
    );
    if (roster.createdAt.toUtc().isAfter(
      _now().toUtc().add(maximumFutureSkew),
    )) {
      throw const FormatException('Rescue roster timestamp is too far ahead');
    }
    await _activate(roster);
    return roster;
  }

  Future<RescueTeamRoster> addMember({
    required String peerId,
    required String callsign,
    required RescueRosterRole role,
    required Uint8List signingPublicKey,
  }) {
    validateCallsign(callsign);
    if (role == RescueRosterRole.leader) {
      throw const FormatException('A rescue roster can have only one leader');
    }
    return _resignWithMembers([
      ...members,
      RescueRosterMember(
        peerId: peerId.trim().toLowerCase(),
        callsign: callsign.trim(),
        role: role,
        signingPublicKey: Uint8List.fromList(signingPublicKey),
      ),
    ]);
  }

  Future<RescueTeamRoster> removeMember(String peerId) {
    final normalized = peerId.trim().toLowerCase();
    final roster = _activeRoster;
    if (roster == null || normalized == roster.leaderPeerId) {
      throw StateError('The rescue roster leader cannot be removed');
    }
    final updated = members
        .where((member) => member.peerId != normalized)
        .toList(growable: false);
    if (updated.length == members.length) {
      throw StateError('Rescue roster member not found');
    }
    return _resignWithMembers(updated);
  }

  String exportRoster() {
    final roster = _activeRoster;
    if (roster == null) throw StateError('No active rescue roster');
    return _codec.encode(roster);
  }

  RescueRosterMember? verifiedMember({
    required String peerId,
    required Uint8List? signingPublicKey,
  }) {
    if (signingPublicKey == null) return null;
    final normalizedPeerId = peerId.trim().toLowerCase();
    for (final member in members) {
      if (member.peerId == normalizedPeerId &&
          _sameBytes(member.signingPublicKey, signingPublicKey)) {
        return member;
      }
    }
    return null;
  }

  RescueRosterMember? memberByPeerId(String peerId) {
    final normalized = peerId.trim().toLowerCase();
    for (final member in members) {
      if (member.peerId == normalized) return member;
    }
    return null;
  }

  static void validateTeamName(String value) {
    final clean = value.trim();
    if (clean.isEmpty ||
        utf8ByteLength(clean) > RescueRosterCodec.maximumTeamNameBytes) {
      throw const FormatException('Invalid rescue team name');
    }
  }

  static void validateCallsign(String value) {
    final clean = value.trim();
    if (clean.isEmpty ||
        utf8ByteLength(clean) > RescueRosterCodec.maximumCallsignBytes) {
      throw const FormatException('Invalid rescue callsign');
    }
  }

  Future<void> clearRoster() async {
    final previous = _activeRoster;
    await _platform.importRescueRosterPins(const []);
    try {
      await _repository.clear();
      _activeRoster = null;
      loading = false;
      if (!_disposed) notifyListeners();
    } catch (_) {
      await _platform.importRescueRosterPins(
        previous?.members ?? const <RescueRosterMember>[],
      );
      rethrow;
    }
  }

  Future<void> _activate(RescueTeamRoster roster) async {
    final previous = _activeRoster;
    await _platform.importRescueRosterPins(roster.members);
    try {
      await _repository.saveActiveRoster(roster);
      _activeRoster = roster;
      if (!_disposed) notifyListeners();
    } catch (_) {
      await _platform.importRescueRosterPins(
        previous?.members ?? const <RescueRosterMember>[],
      );
      rethrow;
    }
  }

  Future<RescueTeamRoster> _resignWithMembers(
    List<RescueRosterMember> updatedMembers,
  ) async {
    final roster = _activeRoster;
    if (roster == null || !canEdit) {
      throw StateError('Only the roster leader can change its members');
    }
    final maximumSeen = await _repository.maximumCreatedAt(roster.teamId);
    final now = _now().toUtc().millisecondsSinceEpoch;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      now > (maximumSeen ?? 0) ? now : maximumSeen! + 1,
      isUtc: true,
    );
    final unsigned = RescueTeamRoster(
      teamId: roster.teamId,
      name: roster.name,
      createdAt: createdAt,
      leaderPeerId: roster.leaderPeerId,
      members: updatedMembers,
      signature: Uint8List(0),
    );
    final signed = await _codec.sign(unsigned, mesh.signPayload);
    await _activate(signed);
    return signed;
  }

  String _randomHex(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_repository.close());
    super.dispose();
  }
}
