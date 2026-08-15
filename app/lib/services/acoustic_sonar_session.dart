import 'dart:async';
import 'dart:typed_data';

import 'acoustic_sonar.dart';
import 'ranging_control_protocol.dart';

enum AcousticSonarSessionState {
  idle,
  awaitingAccept,
  awaitingReady,
  capturing,
  processing,
  completed,
  failed,
}

enum AcousticSonarFailure {
  microphonePermission,
  remoteMicrophonePermission,
  selfChirpMissing,
  tooNoisy,
  timeout,
  invalidMeasurement,
}

typedef AcousticControlSender = Future<void> Function(Uint8List payload);

class AcousticSonarSession {
  AcousticSonarSession({
    required AcousticSonarCapturePort capture,
    required AcousticControlSender sendControl,
    this.onStateChanged,
    this.onMeasurement,
    this.onFailure,
    this.readyFallback = const Duration(milliseconds: 1500),
    this.responderDelay = const Duration(milliseconds: 450),
    this.captureTail = const Duration(milliseconds: 700),
    this.roundPause = const Duration(milliseconds: 600),
    this.sessionTimeout = const Duration(seconds: 25),
    Future<void> Function(Duration)? delay,
  }) : // The public parameter names are part of the injection API.
       // ignore: prefer_initializing_formals
       _capture = capture,
       // ignore: prefer_initializing_formals
       _sendControl = sendControl,
       _delay = delay ?? Future<void>.delayed;

  static const int maximumAttempts = 5;
  static const int targetValidRounds = 3;
  static const int minimumValidRounds = 2;

  final AcousticSonarCapturePort _capture;
  final AcousticControlSender _sendControl;
  final void Function(AcousticSonarSessionState state)? onStateChanged;
  final void Function(AcousticDistanceMeasurement measurement)? onMeasurement;
  final void Function(AcousticSonarFailure failure)? onFailure;
  final Duration readyFallback;
  final Duration responderDelay;
  final Duration captureTail;
  final Duration roundPause;
  final Duration sessionTimeout;
  final Future<void> Function(Duration) _delay;

  AcousticSonarSessionState _state = AcousticSonarSessionState.idle;
  Uint8List? _nonce;
  bool _initiator = false;
  bool _active = false;
  bool _initiatorChirpSent = false;
  bool _advancingRound = false;
  int _attempt = 0;
  AcousticRoundObservation? _localObservation;
  AcousticRoundObservation? _remoteObservation;
  final List<AcousticDistanceMeasurement> _measurements = [];
  Timer? _timeoutTimer;
  Timer? _readyFallbackTimer;

  AcousticSonarSessionState get state => _state;
  bool get isActive => _active;
  bool get isInitiator => _initiator;
  int get attempt => _attempt;

  Future<bool> startInitiator() async {
    await _reset(notifyPeer: false);
    if (!await _capture.hasPermission()) {
      _reportFailure(AcousticSonarFailure.microphonePermission);
      return false;
    }
    _nonce = RangingControlProtocol.randomNonce();
    _initiator = true;
    _active = true;
    _attempt = 0;
    _measurements.clear();
    if (!await _startCapture()) {
      await _fail(AcousticSonarFailure.microphonePermission);
      return false;
    }
    _setState(AcousticSonarSessionState.awaitingAccept);
    _armTimeout();
    await _send(RangingControlAction.request);
    return true;
  }

  Future<void> handle(RangingControlMessage control) async {
    if (control.technology != RangingTechnology.acoustic) return;
    if (control.action == RangingControlAction.request) {
      await _acceptRequest(control);
      return;
    }
    final nonce = _nonce;
    if (nonce == null || !_bytesEqual(nonce, control.sessionNonce)) return;

    switch (control.action) {
      case RangingControlAction.accept:
        if (_initiator) {
          _setState(AcousticSonarSessionState.awaitingReady);
          _readyFallbackTimer?.cancel();
          _readyFallbackTimer = Timer(readyFallback, () {
            unawaited(_emitInitiatorChirp());
          });
        }
      case RangingControlAction.acousticReady:
        if (_initiator) await _emitInitiatorChirp();
      case RangingControlAction.acousticChirp:
        await _handleChirp(control);
      case RangingControlAction.acousticObservation:
        _remoteObservation = AcousticRoundObservation(
          selfChirpSample: 0,
          remoteChirpSample: control.value.round(),
          confidence: control.confidence,
        );
        await _tryFinalizeRound();
      case RangingControlAction.result:
        final measurement = AcousticDistanceMeasurement(
          distanceMeters: control.value,
          errorMeters: control.errorMeters,
          confidence: control.confidence,
        );
        onMeasurement?.call(measurement);
        await _complete();
      case RangingControlAction.stop:
        await _reset(notifyPeer: false);
      case RangingControlAction.error:
        await _handleRemoteError(control.value.round());
      case RangingControlAction.capabilities:
      case RangingControlAction.request:
      case RangingControlAction.oobData:
        break;
    }
  }

