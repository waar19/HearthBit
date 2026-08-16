import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/acoustic_sonar.dart';
import 'package:hearth_bit/services/acoustic_sonar_session.dart';
import 'package:hearth_bit/services/ranging_control_protocol.dart';

void main() {
  test('emite al recibir acousticReady', () async {
    final capture = _FakeCapture();
    final sent = <RangingControlMessage>[];
    final session = _session(capture, sent);
    addTearDown(session.dispose);

    expect(await session.startInitiator(), isTrue);
    final request = sent.single;
    await session.handle(_reply(request, RangingControlAction.accept));
    await session.handle(_reply(request, RangingControlAction.acousticReady));

    expect(capture.emitCount, 1);
    expect(sent.last.action, RangingControlAction.acousticChirp);
  });

  test('usa fallback si una versión antigua no envía acousticReady', () async {
    final capture = _FakeCapture();
    final sent = <RangingControlMessage>[];
    final session = _session(
      capture,
      sent,
      readyFallback: const Duration(milliseconds: 5),
    );
    addTearDown(session.dispose);

    await session.startInitiator();
    final request = sent.single;
    await session.handle(_reply(request, RangingControlAction.accept));
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(capture.emitCount, 1);
    expect(sent.last.action, RangingControlAction.acousticChirp);
  });

  test(
    'responde con error específico cuando falta permiso de micrófono',
    () async {
      final capture = _FakeCapture(permissionGranted: false);
      final sent = <RangingControlMessage>[];
      final failures = <AcousticSonarFailure>[];
      final session = _session(capture, sent, failures: failures);
      addTearDown(session.dispose);
      final request = RangingControlProtocol.decode(
        RangingControlProtocol.encode(
          action: RangingControlAction.request,
          technology: RangingTechnology.acoustic,
        ),
      )!;

      await session.handle(request);

      expect(sent.single.action, RangingControlAction.error);
      expect(
        sent.single.value,
        RangingControlProtocol.errorMicrophonePermission,
      );
      expect(failures, [AcousticSonarFailure.microphonePermission]);
    },
  );

  test('reintenta una ronda ruidosa sin abortar la sesión', () async {
    final capture = _FakeCapture(detections: [const []]);
    final sent = <RangingControlMessage>[];
    final session = _session(capture, sent);
    addTearDown(session.dispose);

    await session.startInitiator();
    final request = sent.single;
    await session.handle(_reply(request, RangingControlAction.accept));
    await session.handle(_reply(request, RangingControlAction.acousticReady));
    await session.handle(
      _reply(request, RangingControlAction.acousticChirp, value: 1),
    );

    expect(session.isActive, isTrue);
    expect(session.attempt, 1);
    expect(
      sent.where((message) => message.action == RangingControlAction.request),
      hasLength(2),
    );
  });

  test(
    'termina la sesión al vencer el timeout de 25 segundos configurable',
    () async {
      final capture = _FakeCapture();
      final sent = <RangingControlMessage>[];
      final failures = <AcousticSonarFailure>[];
      final session = _session(
        capture,
        sent,
        failures: failures,
        sessionTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(session.dispose);

      await session.startInitiator();
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(session.isActive, isFalse);
      expect(failures, contains(AcousticSonarFailure.timeout));
    },
  );
}

AcousticSonarSession _session(
  _FakeCapture capture,
  List<RangingControlMessage> sent, {
  List<AcousticSonarFailure>? failures,
  Duration readyFallback = const Duration(seconds: 1),
  Duration sessionTimeout = const Duration(seconds: 1),
}) {
  return AcousticSonarSession(
    capture: capture,
    sendControl: (payload) async {
      sent.add(RangingControlProtocol.decode(payload)!);
    },
    onFailure: failures?.add,
    readyFallback: readyFallback,
    responderDelay: Duration.zero,
    captureTail: Duration.zero,
    roundPause: Duration.zero,
    sessionTimeout: sessionTimeout,
  );
}

RangingControlMessage _reply(
  RangingControlMessage request,
  RangingControlAction action, {
  double value = 0,
}) {
  return RangingControlProtocol.decode(
    RangingControlProtocol.encode(
      action: action,
      technology: RangingTechnology.acoustic,
      sessionNonce: request.sessionNonce,
      round: request.round,
      value: value,
    ),
  )!;
}

class _FakeCapture implements AcousticSonarCapturePort {
  _FakeCapture({
    this.permissionGranted = true,
    List<List<AcousticDetection>> detections = const [],
  }) : _detections = List<List<AcousticDetection>>.from(detections);

  final bool permissionGranted;
  final List<List<AcousticDetection>> _detections;
  bool _capturing = false;
  int emitCount = 0;

  @override
  bool get isCapturing => _capturing;

  @override
  int get peakBufferedBytes => 0;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get selfChirpSampleOffset => 1000;

  @override
  Future<void> cancel() async {
    _capturing = false;
  }

  @override
  Future<void> dispose() => cancel();

  @override
  Future<void> emitChirp() async {
    emitCount += 1;
  }

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> start() async {
    if (!permissionGranted) return false;
    _capturing = true;
    return true;
  }

  @override
  Future<List<AcousticDetection>> stopAndAnalyze() async {
    _capturing = false;
    return _detections.isEmpty ? const [] : _detections.removeAt(0);
  }
}
