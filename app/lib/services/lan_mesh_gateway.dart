import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'diagnostics_log.dart';
import 'mesh_platform_service.dart';

const _serviceType = '_hearthbit._tcp.local';
const _multicastAddress = '224.0.0.251';
const _multicastPort = 5353;
const _magic = 'HBLN';
const _version = 1;
const _roleServer = 1;
const _roleClient = 2;
const _recordFrame = 1;
const _recordPing = 2;
const _helloSize = 90;
const _gatewayIdSize = 16;
const _maximumGatewayHops = 32;
const _emergencyMagic = 'HBEM';
const _emergencyVersion = 1;
const _emergencyHelloSize = 25;
const _defaultPeerPort = 45893;
const _defaultEmergencyPort = 45894;

class LanMeshGatewayConfig {
  const LanMeshGatewayConfig({
    this.enabled = false,
    this.psk = const <int>[],
    this.maxFrameSize = 2048,
    this.connectTimeout = const Duration(seconds: 10),
    this.idleTimeout = const Duration(seconds: 90),
    this.maxGatewayHops = 8,
    this.peerMode = true,
    this.emergencyOpenMode = false,
    this.listenPort = _defaultPeerPort,
    this.emergencyPort = _defaultEmergencyPort,
  });

  final bool enabled;
  final List<int> psk;
  final int maxFrameSize;
  final Duration connectTimeout;
  final Duration idleTimeout;
  final int maxGatewayHops;
  final bool peerMode;
  final bool emergencyOpenMode;
  final int listenPort;
  final int emergencyPort;

  void validate() {
    if (!enabled) return;
    if (psk.isNotEmpty && psk.length < 32 ||
        psk.isEmpty && !emergencyOpenMode) {
      throw ArgumentError.value(
        psk.length,
        'psk',
        'must contain at least 32 bytes',
      );
    }
    if (maxFrameSize < 1 || maxFrameSize > 65535) {
      throw ArgumentError.value(maxFrameSize, 'maxFrameSize');
    }
    if (maxGatewayHops < 1 || maxGatewayHops > _maximumGatewayHops) {
      throw ArgumentError.value(maxGatewayHops, 'maxGatewayHops');
    }
    if (listenPort < 0 ||
        listenPort > 65535 ||
        emergencyPort < 0 ||
        emergencyPort > 65535) {
      throw ArgumentError('Invalid LAN peer port');
    }
  }
}

class LanGatewayStatus {
  const LanGatewayStatus({
    required this.enabled,
    required this.connected,
    this.gatewayId,
    this.endpoint,
    this.error,
  });

  final bool enabled;
  final bool connected;
  final String? gatewayId;
  final String? endpoint;
  final String? error;
}

/// Cliente opt-in del gateway de malla LAN.
///
/// La trama BitChat se entrega intacta al código nativo. El envelope LAN
/// mantiene autenticación, secuencia, gateway path y deduplicación fuera de
/// esos bytes. Esta clase no se inicia automáticamente.
class LanMeshGatewayService {
  LanMeshGatewayService({MeshPlatformService? platform, List<int>? gatewayId})
    : _platform = platform ?? MeshPlatformService(),
      _gatewayId = Uint8List.fromList(
        gatewayId ?? _randomBytes(_gatewayIdSize),
      );

  final MeshPlatformService _platform;
  final Uint8List _gatewayId;
  final _statusController = StreamController<LanGatewayStatus>.broadcast();
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  LanMeshGatewayConfig _config = const LanMeshGatewayConfig();
  RawDatagramSocket? _discovery;
  StreamSubscription<RawSocketEvent>? _discoverySubscription;
  StreamSubscription<Map<Object?, Object?>>? _meshSubscription;
  ServerSocket? _server;
  ServerSocket? _emergencyServer;
  Socket? _socket;
  _SocketReader? _reader;
  _LanCipher? _cipher;
  Timer? _queryTimer;
  Timer? _pingTimer;
  bool _connecting = false;
  bool _emergencyConnecting = false;
  bool _stopping = false;
  Uint8List? _peerGatewayId;
  Socket? _emergencySocket;
  _SocketReader? _emergencyReader;
  Uint8List? _emergencyPeerGatewayId;
  int _emergencyMaximumFrameSize = 2048;
  final EmergencyLanRateLimiter _emergencyRateLimiter =
      EmergencyLanRateLimiter();

  Stream<LanGatewayStatus> get statuses => _statusController.stream;

