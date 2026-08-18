import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/mesh_models.dart';
import '../models/rescue_case_models.dart';
import '../models/rescue_roster_models.dart';
import '../services/rescue_case_repository.dart';
import 'mesh_controller.dart';
import 'rescue_roster_controller.dart';

class RescueCaseController extends ChangeNotifier {
  RescueCaseController({
    required this.mesh,
    required this.roster,
    RescueCaseRepository? repository,
  }) : _repository = repository ?? RescueCaseRepository();

  static const String channel = 'rescue-case';

  final MeshController mesh;
  final RescueRosterController roster;
  final RescueCaseRepository _repository;
  final Map<String, RescueCase> _casesByHash = {};
  final Set<String> _processedMessageIds = {};

  bool _processing = false;
  bool _processingRequested = false;
  bool _disposed = false;
  bool loading = true;
  String? lastError;

  List<RescueCase> get cases {
    final result = _casesByHash.values.toList(growable: false);
    result.sort(_compareCases);
    return List.unmodifiable(result);
  }

  RescueRosterMember? get localMember => roster.verifiedMember(
    peerId: mesh.peerId,
    signingPublicKey: mesh.signingPublicKey,
  );

  Future<void> initialize() async {
    try {
      await _repository.discardStaleLocalUpdates();
      _casesByHash
        ..clear()
        ..addEntries(
          (await _repository.loadCases()).map(
            (rescueCase) => MapEntry(rescueCase.caseHash, rescueCase),
          ),
        );
      mesh.addListener(_handleDependencyChanged);
      roster.addListener(_handleDependencyChanged);
      loading = false;
      await _processMessages();
    } catch (error) {
      loading = false;
      lastError = error.toString();
    }
    if (!_disposed) notifyListeners();
  }

  bool canAssignToMe(RescueCase rescueCase) =>
      localMember != null && rescueCase.state == RescueCaseState.newCase;

  bool canAdvanceTo(RescueCase rescueCase, RescueCaseState state) {
    final member = localMember;
    if (member == null || state.rank <= rescueCase.state.rank) return false;
    final assignee = rescueCase.assigneePeerId;
    if (assignee == null) return false;
    if (member.role != RescueRosterRole.leader && member.peerId != assignee) {
      return false;
    }
    return switch (state) {
      RescueCaseState.enRoute => rescueCase.state == RescueCaseState.assigned,
      RescueCaseState.attended => rescueCase.state == RescueCaseState.enRoute,
      RescueCaseState.closed => rescueCase.state == RescueCaseState.attended,
      RescueCaseState.newCase || RescueCaseState.assigned => false,
    };
  }

  Future<void> assignToMe(String caseHash) async {
    final member = localMember;
    if (member == null) throw StateError('Local responder is not verified');
    await _emitUpdate(
      caseHash: caseHash,
      state: RescueCaseState.assigned,
      assigneePeerId: member.peerId,
    );
  }

  Future<void> advance(String caseHash, RescueCaseState state) async {
    final rescueCase = _casesByHash[caseHash];
    if (rescueCase == null || !canAdvanceTo(rescueCase, state)) {
      throw StateError('Rescue case transition is not authorized');
    }
    await _emitUpdate(
      caseHash: caseHash,
      state: state,
      assigneePeerId: rescueCase.assigneePeerId!,
    );
  }

