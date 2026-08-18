import 'dart:convert';

import 'mesh_models.dart';

enum RescueCaseState {
  newCase('N', 0),
  assigned('A', 1),
  enRoute('E', 2),
  attended('T', 3),
  closed('C', 4);

  const RescueCaseState(this.wireCode, this.rank);

  final String wireCode;
  final int rank;

  static RescueCaseState? fromWireCode(String value) {
    for (final state in values) {
      if (state.wireCode == value) return state;
    }
    return null;
  }
}

class RescueCase {
  const RescueCase({
    required this.teamId,
    required this.caseHash,
    required this.victimPeerId,
    required this.victim,
    required this.message,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.lastActorPeerId,
    this.canonicalHash,
    this.triage,
    this.latitude,
    this.longitude,
    this.assigneePeerId,
  });

  static const Object _unchanged = Object();

  final String teamId;
  final String caseHash;
  final String? canonicalHash;
  final String victimPeerId;
  final String victim;
  final String message;
  final SosTriage? triage;
  final double? latitude;
  final double? longitude;
  final RescueCaseState state;
  final String? assigneePeerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastActorPeerId;

  RescueCase copyWith({
    RescueCaseState? state,
    Object? assigneePeerId = _unchanged,
    DateTime? updatedAt,
    String? lastActorPeerId,
  }) {
    return RescueCase(
      teamId: teamId,
      caseHash: caseHash,
      canonicalHash: canonicalHash,
      victimPeerId: victimPeerId,
      victim: victim,
      message: message,
      triage: triage,
      latitude: latitude,
      longitude: longitude,
      state: state ?? this.state,
      assigneePeerId: identical(assigneePeerId, _unchanged)
          ? this.assigneePeerId
          : assigneePeerId as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastActorPeerId: lastActorPeerId ?? this.lastActorPeerId,
    );
  }
}

class RescueCaseUpdate {
  const RescueCaseUpdate({
    required this.teamId,
    required this.caseHash,
    required this.previousState,
    required this.state,
    required this.actorPeerId,
    required this.assigneePeerId,
    required this.timestamp,
  });

  final String teamId;
  final String caseHash;
  final RescueCaseState previousState;
  final RescueCaseState state;
  final String actorPeerId;
  final String? assigneePeerId;
  final DateTime timestamp;

  String get eventId =>
      '$teamId|$caseHash|${previousState.wireCode}|${state.wireCode}|$actorPeerId|'
      '${assigneePeerId ?? '-'}|${timestamp.toUtc().millisecondsSinceEpoch}';
}

abstract final class RescueCaseUpdateCodec {
  static const String marker = '[HB-CASE|';
  static const int version = 2;
  static const int maximumEncodedBytes = 256;
  static const int maximumTimestampMilliseconds = 8640000000000000;
  static final RegExp _hash = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _peerId = RegExp(r'^[0-9a-f]{16}$');

  static String encode(RescueCaseUpdate update) {
    _validate(update);
    final encoded =
        '$marker$version|${update.teamId}|${update.caseHash}|'
        '${update.previousState.wireCode}|${update.state.wireCode}|'
        '${update.actorPeerId}|${update.assigneePeerId ?? '-'}|'
        '${update.timestamp.toUtc().millisecondsSinceEpoch}]';
    if (utf8.encode(encoded).length > maximumEncodedBytes) {
      throw const FormatException('Rescue case update is too large');
    }
    return encoded;
  }

  static RescueCaseUpdate? tryDecode(String value) {
    if (!value.startsWith(marker) ||
        !value.endsWith(']') ||
        utf8.encode(value).length > maximumEncodedBytes) {
      return null;
    }
    final fields = value.substring(marker.length, value.length - 1).split('|');
    if (fields.length != 8 || fields[0] != '$version') return null;
    final previousState = RescueCaseState.fromWireCode(fields[3]);
    final state = RescueCaseState.fromWireCode(fields[4]);
    final timestamp = int.tryParse(fields[7]);
    final assignee = fields[6] == '-' ? null : fields[6];
    if (previousState == null ||
        state == null ||
        timestamp == null ||
        timestamp <= 0 ||
        timestamp > maximumTimestampMilliseconds) {
      return null;
    }
    final update = RescueCaseUpdate(
      teamId: fields[1],
      caseHash: fields[2],
      previousState: previousState,
      state: state,
      actorPeerId: fields[5],
      assigneePeerId: assignee,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
    );
    try {
      _validate(update);
      return update;
    } on FormatException {
      return null;
    }
  }

  static void _validate(RescueCaseUpdate update) {
    final timestamp = update.timestamp.toUtc().millisecondsSinceEpoch;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(update.teamId) ||
        !_hash.hasMatch(update.caseHash) ||
        !_peerId.hasMatch(update.actorPeerId) ||
        (update.assigneePeerId != null &&
            !_peerId.hasMatch(update.assigneePeerId!)) ||
        timestamp <= 0 ||
        timestamp > maximumTimestampMilliseconds) {
      throw const FormatException('Invalid rescue case update');
    }
    if (update.state == RescueCaseState.newCase ||
        update.state.rank != update.previousState.rank + 1 ||
        update.assigneePeerId == null) {
      throw const FormatException('Invalid rescue case transition');
    }
  }
}

abstract final class RescueCaseTransition {
  static const Duration assignmentConflictWindow = Duration(seconds: 30);

  /// Solo las asignaciones que observaron `new` dentro de la misma ventana
  /// compiten por el menor peer ID. Fuera de ella, `assigned` es final.
  static RescueCase? resolve(RescueCase current, RescueCaseUpdate update) {
    if (current.teamId != update.teamId ||
        current.caseHash != update.caseHash ||
        update.timestamp.isBefore(current.createdAt)) {
      return null;
    }
    if (update.previousState == RescueCaseState.newCase &&
        update.state == RescueCaseState.assigned &&
        current.state == RescueCaseState.assigned) {
      final currentAssignee = current.assigneePeerId;
      final assignmentDelta = update.timestamp
          .toUtc()
          .difference(current.updatedAt.toUtc())
          .abs();
      if (assignmentDelta > assignmentConflictWindow ||
          currentAssignee == null ||
          update.assigneePeerId!.compareTo(currentAssignee) >= 0) {
        return null;
      }
    } else if (current.state != update.previousState) {
      return null;
    }
    if (update.state == RescueCaseState.assigned) {
      if (update.actorPeerId != update.assigneePeerId) return null;
    } else if (current.assigneePeerId == null ||
        update.assigneePeerId != current.assigneePeerId) {
      return null;
    }
    final updatedAt = update.timestamp.isAfter(current.updatedAt)
        ? update.timestamp
        : current.updatedAt;
    return current.copyWith(
      state: update.state,
      assigneePeerId: update.assigneePeerId,
      updatedAt: updatedAt.toLocal(),
      lastActorPeerId: update.actorPeerId,
    );
  }
}