  Future<void> start(LanMeshGatewayConfig config) async {
    config.validate();
    await stop();
    _config = config;
    if (!config.enabled) {
      _emit(const LanGatewayStatus(enabled: false, connected: false));
      return;
    }
    _stopping = false;
    await _platform.setLanDiscoveryEnabled(true);
    _meshSubscription = _platform.events
        .where((event) => event['type'] == 'rawMeshFrame')
        .listen(_handleNativeFrame);
    await _platform.configureLanBridge(
      enabled: true,
      gatewayId: _hex(_gatewayId),
      maxFrameSize: config.maxFrameSize,
    );
    if (config.peerMode && config.psk.isNotEmpty) {
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        config.listenPort,
        shared: true,
      );
      _server!.listen((socket) => unawaited(_acceptSecurePeer(socket)));
    }
    if (config.peerMode && config.emergencyOpenMode) {
      _emergencyServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        config.emergencyPort,
        shared: true,
      );
      _emergencyServer!.listen(
        (socket) => unawaited(_acceptEmergencyPeer(socket)),
      );
    }
    final discovery = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _multicastPort,
      reuseAddress: true,
      reusePort: true,
    );
    _discovery = discovery;
    discovery.joinMulticast(InternetAddress(_multicastAddress));
    _discoverySubscription = discovery.listen(_handleDiscovery);
    _sendQuery();
    _queryTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _sendQuery(),
    );
    _emit(const LanGatewayStatus(enabled: true, connected: false));
  }

  Future<void> stop() async {
    _stopping = true;
    _queryTimer?.cancel();
    _queryTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    _discovery?.close();
    _discovery = null;
    await _server?.close();
    _server = null;
    await _emergencyServer?.close();
    _emergencyServer = null;
    await _meshSubscription?.cancel();
    _meshSubscription = null;
    try {
      await _platform.configureLanBridge(enabled: false);
    } catch (_) {
      // El plugin puede no existir en tests o escritorio; el socket local
      // todavía debe cerrarse de forma determinista.
    }
    try {
      await _platform.setLanDiscoveryEnabled(false);
    } catch (_) {
      // Igual que arriba: desactivar es idempotente y best-effort.
    }
    _socket?.destroy();
    _socket = null;
    _reader = null;
    _cipher = null;
    _peerGatewayId = null;
    _emergencySocket?.destroy();
    _emergencySocket = null;
    _emergencyReader = null;
    _emergencyPeerGatewayId = null;
    _emergencyMaximumFrameSize = 2048;
    _emergencyRateLimiter.clear();
    _connecting = false;
    _emergencyConnecting = false;
    _seen.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _statusController.close();
  }

  void _handleDiscovery(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _discovery?.receive();
    if (datagram == null) return;
    if (LanMdnsCodec.isQuery(datagram.data) && _config.peerMode) {
      final response = LanMdnsCodec.response(
        gatewayId: _gatewayId,
        port: _server?.port,
        emergencyPort: _emergencyServer?.port,
      );
      if (response != null) {
        _discovery?.send(
          response,
          InternetAddress(_multicastAddress),
          _multicastPort,
        );
      }
    }
    for (final gateway in LanMdnsCodec.parse(
      datagram.data,
      datagram.address.address,
    )) {
      final peerId = gateway.gatewayId;
      if (peerId == null || _constantTimeEquals(peerId, _gatewayId)) {
        continue;
      }
      // El ID menor abre la conexión; el mayor conserva la entrante.
      if (_compareIds(_gatewayId, peerId) >= 0) continue;
      if (_config.psk.isNotEmpty &&
          gateway.secureAvailable &&
          !_connecting &&
          _socket == null) {
        unawaited(_connect(gateway));
      }
      if (_config.emergencyOpenMode &&
          gateway.emergencyPort != null &&
          _emergencySocket == null) {
        unawaited(_connectEmergency(gateway));
      }
    }
  }

  Future<void> _acceptSecurePeer(Socket socket) async {
    if (_stopping || _socket != null) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = _SocketReader(socket);
    try {
      final authenticated = await LanGatewayFraming._authenticateServer(
        reader: reader,
        socket: socket,
        gatewayId: _gatewayId,
        psk: Uint8List.fromList(_config.psk),
        maxFrameSize: _config.maxFrameSize,
        timeout: _config.connectTimeout,
      );
      if (_compareIds(_gatewayId, authenticated.peerGatewayId) <= 0 ||
          _stopping ||
          _socket != null) {
        socket.destroy();
        return;
      }
      _socket = socket;
      _reader = reader;
      _cipher = authenticated.cipher;
      _peerGatewayId = authenticated.peerGatewayId;
      _emit(
        LanGatewayStatus(
          enabled: true,
          connected: true,
          gatewayId: _hex(authenticated.peerGatewayId),
          endpoint: '${socket.remoteAddress.address}:${socket.remotePort}',
        ),
      );
      _pingTimer = Timer.periodic(
        Duration(
          milliseconds: max(5000, _config.idleTimeout.inMilliseconds ~/ 3),
        ),
        (_) => unawaited(_sendPing()),
      );
      unawaited(_readLoop());
    } catch (error) {
      socket.destroy();
      if (!_stopping) {
        _emit(
          LanGatewayStatus(
            enabled: true,
            connected: _emergencySocket != null,
            error: '$error',
          ),
        );
      }
    }
  }

  Future<void> _connect(LanGatewayEndpoint gateway) async {
    if (_connecting || _socket != null || _stopping) return;
    _connecting = true;
    try {
      final socket = await Socket.connect(
        gateway.host,
        gateway.port,
        timeout: _config.connectTimeout,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      final reader = _SocketReader(socket);
      final authenticated = await LanGatewayFraming._authenticateClient(
        reader: reader,
        socket: socket,
        gatewayId: _gatewayId,
        psk: Uint8List.fromList(_config.psk),
        maxFrameSize: _config.maxFrameSize,
        timeout: _config.connectTimeout,
      );
      if (_stopping) {
        socket.destroy();
        return;
      }
      _socket = socket;
      _reader = reader;
      _cipher = authenticated.cipher;
      _peerGatewayId = authenticated.peerGatewayId;
      _emit(
        LanGatewayStatus(
          enabled: true,
          connected: true,
          gatewayId: _hex(authenticated.peerGatewayId),
          endpoint: '${gateway.host}:${gateway.port}',
        ),
      );
      _pingTimer = Timer.periodic(
        Duration(
          milliseconds: max(5000, _config.idleTimeout.inMilliseconds ~/ 3),
        ),
        (_) => unawaited(_sendPing()),
      );
      unawaited(_readLoop());
    } catch (error) {
      _emit(
        LanGatewayStatus(
          enabled: true,
          connected: false,
          endpoint: '${gateway.host}:${gateway.port}',
          error: '$error',
        ),
      );
    } finally {
      _connecting = false;
    }
  }

  Future<void> _acceptEmergencyPeer(Socket socket) async {
    if (_stopping || _emergencySocket != null) {
      socket.destroy();
      return;
    }
    final reader = _SocketReader(socket);
    try {
      final hello = await reader
          .read(_emergencyHelloSize)
          .timeout(_config.connectTimeout);
      final peer = EmergencyLanFraming.parseHello(hello);
      if (_compareIds(_gatewayId, peer.gatewayId) <= 0) {
        socket.destroy();
        return;
      }
      socket.add(
        EmergencyLanFraming.buildHello(
          gatewayId: _gatewayId,
          maximumFrameSize: _config.maxFrameSize,
        ),
      );
      await socket.flush();
      _activateEmergencySocket(
        socket,
        reader,
        peer.gatewayId,
        peer.maximumFrameSize,
      );
    } catch (error) {
      socket.destroy();
      if (!_stopping) {
        DiagnosticsLog.instance.warning(
          'lan_emergency.accept.failed',
          error: error,
        );
      }
    }
  }

  Future<void> _connectEmergency(LanGatewayEndpoint gateway) async {
    final port = gateway.emergencyPort;
    if (port == null ||
        _emergencyConnecting ||
        _emergencySocket != null ||
        _stopping) {
      return;
    }
    _emergencyConnecting = true;
    try {
      final socket = await Socket.connect(
        gateway.host,
        port,
        timeout: _config.connectTimeout,
      );
      final reader = _SocketReader(socket);
      socket.add(
        EmergencyLanFraming.buildHello(
          gatewayId: _gatewayId,
          maximumFrameSize: _config.maxFrameSize,
        ),
      );
      await socket.flush();
      final hello = await reader
          .read(_emergencyHelloSize)
          .timeout(_config.connectTimeout);
      final peer = EmergencyLanFraming.parseHello(hello);
      if (gateway.gatewayId != null &&
          !_constantTimeEquals(gateway.gatewayId!, peer.gatewayId)) {
        throw const FormatException('Emergency LAN identity changed');
      }
      _activateEmergencySocket(
        socket,
        reader,
        peer.gatewayId,
        peer.maximumFrameSize,
      );
    } catch (error) {
      if (!_stopping) {
        DiagnosticsLog.instance.warning(
          'lan_emergency.connect.failed',
          error: error,
        );
      }
    } finally {
      _emergencyConnecting = false;
    }
  }

  void _activateEmergencySocket(
    Socket socket,
    _SocketReader reader,
    Uint8List peerGatewayId,
    int peerMaximumFrameSize,
  ) {
    if (_stopping || _emergencySocket != null) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    _emergencySocket = socket;
    _emergencyReader = reader;
    _emergencyPeerGatewayId = peerGatewayId;
    _emergencyMaximumFrameSize = min(
      _config.maxFrameSize,
      peerMaximumFrameSize,
    );
    _emit(
      LanGatewayStatus(
        enabled: true,
        connected: true,
        gatewayId: _hex(peerGatewayId),
        endpoint: '${socket.remoteAddress.address}:${socket.remotePort}',
      ),
    );
    unawaited(_readEmergencyLoop());
  }

  Future<void> _readEmergencyLoop() async {
    final reader = _emergencyReader;
    final peer = _emergencyPeerGatewayId;
    if (reader == null || peer == null) return;
    try {
      while (!_stopping) {
        final frame = await EmergencyLanFraming._readFrame(
          reader,
          maximumFrameSize: _emergencyMaximumFrameSize,
          timeout: _config.idleTimeout,
        );
        if (!_emergencyRateLimiter.allow(_hex(peer))) {
          throw const FormatException('Emergency LAN rate limit exceeded');
        }
        final id = _hex(LanGatewayFraming.messageId(frame));
        if (!_seen.add(id)) continue;
        while (_seen.length > 4096) {
          _seen.remove(_seen.first);
        }
        await _platform.injectEmergencyLanFrame(frame);
      }
    } catch (error) {
      if (!_stopping) {
        DiagnosticsLog.instance.warning(
          'lan_emergency.read.failed',
          error: error,
        );
      }
    } finally {
      _disconnectEmergency();
    }
  }

  Future<void> _readLoop() async {
    final reader = _reader;
    final cipher = _cipher;
    final peer = _peerGatewayId;
    if (reader == null || cipher == null || peer == null) return;
    try {
      while (!_stopping) {
        final envelope = await cipher.read(
          reader,
          timeout: _config.idleTimeout,
          maximumGatewayHops: _config.maxGatewayHops,
        );
        if (envelope == null) continue;
        if (!_constantTimeEquals(envelope.path.last, peer)) {
          throw const FormatException(
            'LAN path does not match authenticated gateway',
          );
        }
        if (envelope.path.any((id) => _constantTimeEquals(id, _gatewayId))) {
          continue;
        }
        final expected = LanGatewayFraming.messageId(envelope.frame);
        if (!_constantTimeEquals(expected, envelope.messageId)) {
          throw const FormatException('LAN message ID does not match frame');
        }
        final id = _hex(envelope.messageId);
        if (!_seen.add(id)) continue;
        while (_seen.length > 4096) {
          _seen.remove(_seen.first);
        }
        await _platform.injectRawMeshFrame(
          gatewayId: _hex(_gatewayId),
          frame: envelope.frame,
        );
      }
    } catch (error) {
      if (!_stopping) {
        _emit(
          LanGatewayStatus(
            enabled: true,
            connected: false,
            gatewayId: _hex(peer),
            error: '$error',
          ),
        );
      }
    } finally {
      await _disconnect();
    }
  }

  void _handleNativeFrame(Map<Object?, Object?> event) {
    final frame = event['frame'];
    if (frame is Uint8List) {
      unawaited(_sendFrame(frame));
      if (event['emergencyEligible'] == true) {
        unawaited(_sendEmergencyFrame(frame));
      }
    }
  }

  Future<void> _sendEmergencyFrame(Uint8List frame) async {
    final socket = _emergencySocket;
    if (socket == null) return;
    try {
      await EmergencyLanFraming.sendFrame(
        socket,
        frame,
        maximumFrameSize: _emergencyMaximumFrameSize,
      );
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'lan_emergency.send.failed',
        error: error,
        stackTrace: stackTrace,
      );
      _disconnectEmergency();
    }
  }

  Future<void> _sendFrame(Uint8List frame) async {
    final cipher = _cipher;
    final socket = _socket;
    final peer = _peerGatewayId;
    if (cipher == null || socket == null || peer == null) return;
    try {
      await cipher.sendFrame(
        socket,
        frame: frame,
        messageId: LanGatewayFraming.messageId(frame),
        path: [_gatewayId],
      );
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'lan_gateway.receive.failed',
        error: error,
        stackTrace: stackTrace,
      );
      await _disconnect();
    }
  }

  Future<void> _sendPing() async {
    final cipher = _cipher;
    final socket = _socket;
    if (cipher == null || socket == null) return;
    try {
      await cipher.sendPing(socket);
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'lan_gateway.keepalive.failed',
        error: error,
        stackTrace: stackTrace,
      );
      await _disconnect();
    }
  }

  Future<void> _disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _socket?.destroy();
    _socket = null;
    _reader = null;
    _cipher = null;
    _peerGatewayId = null;
    _emit(
      LanGatewayStatus(
        enabled: true,
        connected: _emergencySocket != null,
        gatewayId: _emergencyPeerGatewayId == null
            ? null
            : _hex(_emergencyPeerGatewayId!),
      ),
    );
  }

  void _disconnectEmergency() {
    _emergencySocket?.destroy();
    _emergencySocket = null;
    _emergencyReader = null;
    _emergencyPeerGatewayId = null;
    _emergencyMaximumFrameSize = _config.maxFrameSize;
    _emit(
      LanGatewayStatus(
        enabled: true,
        connected: _socket != null,
        gatewayId: _peerGatewayId == null ? null : _hex(_peerGatewayId!),
      ),
    );
  }

  void _sendQuery() {
    _discovery?.send(
      LanMdnsCodec.query(),
      InternetAddress(_multicastAddress),
      _multicastPort,
    );
  }

  void _emit(LanGatewayStatus status) {
    if (!_statusController.isClosed) _statusController.add(status);
  }
}

