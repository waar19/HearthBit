import 'dart:convert';
import 'dart:typed_data';

import 'voice_note.dart';

enum MeshNodeRole {
  phoneRelay('PHONE_RELAY'),
  phoneBeacon('PHONE_BEACON'),
  infraRelay('INFRA_RELAY'),
  infraDataAnchor('INFRA_DATA_ANCHOR');

  const MeshNodeRole(this.wireName);

  final String wireName;

  static MeshNodeRole fromWire(Object? value) {
    return switch (value) {
      'PHONE_BEACON' => MeshNodeRole.phoneBeacon,
      'INFRA_RELAY' => MeshNodeRole.infraRelay,
      'INFRA_DATA_ANCHOR' => MeshNodeRole.infraDataAnchor,
      _ => MeshNodeRole.phoneRelay,
    };
  }

  bool get canChat => this == MeshNodeRole.phoneRelay;
}

bool isDefaultMeshNickname(String value) =>
    RegExp(r'^SOS-[0-9a-fA-F]{4}$').hasMatch(value.trim());

enum MeshPowerProfile {
  performance('performance'),
  balanced('balanced'),
  powerSaver('powerSaver'),
  critical('critical'),
  survival('survival');

  const MeshPowerProfile(this.wireName);

  final String wireName;

  static MeshPowerProfile fromWire(Object? value) {
    return switch (value) {
      'performance' => MeshPowerProfile.performance,
      'powerSaver' => MeshPowerProfile.powerSaver,
      'critical' => MeshPowerProfile.critical,
      'survival' => MeshPowerProfile.survival,
      _ => MeshPowerProfile.balanced,
    };
  }

  bool get savesPower =>
      this != MeshPowerProfile.performance && this != MeshPowerProfile.balanced;
}

class MeshOperationalCounters {
  const MeshOperationalCounters({
    this.openEmergencyRateLimitedKnown = 0,
    this.openEmergencyRateLimitedUnknown = 0,
    this.relayDampingSuppressed = 0,
    this.relayDampingScheduled = 0,
    this.relayDampingExpired = 0,
    this.trustStoreEvictions = 0,
    this.trustConflicts = 0,
  });

  final int openEmergencyRateLimitedKnown;
  final int openEmergencyRateLimitedUnknown;
  final int relayDampingSuppressed;
  final int relayDampingScheduled;
  final int relayDampingExpired;
  final int trustStoreEvictions;
  final int trustConflicts;

  @Deprecated('Use openEmergencyRateLimitedKnown')
  int get openSosRateLimitedKnown => openEmergencyRateLimitedKnown;

  @Deprecated('Use openEmergencyRateLimitedUnknown')
  int get openSosRateLimitedUnknown => openEmergencyRateLimitedUnknown;

  factory MeshOperationalCounters.fromNative(Map<Object?, Object?> value) {
    int counter(String key, {String? legacyKey}) {
      final parsed =
          (value[key] as num?)?.toInt() ??
          (legacyKey == null ? null : (value[legacyKey] as num?)?.toInt()) ??
          0;
      return parsed < 0 ? 0 : parsed;
    }

    return MeshOperationalCounters(
      openEmergencyRateLimitedKnown: counter(
        'openEmergencyRateLimitedKnown',
        legacyKey: 'openSosRateLimitedKnown',
      ),
      openEmergencyRateLimitedUnknown: counter(
        'openEmergencyRateLimitedUnknown',
        legacyKey: 'openSosRateLimitedUnknown',
      ),
      relayDampingSuppressed: counter('relayDampingSuppressed'),
      relayDampingScheduled: counter('relayDampingScheduled'),
      relayDampingExpired: counter('relayDampingExpired'),
      trustStoreEvictions: counter('trustStoreEvictions'),
      trustConflicts: counter('trustConflicts'),
    );
  }

  Map<String, int> toJson() => {
    'openEmergencyRateLimitedKnown': openEmergencyRateLimitedKnown,
    'openEmergencyRateLimitedUnknown': openEmergencyRateLimitedUnknown,
    'relayDampingSuppressed': relayDampingSuppressed,
    'relayDampingScheduled': relayDampingScheduled,
    'relayDampingExpired': relayDampingExpired,
    'trustStoreEvictions': trustStoreEvictions,
    'trustConflicts': trustConflicts,
  };
}

enum CheckInStatus {
  ok('OK'),
  needsHelp('HELP'),
  injured('INJURED');

