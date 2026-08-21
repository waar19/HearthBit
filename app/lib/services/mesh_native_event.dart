import 'dart:typed_data';

import '../models/mesh_models.dart';

sealed class MeshNativeEvent {
  const MeshNativeEvent(this.raw);

  final Map<Object?, Object?> raw;

  static MeshNativeEvent parse(Map<Object?, Object?> raw) {
    return switch (raw['type']) {
      'snapshot' => MeshSnapshotEvent(raw),
      'status' => MeshStatusEvent(raw),
      'power' => MeshPowerEvent(
        raw,
        batteryLevel: _int(raw['batteryLevel']),
        powerProfile: _string(raw['powerProfile']),
        adaptivePowerSaving: _bool(raw['adaptivePowerSaving']),
      ),
      'peers' => MeshPeersEvent(raw, peers: raw['peers']),
      'presences' => MeshPresencesEvent(raw, presences: raw['presences']),
      'radarConsent' => MeshRadarConsentEvent(raw),
      'beaconRequest' => MeshBeaconRequestEvent(raw),
      'beaconRequestResolved' => MeshBeaconRequestResolvedEvent(
        raw,
        requestId: _string(raw['requestId']),
      ),
      'beaconState' => MeshBeaconStateEvent(
        raw,
        scope: _string(raw['scope']),
        peerId: _string(raw['peerId']),
        requestId: _string(raw['requestId']),
        status: _string(raw['status']),
        expiresAt: _int(raw['expiresAt']),
      ),
      'message' => MeshMessageEvent(
        raw,
        message: switch (raw['message']) {
          final Map<Object?, Object?> value => MeshMessage.tryParse(value),
          _ => null,
        },
      ),
      'error' => MeshErrorEvent(raw, message: _string(raw['message'])),
      'wiped' => MeshWipedEvent(raw),
      'emergencyAck' => MeshEmergencyAckEvent(
        raw,
        canonicalHash: _string(raw['canonicalHash']),
        peerId: _string(raw['peerId']),
      ),
      'keyRotation' => MeshKeyRotationEvent(
        raw,
        status: _string(raw['status']),
        oldPeerId: _string(raw['oldPeerId']),
        newPeerId: _string(raw['newPeerId']),
        sequence: _int(raw['sequence']),
        timestamp: _int(raw['timestamp']),
      ),
      'rescuePing' => MeshRescuePingEvent(
        raw,
        timestamp: _int(raw['timestamp']),
      ),
      'emergencyTransport' => MeshEmergencyTransportEvent(
        raw,
        channels: _strings(raw['channels']),
        timestamp: _int(raw['timestamp']),
      ),
      'rangingMeasurement' => MeshRangingMeasurementEvent(
        raw,
        peerId: _string(raw['peerId']),
        meters: _double(raw['meters']),
        errorMeters: _double(raw['errorMeters']),
        confidence: _double(raw['confidence']),
      ),
      'radioRangingState' => MeshRadioRangingStateEvent(
        raw,
        state: _string(raw['state']),
      ),
      'rangingControl' => MeshRangingControlEvent(
        raw,
        peerId: _string(raw['peerId']),
        payload: _bytes(raw['payload']),
      ),
      'radarExpired' => MeshRadarExpiredEvent(
        raw,
        peerId: _string(raw['peerId']),
      ),
      'radarDiagnostic' => MeshRadarDiagnosticEvent(
        raw,
        peerId: _string(raw['peerId']),
        reason: _string(raw['reason']),
      ),
      'rssi' => MeshRssiEvent(
        raw,
        peerId: _string(raw['peerId']),
        rssi: _int(raw['rssi']),
        at: _int(raw['at']),
        remote: raw['remote'] == true,
        tentative: raw['tentative'] == true,
      ),
      'anchorAdmin' => MeshAnchorAdminEvent(raw),
      final String type => MeshUnknownEvent(raw, type: type),
      _ => MeshUnknownEvent(raw, type: null),
    };
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  static String? _string(Object? value) => value is String ? value : null;

  static bool? _bool(Object? value) => value is bool ? value : null;

  static List<String> _strings(Object? value) => switch (value) {
    final List<Object?> values => values.whereType<String>().toList(
      growable: false,
    ),
    _ => const [],
  };

  static Uint8List? _bytes(Object? value) => switch (value) {
    final Uint8List bytes => bytes,
    final List<int> bytes => Uint8List.fromList(bytes),
    _ => null,
  };
}

final class MeshSnapshotEvent extends MeshNativeEvent {
  const MeshSnapshotEvent(super.raw);
}

final class MeshStatusEvent extends MeshNativeEvent {
  const MeshStatusEvent(super.raw);
}

final class MeshPowerEvent extends MeshNativeEvent {
  const MeshPowerEvent(
    super.raw, {
    required this.batteryLevel,
    required this.powerProfile,
    required this.adaptivePowerSaving,
  });

