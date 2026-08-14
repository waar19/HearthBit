import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/family_models.dart';
import '../models/mesh_models.dart';
import '../services/family_notification_service.dart';
import '../services/family_qr_codec.dart';
import '../services/family_repository.dart';
import 'mesh_controller.dart';

class FamilyTrustClassifier {
  const FamilyTrustClassifier._();

  static FamilyMember? verifiedMember({
    required String peerId,
    required Iterable<MeshPeer> onlinePeers,
    required Iterable<FamilyMember> members,
  }) {
    MeshPeer? onlinePeer;
    for (final peer in onlinePeers) {
      if (peer.id == peerId) {
        onlinePeer = peer;
        break;
      }
    }
    final liveKey = onlinePeer?.signingPublicKey;
    if (liveKey == null) return null;
    for (final member in members) {
      if (_sameBytes(member.signingPublicKey, liveKey)) return member;
    }
    return null;
  }

  static bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }
}

class FamilyController extends ChangeNotifier {
  FamilyController({
    required this.mesh,
    FamilyRepository? repository,
    FamilyQrCodec? qrCodec,
    FamilyNotificationSink? notifications,
  }) : _repository = repository ?? FamilyRepository(),
       _qrCodec = qrCodec ?? FamilyQrCodec(),
       _notifications = notifications ?? FamilyNotificationService();

  final MeshController mesh;
  final FamilyRepository _repository;
  final FamilyQrCodec _qrCodec;
  final FamilyNotificationSink _notifications;
  final Set<String> _observedMessageIds = {};
  List<FamilyGroup> _groups = const [];
  List<FamilyMember> _members = const [];
  Uint8List? _lastObservedLocalKey;
  String? _localQrToken;
  Future<String>? _localQrFuture;
  bool _processingMeshUpdate = false;
  bool _meshUpdatePending = false;
  bool _disposed = false;

  List<FamilyGroup> get groups => _groups;
  List<FamilyMember> get members => _members;
  bool get canShowIdentityQr =>
      mesh.peerId.isNotEmpty &&
      mesh.nickname.isNotEmpty &&
      mesh.signingPublicKey?.length == FamilyQrCodec.publicKeyBytes;
  String? get localFingerprint {
    final key = mesh.signingPublicKey;
    return key == null ? null : FamilyQrCodec.fingerprint(key);
  }

  Future<void> initialize() async {
    await _reload();
    _observedMessageIds.addAll(mesh.messages.map((message) => message.id));
    mesh.addListener(_scheduleMeshUpdate);
    await _reconcileIdentity();
  }

  Future<FamilyGroup> createGroup(String name) async {
    final group = await _repository.createGroup(name);
    await _reload();
    await _notifications.requestPermission();
    return group;
  }

  Future<void> renameGroup(int groupId, String name) async {
    await _repository.renameGroup(groupId, name);
    await _reload();
  }

  Future<void> deleteGroup(int groupId) async {
    await _repository.deleteGroup(groupId);
    await _reload();
  }

  Future<void> addVerifiedMember(int groupId, FamilyQrIdentity identity) async {
    await _repository.addMember(
      groupId: groupId,
      peerId: identity.peerId,
      nickname: identity.nickname,
      signingPublicKey: identity.signingPublicKey,
      fingerprint: identity.fingerprint,
    );
    await _reload();
    await _notifications.requestPermission();
  }

  Future<void> deleteMember(int memberId) async {
    await _repository.deleteMember(memberId);
    await _reload();
  }

  Future<void> panicWipe() async {
    await _repository.destroy();
    _groups = const [];
    _members = const [];
    _observedMessageIds.clear();
    _lastObservedLocalKey = null;
    _localQrToken = null;
    _localQrFuture = null;
    notifyListeners();
  }

  Future<String> buildLocalQr() {
    final key = mesh.signingPublicKey;
    if (key == null || !canShowIdentityQr) {
      throw StateError('Local signing identity is not available');
    }
    final token = '${mesh.peerId}|${mesh.nickname}|${key.join(',')}';
    if (_localQrToken == token && _localQrFuture != null) {
      return _localQrFuture!;
    }
    _localQrToken = token;
    return _localQrFuture = _qrCodec.encode(
      peerId: mesh.peerId,
      nickname: mesh.nickname,
      signingPublicKey: key,
      sign: mesh.signPayload,
    );
  }

  Future<FamilyQrIdentity> verifyQr(String encoded) =>
      _qrCodec.decodeAndVerify(encoded);

  FamilyMember? verifiedMemberForMessage(MeshMessage message) {
    if (message.isMine) return null;
    return verifiedMemberForPeerId(message.senderPeerId);
  }

  FamilyMember? verifiedMemberForPeerId(String peerId) {
    return FamilyTrustClassifier.verifiedMember(
      peerId: peerId,
      onlinePeers: mesh.peers,
      members: _members,
    );
  }

  bool isVerifiedFamilyMessage(MeshMessage message) =>
      verifiedMemberForMessage(message) != null;

  void _scheduleMeshUpdate() {
    _meshUpdatePending = true;
    if (_processingMeshUpdate) return;
    unawaited(_processMeshUpdates());
  }

  Future<void> _processMeshUpdates() async {
    _processingMeshUpdate = true;
    try {
      while (_meshUpdatePending && !_disposed) {
        _meshUpdatePending = false;
        await _reconcileIdentity();
        await _notifyForNewFamilyEmergencies();
      }
    } finally {
      _processingMeshUpdate = false;
    }
  }

  Future<void> _reconcileIdentity() async {
    final current = mesh.signingPublicKey;
    if (current == null) {
      if (_lastObservedLocalKey != null) {
        await _repository.clearTrust();
        _lastObservedLocalKey = null;
        await _reload();
      }
      return;
    }
    final stored = await _repository.readOwnerSigningKey();
    if (stored == null) {
      await _repository.bindOwnerSigningKey(current);
    } else if (!_sameBytes(stored, current)) {
      await _repository.clearTrust();
      await _repository.bindOwnerSigningKey(current);
      await _reload();
    }
    _lastObservedLocalKey = Uint8List.fromList(current);
  }

  Future<void> _notifyForNewFamilyEmergencies() async {
    for (final message in mesh.messages) {
      if (!_observedMessageIds.add(message.id)) continue;
      if (!isFamilyEmergency(message) ||
          verifiedMemberForMessage(message) == null) {
        continue;
      }
      final status = message.isSos
          ? 'SOS'
          : message.checkIn?.status.wireCode ?? 'CHECK-IN';
      await _notifications.show(
        messageId: message.id,
        nickname: message.sender,
        status: status,
      );
    }
  }

  static bool isFamilyEmergency(MeshMessage message) =>
      !message.isDrill && (message.isSos || message.isCheckIn);

  Future<void> _reload() async {
    _groups = await _repository.listGroups();
    _members = await _repository.listMembers();
    if (!_disposed) notifyListeners();
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
    mesh.removeListener(_scheduleMeshUpdate);
    unawaited(_repository.close());
    super.dispose();
  }
}