  Future<void> _emitUpdate({
    required String caseHash,
    required RescueCaseState state,
    required String assigneePeerId,
  }) async {
    final rescueCase = _casesByHash[caseHash];
    final member = localMember;
    if (rescueCase == null || member == null) {
      throw StateError('Rescue case or local responder is unavailable');
    }
    final update = RescueCaseUpdate(
      caseHash: caseHash,
      state: state,
      actorPeerId: member.peerId,
      assigneePeerId: assigneePeerId,
      timestamp: DateTime.now().toUtc(),
    );
    if (!_isAuthorized(member, update) ||
        (state == RescueCaseState.assigned
            ? !canAssignToMe(rescueCase)
            : !canAdvanceTo(rescueCase, state))) {
      throw StateError('Rescue case transition is not authorized');
    }
    final next = _resolve(rescueCase, update);
    if (next == null) throw StateError('Rescue case update is stale');
    final staged = await _repository.stageLocalUpdate(update);
    if (!staged) return;
    try {
      final messageId = await mesh.sendPublic(
        RescueCaseUpdateCodec.encode(update),
        channel: channel,
      );
      if (messageId == null || messageId.isEmpty) {
        throw StateError('Rescue case update was not transmitted');
      }
      await _repository.commitLocalUpdate(rescueCase: next, update: update);
      _casesByHash[caseHash] = next;
      lastError = null;
      if (!_disposed) notifyListeners();
    } catch (error) {
      await _repository.discardLocalUpdate(update);
      lastError = error.toString();
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  void _handleDependencyChanged() {
    unawaited(_processMessages());
  }

  Future<void> _processMessages() async {
    if (_processing) {
      _processingRequested = true;
      return;
    }
    _processing = true;
    try {
      do {
        _processingRequested = false;
        final messages = mesh.messages.toList(growable: false)
          ..sort((first, second) {
            final timestampOrder = first.timestamp.compareTo(second.timestamp);
            return timestampOrder != 0
                ? timestampOrder
                : first.id.compareTo(second.id);
          });
        for (final message in messages) {
          if (_processedMessageIds.contains(message.id)) continue;
          if (message.isSos) {
            await _ingestSos(message);
            _processedMessageIds.add(message.id);
            continue;
          }
          if (!message.content.startsWith(RescueCaseUpdateCodec.marker)) {
            continue;
          }
          final update = RescueCaseUpdateCodec.tryDecode(message.content);
          if (update != null && !message.isMine) {
            await _ingestUpdate(message, update);
          }
          _processedMessageIds.add(message.id);
        }
      } while (_processingRequested);
      lastError = null;
    } catch (error) {
      lastError = error.toString();
    } finally {
      _processing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _ingestSos(MeshMessage message) async {
    final hash = message.canonicalHash?.toLowerCase();
    if (hash == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return;
    final rescueCase = RescueCase(
      caseHash: hash,
      victimPeerId: message.senderPeerId.toLowerCase(),
      victim: message.sender.trim().isEmpty
          ? message.senderPeerId
          : message.sender,
      message: message.sosDescription.trim().isEmpty
          ? message.content
          : message.sosDescription.trim(),
      triage: message.sosTriage,
      latitude: message.sosLatitude,
      longitude: message.sosLongitude,
      state: RescueCaseState.newCase,
      createdAt: message.timestamp,
      updatedAt: message.timestamp,
      lastActorPeerId: message.senderPeerId.toLowerCase(),
    );
    final inserted = await _repository.insertSos(rescueCase);
    if (inserted) _casesByHash[hash] = rescueCase;
  }

  Future<void> _ingestUpdate(
    MeshMessage message,
    RescueCaseUpdate update,
  ) async {
    final senderPeerId = message.senderPeerId.toLowerCase();
    if (update.actorPeerId != senderPeerId) return;
    final livePeer = _livePeer(senderPeerId);
    if (livePeer == null) return;
    final member = roster.verifiedMember(
      peerId: senderPeerId,
      signingPublicKey: livePeer.signingPublicKey,
    );
    if (member == null || !_isAuthorized(member, update)) return;
    final current = _casesByHash[update.caseHash];
    if (current == null || update.timestamp.isBefore(current.createdAt)) return;
    final next = _resolve(current, update);
    if (next == null) return;
    final inserted = await _repository.applyIncomingUpdate(
      rescueCase: next,
      update: update,
    );
    if (inserted) _casesByHash[update.caseHash] = next;
  }

  MeshPeer? _livePeer(String peerId) {
    for (final peer in mesh.peers) {
      if (peer.id.toLowerCase() == peerId && peer.signingPublicKey != null) {
        return peer;
      }
    }
    return null;
  }

  static bool _isAuthorized(
    RescueRosterMember member,
    RescueCaseUpdate update,
  ) {
    return switch (update.state) {
      RescueCaseState.newCase => false,
      RescueCaseState.assigned => update.assigneePeerId == update.actorPeerId,
      RescueCaseState.enRoute ||
      RescueCaseState.attended ||
      RescueCaseState.closed =>
        update.assigneePeerId != null &&
            (update.actorPeerId == update.assigneePeerId ||
                member.role == RescueRosterRole.leader),
    };
  }

  static RescueCase? _resolve(RescueCase current, RescueCaseUpdate update) {
    if (update.state.rank < current.state.rank) return null;
    if (update.state.rank == current.state.rank) {
      final timestampOrder = update.timestamp.compareTo(current.updatedAt);
      if (timestampOrder < 0) return null;
      if (timestampOrder == 0) {
        final incoming =
            '${update.actorPeerId}|${update.assigneePeerId ?? '-'}';
        final existing =
            '${current.lastActorPeerId}|${current.assigneePeerId ?? '-'}';
        if (incoming.compareTo(existing) <= 0) return null;
      }
    }
    return current.copyWith(
      state: update.state,
      assigneePeerId: update.assigneePeerId,
      updatedAt: update.timestamp.toLocal(),
      lastActorPeerId: update.actorPeerId,
    );
  }

  static int _compareCases(RescueCase first, RescueCase second) {
    final firstClosed = first.state == RescueCaseState.closed;
    final secondClosed = second.state == RescueCaseState.closed;
    if (firstClosed != secondClosed) return firstClosed ? 1 : -1;
    final triageOrder = _triagePriority(
      second.triage,
    ).compareTo(_triagePriority(first.triage));
    if (triageOrder != 0) return triageOrder;
    final stateOrder = first.state.rank.compareTo(second.state.rank);
    if (stateOrder != 0) return stateOrder;
    final ageOrder = first.createdAt.compareTo(second.createdAt);
    if (ageOrder != 0) return ageOrder;
    return first.caseHash.compareTo(second.caseHash);
  }

  static int _triagePriority(SosTriage? triage) {
    if (triage == null) return 0;
    var score = 0;
    if (triage.injuryStatus == SosInjuryStatus.injured) score += 4;
    if (triage.trappedStatus == SosTrappedStatus.yes) score += 3;
    score += switch (triage.primaryNeed) {
      SosPrimaryNeed.medical => 3,
      SosPrimaryNeed.extraction => 2,
      SosPrimaryNeed.water => 1,
      SosPrimaryNeed.shelter => 1,
      SosPrimaryNeed.other => 0,
    };
    return score;
  }

  @override
  void dispose() {
    _disposed = true;
    mesh.removeListener(_handleDependencyChanged);
    roster.removeListener(_handleDependencyChanged);
    unawaited(_repository.close());
    super.dispose();
  }
}