  Future<void> stop({bool notifyPeer = true}) => _reset(notifyPeer: notifyPeer);

  Future<void> dispose() async {
    await _reset(notifyPeer: false);
    await _capture.dispose();
  }

  Future<void> _acceptRequest(RangingControlMessage control) async {
    await _capture.cancel();
    _readyFallbackTimer?.cancel();
    _nonce = Uint8List.fromList(control.sessionNonce);
    _initiator = false;
    _active = true;
    _attempt = control.round;
    _initiatorChirpSent = false;
    _advancingRound = false;
    _localObservation = null;
    _remoteObservation = null;
    if (!await _capture.hasPermission() || !await _startCapture()) {
      await _send(
        RangingControlAction.error,
        value: RangingControlProtocol.errorMicrophonePermission.toDouble(),
      );
      await _fail(AcousticSonarFailure.microphonePermission);
      return;
    }
    _setState(AcousticSonarSessionState.capturing);
    _armTimeout();
    await _send(RangingControlAction.accept);
    unawaited(_announceReady(control.sessionNonce, control.round));
  }

  Future<void> _announceReady(Uint8List nonce, int round) async {
    await _capture.ready;
    if (!_active ||
        _initiator ||
        _attempt != round ||
        _nonce == null ||
        !_bytesEqual(_nonce!, nonce)) {
      return;
    }
    await _send(RangingControlAction.acousticReady);
  }

  Future<bool> _startCapture() async {
    final started = await _capture.start();
    if (started) _setState(AcousticSonarSessionState.capturing);
    return started;
  }

  Future<void> _emitInitiatorChirp() async {
    if (!_active || !_initiator || _initiatorChirpSent) return;
    _initiatorChirpSent = true;
    _readyFallbackTimer?.cancel();
    await _capture.emitChirp();
    await _send(RangingControlAction.acousticChirp, value: 0);
  }

  Future<void> _handleChirp(RangingControlMessage control) async {
    if (control.value == 0 && !_initiator) {
      await _delay(responderDelay);
      if (!_active || _attempt != control.round) return;
      await _capture.emitChirp();
      await _send(RangingControlAction.acousticChirp, value: 1);
      await _delay(captureTail);
      await _finishCapture(selfChirpFirst: false);
      return;
    }
    if (control.value == 1 && _initiator) {
      await _delay(captureTail);
      if (!_active || _attempt != control.round) return;
      await _finishCapture(selfChirpFirst: true);
    }
  }

  Future<void> _finishCapture({required bool selfChirpFirst}) async {
    _setState(AcousticSonarSessionState.processing);
    final expectedSelfSample = _capture.selfChirpSampleOffset;
    final detections = await _capture.stopAndAnalyze();
    final assignment = AcousticSonarDsp.assignChirps(
      detections: detections,
      expectedSelfSample: expectedSelfSample,
      selfChirpFirst: selfChirpFirst,
    );
    if (assignment == null) {
      final selfMissing = !_hasExpectedSelfDetection(
        detections,
        expectedSelfSample,
      );
      await _roundFailed(
        selfMissing
            ? AcousticSonarFailure.selfChirpMissing
            : AcousticSonarFailure.tooNoisy,
        selfMissing
            ? RangingControlProtocol.errorSelfChirpMissing
            : RangingControlProtocol.errorRoundFailed,
      );
      return;
    }
    _localObservation = assignment.observation;
    await _send(
      RangingControlAction.acousticObservation,
      value: _localObservation!.signedDeltaSamples.toDouble(),
      confidence: _localObservation!.confidence,
    );
    await _tryFinalizeRound();
  }

  bool _hasExpectedSelfDetection(
    List<AcousticDetection> detections,
    int? expectedSelfSample,
  ) {
    if (expectedSelfSample == null) return detections.isNotEmpty;
    final tolerance = (AcousticSonarDsp.sampleRate * 0.25).round();
    return detections.any(
      (detection) =>
          (detection.sampleIndex - expectedSelfSample).abs() <= tolerance,
    );
  }

  Future<void> _tryFinalizeRound() async {
    final local = _localObservation;
    final remote = _remoteObservation;
    if (local == null || remote == null) return;
    final measurement = AcousticSonarDsp.combineRound(
      local: local,
      remote: remote,
    );
    if (measurement == null) {
      await _roundFailed(
        AcousticSonarFailure.invalidMeasurement,
        RangingControlProtocol.errorRoundFailed,
      );
      return;
    }
    if (!_initiator) return;
    _measurements.add(measurement);
    if (_measurements.length >= targetValidRounds ||
        (_attempt >= maximumAttempts - 1 &&
            _measurements.length >= minimumValidRounds)) {
      await _finishMeasurement();
      return;
    }
    if (_attempt >= maximumAttempts - 1) {
      await _fail(
        AcousticSonarFailure.tooNoisy,
        notifyPeer: true,
        errorCode: RangingControlProtocol.errorRoundFailed,
      );
      return;
    }
    await _advanceToNextAttempt();
  }