  const CheckInStatus(this.wireCode);

  final String wireCode;

  static CheckInStatus? fromWire(String value) {
    for (final status in values) {
      if (status.wireCode == value) return status;
    }
    return null;
  }
}

enum SosLocationPrecision {
  exact,
  approximate,
  none;

  String get wireName => name;
}

enum SosInjuryStatus { unknown, none, injured }

enum SosTrappedStatus { unknown, no, yes }

enum SosPrimaryNeed { medical, water, extraction, shelter, other }

class SosTriage {
  const SosTriage({
    this.peopleCount,
    this.injuryStatus = SosInjuryStatus.unknown,
    this.injuredCount,
    this.trappedStatus = SosTrappedStatus.unknown,
    required this.primaryNeed,
  }) : assert(
         peopleCount == null ||
             (peopleCount >= minimumCount && peopleCount <= maximumCount),
       ),
       assert(
         injuredCount == null ||
             (injuredCount >= minimumCount && injuredCount <= maximumCount),
       ),
       assert(injuredCount == null || injuryStatus == SosInjuryStatus.injured);

  static const int currentVersion = 1;
  static const int minimumCount = 1;
  static const int maximumCount = 99;
  static const String marker = 'T1';
  static const Object _unchanged = Object();

  final int? peopleCount;
  final SosInjuryStatus injuryStatus;
  final int? injuredCount;
  final SosTrappedStatus trappedStatus;
  final SosPrimaryNeed primaryNeed;

  String encode() {
    final injury = switch (injuryStatus) {
      SosInjuryStatus.unknown => '?',
      SosInjuryStatus.none => 'N',
      SosInjuryStatus.injured => injuredCount?.toString() ?? 'Y',
    };
    final trapped = switch (trappedStatus) {
      SosTrappedStatus.unknown => '?',
      SosTrappedStatus.no => 'N',
      SosTrappedStatus.yes => 'Y',
    };
    final need = switch (primaryNeed) {
      SosPrimaryNeed.medical => 'M',
      SosPrimaryNeed.water => 'W',
      SosPrimaryNeed.extraction => 'E',
      SosPrimaryNeed.shelter => 'S',
      SosPrimaryNeed.other => 'O',
    };
    return '$marker|${peopleCount ?? '?'}|$injury|$trapped|$need';
  }

  static SosTriage? tryDecode(String value) {
    final fields = value.split('|');
    if (fields.length != 5 || fields[0] != marker) return null;
    final people = _parseCount(fields[1]);
    if (fields[1] != '?' && people == null) return null;

    final injuryToken = fields[2];
    final injuryCount = _parseCount(injuryToken);
    final injury = switch (injuryToken) {
      '?' => SosInjuryStatus.unknown,
      'N' => SosInjuryStatus.none,
      'Y' => SosInjuryStatus.injured,
      _ when injuryCount != null => SosInjuryStatus.injured,
      _ => null,
    };
    final trapped = switch (fields[3]) {
      '?' => SosTrappedStatus.unknown,
      'N' => SosTrappedStatus.no,
      'Y' => SosTrappedStatus.yes,
      _ => null,
    };
    final need = switch (fields[4]) {
      'M' => SosPrimaryNeed.medical,
      'W' => SosPrimaryNeed.water,
      'E' => SosPrimaryNeed.extraction,
      'S' => SosPrimaryNeed.shelter,
      'O' => SosPrimaryNeed.other,
      _ => null,
    };
    if (injury == null || trapped == null || need == null) return null;
    return SosTriage(
      peopleCount: people,
      injuryStatus: injury,
      injuredCount: injuryCount,
      trappedStatus: trapped,
      primaryNeed: need,
    );
  }

