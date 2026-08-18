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
    required this.caseHash,
    required this.victimPeerId,
    required this.victim,
    required this.message,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.lastActorPeerId,
    this.triage,
    this.latitude,
    this.longitude,
    this.assigneePeerId,
  });

  static const Object _unchanged = Object();

  final String caseHash;
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
      caseHash: caseHash,
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
    required this.caseHash,
    required this.state,
    required this.actorPeerId,
    required this.assigneePeerId,
    required this.timestamp,
  });

  final String caseHash;
  final RescueCaseState state;
  final String actorPeerId;
  final String? assigneePeerId;
  final DateTime timestamp;

  String get eventId =>
      '$caseHash|${state.wireCode}|$actorPeerId|'
      '${assigneePeerId ?? '-'}|${timestamp.toUtc().millisecondsSinceEpoch}';
}

abstract final class RescueCaseUpdateCodec {
  static const String marker = '[HB-CASE|';
  static const int version = 1;
  static const int maximumEncodedBytes = 192;
  static const int maximumTimestampMilliseconds = 8640000000000000;
  static final RegExp _hash = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _peerId = RegExp(r'^[0-9a-f]{16}$');

  static String encode(RescueCaseUpdate update) {
    _validate(update);
    final encoded =
        '$marker$version|${update.caseHash}|${update.state.wireCode}|'
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
    if (fields.length != 6 || fields[0] != '$version') return null;
    final state = RescueCaseState.fromWireCode(fields[2]);
    final timestamp = int.tryParse(fields[5]);
    final assignee = fields[4] == '-' ? null : fields[4];
    if (state == null ||
        timestamp == null ||
        timestamp <= 0 ||
        timestamp > maximumTimestampMilliseconds) {
      return null;
    }
    final update = RescueCaseUpdate(
      caseHash: fields[1],
      state: state,
      actorPeerId: fields[3],
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
    if (!_hash.hasMatch(update.caseHash) ||
        !_peerId.hasMatch(update.actorPeerId) ||
        (update.assigneePeerId != null &&
            !_peerId.hasMatch(update.assigneePeerId!)) ||
        timestamp <= 0 ||
        timestamp > maximumTimestampMilliseconds) {
      throw const FormatException('Invalid rescue case update');
    }
    switch (update.state) {
      case RescueCaseState.newCase:
        if (update.assigneePeerId != null) {
          throw const FormatException('A new case cannot have an assignee');
        }
      case RescueCaseState.assigned ||
          RescueCaseState.enRoute ||
          RescueCaseState.attended ||
          RescueCaseState.closed:
        if (update.assigneePeerId == null) {
          throw const FormatException('Operational states require an assignee');
        }
    }
  }
}
