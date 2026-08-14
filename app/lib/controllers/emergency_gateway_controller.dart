import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mesh_models.dart';
import '../services/app_preferences.dart';
import '../services/secure_storage_config.dart';
import '../services/tls_peer_verifier.dart';
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
    this.trustMode = TlsTrustMode.system,
    this.certificateSha256,
    this.includeSensitiveContent = false,
    this.includeCoordinates = false,
  });

  final EmergencyGatewayKind kind;
  final String server;
  final String destination;
  final String username;
  final int port;
  final bool tls;
  final TlsTrustMode trustMode;
  final String? certificateSha256;
  final bool includeSensitiveContent;
  final bool includeCoordinates;

  String? get validationError {
    if (port < 1 || port > 65535) return 'Gateway port is invalid';
    if (!tls) return 'TLS is required for emergency gateways';
    if (trustMode == TlsTrustMode.pinned &&
        !TlsPeerVerifier.isValidFingerprint(certificateSha256)) {
      return 'Pinned TLS requires a SHA-256 certificate fingerprint';
    }
    if (destination.trim().isEmpty) return 'Gateway destination is empty';
    if (kind == EmergencyGatewayKind.matrix) {
      final uri = Uri.tryParse(server.trim());
      if (uri == null ||
          uri.scheme.toLowerCase() != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return 'Matrix homeserver must be a valid HTTPS URL';
      }
    } else {
      final host = server.trim();
      if (host.isEmpty ||
          host.contains('://') ||
          host.contains('/') ||
          destination.contains('+') ||
          destination.contains('#')) {
        return 'MQTT requires a TLS hostname and a topic without wildcards';
      }
    }
    return null;
  }

  bool get isValid => validationError == null;
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
       _secureStorage = secureStorage ?? hearthBitSecureStorage,
       _httpClient = httpClient ?? http.Client();

  static const _kindKey = 'gateway.kind';
  static const _serverKey = 'gateway.server';
  static const _destinationKey = 'gateway.destination';
  static const _usernameKey = 'gateway.username';
  static const _portKey = 'gateway.port';
  static const _tlsKey = 'gateway.tls';
  static const _trustModeKey = 'gateway.tlsTrustMode.v1';
  static const _certificateKey = 'gateway.certificateSha256.v1';
  static const _includeSensitiveKey = 'gateway.includeSensitiveContent.v1';
  static const _includeCoordinatesKey = 'gateway.includeCoordinates.v1';
  static const _publishedKey = 'gateway.publishedIds';
  static const _secretKey = 'gateway.secret';
  static const _pendingMessagesKey = 'gateway.pendingMessages.v1';

  final MeshController mesh;
  final AppPreferences preferences;
  final Connectivity _connectivity;
  final SharedPreferencesAsync _storage;
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;
  final Set<String> _publishedIds = {};
  final Map<String, MeshMessage> _pendingMessages = {};
  final Map<String, String> _tofuClaims = {};
  final Map<String, Future<void>> _tofuWrites = {};
  final Map<String, (Object, StackTrace)> _tofuWriteErrors = {};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;
  int _consecutiveFailures = 0;
  EmergencyGatewayConfig? config;
  bool internetTransportAvailable = false;
  bool publishing = false;
  String? lastError;
  DateTime? lastPublishedAt;

  int get pendingCount => {
    ..._pendingMessages.keys,
    ..._eligibleMessages()
        .where((message) => !_publishedIds.contains(message.id))
        .map((message) => message.id),
  }.length;

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
        trustMode: _trustModeFromName(await _storage.getString(_trustModeKey)),
        certificateSha256: await _storage.getString(_certificateKey),
        includeSensitiveContent:
            await _storage.getBool(_includeSensitiveKey) ?? false,
        includeCoordinates:
            await _storage.getBool(_includeCoordinatesKey) ?? false,
      );
    }
    _publishedIds.addAll(
      await _storage.getStringList(_publishedKey) ?? const [],
    );
    _restorePendingMessages(
      await _secureStorage.read(key: _pendingMessagesKey),
    );
    mesh.addListener(_schedulePublish);
    preferences.addListener(_schedulePublish);
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivity,
    );
    _handleConnectivity(await _connectivity.checkConnectivity());
  }

  Future<void> saveConfig(EmergencyGatewayConfig value, String secret) async {
    final validationError = value.validationError;
    if (validationError != null) throw ArgumentError(validationError);
    config = value;
    await Future.wait([
      _storage.setString(_kindKey, value.kind.name),
      _storage.setString(_serverKey, value.server.trim()),
      _storage.setString(_destinationKey, value.destination.trim()),
      _storage.setString(_usernameKey, value.username.trim()),
      _storage.setInt(_portKey, value.port),
      _storage.setBool(_tlsKey, value.tls),
      _storage.setString(_trustModeKey, value.trustMode.name),
      if (value.certificateSha256 == null)
        _storage.remove(_certificateKey)
      else
        _storage.setString(
          _certificateKey,
          TlsPeerVerifier.normalizeFingerprint(value.certificateSha256)!,
        ),
      _storage.setBool(_includeSensitiveKey, value.includeSensitiveContent),
      _storage.setBool(_includeCoordinatesKey, value.includeCoordinates),
      if (secret.isNotEmpty)
        _secureStorage.write(key: _secretKey, value: secret),
    ]);
    notifyListeners();
    _schedulePublish();
  }

  Future<void> panicWipe() async {
    await Future.wait([
      _storage.remove(_kindKey),
      _storage.remove(_serverKey),
      _storage.remove(_destinationKey),
      _storage.remove(_usernameKey),
      _storage.remove(_portKey),
      _storage.remove(_tlsKey),
      _storage.remove(_trustModeKey),
      _storage.remove(_certificateKey),
      _storage.remove(_includeSensitiveKey),
      _storage.remove(_includeCoordinatesKey),
      _storage.remove(_publishedKey),
      _secureStorage.delete(key: _secretKey),
      _secureStorage.delete(key: _pendingMessagesKey),
      preferences.setGatewayOptIn(false),
    ]);
    config = null;
    _publishedIds.clear();
    _pendingMessages.clear();
    _retryTimer?.cancel();
    _retryTimer = null;
    _consecutiveFailures = 0;
    publishing = false;
    lastError = null;
    lastPublishedAt = null;
    notifyListeners();
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
    if (publishing) return;
    if (preferences.gatewayOptIn) {
      await _refreshPendingQueue();
    }
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
      for (final message in _pendingMessages.values.toList(growable: false)) {
        if (_publishedIds.contains(message.id)) continue;
        await _publish(currentConfig, secret, message);
        _publishedIds.add(message.id);
        _pendingMessages.remove(message.id);
        await _persistPendingMessages();
        lastPublishedAt = DateTime.now();
      }
      _consecutiveFailures = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      final retained = _publishedIds.toList(growable: false);
      await _storage.setStringList(
        _publishedKey,
        retained.length <= 256
            ? retained
            : retained.sublist(retained.length - 256),
      );
    } catch (error) {
      lastError = error.toString();
      _scheduleRetry();
    } finally {
      publishing = false;
      notifyListeners();
    }
  }

  Iterable<MeshMessage> _eligibleMessages() =>
      mesh.messages.where(isEmergencyEligible);

  Future<void> _refreshPendingQueue() async {
    for (final message in _eligibleMessages()) {
      if (!_publishedIds.contains(message.id)) {
        _pendingMessages[message.id] = message;
      }
    }
    while (_pendingMessages.length > 256) {
      _pendingMessages.remove(_pendingMessages.keys.first);
    }
    await _persistPendingMessages();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _consecutiveFailures = (_consecutiveFailures + 1).clamp(1, 8);
    final delay = Duration(seconds: 1 << _consecutiveFailures);
    _retryTimer = Timer(delay, _schedulePublish);
  }

  static bool isEmergencyEligible(MeshMessage message) =>
      !message.isDrill && (message.isSos || message.isCheckIn);

  static Map<String, Object?> _payload(
    EmergencyGatewayConfig config,
    MeshMessage message,
  ) {
    final payload = <String, Object?>{
      'schema': 'org.hearthbit.emergency.v1',
      'id': message.id,
      'timestamp': message.timestamp.toUtc().toIso8601String(),
      'type': message.isSos ? 'sos' : 'checkIn',
    };
    if (config.includeSensitiveContent) {
      payload
        ..['sender'] = message.sender
        ..['senderPeerId'] = message.senderPeerId
        ..['content'] = message.content;
    }
    if (config.includeCoordinates) {
      final checkIn = message.checkIn;
      final latitude = message.isSos ? message.sosLatitude : checkIn?.latitude;
      final longitude = message.isSos
          ? message.sosLongitude
          : checkIn?.longitude;
      if (latitude != null && longitude != null) {
        payload
          ..['latitude'] = latitude
          ..['longitude'] = longitude;
      }
    }
    return payload;
  }

  @visibleForTesting
  static Map<String, Object?> buildPayloadForTest(
    EmergencyGatewayConfig config,
    MeshMessage message,
  ) => _payload(config, message);

  Future<void> _persistPendingMessages() {
    final encoded = jsonEncode([
      for (final message in _pendingMessages.values)
        {
          'id': message.id,
          'sender': message.sender,
          'senderPeerId': message.senderPeerId,
          'timestamp': message.timestamp.millisecondsSinceEpoch,
          'content': message.content,
          'channel': message.channel,
          'private': message.isPrivate,
          'mine': message.isMine,
        },
    ]);
    return _secureStorage.write(key: _pendingMessagesKey, value: encoded);
  }

  void _restorePendingMessages(String? encoded) {
    if (encoded == null || encoded.isEmpty) return;
    try {
      final entries = jsonDecode(encoded);
      if (entries is! List<Object?>) return;
      for (final entry in entries) {
        if (entry is! Map<String, Object?>) continue;
        final id = entry['id'];
        final timestamp = entry['timestamp'];
        if (id is! String || timestamp is! int) continue;
        final message = MeshMessage(
          id: id,
          sender: entry['sender'] as String? ?? '',
          content: entry['content'] as String? ?? '',
          senderPeerId: entry['senderPeerId'] as String? ?? '',
          isPrivate: entry['private'] as bool? ?? false,
          isMine: entry['mine'] as bool? ?? false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
          channel: entry['channel'] as String?,
        );
        if (isEmergencyEligible(message) && !_publishedIds.contains(id)) {
          _pendingMessages[id] = message;
        }
      }
    } on FormatException {
      // Una cola dañada no debe activar publicaciones de contenido ambiguo.
      _pendingMessages.clear();
    }
  }

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
      port: config.port,
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
    final verifier = await _tlsVerifier(config);
    IOClient? pinnedClient;
    http.Client client = _httpClient;
    if (config.trustMode != TlsTrustMode.system) {
      final ioClient = HttpClient(context: verifier.createSecurityContext())
        ..badCertificateCallback = (certificate, host, port) {
          final endpointMatches = host == uri.host && port == uri.port;
          return endpointMatches &&
              _verifyAndClaimCertificate(config, verifier, certificate);
        };
      pinnedClient = IOClient(ioClient);
      client = pinnedClient;
    }
    try {
      final response = await client
          .put(
            uri,
            headers: {
              'authorization': 'Bearer $accessToken',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'msgtype': 'm.notice',
              'body': jsonEncode(_payload(config, message)),
              'org.hearthbit.emergency': _payload(config, message),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Matrix gateway returned ${response.statusCode}');
      }
      await _persistObservedTofu(config, verifier);
    } finally {
      pinnedClient?.close();
      await _awaitTofuPersistence(config);
    }
  }

  Future<void> _publishMqtt(
    EmergencyGatewayConfig config,
    String password,
    MeshMessage message,
  ) async {
    final verifier = await _tlsVerifier(config);
    final client =
        MqttServerClient.withPort(
            config.server,
            'hearthbit-${_shortPeerId()}',
            config.port,
          )
          ..secure = config.tls
          ..logging(on: false)
          ..keepAlivePeriod = 20;
    if (config.trustMode != TlsTrustMode.system) {
      client
        ..securityContext = verifier.createSecurityContext()
        ..onBadCertificate = (certificate) =>
            _verifyAndClaimCertificate(config, verifier, certificate);
    }
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
      await _persistObservedTofu(config, verifier);
      final builder = MqttClientPayloadBuilder()
        ..addUTF8String(jsonEncode(_payload(config, message)));
      final published = client.published;
      if (published == null) {
        throw StateError('MQTT publish acknowledgements are unavailable');
      }
      final acknowledged = Completer<void>();
      late final StreamSubscription<MqttPublishMessage> subscription;
      var messageIdentifier = 0;
      subscription = published.listen((message) {
        if (message.variableHeader?.messageIdentifier == messageIdentifier &&
            !acknowledged.isCompleted) {
          acknowledged.complete();
        }
      });
      messageIdentifier = client.publishMessage(
        config.destination,
        MqttQos.atLeastOnce,
        builder.payload!,
      );
      try {
        await acknowledged.future.timeout(const Duration(seconds: 15));
      } finally {
        await subscription.cancel();
      }
    } finally {
      try {
        await _awaitTofuPersistence(config);
      } finally {
        client.disconnect();
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _connectivitySubscription?.cancel();
    mesh.removeListener(_schedulePublish);
    preferences.removeListener(_schedulePublish);
    _httpClient.close();
    super.dispose();
  }

  String _shortPeerId() =>
      mesh.peerId.length <= 12 ? mesh.peerId : mesh.peerId.substring(0, 12);

  Future<TlsPeerVerifier> _tlsVerifier(EmergencyGatewayConfig config) async {
    await _awaitTofuPersistence(config);
    final stored = config.trustMode == TlsTrustMode.tofu
        ? await _secureStorage.read(key: _tofuStorageKey(config))
        : null;
    return TlsPeerVerifier(
      mode: config.trustMode,
      configuredFingerprint: config.certificateSha256,
      storedFingerprint: stored,
    );
  }

  Future<void> _persistObservedTofu(
    EmergencyGatewayConfig config,
    TlsPeerVerifier verifier,
  ) async {
    final fingerprint = verifier.observedFingerprint;
    if (config.trustMode == TlsTrustMode.tofu && fingerprint != null) {
      if (!_claimTofuFingerprint(config, fingerprint)) {
        throw StateError('Conflicting TLS certificate during TOFU persistence');
      }
      await _awaitTofuPersistence(config);
    }
  }

  bool _verifyAndClaimCertificate(
    EmergencyGatewayConfig config,
    TlsPeerVerifier verifier,
    X509Certificate certificate,
  ) {
    if (!verifier.verifyCertificate(certificate)) return false;
    final fingerprint = verifier.observedFingerprint;
    return fingerprint == null || _claimTofuFingerprint(config, fingerprint);
  }

  bool _claimTofuFingerprint(
    EmergencyGatewayConfig config,
    String fingerprint,
  ) {
    if (config.trustMode != TlsTrustMode.tofu) return true;
    final normalized = TlsPeerVerifier.normalizeFingerprint(fingerprint);
    if (normalized == null) return false;
    final key = _tofuStorageKey(config);
    final claimed = _tofuClaims[key];
    if (claimed != null) return claimed == normalized;
    _tofuClaims[key] = normalized;
    _tofuWrites[key] = _secureStorage
        .write(key: key, value: normalized)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _tofuWriteErrors[key] = (error, stackTrace);
          },
        );
    return true;
  }

  Future<void> _awaitTofuPersistence(EmergencyGatewayConfig config) async {
    if (config.trustMode != TlsTrustMode.tofu) return;
    final key = _tofuStorageKey(config);
    await _tofuWrites[key];
    final failure = _tofuWriteErrors[key];
    if (failure != null) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }

  Future<void> resetTofuTrust(EmergencyGatewayConfig config) async {
    final key = _tofuStorageKey(config);
    try {
      await _tofuWrites[key];
    } catch (_) {
      // El reset explícito también debe recuperar una escritura previa fallida.
    }
    await _secureStorage.delete(key: key);
    _tofuWrites.remove(key);
    _tofuClaims.remove(key);
    _tofuWriteErrors.remove(key);
  }

  @visibleForTesting
  bool claimTofuFingerprintForTest(
    EmergencyGatewayConfig config,
    String fingerprint,
  ) => _claimTofuFingerprint(config, fingerprint);

  @visibleForTesting
  Future<void> awaitTofuPersistenceForTest(EmergencyGatewayConfig config) =>
      _awaitTofuPersistence(config);

  static String _tofuStorageKey(EmergencyGatewayConfig config) {
    final endpoint =
        '${config.kind.name}|${config.server.trim()}|${config.port}';
    return 'gateway.tls.tofu.${sha256.convert(utf8.encode(endpoint))}';
  }

  static TlsTrustMode _trustModeFromName(String? name) {
    for (final mode in TlsTrustMode.values) {
      if (mode.name == name) return mode;
    }
    return TlsTrustMode.system;
  }
}