class LanGatewayEndpoint {
  const LanGatewayEndpoint(
    this.host,
    this.port,
    this.gatewayId, {
    this.emergencyPort,
    this.secureAvailable = true,
  });

  final String host;
  final int port;
  final Uint8List? gatewayId;
  final int? emergencyPort;
  final bool secureAvailable;
}

class LanMdnsCodec {
  static bool isQuery(Uint8List data) =>
      data.length >= 12 &&
      ByteData.sublistView(data).getUint16(2) & 0x8000 == 0;

  static Uint8List query() {
    final output = BytesBuilder(copy: false)
      ..add(Uint8List(12)..buffer.asByteData().setUint16(4, 1))
      ..add(_encodeName(_serviceType))
      ..add([0, 12, 0, 1]);
    return output.takeBytes();
  }

  static Uint8List? response({
    required Uint8List gatewayId,
    required int? port,
    required int? emergencyPort,
  }) {
    if (gatewayId.length != _gatewayIdSize ||
        port == null && emergencyPort == null) {
      return null;
    }
    final id = _hex(gatewayId);
    final instance = '$id.$_serviceType';
    final target = '$id.local';
    final records = <Uint8List>[];
    final advertisedPort = port ?? emergencyPort!;
    records.add(_dnsRecord(_serviceType, 12, _encodeName(instance)));
    final srv = BytesBuilder(copy: false)
      ..add([0, 0, 0, 0])
      ..add(_u16(advertisedPort))
      ..add(_encodeName(target));
    records.add(_dnsRecord(instance, 33, srv.takeBytes()));
    final textValues = <String>[
      'gid=$id',
      if (port != null) 'secure=1',
      if (emergencyPort != null) 'eport=$emergencyPort',
    ];
    final txt = BytesBuilder(copy: false);
    for (final value in textValues) {
      final bytes = utf8.encode(value);
      txt
        ..addByte(bytes.length)
        ..add(bytes);
    }
    records.add(_dnsRecord(instance, 16, txt.takeBytes()));
    final header = Uint8List(12);
    ByteData.sublistView(header)
      ..setUint16(2, 0x8400)
      ..setUint16(6, records.length);
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(records.expand((record) => record).toList()))
        .takeBytes();
  }

  static List<LanGatewayEndpoint> parse(Uint8List data, String sourceHost) {
    if (data.length < 12) return const [];
    final bytes = ByteData.sublistView(data);
    if (bytes.getUint16(2) & 0x8000 == 0) return const [];
    var offset = 12;
    final questions = bytes.getUint16(4);
    final records =
        bytes.getUint16(6) + bytes.getUint16(8) + bytes.getUint16(10);
    try {
      for (var index = 0; index < questions; index++) {
        offset = _readName(data, offset).offset + 4;
      }
      final services = <({String name, int port, String target})>[];
      final ids = <String, Uint8List>{};
      final emergencyPorts = <String, int>{};
      final secureServices = <String>{};
      final addresses = <String, String>{};
      for (var index = 0; index < records; index++) {
        final named = _readName(data, offset);
        final name = named.name.toLowerCase();
        offset = named.offset;
        if (offset + 10 > data.length) return const [];
        final type = bytes.getUint16(offset);
        final length = bytes.getUint16(offset + 8);
        offset += 10;
        final end = offset + length;
        if (end > data.length) return const [];
        if (type == 33 && length >= 7) {
          services.add((
            name: name,
            port: bytes.getUint16(offset + 4),
            target: _readName(data, offset + 6).name.toLowerCase(),
          ));
        } else if (type == 16) {
          var textOffset = offset;
          while (textOffset < end) {
            final size = data[textOffset++];
            if (textOffset + size > end) break;
            final text = utf8.decode(
              data.sublist(textOffset, textOffset + size),
            );
            textOffset += size;
            if (text.startsWith('gid=')) {
              final decoded = _decodeHex(text.substring(4));
              if (decoded?.length == _gatewayIdSize) ids[name] = decoded!;
            } else if (text.startsWith('eport=')) {
              final value = int.tryParse(text.substring(6));
              if (value != null && value > 0 && value <= 65535) {
                emergencyPorts[name] = value;
              }
            } else if (text == 'secure=1') {
              secureServices.add(name);
            }
          }
        } else if (type == 1 && length == 4) {
          addresses[name] = data.sublist(offset, end).join('.');
        }
        offset = end;
      }
      final suffix = '.$_serviceType';
      return services
          .where((service) => service.name.endsWith(suffix) && service.port > 0)
          .map(
            (service) => LanGatewayEndpoint(
              addresses[service.target] ?? sourceHost,
              service.port,
              ids[service.name],
              emergencyPort: emergencyPorts[service.name],
              secureAvailable: secureServices.contains(service.name),
            ),
          )
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on RangeError {
      return const [];
    }
  }
}

