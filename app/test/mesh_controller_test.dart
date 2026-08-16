import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/acoustic_sos.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/message_repository.dart';

class _FakePlatform extends MeshPlatformService {
  final StreamController<Map<Object?, Object?>> _controller =
      StreamController.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int sosCalls = 0;
  final List<({bool enabled, int minutes})> radarConsentCalls = [];
  int startLocalBeaconCalls = 0;
  int stopLocalBeaconCalls = 0;
  final List<({String requestId, bool accept})> beaconResponses = [];
  int panicWipeCalls = 0;
  final List<String> nodeRoles = [];
  final List<String> retryEmergencyCalls = [];
  String? retryEmergencyResult;
  final List<({String content, String? channel})> publicMessages = [];
  final List<({String peerId, String content, String? messageId})>
  privateMessages = [];
  final List<String> privateChannelRequests = [];
  bool permissionsGranted = true;
  bool backgroundLocation = true;
  Object? startError;
  Object? privateMessageError;
  Completer<String>? privateMessageGate;
  NativeRescueState rescueState = const NativeRescueState(active: false);
  final List<bool> rescueConfigurations = [];
  final List<Uint8List> emergencyLanFrames = [];

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
  Future<NativeRescueState> getRescueModeState() async => rescueState;

  @override
  Future<NativeRescueState> configureRescueMode({
    required bool active,
    String? description,
    DateTime? startedAt,
    DateTime? lastPingAt,
    DateTime? expiresAt,
    Duration interval = const Duration(minutes: 2),
    SosLocationPrecision locationPrecision = SosLocationPrecision.approximate,
  }) async {
    rescueConfigurations.add(active);
    rescueState = NativeRescueState(
      active: active,
      description: active ? description : null,
      startedAt: active ? startedAt : null,
      lastPingAt: active ? lastPingAt : null,
      expiresAt: active ? expiresAt : null,
      locationPrecision: locationPrecision,
    );
    return rescueState;
  }

  @override
  Future<String> sendPublic(String content, {String? channel}) async {
    publicMessages.add((content: content, channel: channel));
    return 'public-${publicMessages.length}';
  }

  @override
  Future<String> sendPrivate(
    String peerId,
    String content, {
    String? messageId,
  }) async {
    privateMessages.add((
      peerId: peerId,
      content: content,
      messageId: messageId,
    ));
    final error = privateMessageError;
    if (error != null) throw error;
    final gate = privateMessageGate;
    if (gate != null) return gate.future;
    return messageId ?? 'private-${privateMessages.length}';
  }