  static int? _parseCount(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < minimumCount || parsed > maximumCount) {
      return null;
    }
    return parsed;
  }

  SosTriage copyWith({
    Object? peopleCount = _unchanged,
    SosInjuryStatus? injuryStatus,
    Object? injuredCount = _unchanged,
    SosTrappedStatus? trappedStatus,
    SosPrimaryNeed? primaryNeed,
  }) {
    final nextInjuryStatus = injuryStatus ?? this.injuryStatus;
    final nextInjuredCount = identical(injuredCount, _unchanged)
        ? this.injuredCount
        : injuredCount as int?;
    return SosTriage(
      peopleCount: identical(peopleCount, _unchanged)
          ? this.peopleCount
          : peopleCount as int?,
      injuryStatus: nextInjuryStatus,
      injuredCount: nextInjuryStatus == SosInjuryStatus.injured
          ? nextInjuredCount
          : null,
      trappedStatus: trappedStatus ?? this.trappedStatus,
      primaryNeed: primaryNeed ?? this.primaryNeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SosTriage &&
          peopleCount == other.peopleCount &&
          injuryStatus == other.injuryStatus &&
          injuredCount == other.injuredCount &&
          trappedStatus == other.trappedStatus &&
          primaryNeed == other.primaryNeed;

  @override
  int get hashCode => Object.hash(
    peopleCount,
    injuryStatus,
    injuredCount,
    trappedStatus,
    primaryNeed,
  );
}

class SosMessageCodec {
  SosMessageCodec._();

  static final RegExp _versionMarker = RegExp(r'^T[0-9]+$');

  static String encode({
    required String description,
    double? latitude,
    double? longitude,
    SosTriage? triage,
  }) {
    final readable = triage == null
        ? description
        : description.replaceAll('|', '/');
    final coordinates = latitude == null || longitude == null
        ? '||'
        : '|$latitude|$longitude';
    return 'SOS|$readable$coordinates'
        '${triage == null ? '' : '|${triage.encode()}'}';
  }

  static String description(String content) {
    if (!content.startsWith('SOS|')) return content;
    final parts = content.split('|');
    if (_usesVersionedLayout(parts)) return parts[1];
    if (parts.length < 4) return parts.skip(1).join('|');
    return parts.sublist(1, parts.length - 2).join('|');
  }

  static double? latitude(String content) => _coordinate(content, true);

  static double? longitude(String content) => _coordinate(content, false);

  static SosTriage? triage(String content) {
    if (!content.startsWith('SOS|')) return null;
    final parts = content.split('|');
    if (parts.length != 9 || parts[4] != SosTriage.marker) return null;
    return SosTriage.tryDecode(parts.sublist(4).join('|'));
  }

  static double? _coordinate(String content, bool latitude) {
    if (!content.startsWith('SOS|')) return null;
    final parts = content.split('|');
    if (parts.length < 4) return null;
    final fixedLayout = _usesVersionedLayout(parts);
    final index = fixedLayout
        ? (latitude ? 2 : 3)
        : parts.length - (latitude ? 2 : 1);
    final value = double.tryParse(parts[index]);
    if (value == null || !value.isFinite) return null;
    if (latitude && (value < -90 || value > 90)) return null;
    if (!latitude && (value < -180 || value > 180)) return null;
    return value;
  }

  static bool _usesVersionedLayout(List<String> parts) =>
      parts.length >= 5 && _versionMarker.hasMatch(parts[4]);
}

class DrillCheckIn {
  const DrillCheckIn({
    required this.version,
    required this.status,
    required this.timestamp,
    required this.readableMessage,
  });

  static const marker = '[HB-DRILL|';
  static const currentVersion = 1;
  static const _kind = 'CHECKIN';

  final int version;
  final CheckInStatus status;
  final DateTime timestamp;
  final String readableMessage;

  static String encode({
    required CheckInStatus status,
    required String readableMessage,
    required String safetyNotice,
    required DateTime timestamp,
  }) {
    final notice = safetyNotice.trim();
    final message = readableMessage.trim();
    return '$notice${message.isEmpty ? '' : ': $message'}\n'
        '$marker$currentVersion|$_kind|${status.wireCode}|'
        '${timestamp.millisecondsSinceEpoch}]';
  }

  static DrillCheckIn? tryParse(String content) {
    final markerStart = content.lastIndexOf(marker);
    if (markerStart < 0 || !content.endsWith(']')) return null;
    final fields = content
        .substring(markerStart + marker.length, content.length - 1)
        .split('|');
    if (fields.length != 4) return null;
    final version = int.tryParse(fields[0]);
    final status = CheckInStatus.fromWire(fields[2]);
    final timestampMs = int.tryParse(fields[3]);
    if (version != currentVersion ||
        fields[1] != _kind ||
        status == null ||
        timestampMs == null ||
        timestampMs <= 0) {
      return null;
    }
    final readable = content.substring(0, markerStart).trim();
    if (readable.isEmpty) return null;
    return DrillCheckIn(
      version: version!,
      status: status,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      readableMessage: readable,
    );
  }
}

class EmergencyCheckIn {
  const EmergencyCheckIn({
    required this.status,
    required this.peerId,
    required this.sender,
    required this.timestamp,
    required this.message,
    this.latitude,
    this.longitude,
  });

  static const marker = '[HB-CHECKIN|';

  factory EmergencyCheckIn.fromMessage(MeshMessage message) {
    final markerStart = message.content.lastIndexOf(marker);
    if (markerStart < 0 || !message.content.endsWith(']')) {
      throw const FormatException('Not a HearthBit check-in');
    }
    final readable = message.content.substring(0, markerStart).trim();
    final fields = message.content
        .substring(markerStart + marker.length, message.content.length - 1)
        .split('|');
    if (fields.length != 5) {
      throw const FormatException('Invalid HearthBit check-in');
    }
    final status = CheckInStatus.fromWire(fields[0]);
    final timestampMs = int.tryParse(fields[1]);
    if (status == null || timestampMs == null) {
      throw const FormatException('Invalid HearthBit check-in fields');
    }
    return EmergencyCheckIn(
      status: status,
      peerId: message.senderPeerId,
      sender: message.sender,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      message: readable,
      latitude: double.tryParse(fields[2]),
      longitude: double.tryParse(fields[3]),
    );
  }

  final CheckInStatus status;
  final String peerId;
  final String sender;
  final DateTime timestamp;
  final String message;
  final double? latitude;
  final double? longitude;

  static String encode({
    required CheckInStatus status,
    required String readableMessage,
    required DateTime timestamp,
    double? latitude,
    double? longitude,
  }) {
    final lat = latitude?.toStringAsFixed(6) ?? '';
    final lon = longitude?.toStringAsFixed(6) ?? '';
    return '${readableMessage.trim()}\n'
        '$marker${status.wireCode}|${timestamp.millisecondsSinceEpoch}|'
        '$lat|$lon|1]';
  }
}

class RadarLocationUpdate {
  const RadarLocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  static const marker = '[HB-LOC|';

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;

  static String encode({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime timestamp,
  }) =>
      '$marker${latitude.toStringAsFixed(6)}|'
      '${longitude.toStringAsFixed(6)}|'
      '${accuracyMeters.toStringAsFixed(1)}|'
      '${timestamp.millisecondsSinceEpoch}]';

  static RadarLocationUpdate? tryParse(String content) {
    if (!content.startsWith(marker) || !content.endsWith(']')) return null;
    final fields = content
        .substring(marker.length, content.length - 1)
        .split('|');
    if (fields.length != 4) return null;
    final latitude = double.tryParse(fields[0]);
    final longitude = double.tryParse(fields[1]);
    final accuracy = double.tryParse(fields[2]);
    final timestampMs = int.tryParse(fields[3]);
    if (latitude == null ||
        longitude == null ||
        accuracy == null ||
        timestampMs == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        !accuracy.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        accuracy < 0 ||
        accuracy > 10000 ||
        timestampMs <= 0) {
      return null;
    }
    return RadarLocationUpdate(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }
}

enum EmergencyDeliveryKind {
  sos('sos'),
  checkIn('checkIn');

  const EmergencyDeliveryKind(this.wireName);

  final String wireName;

  static EmergencyDeliveryKind fromWire(Object? value) => value == 'checkIn'
      ? EmergencyDeliveryKind.checkIn
      : EmergencyDeliveryKind.sos;
}

enum EmergencyDeliveryState {
  pending('pending'),
  relayed('relayed'),
  acknowledged('acknowledged'),
  expired('expired');

  const EmergencyDeliveryState(this.wireName);

  final String wireName;

  static EmergencyDeliveryState fromWire(Object? value) {
    return switch (value) {
      'relayed' => EmergencyDeliveryState.relayed,
      'acknowledged' => EmergencyDeliveryState.acknowledged,
      'expired' => EmergencyDeliveryState.expired,
      _ => EmergencyDeliveryState.pending,
    };
  }
}

class EmergencyDelivery {
  const EmergencyDelivery({
    required this.localId,
    required this.kind,
    required this.content,
    required this.createdAt,
    required this.expiresAt,
    required this.nextAttemptAt,
    required this.state,
    this.attempts = 0,
    this.lastAttemptAt,
    this.canonicalHash,
    this.lastError,
    this.acknowledgedBy = const {},
  });

  factory EmergencyDelivery.fromDatabase(
    Map<String, Object?> row, {
    Set<String> acknowledgedBy = const {},
  }) {
    DateTime? optionalDate(String key) {
      final value = row[key] as int?;
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
    }

    return EmergencyDelivery(
      localId: row['local_id']! as String,
      kind: EmergencyDeliveryKind.fromWire(row['kind']),
      content: row['content']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ).toLocal(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        row['expires_at']! as int,
        isUtc: true,
      ).toLocal(),
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
        row['next_attempt_at']! as int,
        isUtc: true,
      ).toLocal(),
      state: EmergencyDeliveryState.fromWire(row['state']),
      attempts: row['attempts']! as int,
      lastAttemptAt: optionalDate('last_attempt_at'),
      canonicalHash: row['canonical_hash'] as String?,
      lastError: row['last_error'] as String?,
      acknowledgedBy: Set.unmodifiable(acknowledgedBy),
    );
  }

  final String localId;
  final EmergencyDeliveryKind kind;
  final String content;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime nextAttemptAt;
  final EmergencyDeliveryState state;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? canonicalHash;
  final String? lastError;
  final Set<String> acknowledgedBy;

  int get confirmationCount => acknowledgedBy.length;
  bool get isTerminal =>
      state == EmergencyDeliveryState.acknowledged ||
      state == EmergencyDeliveryState.expired;

  Map<String, Object?> toDatabase() => {
    'local_id': localId,
    'kind': kind.wireName,
    'content': content,
    'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
    'next_attempt_at': nextAttemptAt.toUtc().millisecondsSinceEpoch,
    'state': state.wireName,
    'attempts': attempts,
    'last_attempt_at': lastAttemptAt?.toUtc().millisecondsSinceEpoch,
    'canonical_hash': canonicalHash,
    'last_error': lastError,
  };

  EmergencyDelivery copyWith({
    EmergencyDeliveryState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    DateTime? lastAttemptAt,
    String? canonicalHash,
    String? lastError,
    Set<String>? acknowledgedBy,
    bool clearLastError = false,
  }) {
    return EmergencyDelivery(
      localId: localId,
      kind: kind,
      content: content,
      createdAt: createdAt,
      expiresAt: expiresAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      canonicalHash: canonicalHash ?? this.canonicalHash,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
    );
  }
}