class LanGatewayFraming {
  static Future<_AuthenticatedLan> _authenticateServer({
    required _SocketReader reader,
    required Socket socket,
    required Uint8List gatewayId,
    required Uint8List psk,
    required int maxFrameSize,
    required Duration timeout,
  }) async {
    final serverHello = buildHello(
      role: _roleServer,
      gatewayId: gatewayId,
      nonce: _randomBytes(32),
      maximumFrameSize: maxFrameSize,
      psk: psk,
    );
    socket.add(serverHello);
    await socket.flush();
    final clientHello = await reader.read(_helloSize).timeout(timeout);
    final client = parseHello(clientHello, expectedRole: _roleClient, psk: psk);
    if (_constantTimeEquals(client.gatewayId, gatewayId)) {
      throw const FormatException('Cannot connect a gateway to itself');
    }
    final transcript = Uint8List.fromList([...serverHello, ...clientHello]);
    final serverNonce = serverHello.sublist(22, 54);
    final clientNonce = clientHello.sublist(22, 54);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    final material = await hkdf.deriveKey(
      secretKey: SecretKey(psk),
      nonce: [...serverNonce, ...clientNonce],
      info: [...utf8.encode('hearthbit-lan-v1:'), ...transcript],
    );
    final keys = await material.extractBytes();
    socket.add(
      _hmac(psk, [...utf8.encode('finish:'), ...transcript, _roleServer]),
    );
    await socket.flush();
    final clientFinish = await reader.read(32).timeout(timeout);
    final expectedClientFinish = _hmac(psk, [
      ...utf8.encode('finish:'),
      ...transcript,
      _roleClient,
    ]);
    if (!_constantTimeEquals(clientFinish, expectedClientFinish)) {
      throw const FormatException('LAN transcript authentication failed');
    }
    return _AuthenticatedLan(
      peerGatewayId: client.gatewayId,
      maximumFrameSize: min(maxFrameSize, client.maximumFrameSize),
      cipher: _LanCipher(
        sendKey: Uint8List.fromList(keys.sublist(0, 32)),
        receiveKey: Uint8List.fromList(keys.sublist(32)),
        maximumFrameSize: min(maxFrameSize, client.maximumFrameSize),
      ),
    );
  }