  @override
  Future<void> ensurePrivateChannel(String peerId) async {
    privateChannelRequests.add(peerId);
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
  Future<EmergencyTransmission> sendEmergency({
    required String messageId,
    required String content,
    required String channel,
  }) async {
    if (channel == 'sos') {
      sosCalls += 1;
    } else {
      publicMessages.add((content: content, channel: channel));
    }
    return EmergencyTransmission(
      messageId: messageId,
      canonicalHash: messageId.hashCode.toRadixString(16).padLeft(64, '0'),
      announcementFrame: channel == 'sos'
          ? Uint8List.fromList([1, 2, 3])
          : null,
      messageFrame: channel == 'sos' ? Uint8List.fromList([4, 5, 6]) : null,
    );
  }

  @override
  Future<String?> retryEmergency(String canonicalHash) async {
    retryEmergencyCalls.add(canonicalHash);
    return retryEmergencyResult;
  }

  @override
  Future<void> injectEmergencyLanFrame(Uint8List frame) async {
    emergencyLanFrames.add(Uint8List.fromList(frame));
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
  Future<Map<Object?, Object?>> getMeshDiagnostics() async => {
    'platform': 'android',
    'advertising': true,
    'meshScanActive': true,
    'genericScanActive': false,
    'genericScanEnabled': true,
    'batteryLevel': 13,
    'powerProfile': 'powerSaver',
    'adaptivePowerSaving': true,
    'bleDutyCyclePercent': 27,
    'activeScans': 1,
    'scanStarts': 8,
    'storeForwardEntries': 3,
    'transports': ['ble', 'lan', 'ble'],
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
  Future<void> startLocalBeacon({
    int flags = 0x07,
    Duration duration = const Duration(minutes: 5),
  }) async {
    startLocalBeaconCalls += 1;
  }

  @override
  Future<void> stopLocalBeacon() async {
    stopLocalBeaconCalls += 1;
  }

  @override
  Future<void> respondToBeaconRequest({
    required String requestId,
    required bool accept,
  }) async {
    beaconResponses.add((requestId: requestId, accept: accept));
  }

  @override
  Future<Map<Object?, Object?>> panicWipe() async {
    panicWipeCalls += 1;
    return {
      'type': 'snapshot',
      'status': 'stopped',
      'nickname': 'SOS-NEW1',
      'peerId': 'fresh-peer-id',
      'signingPublicKey': Uint8List(32),
      'role': 'PHONE_RELAY',
    };
  }

  @override
  Future<void> setNodeRole(String role) async {
    nodeRoles.add(role);
  }
}

class _FakeRepository extends MessageRepository {
  _FakeRepository({List<MeshMessage> initialMessages = const []})
    : loaded = List.of(initialMessages);

  final List<MeshMessage> loaded;
  final List<MeshMessage> saved = [];
  final List<MeshPeer> knownPeers = [];
  final List<PendingPrivateMessage> outbox = [];
  final List<EmergencyDelivery> emergencyOutbox = [];
  final Map<String, String> emergencyAttemptLocalIds = {};
  int acknowledgementMisses = 0;

  @override
  Future<List<MeshMessage>> load() async => List.of(loaded);

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
  Future<List<PendingPrivateMessage>> listPendingPrivateMessages() async =>
      List.of(outbox);

  @override
  Future<void> expirePrivateMessageOutbox(DateTime now) async {}

  @override
  Future<void> insertPendingPrivateMessage(
    PendingPrivateMessage message,
  ) async {
    if (outbox.every((item) => item.localId != message.localId)) {
      outbox.add(message);
    }
  }

  @override
  Future<void> updatePendingPrivateMessage(
    PendingPrivateMessage message,
  ) async {
    final index = outbox.indexWhere((item) => item.localId == message.localId);
    if (index >= 0) outbox[index] = message;
  }

  @override
  Future<void> deletePendingPrivateMessage(String localId) async {
    outbox.removeWhere((item) => item.localId == localId);
  }

  @override
  Future<void> insertEmergencyDelivery(EmergencyDelivery delivery) async {
    emergencyOutbox.add(delivery);
    final hash = delivery.canonicalHash;
    if (hash != null) emergencyAttemptLocalIds[hash] = delivery.localId;
  }

  @override
  Future<void> updateEmergencyDelivery(EmergencyDelivery delivery) async {
    final index = emergencyOutbox.indexWhere(
      (item) => item.localId == delivery.localId,
    );
    if (index >= 0) emergencyOutbox[index] = delivery;
    final hash = delivery.canonicalHash;
    if (hash != null) emergencyAttemptLocalIds[hash] = delivery.localId;
  }

  @override
  Future<List<EmergencyDelivery>> loadEmergencyDeliveries() async =>
      List.of(emergencyOutbox.reversed);

  @override
  Future<void> expireEmergencyDeliveries(DateTime now) async {
    for (var index = 0; index < emergencyOutbox.length; index++) {
      final delivery = emergencyOutbox[index];
      if (!delivery.isTerminal && !delivery.expiresAt.isAfter(now)) {
        emergencyOutbox[index] = delivery.copyWith(
          state: EmergencyDeliveryState.expired,
        );
      }
    }
  }

  @override
  Future<String?> recordEmergencyAcknowledgement({
    required String canonicalHash,
    required String peerId,
    required DateTime acknowledgedAt,
  }) async {
    if (acknowledgementMisses > 0) {
      acknowledgementMisses -= 1;
      return null;
    }
    final localId = emergencyAttemptLocalIds[canonicalHash];
    final index = emergencyOutbox.indexWhere((item) => item.localId == localId);
    if (index < 0) return null;
    final delivery = emergencyOutbox[index];
    emergencyOutbox[index] = delivery.copyWith(
      state: EmergencyDeliveryState.acknowledged,
      acknowledgedBy: {...delivery.acknowledgedBy, peerId},
    );
    return delivery.localId;
  }

  @override
  Future<void> clear() async {
    saved.clear();
    knownPeers.clear();
    outbox.clear();
    emergencyOutbox.clear();
    emergencyAttemptLocalIds.clear();
  }

  @override
  Future<void> destroy() async {
    loaded.clear();
    emergencyOutbox.clear();
    await clear();
  }
}

class _FakeAcousticSos implements AcousticSosTransportPort {
  List<Uint8List> broadcastFrames = const [];
  Future<void> Function(Uint8List frame)? receiver;

  @override
  bool broadcasting = false;
  @override
  bool listening = false;

  @override
  Future<bool> startBroadcast(List<Uint8List> signedEmergencyFrames) async {
    broadcastFrames = signedEmergencyFrames
        .map(Uint8List.fromList)
        .toList(growable: false);
    broadcasting = true;
    return true;
  }

  @override
  Future<void> stopBroadcast() async {
    broadcasting = false;
    broadcastFrames = const [];
  }

  @override
  Future<bool> startListening(
    Future<void> Function(Uint8List frame) onFrame,
  ) async {
    receiver = onFrame;
    listening = true;
    return true;
  }

  @override
  Future<void> stopListening() async {
    receiver = null;
    listening = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  late _FakeRepository repository;
  late _FakeAcousticSos acousticSos;
  late MeshController controller;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = _FakePlatform();
    repository = _FakeRepository();
    acousticSos = _FakeAcousticSos();
    controller = MeshController(
      platform: platform,
      repository: repository,
      acousticSos: acousticSos,
    );
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);

  Map<Object?, Object?> peerSnapshot({
    required String peerId,
    required bool secure,
    String nickname = 'Rescate',
    bool online = true,
    DateTime? lastSeen,
  }) {
    return {
      'type': 'snapshot',
      'status': 'active',
      'nickname': 'Yo',
      'peerId': 'local-peer',
      'role': 'PHONE_RELAY',
      'peers': [
        {
          'id': peerId,
          'nickname': nickname,
          'lastSeen': (lastSeen ?? DateTime.now()).millisecondsSinceEpoch,
          'online': online,
          'secure': secure,
          'role': 'PHONE_RELAY',
          'hearthbitVerified': true,
        },
      ],
    };
  }

  test('expone un diagnóstico agregado sin identidades de peers', () async {
    await controller.refreshDiagnostics();
    expect(controller.platformName, 'android');
    expect(controller.meshAdvertising, isTrue);
    expect(controller.meshScanActive, isTrue);
    expect(controller.genericScanActive, isFalse);
    expect(controller.genericScanEnabled, isTrue);
    expect(controller.batteryLevel, 13);
    expect(controller.powerProfile, MeshPowerProfile.powerSaver);
    expect(controller.bleDutyCyclePercent, 27);
    expect(controller.activeBleScans, 1);
    expect(controller.scanStarts, 8);
    expect(controller.storeForwardEntries, 3);
    expect(controller.activeTransports, {'ble', 'lan'});
  });

  test('un evento inválido no cancela los eventos posteriores', () async {
    platform.emit({
      'type': 'message',
      'message': {'id': 7, 'content': Object()},
    });
    platform.emit({
      'type': 'message',
      'message': {
        'id': 'valid-after-invalid',
        'sender': 'Ana',
        'content': 'Seguimos conectados',
        'senderPeerId': 'peer-1234',
        'private': false,
        'mine': false,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });

    await pumpEvents();

    expect(
      controller.messages.any((message) => message.id == 'valid-after-invalid'),
      isTrue,
    );
  });

  test(
    'interop OFF presenta externos sin chat y conserva su SOS marcado',
    () async {
      const externalPeerId = 'bitchat-external';
      platform.emit({
        'type': 'snapshot',
        'status': 'active',
        'nickname': 'Yo',
        'peerId': 'local-peer',
        'role': 'PHONE_RELAY',
        'peers': [
          {
            'id': externalPeerId,
            'nickname': 'BitChat',
            'lastSeen': DateTime.now().millisecondsSinceEpoch,
            'online': true,
            'secure': false,
            'hearthbitVerified': false,
          },
        ],
      });
      await pumpEvents();

      final externalPeer = controller.peerById(externalPeerId)!;
      expect(controller.canChatWithPeer(externalPeer), isFalse);
      final sendResult = await controller.sendPrivate(
        externalPeer,
        'No enviar',
      );
      expect(sendResult.disposition, PrivateMessageSendDisposition.failed);
      expect(repository.outbox, isEmpty);

      platform.emit({
        'type': 'message',
        'message': {
          'id': 'external-sos',
          'sender': 'BitChat',
          'content': 'SOS|Ayuda||',
          'senderPeerId': externalPeerId,
          'private': false,
          'mine': false,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'channel': 'sos',
          'external': true,
        },
      });
      await pumpEvents();

      final sos = controller.messages.singleWhere(
        (message) => message.id == 'external-sos',
      );
      expect(sos.isSos, isTrue);
      expect(sos.external, isTrue);
    },
  );

  test('limita mensajes en memoria y conserva los más recientes', () async {
    final initialMessages = List.generate(
      520,
      (index) => MeshMessage(
        id: 'message-$index',
        sender: 'Peer',
        content: 'Mensaje $index',
        senderPeerId: 'peer',
        isPrivate: false,
        isMine: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(index),
      ),
    );
    final localController = MeshController(
      platform: _FakePlatform(),
      repository: _FakeRepository(initialMessages: initialMessages),
    );
    addTearDown(localController.dispose);

    await localController.initialize();

    expect(
      localController.messages,
      hasLength(MeshController.maximumMessagesInMemory),
    );
    expect(localController.messages.first.id, 'message-20');
    expect(localController.messages.last.id, 'message-519');
  });

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
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
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
            'lastSeen': DateTime.now().millisecondsSinceEpoch,
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

  test('encola un mensaje privado si el peer está desconectado', () async {
    final peer = MeshPeer(
      id: 'peer-offline',
      nickname: 'Rescate',
      lastSeen: DateTime.now(),
      secure: false,
      hearthbitVerified: true,
    );

    final result = await controller.sendPrivate(peer, 'Sigo aquí');

    expect(result.disposition, PrivateMessageSendDisposition.queued);
    expect(platform.privateMessages, isEmpty);
    expect(repository.outbox, hasLength(1));
    expect(repository.outbox.single.content, 'Sigo aquí');
    expect(controller.messages.single.isPending, isTrue);
  });

  test(
    'peer stale queda offline y drena su DM una sola vez tras rekey',
    () async {
      const remoteId = 'peer-stale';
      final staleAt = DateTime.now().subtract(
        MeshController.peerReachabilityWindow + const Duration(seconds: 1),
      );
      platform.emit(
        peerSnapshot(
          peerId: remoteId,
          secure: true,
          online: true,
          lastSeen: staleAt,
        ),
      );
      platform.emit({
        'type': 'message',
        'message': {
          'id': 'private-before-gap',
          'sender': 'Rescate',
          'content': 'Antes del corte',
          'senderPeerId': remoteId,
          'private': true,
          'mine': false,
          'timestamp': staleAt.millisecondsSinceEpoch,
        },
      });
      await pumpEvents();

      expect(controller.peers, isEmpty);
      expect(controller.peerById(remoteId), isNull);
      expect(controller.isPeerOnline(remoteId), isFalse);
      expect(controller.conversations.single.isOnline, isFalse);

      final result = await controller.sendPrivate(
        controller.knownPeerById(remoteId)!,
        'Después de dos horas',
      );
      final localId = repository.outbox.single.localId;

      expect(result.disposition, PrivateMessageSendDisposition.queued);
      expect(platform.privateMessages, isEmpty);
      expect(platform.privateChannelRequests, isEmpty);
      expect(controller.messages.last.id, localId);
      expect(controller.messages.last.isPending, isTrue);

      platform.emit(
        peerSnapshot(peerId: remoteId, secure: false, online: true),
      );
      await pumpEvents();

      expect(controller.isPeerOnline(remoteId), isTrue);
      expect(platform.privateChannelRequests, [remoteId]);
      expect(platform.privateMessages, isEmpty);

      platform.privateMessageGate = Completer<String>();
      platform.emit(peerSnapshot(peerId: remoteId, secure: true, online: true));
      platform.emit(peerSnapshot(peerId: remoteId, secure: true, online: true));
      await pumpEvents();
      await pumpEvents();

      expect(platform.privateMessages, hasLength(1));
      expect(platform.privateMessages.single.messageId, localId);
      expect(repository.outbox, hasLength(1));

      platform.privateMessageGate!.complete(localId);
      await controller.retryPendingPrivateMessages();

      expect(platform.privateMessages, hasLength(1));
      expect(repository.outbox, isEmpty);
      expect(
        controller.messages.where((message) => message.id == localId),
        hasLength(1),
      );
      expect(
        controller.messages
            .singleWhere((message) => message.id == localId)
            .isPending,
        isFalse,
      );
    },
  );

  test(
    'un peer online sin canal seguro inicia Noise antes de drenar el mensaje',
    () async {
      const remoteId = 'peer-handshake';
      platform.emit(peerSnapshot(peerId: remoteId, secure: false));
      await pumpEvents();

      final result = await controller.sendPrivate(
        controller.peerById(remoteId)!,
        'Iniciar canal',
      );

      expect(result.disposition, PrivateMessageSendDisposition.queued);
      expect(platform.privateChannelRequests, [remoteId]);
      expect(platform.privateMessages, isEmpty);
      expect(repository.outbox, hasLength(1));

      platform.emit(peerSnapshot(peerId: remoteId, secure: true));
      await pumpEvents();
      await controller.retryPendingPrivateMessages();

      expect(platform.privateMessages, hasLength(1));
      expect(repository.outbox, isEmpty);
    },
  );

  test(
    'reintenta el outbox cuando el peer vuelve seguro y conectado',
    () async {
      const remoteId = 'peer-retry';
      final peer = MeshPeer(
        id: remoteId,
        nickname: 'Rescate',
        lastSeen: DateTime.now(),
        secure: false,
        hearthbitVerified: true,
      );
      await controller.sendPrivate(peer, 'Mensaje pendiente');
      final localId = repository.outbox.single.localId;

      platform.emit(peerSnapshot(peerId: remoteId, secure: true));
      await pumpEvents();
      await controller.retryPendingPrivateMessages();

      expect(platform.privateMessages, hasLength(1));
      expect(platform.privateMessages.single.peerId, remoteId);
      expect(platform.privateMessages.single.content, 'Mensaje pendiente');
      expect(platform.privateMessages.single.messageId, localId);
      expect(repository.outbox, isEmpty);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.isPending, isFalse);
      expect(controller.messages.single.content, 'Mensaje pendiente');
    },
  );

  test('carga y reintenta el outbox después de reiniciar', () async {
    const remoteId = 'peer-restart';
    repository.outbox.add(
      PendingPrivateMessage(
        localId: 'local-persisted',
        recipientPeerId: remoteId,
        content: 'Persistido',
        createdAt: DateTime.now(),
      ),
    );
    controller.dispose();
    platform = _FakePlatform();
    controller = MeshController(platform: platform, repository: repository);
    await controller.initialize();

    expect(controller.messages.single.isPending, isTrue);

    platform.emit(peerSnapshot(peerId: remoteId, secure: true));
    await pumpEvents();
    await controller.retryPendingPrivateMessages();

    expect(platform.privateMessages.single.content, 'Persistido');
    expect(platform.privateMessages.single.messageId, 'local-persisted');
    expect(repository.outbox, isEmpty);
    expect(controller.messages.single.isPending, isFalse);
  });

  test('reutiliza el mismo ID al reintentar un mensaje pendiente', () async {
    const remoteId = 'peer-idempotent';
    final peer = MeshPeer(
      id: remoteId,
      nickname: 'Rescate',
      lastSeen: DateTime.now(),
      secure: false,
      hearthbitVerified: true,
    );
    await controller.sendPrivate(peer, 'No duplicar');
    final localId = repository.outbox.single.localId;
    platform.privateMessageError = StateError('respuesta perdida');

    platform.emit(peerSnapshot(peerId: remoteId, secure: true));
    await pumpEvents();
    await controller.retryPendingPrivateMessages();

    expect(repository.outbox, hasLength(1));
    expect(
      platform.privateMessages.map((message) => message.messageId).toSet(),
      {localId},
    );
    final failedAttempts = platform.privateMessages.length;

    platform.privateMessageError = null;
    await controller.retryPendingPrivateMessages();

    expect(platform.privateMessages, hasLength(failedAttempts + 1));
    expect(
      platform.privateMessages.map((message) => message.messageId).toSet(),
      {localId},
    );
    expect(repository.outbox, isEmpty);
  });

  test('serializa reintentos aunque lleguen snapshots duplicados', () async {
    const remoteId = 'peer-serialized';
    final peer = MeshPeer(
      id: remoteId,
      nickname: 'Rescate',
      lastSeen: DateTime.now(),
      secure: false,
      hearthbitVerified: true,
    );
    await controller.sendPrivate(peer, 'Solo una vez');
    platform.privateMessageGate = Completer<String>();

    platform.emit(peerSnapshot(peerId: remoteId, secure: true));
    platform.emit(peerSnapshot(peerId: remoteId, secure: true));
    await pumpEvents();
    await pumpEvents();

    expect(platform.privateMessages, hasLength(1));

    platform.privateMessageGate!.complete('private-accepted');
    await controller.retryPendingPrivateMessages();

    expect(platform.privateMessages, hasLength(1));
    expect(repository.outbox, isEmpty);
  });

  test('devuelve fallo explícito si el envío privado es rechazado', () async {
    const remoteId = 'peer-error';
    platform.emit(peerSnapshot(peerId: remoteId, secure: true));
    await pumpEvents();
    platform.privateMessageError = StateError('sesión cerrada');
    final peer = controller.peerById(remoteId)!;

    final result = await controller.sendPrivate(peer, 'No borrar');

    expect(result.disposition, PrivateMessageSendDisposition.failed);
    expect(result.error, contains('sesión cerrada'));
    expect(repository.outbox, hasLength(1));
    expect(controller.messages.single.isPending, isTrue);
  });

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

  test(
    'restaura la malla solicitada y conserva una detención explícita',
    () async {
      final preferences = AppPreferences();
      await preferences.initialize();
      await preferences.setMeshDesiredActive(true);
      final restoredPlatform = _FakePlatform();
      final restored = MeshController(
        platform: restoredPlatform,
        repository: _FakeRepository(),
        preferences: preferences,
      );

      await restored.initialize();

      expect(restoredPlatform.startCalls, 1);
      expect(restored.status, MeshConnectionStatus.starting);

      await restored.stop();
      expect(preferences.meshDesiredActive, isFalse);

      restored.dispose();
      preferences.dispose();
    },
  );

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

  test(
    'el modo rescate delega pings al scheduler nativo y se detiene',
    () async {
      platform.emit({'type': 'status', 'status': 'active'});
      await pumpEvents();

      await controller.setRescueMode(
        true,
        interval: const Duration(milliseconds: 40),
      );
      expect(controller.rescueMode, isTrue);
      expect(platform.sosCalls, 1);
      expect(
        platform.radarConsentCalls,
        contains((enabled: true, minutes: 30)),
      );
      expect(
        platform.radarConsentCalls
            .where((call) => call.enabled)
            .map((call) => call.minutes),
        everyElement(30),
      );
      expect(
        platform.radarConsentCalls.where((call) => call.enabled).length,
        2,
      );
      expect(controller.lastRescuePing, isNotNull);
      expect(platform.rescueConfigurations.last, isTrue);

      await controller.setRescueMode(false);
      expect(controller.rescueMode, isFalse);
      expect(platform.radarConsentCalls.last.enabled, isFalse);
      expect(platform.rescueConfigurations.last, isFalse);
    },
  );

  test('SOS conserva frames firmados para retransmisión por QR', () async {
    await controller.setRescueMode(
      true,
      description: 'Estoy atrapado',
      locationPrecision: SosLocationPrecision.none,
    );

    final qr = controller.latestSosQr;
    expect(qr, isNotNull);
    expect(qr!.announcementFrame, [1, 2, 3]);
    expect(qr.messageFrame, [4, 5, 6]);
    expect(qr.fallbackText, contains('Estoy atrapado'));
    expect(qr.fallbackText, contains(controller.peerId));

    await controller.setRescueMode(false);
    expect(controller.latestSosQr, isNull);
  });

  test('baliza emite SOS firmado y la escucha lo reinyecta', () async {
    await controller.setRescueMode(
      true,
      description: 'Necesito rescate',
      locationPrecision: SosLocationPrecision.none,
    );
    await controller.startLocalBeacon();

    expect(controller.acousticSosBroadcasting, isTrue);
    expect(acousticSos.broadcastFrames, [
      [1, 2, 3],
      [4, 5, 6],
    ]);

    expect(await controller.startAcousticSosListening(), isTrue);
    await acousticSos.receiver?.call(Uint8List.fromList([9, 8, 7]));
    expect(platform.emergencyLanFrames, [
      [9, 8, 7],
    ]);

    await controller.stopLocalBeacon();
    await controller.stopAcousticSosListening();
    expect(controller.acousticSosBroadcasting, isFalse);
    expect(controller.acousticSosListening, isFalse);
  });

  test('restaura modo rescate vigente después de reiniciar Flutter', () async {
    final now = DateTime.now();
    platform.rescueState = NativeRescueState(
      active: true,
      description: 'Persona lesionada',
      startedAt: now.subtract(const Duration(minutes: 3)),
      lastPingAt: now.subtract(const Duration(seconds: 20)),
      expiresAt: now.add(const Duration(hours: 2)),
    );
    controller.dispose();
    controller = MeshController(platform: platform, repository: repository);

    await controller.initialize();

    expect(controller.rescueMode, isTrue);
    expect(controller.rescueStartedAt, isNotNull);
    expect(controller.lastRescuePing, isNotNull);
    expect(controller.rescueExpiresAt, platform.rescueState.expiresAt);
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

  test(
    'solicitud de baliza requiere respuesta explícita fuera de rescate',
    () async {
      final expiresAt = DateTime.now().add(const Duration(minutes: 2));
      platform.emit({
        'type': 'beaconRequest',
        'requestId': '00112233445566778899aabbccddeeff',
        'peerId': '0011223344556677',
        'nickname': 'Rescatista',
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'flags': 0x07,
        'autoAccepted': false,
      });
      await pumpEvents();

      expect(controller.pendingBeaconRequest?.nickname, 'Rescatista');
      expect(platform.startLocalBeaconCalls, 0);

      await controller.respondToBeaconRequest(true);
      expect(controller.pendingBeaconRequest, isNull);
      expect(platform.beaconResponses.single, (
        requestId: '00112233445566778899aabbccddeeff',
        accept: true,
      ));
    },
  );

  test('estado nativo controla inicio y fin de la baliza local', () async {
    final expiresAt = DateTime.now().add(const Duration(minutes: 5));
    platform.emit({
      'type': 'beaconState',
      'scope': 'local',
      'status': 'active',
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'flags': 0x07,
    });
    await pumpEvents();
    expect(controller.localBeaconActive, isTrue);
    expect(controller.localBeaconExpiresAt, isNotNull);

    platform.emit({
      'type': 'beaconState',
      'scope': 'local',
      'status': 'stopped',
    });
    await pumpEvents();
    expect(controller.localBeaconActive, isFalse);
    expect(controller.localBeaconExpiresAt, isNull);
  });

  test(
    'solicitud autoaceptada por consentimiento previo no abre diálogo',
    () async {
      platform.emit({
        'type': 'beaconRequest',
        'requestId': 'ffeeddccbbaa99887766554433221100',
        'peerId': '0011223344556677',
        'nickname': 'Rescatista',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
        'flags': 0x07,
        'autoAccepted': true,
      });
      await pumpEvents();

      expect(controller.pendingBeaconRequest, isNull);
      expect(platform.beaconResponses, isEmpty);
    },
  );

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

  test('check-in al círculo usa exclusivamente canales privados', () async {
    const first = '1111222233334444';
    const second = '8899aabbccddeeff';
    platform.emit(peerSnapshot(peerId: first, secure: true));
    platform.emit(peerSnapshot(peerId: second, secure: true));
    await pumpEvents();

    final accepted = await controller.sendCircleCheckIn(
      CheckInStatus.ok,
      'Estamos bien',
      const [first, second],
    );

    expect(accepted, 2);
    expect(platform.publicMessages, isEmpty);
    final recipients = {
      ...platform.privateMessages.map((item) => item.peerId),
      ...repository.outbox.map((item) => item.recipientPeerId),
    };
    expect(recipients, {first, second});
    expect(
      platform.privateMessages.every(
        (item) => item.content.contains(EmergencyCheckIn.marker),
      ),
      isTrue,
    );
  });

  test('redondea coordenadas aproximadas a tres decimales', () {
    expect(MeshController.coarsenEmergencyCoordinate(4.609710), 4.610);
    expect(MeshController.coarsenEmergencyCoordinate(-74.081750), -74.082);
  });

  test(
    'simulacro solo usa sendPublic y no toca subsistemas de emergencia',
    () async {
      platform.emit({'type': 'status', 'status': 'active'});
      await pumpEvents();

      await controller.activateDrill();
      await controller.sendDrillCheckIn(
        CheckInStatus.needsHelp,
        'Solicitud de ayuda de práctica',
      );

      expect(controller.drillModeEnabled, isTrue);
      expect(controller.rescueMode, isFalse);
      expect(controller.survivalMode, isFalse);
      expect(platform.publicMessages, hasLength(1));
      expect(platform.publicMessages.single.channel, 'drill');
      expect(
        platform.publicMessages.single.content,
        contains(DrillCheckIn.marker),
      );
      expect(platform.publicMessages.single.content, isNot(startsWith('SOS|')));
      expect(platform.sosCalls, 0);
      expect(platform.radarConsentCalls, isEmpty);
      expect(platform.startLocalBeaconCalls, 0);
      expect(platform.stopLocalBeaconCalls, 0);
      expect(platform.beaconResponses, isEmpty);
    },
  );

  test('simulacro bloquea radar y baliza física', () async {
    await controller.activateDrill();

    await controller.allowRadarFor15Minutes();
    await controller.startLocalBeacon();

    expect(platform.radarConsentCalls, isEmpty);
    expect(platform.startLocalBeaconCalls, 0);
  });

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

  test('consume ubicación privada de radar sin guardarla como chat', () async {
    final timestamp = DateTime.now();
    platform.emit({
      'type': 'message',
      'message': {
        'id': 'radar-location-1',
        'sender': 'Rescate',
        'content': RadarLocationUpdate.encode(
          latitude: 4.60971,
          longitude: -74.08175,
          accuracyMeters: 3.5,
          timestamp: timestamp,
        ),
        'senderPeerId': 'peer-radar',
        'private': true,
        'mine': false,
        'timestamp': timestamp.millisecondsSinceEpoch,
      },
    });
    await pumpEvents();

    expect(controller.messages, isEmpty);
    expect(repository.saved, isEmpty);
    expect(controller.peerLocations.latestFor('peer-radar')?.latitude, 4.60971);
  });

  test('SOS pasa de emitido a confirmado con ACK único por peer', () async {
    platform.emit({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    await pumpEvents();

    await controller.sendSos('Ayuda');
    final relayed = controller.emergencyDeliveries.single;
    expect(relayed.state, EmergencyDeliveryState.relayed);
    expect(relayed.confirmationCount, 0);

    platform.emit({
      'type': 'emergencyAck',
      'canonicalHash': relayed.canonicalHash,
      'peerId': 'peer-confirming',
    });
    await pumpEvents();
    await pumpEvents();

    final acknowledged = controller.emergencyDeliveries.single;
    expect(acknowledged.state, EmergencyDeliveryState.acknowledged);
    expect(acknowledged.confirmationCount, 1);
  });

  test('reintenta una vez el ACK que se adelanta a la persistencia', () async {
    platform.emit({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    await pumpEvents();
    await controller.sendSos('Ayuda');
    final delivery = controller.emergencyDeliveries.single;
    repository.acknowledgementMisses = 1;

    platform.emit({
      'type': 'emergencyAck',
      'canonicalHash': delivery.canonicalHash,
      'peerId': 'peer-racing',
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await pumpEvents();

    expect(
      controller.emergencyDeliveries.single.state,
      EmergencyDeliveryState.acknowledged,
    );
  });

  test('reintento de SOS conserva el nuevo hash nativo', () async {
    platform.emit({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    await pumpEvents();
    await controller.sendSos('Ayuda');
    final original = controller.emergencyDeliveries.single;
    final originalHash = original.canonicalHash;
    const retryHash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    platform.retryEmergencyResult = retryHash;

    await controller.retryEmergency(original.localId);

    final retried = controller.emergencyDeliveries.single;
    expect(platform.retryEmergencyCalls, [originalHash]);
    expect(retried.canonicalHash, retryHash);
    expect(repository.emergencyOutbox.single.canonicalHash, retryHash);
    expect(platform.sosCalls, 1);

    platform.emit({
      'type': 'emergencyAck',
      'canonicalHash': originalHash,
      'peerId': 'peer-old-attempt',
    });
    platform.emit({
      'type': 'emergencyAck',
      'canonicalHash': retryHash,
      'peerId': 'peer-new-attempt',
    });
    await pumpEvents();
    await pumpEvents();

    expect(
      controller.emergencyDeliveries.single.state,
      EmergencyDeliveryState.acknowledged,
    );
    expect(controller.emergencyDeliveries.single.confirmationCount, 2);
  });

  test('el borrado de pánico elimina el consentimiento local', () async {
    final previousPeerId = controller.peerId;
    await controller.allowRadarFor15Minutes();
    await controller.panicWipe();

    expect(controller.radarConsentActive, isFalse);
    expect(controller.peerId, isNot(previousPeerId));
    expect(controller.peerId, 'fresh-peer-id');
    expect(repository.loaded, isEmpty);
    expect(repository.outbox, isEmpty);
    expect(platform.panicWipeCalls, 1);
  });
}