class MeshPeer {
  const MeshPeer({
    required this.id,
    required this.nickname,
    required this.lastSeen,
    required this.secure,
    this.online = true,
    this.supportsTransfers = false,
    this.supportsEmergencyAck = false,
    this.hearthbitVerified = false,
    this.role = MeshNodeRole.phoneRelay,
    this.hasLongRangeTrunk = false,
    this.radarAllowedUntil,
    this.radarConsentSource,
    this.signingPublicKey,
  });

  factory MeshPeer.fromMap(Map<Object?, Object?> map) {
    final parsed = tryParse(map);
    if (parsed == null) throw const FormatException('Invalid mesh peer');
    return parsed;
  }

  static MeshPeer? tryParse(Map<Object?, Object?> map) {
    final id = map['id'];
    final nickname = map['nickname'];
    final lastSeen = map['lastSeen'];
    if (id is! String ||
        id.isEmpty ||
        utf8.encode(id).length > 128 ||
        nickname is! String ||
        nickname.trim().isEmpty ||
        utf8.encode(nickname).length > 80 ||
        lastSeen is! num ||
        !lastSeen.isFinite ||
        lastSeen <= 0 ||
        lastSeen > 8640000000000000) {
      return null;
    }
    final online = map['online'] is bool ? map['online']! as bool : true;
    final radarConsentSource = map['radarConsentSource'];
    if (radarConsentSource != null &&
        (radarConsentSource is! String || radarConsentSource.length > 64)) {
      return null;
    }
    final signingPublicKey = map['signingPublicKey'];
    if (signingPublicKey is List<int> &&
        signingPublicKey.any((byte) => byte < 0 || byte > 255)) {
      return null;
    }
    return MeshPeer(
      id: id,
      nickname: nickname,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeen.toInt()),
      secure: online && map['secure'] == true,
      online: online,
      supportsTransfers: map['supportsTransfers'] == true,
      supportsEmergencyAck: map['supportsEmergencyAck'] == true,
      hearthbitVerified:
          map['hearthbitVerified'] == true || map['supportsTransfers'] == true,
      role: MeshNodeRole.fromWire(map['role']),
      hasLongRangeTrunk: map['hasLongRangeTrunk'] == true,
      radarAllowedUntil: switch (map['radarAllowedUntil']) {
        final num value
            when value.isFinite && value > 0 && value <= 8640000000000000 =>
          DateTime.fromMillisecondsSinceEpoch(value.toInt()),
        _ => null,
      },
      radarConsentSource: radarConsentSource as String?,
      signingPublicKey: switch (signingPublicKey) {
        final Uint8List value when value.length == 32 => value,
        final List<int> value when value.length == 32 => Uint8List.fromList(
          value,
        ),
        _ => null,
      },
    );
  }

  final String id;
  final String nickname;
  final DateTime lastSeen;
  final bool secure;
  final bool online;
  final bool supportsTransfers;
  final bool supportsEmergencyAck;
  final bool hearthbitVerified;
  final MeshNodeRole role;
  final bool hasLongRangeTrunk;
  final DateTime? radarAllowedUntil;
  final String? radarConsentSource;

  /// Clave Ed25519 autenticada por el ANNOUNCE. Nunca contiene material privado.
  final Uint8List? signingPublicKey;

  bool get radarAllowed => radarAllowedUntil?.isAfter(DateTime.now()) ?? false;

  bool isOnlineAt(DateTime now, {required Duration freshnessWindow}) =>
      online && !lastSeen.isBefore(now.subtract(freshnessWindow));

  factory MeshPeer.fromDatabase(Map<String, Object?> map) {
    return MeshPeer(
      id: map['id']! as String,
      nickname: map['nickname']! as String,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen']! as int),
      secure: false,
      online: false,
      hearthbitVerified: map['hearthbit_verified'] == 1,
    );
  }

  Map<String, Object?> toDatabase() => {
    'id': id,
    'nickname': nickname,
    'last_seen': lastSeen.millisecondsSinceEpoch,
    'hearthbit_verified': hearthbitVerified ? 1 : 0,
  };
}