  static Future<_AuthenticatedLan> _authenticateClient({
    required _SocketReader reader,
    required Socket socket,
    required Uint8List gatewayId,
    required Uint8List psk,
    required int maxFrameSize,
    required Duration timeout,
  }) async {
    final serverHello = await reader.read(_helloSize).timeout(timeout);
    final server = parseHello(serverHello, expectedRole: _roleServer, psk: psk);
    if (_constantTimeEquals(server.gatewayId, gatewayId)) {
      throw const FormatException('Cannot connect a gateway to itself');
    }
    final clientHello = buildHello(
      role: _roleClient,
      gatewayId: gatewayId,
      nonce: _randomBytes(32),
      maximumFrameSize: maxFrameSize,
      psk: psk,
    );
    socket.add(clientHello);
    await socket.flush();
    final transcript = Uint8List.fromList([...serverHello, ...clientHello]);
    final serverNonce = serverHello.sublist(22, 54);
    final clientNonce = clientHello.sublist(22, 54);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    final material = await hkdf.deriveKey(
      secretKey: SecretKey(psk),
      nonce: [...serverNonce, ...clientNonce],
      info: [...utf8.encode('hearthbit-lan-v1:'), ...transcript],
    );
    final keys = await material.extractBytes();
    final serverFinish = await reader.read(32).timeout(timeout);
    final expectedServerFinish = _hmac(psk, [
      ...utf8.encode('finish:'),
      ...transcript,
      _roleServer,
    ]);
    if (!_constantTimeEquals(serverFinish, expectedServerFinish)) {
      throw const FormatException('LAN transcript authentication failed');
    }
    socket.add(
      _hmac(psk, [...utf8.encode('finish:'), ...transcript, _roleClient]),
    );
    await socket.flush();
    return _AuthenticatedLan(
      peerGatewayId: server.gatewayId,
      maximumFrameSize: min(maxFrameSize, server.maximumFrameSize),
      cipher: _LanCipher(
        sendKey: Uint8List.fromList(keys.sublist(32)),
        receiveKey: Uint8List.fromList(keys.sublist(0, 32)),
        maximumFrameSize: min(maxFrameSize, server.maximumFrameSize),
      ),
    );
  }

