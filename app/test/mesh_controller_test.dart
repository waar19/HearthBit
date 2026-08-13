import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/message_repository.dart';

class _FakePlatform extends MeshPlatformService {
  final StreamController<Map<Object?, Object?>> _controller =
      StreamController.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int sosCalls = 0;
  final List<({bool enabled, int minutes})> radarConsentCalls = [];
  int panicWipeCalls = 0;
  final List<String> nodeRoles = [];
  final List<({String content, String? channel})> publicMessages = [];
  bool permissionsGranted = true;
  bool backgroundLocation = true;
  Object? startError;

  void emit(Map<Object?, Object?> event) => _controller.add(event);

  @override
  Stream<Map<Object?, Object?>> get events => _controller.stream;

  @override
  Future<Map<Object?, Object?>> getCapabilities() async => const {
    'backgroundRelay': true,
  };

  @override
  Future<bool> requestPermissions() async => permissionsGranted;

  @override
  Future<void> start() async {
    startCalls += 1;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<String> sendPublic(String content, {String? channel}) async {
    publicMessages.add((content: content, channel: channel));
    return 'public-${publicMessages.length}';
  }

  @override
  Future<String> sendSos({
    required String content,
    double? latitude,
    double? longitude,
  }) async {
    sosCalls += 1;
    return 'sos-$sosCalls';
  }

  @override
  Future<Map<Object?, Object?>> getPowerStatus() async => {
    'ignoringBatteryOptimizations': false,
    'lowPowerMode': true,
    'backgroundLocation': backgroundLocation,
    'batteryLevel': 14,
    'adaptivePowerSaving': true,
    'powerProfile': 'critical',
  };

  @override
  Future<bool> requestBackgroundLocation() async => backgroundLocation;

  @override
  Future<bool> requestDisableBatteryOptimizations() async => false;

  @override
  Future<void> setRadarConsent({
    required bool enabled,
    int minutes = 15,
  }) async {
    radarConsentCalls.add((enabled: enabled, minutes: minutes));
  }

  @override
  Future<void> panicWipe() async {
    panicWipeCalls += 1;
  }

  @override
  Future<void> setNodeRole(String role) async {
    nodeRoles.add(role);
  }
}

class _FakeRepository extends MessageRepository {
  final List<MeshMessage> saved = [];
  final List<MeshPeer> knownPeers = [];

  @override
  Future<List<MeshMessage>> load() async => const [];

  @override
  Future<void> save(MeshMessage message) async {
    saved.add(message);
  }

  @override
  Future<List<MeshPeer>> loadKnownPeers() async => List.of(knownPeers);

  @override
  Future<void> saveKnownPeers(Iterable<MeshPeer> peers) async {
    knownPeers
      ..clear()
      ..addAll(peers);
  }