class GenericBlePresence {
  const GenericBlePresence({
    required this.id,
    required this.role,
    required this.kind,
    required this.chatAvailable,
    required this.rssi,
    required this.lastSeen,
  });

  factory GenericBlePresence.fromMap(Map<Object?, Object?> map) {
    final parsed = tryParse(map);
    if (parsed == null) {
      throw const FormatException('Invalid generic BLE presence');
    }
    return parsed;
  }

  static GenericBlePresence? tryParse(Map<Object?, Object?> map) {
    final id = map['id'];
    final kind = map['kind'];
    final rssi = map['rssi'];
    final lastSeen = map['lastSeen'];
    if (id is! String ||
        id.isEmpty ||
        utf8.encode(id).length > 128 ||
        kind != null && (kind is! String || utf8.encode(kind).length > 32) ||
        rssi is! num ||
        !rssi.isFinite ||
        rssi < -127 ||
        rssi > 20 ||
        lastSeen is! num ||
        !lastSeen.isFinite ||
        lastSeen <= 0 ||
        lastSeen > 8640000000000000) {
      return null;
    }
    return GenericBlePresence(
      id: id,
      role: MeshNodeRole.fromWire(map['role']),
      kind: kind as String? ?? 'genericBle',
      chatAvailable: map['chatAvailable'] == true,
      rssi: rssi.toInt(),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeen.toInt()),
    );
  }

  /// Identificador efímero, local a esta ejecución y rotado por Android.
  final String id;
  final MeshNodeRole role;
  final String kind;
  final bool chatAvailable;
  final int rssi;
  final DateTime lastSeen;
}