  static Uint8List buildHello({
    required int role,
    required Uint8List gatewayId,
    required Uint8List nonce,
    required int maximumFrameSize,
    required Uint8List psk,
  }) {
    if (gatewayId.length != 16 || nonce.length != 32) {
      throw const FormatException('Invalid LAN identity or nonce');
    }
    final unsigned = Uint8List(58);
    final data = unsigned.buffer.asByteData();
    unsigned.setRange(0, 4, ascii.encode(_magic));
    unsigned[4] = _version;
    unsigned[5] = role;
    unsigned.setRange(6, 22, gatewayId);
    unsigned.setRange(22, 54, nonce);
    data.setUint32(54, maximumFrameSize);
    return Uint8List.fromList([
      ...unsigned,
      ..._hmac(psk, [...utf8.encode('hello:'), ...unsigned]),
    ]);
  }

  static LanGatewayHello parseHello(
    Uint8List hello, {
    required int expectedRole,
    required Uint8List psk,
  }) {
    if (hello.length != _helloSize) {
      throw const FormatException('Invalid LAN hello');
    }
    final unsigned = hello.sublist(0, 58);
    final tag = hello.sublist(58);
    if (!_constantTimeEquals(
      tag,
      _hmac(psk, [...utf8.encode('hello:'), ...unsigned]),
    )) {
      throw const FormatException('LAN authentication failed');
    }
    if (ascii.decode(unsigned.sublist(0, 4)) != _magic ||
        unsigned[4] != _version ||
        unsigned[5] != expectedRole) {
      throw const FormatException('Unsupported LAN peer');
    }
    final maximum = ByteData.sublistView(unsigned).getUint32(54);
    if (maximum < 1 || maximum > 65535) {
      throw const FormatException('Invalid LAN maximum frame size');
    }
    return LanGatewayHello(
      Uint8List.fromList(unsigned.sublist(6, 22)),
      maximum,
    );
  }

  static Uint8List messageId(List<int> frame) {
    final canonical = Uint8List.fromList(frame);
    if (canonical.length >= 12) {
      canonical[2] = 0;
      canonical[11] &= ~0x10;
    }
    return Uint8List.fromList(
      crypto.sha256.convert(canonical).bytes.sublist(0, 16),
    );
  }
}

class LanGatewayHello {
  const LanGatewayHello(this.gatewayId, this.maximumFrameSize);

  final Uint8List gatewayId;
  final int maximumFrameSize;
}

class _AuthenticatedLan {
  const _AuthenticatedLan({
    required this.peerGatewayId,
    required this.maximumFrameSize,
    required this.cipher,
  });

  final Uint8List peerGatewayId;
  final int maximumFrameSize;
  final _LanCipher cipher;
}

class _LanFrameEnvelope {
  const _LanFrameEnvelope(this.messageId, this.path, this.frame);

  final Uint8List messageId;
  final List<Uint8List> path;
  final Uint8List frame;
}

class _LanCipher {
  _LanCipher({
    required Uint8List sendKey,
    required Uint8List receiveKey,
    required this.maximumFrameSize,
  }) : _sendKey = SecretKey(sendKey),
       _receiveKey = SecretKey(receiveKey);

  final SecretKey _sendKey;
  final SecretKey _receiveKey;
  final int maximumFrameSize;
  final AesGcm _aes = AesGcm.with256bits();
  int _sendSequence = 0;
  int _receiveSequence = 0;
  Future<void> _sendTail = Future.value();

  Future<void> sendFrame(
    Socket socket, {
    required Uint8List frame,
    required Uint8List messageId,
    required List<Uint8List> path,
  }) {
    if (frame.isEmpty || frame.length > maximumFrameSize) {
      throw const FormatException('LAN frame exceeds negotiated limit');
    }
    if (messageId.length != 16 ||
        path.isEmpty ||
        path.length > _maximumGatewayHops ||
        path.any((id) => id.length != _gatewayIdSize)) {
      throw const FormatException('Invalid LAN frame envelope');
    }
    final plain = BytesBuilder(copy: false)
      ..add([_recordFrame])
      ..add(messageId)
      ..add([path.length]);
    for (final id in path) {
      plain.add(id);
    }
    final size = Uint8List(4)..buffer.asByteData().setUint32(0, frame.length);
    plain
      ..add(size)
      ..add(frame);
    return _queueSend(socket, plain.takeBytes());
  }