  final int? batteryLevel;
  final String? powerProfile;
  final bool? adaptivePowerSaving;
}

final class MeshPeersEvent extends MeshNativeEvent {
  const MeshPeersEvent(super.raw, {required this.peers});

  final Object? peers;
}

final class MeshPresencesEvent extends MeshNativeEvent {
  const MeshPresencesEvent(super.raw, {required this.presences});

  final Object? presences;
}

final class MeshRadarConsentEvent extends MeshNativeEvent {
  const MeshRadarConsentEvent(super.raw);
}

final class MeshBeaconRequestEvent extends MeshNativeEvent {
  const MeshBeaconRequestEvent(super.raw);
}

final class MeshBeaconRequestResolvedEvent extends MeshNativeEvent {
  const MeshBeaconRequestResolvedEvent(super.raw, {required this.requestId});

  final String? requestId;
}

final class MeshBeaconStateEvent extends MeshNativeEvent {
  const MeshBeaconStateEvent(
    super.raw, {
    required this.scope,
    required this.peerId,
    required this.requestId,
    required this.status,
    required this.expiresAt,
  });

  final String? scope;
  final String? peerId;
  final String? requestId;
  final String? status;
  final int? expiresAt;
}

final class MeshMessageEvent extends MeshNativeEvent {
  const MeshMessageEvent(super.raw, {required this.message});

  final MeshMessage? message;
}

final class MeshErrorEvent extends MeshNativeEvent {
  const MeshErrorEvent(super.raw, {required this.message});

  final String? message;
}

final class MeshWipedEvent extends MeshNativeEvent {
  const MeshWipedEvent(super.raw);
}

final class MeshEmergencyAckEvent extends MeshNativeEvent {
  const MeshEmergencyAckEvent(
    super.raw, {
    required this.canonicalHash,
    required this.peerId,
  });

  final String? canonicalHash;
  final String? peerId;
}

final class MeshKeyRotationEvent extends MeshNativeEvent {
  const MeshKeyRotationEvent(
    super.raw, {
    required this.status,
    required this.oldPeerId,
    required this.newPeerId,
    required this.sequence,
    required this.timestamp,
  });

  final String? status;
  final String? oldPeerId;
  final String? newPeerId;
  final int? sequence;
  final int? timestamp;
}

final class MeshRescuePingEvent extends MeshNativeEvent {
  const MeshRescuePingEvent(super.raw, {required this.timestamp});

  final int? timestamp;
}

final class MeshEmergencyTransportEvent extends MeshNativeEvent {
  const MeshEmergencyTransportEvent(
    super.raw, {
    required this.channels,
    required this.timestamp,
  });

  final List<String> channels;
  final int? timestamp;
}

final class MeshRangingMeasurementEvent extends MeshNativeEvent {
  const MeshRangingMeasurementEvent(
    super.raw, {
    required this.peerId,
    required this.meters,
    required this.errorMeters,
    required this.confidence,
  });

  final String? peerId;
  final double? meters;
  final double? errorMeters;
  final double? confidence;
}

final class MeshRadioRangingStateEvent extends MeshNativeEvent {
  const MeshRadioRangingStateEvent(super.raw, {required this.state});

  final String? state;
}

final class MeshRangingControlEvent extends MeshNativeEvent {
  const MeshRangingControlEvent(
    super.raw, {
    required this.peerId,
    required this.payload,
  });

  final String? peerId;
  final Uint8List? payload;
}

final class MeshRadarExpiredEvent extends MeshNativeEvent {
  const MeshRadarExpiredEvent(super.raw, {required this.peerId});

  final String? peerId;
}

final class MeshRadarDiagnosticEvent extends MeshNativeEvent {
  const MeshRadarDiagnosticEvent(
    super.raw, {
    required this.peerId,
    required this.reason,
  });

  final String? peerId;
  final String? reason;
}

final class MeshRssiEvent extends MeshNativeEvent {
  const MeshRssiEvent(
    super.raw, {
    required this.peerId,
    required this.rssi,
    required this.at,
    required this.remote,
    required this.tentative,
  });

  final String? peerId;
  final int? rssi;
  final int? at;
  final bool remote;
  final bool tentative;
}

final class MeshAnchorAdminEvent extends MeshNativeEvent {
  const MeshAnchorAdminEvent(super.raw);
}

final class MeshUnknownEvent extends MeshNativeEvent {
  const MeshUnknownEvent(super.raw, {required this.type});

  final String? type;
}