/// Regla única para ofrecer archivos desde cualquier vista de la aplicación.
bool canOfferFileToPeer(MeshPeer peer, {required bool isOnline}) =>
    isOnline && peer.supportsTransfers;

enum MeshMessageDeliveryStatus { transmitted, pending, expired }

class MeshMessage {
  static const int maximumIdLength = 128;
  static const int maximumNicknameLength = 80;
  static const int maximumContentBytes = 64 * 1024;
  static const int maximumChannelLength = 32;

  const MeshMessage({
    required this.id,
    required this.sender,
    required this.content,
    required this.senderPeerId,
    required this.isPrivate,
    required this.isMine,
    required this.timestamp,
    this.channel,
    this.deliveryStatus = MeshMessageDeliveryStatus.transmitted,
    this.external = false,
    this.canonicalHash,
  });

  factory MeshMessage.fromMap(Map<Object?, Object?> map) {
    final parsed = tryParse(map);
    if (parsed == null) throw const FormatException('Invalid mesh message');
    return parsed;
  }

  static MeshMessage? tryParse(Map<Object?, Object?> map) {
    final id = map['id'];
    final sender = map['sender'];
    final content = map['content'];
    final senderPeerId = map['senderPeerId'];
    final timestamp = map['timestamp'];
    final channel = map['channel'];
    final canonicalHash = map['canonicalHash'];
    if (id is! String ||
        id.isEmpty ||
        utf8.encode(id).length > maximumIdLength ||
        sender is! String ||
        utf8.encode(sender).length > maximumNicknameLength ||
        content is! String ||
        utf8.encode(content).length > maximumContentBytes ||
        senderPeerId is! String ||
        senderPeerId.isEmpty ||
        utf8.encode(senderPeerId).length > maximumIdLength ||
        timestamp is! num ||
        !timestamp.isFinite ||
        timestamp <= 0 ||
        timestamp > 8640000000000000 ||
        (channel != null &&
            (channel is! String ||
                utf8.encode(channel).length > maximumChannelLength)) ||
        (canonicalHash != null &&
            (canonicalHash is! String ||
                !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(canonicalHash)))) {
      return null;
    }
    return MeshMessage(
      id: id,
      sender: sender,
      content: content,
      senderPeerId: senderPeerId,
      isPrivate: map['private'] == true,
      isMine: map['mine'] == true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()),
      channel: channel as String?,
      external: map['external'] == true,
      canonicalHash: (canonicalHash as String?)?.toLowerCase(),
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
      external: map['external'] == 1,
      canonicalHash: (map['canonical_hash'] as String?)?.toLowerCase(),
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
  final MeshMessageDeliveryStatus deliveryStatus;
  final bool external;
  final String? canonicalHash;

  bool get isDrill => channel?.trim().toLowerCase() == 'drill';

  DrillCheckIn? get drill {
    if (!isDrill || isPrivate) return null;
    return DrillCheckIn.tryParse(content);
  }

  bool get isSos =>
      !isDrill && (channel == 'sos' || content.startsWith('SOS|'));

  bool get isPending => deliveryStatus == MeshMessageDeliveryStatus.pending;

  bool get isExpired => deliveryStatus == MeshMessageDeliveryStatus.expired;

  bool get isCheckIn =>
      !isDrill &&
      (channel == 'checkin' || content.contains(EmergencyCheckIn.marker));

  VoiceNoteEnvelope? get voiceNote =>
      isPrivate ? VoiceNoteEnvelope.tryParse(content) : null;

  bool get isVoiceNote => voiceNote != null;

  String? get voiceTransferId => voiceNote?.transferId;

  int? get voiceDurationSeconds => voiceNote?.durationSeconds;

  List<double> get voiceWaveform => voiceNote?.waveform ?? const [];

  bool get isRadarLocation => isPrivate && radarLocation != null;

  RadarLocationUpdate? get radarLocation =>
      isPrivate ? RadarLocationUpdate.tryParse(content) : null;

  EmergencyCheckIn? get checkIn {
    if (!isCheckIn) return null;
    try {
      return EmergencyCheckIn.fromMessage(this);
    } on FormatException {
      return null;
    }
  }

  /// Conserva `SOS|descripción|lat|lon` y acepta un sufijo de triage T1.
  String get sosDescription => SosMessageCodec.description(content);

  double? get sosLatitude => SosMessageCodec.latitude(content);

  double? get sosLongitude => SosMessageCodec.longitude(content);

  SosTriage? get sosTriage => SosMessageCodec.triage(content);

  Map<String, Object?> toDatabase() => {
    'id': id,
    'sender': sender,
    'content': content,
    'sender_peer_id': senderPeerId,
    'is_private': isPrivate ? 1 : 0,
    'is_mine': isMine ? 1 : 0,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'channel': channel,
    'external': external ? 1 : 0,
    'canonical_hash': canonicalHash,
  };
}

enum MeshConnectionStatus { stopped, starting, active, degraded, error }

class MeshConversation {
  const MeshConversation({
    required this.peer,
    required this.lastMessage,
    required this.isOnline,
  });

  final MeshPeer peer;
  final MeshMessage lastMessage;
  final bool isOnline;
}