  Future<void> sendPing(Socket socket) =>
      _queueSend(socket, Uint8List.fromList([_recordPing]));

  Future<_LanFrameEnvelope?> read(
    _SocketReader reader, {
    required Duration timeout,
    required int maximumGatewayHops,
  }) async {
    final sizeBytes = await reader.read(4).timeout(timeout);
    final size = ByteData.sublistView(sizeBytes).getUint32(0);
    final maximum =
        9 +
        16 +
        18 +
        _maximumGatewayHops * _gatewayIdSize +
        4 +
        maximumFrameSize;
    if (size < 26 || size > maximum) {
      throw const FormatException('Invalid encrypted LAN record length');
    }
    final body = await reader.read(size).timeout(timeout);
    final header = body.sublist(0, 9);
    final sequence = ByteData.sublistView(header).getUint64(1);
    if (header[0] != _version || sequence != _receiveSequence) {
      throw const FormatException('Invalid LAN record sequence');
    }
    final encrypted = body.sublist(9);
    if (encrypted.length < 16) {
      throw const FormatException('Truncated LAN record');
    }
    final clear = await _aes.decrypt(
      SecretBox(
        encrypted.sublist(0, encrypted.length - 16),
        nonce: _nonce(sequence),
        mac: Mac(encrypted.sublist(encrypted.length - 16)),
      ),
      secretKey: _receiveKey,
      aad: header,
    );
    _receiveSequence++;
    if (clear.length == 1 && clear[0] == _recordPing) return null;
    if (clear.length < 22 || clear[0] != _recordFrame) {
      throw const FormatException('Invalid LAN frame record');
    }
    final pathCount = clear[17];
    if (pathCount < 1 ||
        pathCount > min(maximumGatewayHops, _maximumGatewayHops)) {
      throw const FormatException('Invalid LAN gateway path');
    }
    var offset = 18;
    final path = <Uint8List>[];
    for (var index = 0; index < pathCount; index++) {
      if (offset + _gatewayIdSize > clear.length) {
        throw const FormatException('Truncated LAN gateway path');
      }
      path.add(
        Uint8List.fromList(clear.sublist(offset, offset + _gatewayIdSize)),
      );
      offset += _gatewayIdSize;
    }
    if (offset + 4 > clear.length) {
      throw const FormatException('Truncated LAN frame size');
    }
    final frameSize = ByteData.sublistView(
      Uint8List.fromList(clear),
    ).getUint32(offset);
    offset += 4;
    final frame = Uint8List.fromList(clear.sublist(offset));
    if (frameSize != frame.length ||
        frame.isEmpty ||
        frame.length > maximumFrameSize) {
      throw const FormatException('Invalid LAN frame size');
    }
    return _LanFrameEnvelope(
      Uint8List.fromList(clear.sublist(1, 17)),
      path,
      frame,
    );
  }

  Future<void> _queueSend(Socket socket, Uint8List plaintext) {
    final operation = _sendTail.then((_) => _send(socket, plaintext));
    _sendTail = operation.catchError((_) {});
    return operation;
  }

  Future<void> _send(Socket socket, Uint8List plaintext) async {
    final sequence = _sendSequence++;
    final header = Uint8List(9);
    final data = header.buffer.asByteData();
    header[0] = _version;
    data.setUint64(1, sequence);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: _sendKey,
      nonce: _nonce(sequence),
      aad: header,
    );
    final body = Uint8List.fromList([
      ...header,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    final size = Uint8List(4)..buffer.asByteData().setUint32(0, body.length);
    socket
      ..add(size)
      ..add(body);
    await socket.flush();
  }
}

class _SocketReader {
  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _chunks.add(data);
        _available += data.length;
        _drain();
      },
      onDone: () {
        _closed = true;
        _drain();
      },
      onError: (Object error) {
        _error = error;
        _closed = true;
        _drain();
      },
      cancelOnError: false,
    );
  }

  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  late final StreamSubscription<Uint8List> _subscription;
  int _available = 0;
  bool _closed = false;
  Object? _error;
  Completer<Uint8List>? _pending;
  int _pendingSize = 0;

  Future<Uint8List> read(int size) {
    if (_pending != null || size < 0) {
      throw StateError('Concurrent or invalid LAN socket read');
    }
    final pending = Completer<Uint8List>();
    _pending = pending;
    _pendingSize = size;
    _drain();
    return pending.future;
  }

  void _drain() {
    final pending = _pending;
    if (pending == null) return;
    if (_available >= _pendingSize) {
      final output = Uint8List(_pendingSize);
      var offset = 0;
      while (offset < output.length) {
        final chunk = _chunks.removeFirst();
        final count = min(chunk.length, output.length - offset);
        output.setRange(offset, offset + count, chunk);
        offset += count;
        if (count < chunk.length) {
          _chunks.addFirst(Uint8List.fromList(chunk.sublist(count)));
        }
      }
      _available -= output.length;
      _pending = null;
      pending.complete(output);
    } else if (_closed) {
      _pending = null;
      unawaited(_subscription.cancel());
      pending.completeError(
        _error ?? const SocketException('LAN connection closed'),
      );
    }
  }
}