  @override
  Future<void> clear() async {
    saved.clear();
    knownPeers.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  late MeshController controller;

  setUp(() async {
    platform = _FakePlatform();
    controller = MeshController(
      platform: platform,
      repository: _FakeRepository(),
    );
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);

  test('el estado degraded llega desde el nativo y permite enviar', () async {
    platform.emit({'type': 'status', 'status': 'degraded'});
    await pumpEvents();
    expect(controller.status, MeshConnectionStatus.degraded);
    expect(controller.canSend, isTrue);
  });

  test('active tras degraded recupera la malla completa', () async {
    platform.emit({'type': 'status', 'status': 'degraded'});
    platform.emit({'type': 'status', 'status': 'active'});
    await pumpEvents();
    expect(controller.status, MeshConnectionStatus.active);
  });

  test('snapshot resincroniza estado, identidad y cercanos', () async {
    final consentUntil = DateTime.now()
        .add(const Duration(minutes: 12))
        .millisecondsSinceEpoch;
    platform.emit({
      'type': 'snapshot',
      'status': 'active',
      'nickname': 'Nodo 7',
      'peerId': '0102030405060708',
      'role': 'PHONE_RELAY',
      'radarConsentUntil': consentUntil,
      'peers': [
        {
          'id': '1112131415161718',
          'nickname': 'Rescate',
          'lastSeen': 1234,
          'secure': true,
          'supportsTransfers': true,
          'role': 'INFRA_DATA_ANCHOR',
          'radarAllowedUntil': consentUntil,
          'radarConsentSource': 'temporary',
        },
      ],
      'presences': [
        {
          'id': 'aabbccddeeff001122334455',
          'role': 'PHONE_BEACON',
          'kind': 'genericBle',
          'chatAvailable': false,
          'rssi': -68,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        },
      ],
    });
    await pumpEvents();

    expect(controller.status, MeshConnectionStatus.active);
    expect(controller.nickname, 'Nodo 7');
    expect(controller.peerId, '0102030405060708');
    expect(controller.peers.single.nickname, 'Rescate');
    expect(controller.peers.single.supportsTransfers, isTrue);
    expect(controller.peers.single.role, MeshNodeRole.infraDataAnchor);
    expect(controller.genericPresences.single.chatAvailable, isFalse);
    expect(controller.radarConsentActive, isTrue);
    expect(controller.peers.single.radarAllowed, isTrue);
  });

  test(
    'conserva la conversación cuando el destinatario se desconecta',
    () async {
      const remoteId = '1112131415161718';
      platform.emit({
        'type': 'peers',
        'peers': [
          {
            'id': remoteId,
            'nickname': 'Rescate',
            'lastSeen': 1234,
            'secure': true,
          },
        ],
      });
      platform.emit({
        'type': 'message',
        'message': {
          'id': 'private-1',
          'sender': 'Rescate',
          'content': '¿Sigues ahí?',
          'senderPeerId': remoteId,
          'private': true,
          'mine': false,
          'timestamp': 2000,
        },
      });
      await pumpEvents();

      expect(controller.conversations.single.isOnline, isTrue);
      platform.emit({'type': 'peers', 'peers': <Object?>[]});
      await pumpEvents();

      final conversation = controller.conversations.single;
      expect(conversation.peer.nickname, 'Rescate');
      expect(conversation.lastMessage.content, '¿Sigues ahí?');
      expect(conversation.isOnline, isFalse);
    },
  );

  test('un error durante el arranque marca estado de error', () async {
    unawaited(controller.start());
    await pumpEvents();
    platform.emit({'type': 'error', 'message': 'Bluetooth apagado'});
    await pumpEvents();
    expect(controller.status, MeshConnectionStatus.error);
    expect(controller.lastError, contains('Bluetooth'));
  });

  test(
    'reintentar tras un fallo vuelve a invocar el arranque nativo',
    () async {
      platform.startError = StateError('sin adaptador');
      await controller.start();
      expect(controller.status, MeshConnectionStatus.error);

      platform.startError = null;
      await controller.start();
      expect(platform.startCalls, 2);
      expect(controller.lastError, isNull);

      platform.emit({'type': 'status', 'status': 'active'});
      await pumpEvents();
      expect(controller.status, MeshConnectionStatus.active);
    },
  );

  test('permisos rechazados no dejan la malla como activa', () async {
    platform.permissionsGranted = false;
    await controller.start();
    expect(controller.status, MeshConnectionStatus.error);
    expect(platform.startCalls, 0);
    expect(controller.canSend, isFalse);
  });

  test('el estado de energía llega desde el nativo', () async {
    await controller.refreshPowerStatus();
    expect(controller.ignoringBatteryOptimizations, isFalse);
    expect(controller.lowPowerMode, isTrue);
    expect(controller.backgroundLocationGranted, isTrue);
    expect(controller.batteryLevel, 14);
    expect(controller.powerProfile, MeshPowerProfile.critical);
    expect(controller.adaptivePowerSaving, isTrue);

    platform.emit({
      'type': 'power',
      'batteryLevel': 100,
      'adaptivePowerSaving': false,
      'powerProfile': 'performance',
    });
    await pumpEvents();
    expect(controller.powerProfile, MeshPowerProfile.performance);
    expect(controller.adaptivePowerSaving, isFalse);
  });

  test('el modo rescate reenvía el SOS y se detiene al apagarse', () async {
    platform.emit({'type': 'status', 'status': 'active'});
    await pumpEvents();

    await controller.setRescueMode(
      true,
      interval: const Duration(milliseconds: 40),
    );
    expect(controller.rescueMode, isTrue);
    expect(platform.sosCalls, 1);
    expect(platform.radarConsentCalls, contains((enabled: true, minutes: 10)));
    expect(controller.lastRescuePing, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(platform.sosCalls, greaterThanOrEqualTo(2));

    await controller.setRescueMode(false);
    expect(controller.rescueMode, isFalse);
    expect(platform.radarConsentCalls.last.enabled, isFalse);
    final callsAtStop = platform.sosCalls;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(platform.sosCalls, callsAtStop);
  });

  test('detener la malla también apaga el modo rescate', () async {
    await controller.setRescueMode(true, interval: const Duration(minutes: 5));
    await controller.stop();
    expect(controller.rescueMode, isFalse);
    expect(platform.stopCalls, 1);
  });

  test('permite y revoca el radar temporal explícitamente', () async {
    await controller.allowRadarFor15Minutes();
    expect(controller.radarConsentActive, isTrue);
    expect(platform.radarConsentCalls.last, (enabled: true, minutes: 15));

    await controller.revokeRadarConsent();
    expect(controller.radarConsentActive, isFalse);
    expect(platform.radarConsentCalls.last.enabled, isFalse);
  });

  test('cambia el rol local y bloquea chat en modo presencia', () async {
    platform.emit({'type': 'status', 'status': 'active'});
    await pumpEvents();
    expect(controller.canSend, isTrue);

    await controller.updateNodeRole(MeshNodeRole.phoneBeacon);

    expect(platform.nodeRoles.single, 'PHONE_BEACON');
    expect(controller.localRole, MeshNodeRole.phoneBeacon);
    expect(controller.canSend, isFalse);

    await controller.updateNodeRole(MeshNodeRole.phoneRelay);
    expect(controller.canSend, isTrue);
  });

  test(
    'envía un check-in legible y estructurado por el canal público',
    () async {
      platform.emit({'type': 'status', 'status': 'active'});
      await pumpEvents();

      await controller.sendCheckIn(CheckInStatus.ok, 'Estoy bien');

      expect(platform.publicMessages, hasLength(1));
      expect(platform.publicMessages.single.channel, 'checkin');
      expect(
        platform.publicMessages.single.content,
        startsWith('Estoy bien\n'),
      );
      expect(
        platform.publicMessages.single.content,
        contains(EmergencyCheckIn.marker),
      );
    },
  );

  test('modo supervivencia emite SOS y cambia a baliza', () async {
    platform.emit({'type': 'status', 'status': 'active'});
    await pumpEvents();

    await controller.setSurvivalMode(true);

    expect(platform.sosCalls, 1);
    expect(platform.nodeRoles.last, MeshNodeRole.phoneBeacon.wireName);
    expect(controller.survivalMode, isTrue);
  });

  test('actualiza presencias genéricas sin convertirlas en peers', () async {
    platform.emit({
      'type': 'presences',
      'presences': [
        {
          'id': '00112233445566778899aabb',
          'role': 'PHONE_BEACON',
          'kind': 'genericBle',
          'chatAvailable': false,
          'rssi': -81,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        },
      ],
    });
    await pumpEvents();

    expect(controller.genericPresences.single.rssi, -81);
    expect(controller.peers, isEmpty);
  });

  test('el borrado de pánico elimina el consentimiento local', () async {
    await controller.allowRadarFor15Minutes();
    await controller.panicWipe();

    expect(controller.radarConsentActive, isFalse);
    expect(platform.panicWipeCalls, 1);
  });
}
