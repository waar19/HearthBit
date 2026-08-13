import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mesh_models.dart';
import '../services/app_preferences.dart';
import 'mesh_controller.dart';

enum EmergencyGatewayKind { matrix, mqtt }

class EmergencyGatewayConfig {
  const EmergencyGatewayConfig({
    required this.kind,
    required this.server,
    required this.destination,
    required this.username,
    required this.port,
    required this.tls,
  });

  final EmergencyGatewayKind kind;
  final String server;
  final String destination;
  final String username;
  final int port;
  final bool tls;

  bool get isValid =>
      server.trim().isNotEmpty && destination.trim().isNotEmpty && port > 0;
}

class EmergencyGatewayController extends ChangeNotifier {
  EmergencyGatewayController({
    required this.mesh,
    required this.preferences,
    Connectivity? connectivity,
    SharedPreferencesAsync? storage,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  }) : _connectivity = connectivity ?? Connectivity(),
       _storage = storage ?? SharedPreferencesAsync(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _httpClient = httpClient ?? http.Client();

  static const _kindKey = 'gateway.kind';
  static const _serverKey = 'gateway.server';
  static const _destinationKey = 'gateway.destination';
  static const _usernameKey = 'gateway.username';
  static const _portKey = 'gateway.port';
  static const _tlsKey = 'gateway.tls';
  static const _publishedKey = 'gateway.publishedIds';
  static const _secretKey = 'gateway.secret';

  final MeshController mesh;
  final AppPreferences preferences;
  final Connectivity _connectivity;
  final SharedPreferencesAsync _storage;
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;
  final Set<String> _publishedIds = {};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  EmergencyGatewayConfig? config;
  bool internetTransportAvailable = false;
  bool publishing = false;
  String? lastError;
  DateTime? lastPublishedAt;

  int get pendingCount => _eligibleMessages()
      .where((message) => !_publishedIds.contains(message.id))
      .length;

  Future<void> initialize() async {
    final kindName = await _storage.getString(_kindKey);
    final server = await _storage.getString(_serverKey);
    final destination = await _storage.getString(_destinationKey);
    if (server != null && destination != null) {
      config = EmergencyGatewayConfig(
        kind: kindName == 'mqtt'
            ? EmergencyGatewayKind.mqtt
            : EmergencyGatewayKind.matrix,
        server: server,
        destination: destination,
        username: await _storage.getString(_usernameKey) ?? '',
        port: await _storage.getInt(_portKey) ?? 443,
        tls: await _storage.getBool(_tlsKey) ?? true,
      );
    }
    _publishedIds.addAll(
      await _storage.getStringList(_publishedKey) ?? const [],
    );
    mesh.addListener(_schedulePublish);
    preferences.addListener(_schedulePublish);
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivity,
    );
    _handleConnectivity(await _connectivity.checkConnectivity());
  }

  Future<void> saveConfig(EmergencyGatewayConfig value, String secret) async {
    config = value;
    await Future.wait([
      _storage.setString(_kindKey, value.kind.name),
      _storage.setString(_serverKey, value.server.trim()),
      _storage.setString(_destinationKey, value.destination.trim()),
      _storage.setString(_usernameKey, value.username.trim()),
      _storage.setInt(_portKey, value.port),
      _storage.setBool(_tlsKey, value.tls),
      _secureStorage.write(key: _secretKey, value: secret),
    ]);
    notifyListeners();
    _schedulePublish();
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    internetTransportAvailable = results.any(
      (result) =>
          result != ConnectivityResult.none &&
          result != ConnectivityResult.bluetooth,
    );
    notifyListeners();
    _schedulePublish();
  }

  void _schedulePublish() {
    if (!publishing) unawaited(publishPending());
  }

  Future<void> publishPending() async {
    final currentConfig = config;
    if (!preferences.gatewayOptIn ||
        !internetTransportAvailable ||
        currentConfig == null ||
        !currentConfig.isValid ||
        publishing) {
      return;
    }
    publishing = true;
    lastError = null;
    notifyListeners();
    try {
      final secret = await _secureStorage.read(key: _secretKey) ?? '';
      for (final message in _eligibleMessages()) {
        if (_publishedIds.contains(message.id)) continue;
        await _publish(currentConfig, secret, message);
        _publishedIds.add(message.id);
        lastPublishedAt = DateTime.now();
      }
      final retained = _publishedIds.toList(growable: false);
      await _storage.setStringList(
        _publishedKey,
        retained.length <= 256
            ? retained
            : retained.sublist(retained.length - 256),
      );
    } catch (error) {
      lastError = error.toString();
    } finally {
      publishing = false;
      notifyListeners();
    }
  }

  Iterable<MeshMessage> _eligibleMessages() =>
      mesh.messages.where((message) => message.isSos || message.isCheckIn);

  Map<String, Object?> _payload(MeshMessage message) => {
    'schema': 'org.hearthbit.emergency.v1',
    'id': message.id,
    'sender': message.sender,
    'senderPeerId': message.senderPeerId,
    'timestamp': message.timestamp.toUtc().toIso8601String(),
    'type': message.isSos ? 'sos' : 'checkIn',
    'content': message.content,
  };

  Future<void> _publish(
    EmergencyGatewayConfig config,
    String secret,
    MeshMessage message,
  ) {
    return switch (config.kind) {
      EmergencyGatewayKind.matrix => _publishMatrix(config, secret, message),
      EmergencyGatewayKind.mqtt => _publishMqtt(config, secret, message),
    };
  }

  Future<void> _publishMatrix(
    EmergencyGatewayConfig config,
    String accessToken,
    MeshMessage message,
  ) async {
    if (accessToken.isEmpty) throw StateError('Matrix access token is empty');
    final base = Uri.parse(config.server);
    final uri = base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        '_matrix',
        'client',
        'v3',
        'rooms',
        config.destination,
        'send',
        'm.room.message',
        message.id,
      ],
    );
    final response = await _httpClient
        .put(
          uri,
          headers: {
            'authorization': 'Bearer $accessToken',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'msgtype': 'm.notice',
            'body': jsonEncode(_payload(message)),
            'org.hearthbit.emergency': _payload(message),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Matrix gateway returned ${response.statusCode}');
    }
  }

  Future<void> _publishMqtt(
    EmergencyGatewayConfig config,
    String password,
    MeshMessage message,
  ) async {
    final client =
        MqttServerClient.withPort(
            config.server,
            'hearthbit-${_shortPeerId()}',
            config.port,
          )
          ..secure = config.tls
          ..logging(on: false)
          ..keepAlivePeriod = 20;
    var connection = MqttConnectMessage()
        .withClientIdentifier('hearthbit-${_shortPeerId()}')
        .startClean();
    if (config.username.isNotEmpty) {
      connection = connection.authenticateAs(config.username, password);
    }
    client.connectionMessage = connection;
    try {
      await client.connect();
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw StateError('MQTT gateway connection failed');
      }
      final builder = MqttClientPayloadBuilder()
        ..addUTF8String(jsonEncode(_payload(message)));
      client.publishMessage(
        config.destination,
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    } finally {
      client.disconnect();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    mesh.removeListener(_schedulePublish);
    preferences.removeListener(_schedulePublish);
    _httpClient.close();
    super.dispose();
  }

  String _shortPeerId() =>
      mesh.peerId.length <= 12 ? mesh.peerId : mesh.peerId.substring(0, 12);
}