  Future<void> _roundFailed(AcousticSonarFailure failure, int errorCode) async {
    await _send(RangingControlAction.error, value: errorCode.toDouble());
    if (_initiator) {
      await _retryOrFail(failure);
      return;
    }
    await _capture.cancel();
    _localObservation = null;
    _remoteObservation = null;
    _setState(AcousticSonarSessionState.awaitingAccept);
  }

  Future<void> _handleRemoteError(int errorCode) async {
    if (errorCode == RangingControlProtocol.errorMicrophonePermission) {
      await _fail(AcousticSonarFailure.remoteMicrophonePermission);
      return;
    }
    if (_initiator) {
      await _retryOrFail(
        errorCode == RangingControlProtocol.errorSelfChirpMissing
            ? AcousticSonarFailure.selfChirpMissing
            : AcousticSonarFailure.tooNoisy,
      );
      return;
    }
    await _capture.cancel();
    _setState(AcousticSonarSessionState.awaitingAccept);
  }

  Future<void> _retryOrFail(AcousticSonarFailure failure) async {
    if (_advancingRound) return;
    if (_attempt >= maximumAttempts - 1) {
      if (_measurements.length >= minimumValidRounds) {
        await _finishMeasurement();
      } else {
        await _fail(failure);
      }
      return;
    }
    await _advanceToNextAttempt();
  }

  Future<void> _advanceToNextAttempt() async {
    if (_advancingRound || !_active || !_initiator) return;
    _advancingRound = true;
    await _capture.cancel();
    _attempt += 1;
    _localObservation = null;
    _remoteObservation = null;
    _initiatorChirpSent = false;
    await _delay(roundPause);
    if (!_active) {
      _advancingRound = false;
      return;
    }
    if (!await _startCapture()) {
      _advancingRound = false;
      await _fail(AcousticSonarFailure.microphonePermission);
      return;
    }
    _setState(AcousticSonarSessionState.awaitingAccept);
    _advancingRound = false;
    await _send(RangingControlAction.request);
  }

  Future<void> _finishMeasurement() async {
    final aggregate = AcousticSonarDsp.aggregate(_measurements);
    if (aggregate == null) {
      await _fail(AcousticSonarFailure.invalidMeasurement);
      return;
    }
    await _send(
      RangingControlAction.result,
      value: aggregate.distanceMeters,
      errorMeters: aggregate.errorMeters,
      confidence: aggregate.confidence,
    );
    onMeasurement?.call(aggregate);
    await _complete();
  }

  Future<void> _complete() async {
    _setState(AcousticSonarSessionState.completed);
    _active = false;
    _cancelTimers();
    await _capture.cancel();
  }

  Future<void> _fail(
    AcousticSonarFailure failure, {
    bool notifyPeer = false,
    int errorCode = RangingControlProtocol.errorRoundFailed,
  }) async {
    if (notifyPeer && _nonce != null) {
      await _send(RangingControlAction.error, value: errorCode.toDouble());
    }
    _setState(AcousticSonarSessionState.failed);
    _active = false;
    _cancelTimers();
    await _capture.cancel();
    _reportFailure(failure);
  }

  void _reportFailure(AcousticSonarFailure failure) {
    onFailure?.call(failure);
  }

  Future<void> _reset({required bool notifyPeer}) async {
    if (notifyPeer && _active && _nonce != null) {
      await _send(RangingControlAction.stop);
    }
    _active = false;
    _cancelTimers();
    await _capture.cancel();
    _nonce = null;
    _localObservation = null;
    _remoteObservation = null;
    _measurements.clear();
    _initiatorChirpSent = false;
    _advancingRound = false;
    _setState(AcousticSonarSessionState.idle);
  }

  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(sessionTimeout, () {
      if (!_active) return;
      unawaited(
        _fail(
          AcousticSonarFailure.timeout,
          notifyPeer: true,
          errorCode: RangingControlProtocol.errorRoundFailed,
        ),
      );
    });
  }

  void _cancelTimers() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = null;
  }

  Future<void> _send(
    RangingControlAction action, {
    double value = 0,
    double errorMeters = 0,
    double confidence = 0,
  }) async {
    final nonce = _nonce;
    if (nonce == null) return;
    await _sendControl(
      RangingControlProtocol.encode(
        action: action,
        technology: RangingTechnology.acoustic,
        sessionNonce: nonce,
        round: _attempt,
        value: value,
        errorMeters: errorMeters,
        confidence: confidence,
      ),
    );
  }

  void _setState(AcousticSonarSessionState state) {
    if (_state == state) return;
    _state = state;
    onStateChanged?.call(state);
  }

  bool _bytesEqual(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
