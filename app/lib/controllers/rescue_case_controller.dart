import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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
    DateTime Function()? now,
  }) : _repository = repository ?? RescueCaseRepository(),
       _now = now ?? DateTime.now;

  static const String channel = 'rescue-case';
  static const Duration maximumFutureSkew = Duration(minutes: 5);
  static const Duration packetTimestampTolerance = Duration(seconds: 1);
  static const int maximumProcessedMessageIds = 4096;
  static const String _caseHashDomain = 'hearthbit.rescue-case.v1';

  final MeshController mesh;
  final RescueRosterController roster;
  final RescueCaseRepository _repository;
  final DateTime Function() _now;
  final Map<String, RescueCase> _casesByHash = {};
  final Set<String> _processedMessageIds = {};
  final Map<String, int> _retryCounts = {};

  bool _processing = false;
  bool _processingRequested = false;
  bool _disposed = false;
  String? _loadedTeamId;
  bool loading = true;
  String? lastError;
  String? get activeTeamId => roster.activeRoster?.teamId;

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
      mesh.addListener(_handleDependencyChanged);
      roster.addListener(_handleDependencyChanged);
      await _reloadForActiveTeam();
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
      teamId: rescueCase.teamId,
      caseHash: caseHash,
      previousState: rescueCase.state,
      state: state,
      actorPeerId: member.peerId,
      assigneePeerId: assigneePeerId,
      timestamp: _now().toUtc(),
    );
    if (!_isAuthorized(member, update, rescueCase) ||
        (state == RescueCaseState.assigned
            ? !canAssignToMe(rescueCase)
            : !canAdvanceTo(rescueCase, state))) {
      throw StateError('Rescue case transition is not authorized');
    }
    final next = RescueCaseTransition.resolve(rescueCase, update);
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
      final committed = await _repository.commitLocalUpdate(update);
      _applyWriteResult(committed);
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

  Future<void> _reloadForActiveTeam() async {
    final teamId = roster.activeRoster?.teamId;
    if (teamId == _loadedTeamId) return;
    _loadedTeamId = teamId;
    _casesByHash.clear();
    if (teamId != null) {
      for (final rescueCase in await _repository.loadCases(teamId: teamId)) {
        _casesByHash[rescueCase.caseHash] = rescueCase;
      }
    }
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
        await _reloadForActiveTeam();
        final messages = mesh.messages.toList(growable: false)
          ..sort((first, second) {
            final timestampOrder = first.timestamp.compareTo(second.timestamp);
            return timestampOrder != 0
                ? timestampOrder
                : first.id.compareTo(second.id);
          });
        for (final message in messages) {
          final processingKey = _processingKey(message.id);
          if (processingKey != null &&
              _processedMessageIds.contains(processingKey)) {
            continue;
          }
          if (message.isSos) {
            final outcome = await _ingestSos(message);
            if (outcome != _IngestOutcome.retryLater && processingKey != null) {
              _rememberProcessed(processingKey);
            } else {
              _recordRetry(processingKey);
            }
            continue;
          }
          if (message.isPrivate ||
              message.external ||
              message.channel != channel ||
              !message.content.startsWith(RescueCaseUpdateCodec.marker)) {
            continue;
          }
          final update = RescueCaseUpdateCodec.tryDecode(message.content);
          var outcome = _IngestOutcome.permanent;
          if (update != null && !message.isMine) {
            outcome = await _ingestUpdate(message, update);
          }
          if (outcome != _IngestOutcome.retryLater && processingKey != null) {
            _rememberProcessed(processingKey);
          } else {
            _recordRetry(processingKey);
          }
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

  Future<_IngestOutcome> _ingestSos(MeshMessage message) async {
    if (message.isPrivate || message.external || message.channel != 'sos') {
      return _IngestOutcome.permanent;
    }
    final activeRoster = roster.activeRoster;
    if (activeRoster == null) {
      return _IngestOutcome.retryLater;
    }
    final sender = message.senderPeerId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(sender) || message.id.isEmpty) {
      return _IngestOutcome.permanent;
    }
    final hash = stableCaseHash(senderPeerId: sender, messageId: message.id);
    final canonicalHash = message.canonicalHash?.toLowerCase();
    final rescueCase = RescueCase(
      teamId: activeRoster.teamId,
      caseHash: hash,
      canonicalHash:
          canonicalHash != null &&
              RegExp(r'^[0-9a-f]{64}$').hasMatch(canonicalHash)
          ? canonicalHash
          : null,
      victimPeerId: sender,
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
      lastActorPeerId: sender,
    );
    final inserted = await _repository.insertSos(rescueCase);
    _applyWriteResult(inserted);
    return _IngestOutcome.accepted;
  }

  Future<_IngestOutcome> _ingestUpdate(
    MeshMessage message,
    RescueCaseUpdate update,
  ) async {
    final activeRoster = roster.activeRoster;
    if (activeRoster == null) {
      return _IngestOutcome.retryLater;
    }
    final senderPeerId = message.senderPeerId.toLowerCase();
    if (update.teamId != activeRoster.teamId ||
        update.actorPeerId != senderPeerId) {
      return _IngestOutcome.permanent;
    }
    final member = roster.memberByPeerId(senderPeerId);
    if (member == null) return _IngestOutcome.permanent;
    final current = _casesByHash[update.caseHash];
    if (current == null) return _IngestOutcome.retryLater;
    final packetDelta = update.timestamp
        .toUtc()
        .difference(message.timestamp.toUtc())
        .abs();
    if (packetDelta > packetTimestampTolerance ||
        update.timestamp.isBefore(current.createdAt) ||
        update.timestamp.isAfter(_now().toUtc().add(maximumFutureSkew)) ||
        !_isAuthorized(member, update, current)) {
      return _IngestOutcome.permanent;
    }
    final applied = await _repository.applyIncomingUpdate(update);
    _applyWriteResult(applied);
    return _IngestOutcome.accepted;
  }

  static bool _isAuthorized(
    RescueRosterMember member,
    RescueCaseUpdate update,
    RescueCase current,
  ) {
    return switch (update.state) {
      RescueCaseState.newCase => false,
      RescueCaseState.assigned =>
        update.previousState == RescueCaseState.newCase &&
            update.assigneePeerId == update.actorPeerId,
      RescueCaseState.enRoute ||
      RescueCaseState.attended ||
      RescueCaseState.closed =>
        update.previousState.rank + 1 == update.state.rank &&
            update.assigneePeerId == current.assigneePeerId &&
            (update.actorPeerId == update.assigneePeerId ||
                member.role == RescueRosterRole.leader),
    };
  }

  static String stableCaseHash({
    required String senderPeerId,
    required String messageId,
  }) {
    final sender = senderPeerId.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(sender) || messageId.isEmpty) {
      throw const FormatException('Invalid stable rescue case identity');
    }
    return sha256
        .convert(utf8.encode('$_caseHashDomain\u0000$sender\u0000$messageId'))
        .toString();
  }

  String? _processingKey(String messageId) {
    final teamId = roster.activeRoster?.teamId;
    return teamId == null ? null : '$teamId|$messageId';
  }

  void _rememberProcessed(String processingKey) {
    _retryCounts.remove(processingKey);
    _processedMessageIds.add(processingKey);
    if (_processedMessageIds.length > maximumProcessedMessageIds) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }
  }

  void _recordRetry(String? processingKey) {
    if (processingKey == null) return;
    _retryCounts[processingKey] = (_retryCounts[processingKey] ?? 0) + 1;
    if (_retryCounts.length > maximumProcessedMessageIds) {
      _retryCounts.remove(_retryCounts.keys.first);
    }
  }

  void _applyWriteResult(RescueCaseWriteResult result) {
    for (final caseHash in result.prunedCaseHashes) {
      _casesByHash.remove(caseHash);
    }
    final rescueCase = result.rescueCase;
    if (rescueCase != null && rescueCase.teamId == _loadedTeamId) {
      _casesByHash[rescueCase.caseHash] = rescueCase;
    }
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

enum _IngestOutcome { accepted, permanent, retryLater }