class EmergencyLanPeer {
  const EmergencyLanPeer(this.gatewayId, this.maximumFrameSize);

  final Uint8List gatewayId;
  final int maximumFrameSize;
}

class EmergencyLanFraming {
  static Uint8List buildHello({
    required Uint8List gatewayId,
    required int maximumFrameSize,
  }) {
    if (gatewayId.length != _gatewayIdSize ||
        maximumFrameSize < 1 ||
        maximumFrameSize > 65535) {
      throw const FormatException('Invalid emergency LAN hello');
    }
    final output = Uint8List(_emergencyHelloSize);
    output.setRange(0, 4, ascii.encode(_emergencyMagic));
    output[4] = _emergencyVersion;
    output.setRange(5, 21, gatewayId);
    ByteData.sublistView(output).setUint32(21, maximumFrameSize);
    return output;
  }

  static EmergencyLanPeer parseHello(Uint8List bytes) {
    if (bytes.length != _emergencyHelloSize ||
        ascii.decode(bytes.sublist(0, 4)) != _emergencyMagic ||
        bytes[4] != _emergencyVersion) {
      throw const FormatException('Invalid emergency LAN peer');
    }
    final maximum = ByteData.sublistView(bytes).getUint32(21);
    if (maximum < 1 || maximum > 65535) {
      throw const FormatException('Invalid emergency LAN maximum frame');
    }
    return EmergencyLanPeer(Uint8List.fromList(bytes.sublist(5, 21)), maximum);
  }

  static Future<void> sendFrame(
    Socket socket,
    Uint8List frame, {
    required int maximumFrameSize,
  }) async {
    if (frame.isEmpty || frame.length > maximumFrameSize) {
      throw const FormatException('Emergency LAN frame exceeds limit');
    }
    final size = Uint8List(4)..buffer.asByteData().setUint32(0, frame.length);
    socket
      ..add(size)
      ..add(frame);
    await socket.flush();
  }

  static Future<Uint8List> _readFrame(
    _SocketReader reader, {
    required int maximumFrameSize,
    required Duration timeout,
  }) async {
    final sizeBytes = await reader.read(4).timeout(timeout);
    final size = ByteData.sublistView(sizeBytes).getUint32(0);
    if (size < 1 || size > maximumFrameSize) {
      throw const FormatException('Invalid emergency LAN frame length');
    }
    return reader.read(size).timeout(timeout);
  }
}

class EmergencyLanRateLimiter {
  final Map<String, Queue<DateTime>> _events = {};

  bool allow(String source, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(const Duration(minutes: 1));
    final events = _events.putIfAbsent(source, Queue.new);
    while (events.isNotEmpty && events.first.isBefore(cutoff)) {
      events.removeFirst();
    }
    if (events.length >= 30) return false;
    events.addLast(current);
    return true;
  }

  void clear() => _events.clear();
}

Uint8List _dnsRecord(String name, int type, Uint8List value) {
  final output = BytesBuilder(copy: false)
    ..add(_encodeName(name))
    ..add(_u16(type))
    ..add([0, 1])
    ..add([0, 0, 0, 120])
    ..add(_u16(value.length))
    ..add(value);
  return output.takeBytes();
}

Uint8List _u16(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value);

int _compareIds(List<int> first, List<int> second) {
  for (var index = 0; index < min(first.length, second.length); index++) {
    final difference = first[index] - second[index];
    if (difference != 0) return difference;
  }
  return first.length - second.length;
}

({String name, int offset}) _readName(
  Uint8List data,
  int start, [
  int depth = 0,
]) {
  if (depth > 16) throw const FormatException('DNS compression loop');
  final labels = <String>[];
  var offset = start;
  var next = start;
  while (true) {
    if (offset >= data.length) {
      throw const FormatException('Truncated DNS name');
    }
    final length = data[offset];
    if (length & 0xc0 == 0xc0) {
      if (offset + 1 >= data.length) {
        throw const FormatException('Truncated DNS pointer');
      }
      final pointer = ((length & 0x3f) << 8) | data[offset + 1];
      labels.add(_readName(data, pointer, depth + 1).name);
      next = offset + 2;
      break;
    }
    if (length == 0) {
      next = offset + 1;
      break;
    }
    if (length & 0xc0 != 0) throw const FormatException('Invalid DNS label');
    offset++;
    final end = offset + length;
    if (end > data.length) throw const FormatException('Truncated DNS label');
    labels.add(utf8.decode(data.sublist(offset, end)));
    offset = end;
  }
  return (name: labels.join('.'), offset: next);
}

Uint8List _encodeName(String name) {
  final output = BytesBuilder(copy: false);
  for (final label in name.split('.')) {
    final bytes = utf8.encode(label);
    output
      ..addByte(bytes.length)
      ..add(bytes);
  }
  output.addByte(0);
  return output.takeBytes();
}

Uint8List _hmac(List<int> key, List<int> data) =>
    Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(data).bytes);

Uint8List _nonce(int sequence) {
  final nonce = Uint8List(12);
  nonce.buffer.asByteData().setUint64(4, sequence);
  return nonce;
}

Uint8List _randomBytes(int size) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(size, (_) => random.nextInt(256)));
}

bool _constantTimeEquals(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

Uint8List? _decodeHex(String value) {
  if (value.length.isOdd) return null;
  try {
    return Uint8List.fromList([
      for (var offset = 0; offset < value.length; offset += 2)
        int.parse(value.substring(offset, offset + 2), radix: 16),
    ]);
  } on FormatException {
    return null;
  }
}
