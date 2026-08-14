import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/acoustic_sonar.dart';
import '../services/beacon_control_protocol.dart';
import '../services/compass_calibration_gate.dart';
import '../services/diagnostics_log.dart';
import '../services/mesh_platform_service.dart';
import '../services/radar_fusion.dart';
import '../services/radar_signal.dart';
import '../services/radar_ui_state.dart';
import '../services/ranging_control_protocol.dart';

/// Radar de rescate estilo AirTag: mide la intensidad de la señal BLE del
/// dispositivo objetivo y guía a la persona con proximidad, tendencia
/// («te estás acercando» / «la señal se debilita») y vibración tipo Geiger.
class RadarScreen extends StatefulWidget {
  const RadarScreen({
    required this.peerId,
    required this.nickname,
    required this.consentExpiresAt,
    required this.consentSource,
    this.latitude,
    this.longitude,
    this.platform,
    super.key,
  });

  final String peerId;
  final String nickname;
  final DateTime consentExpiresAt;
  final String consentSource;

  /// Última posición GPS conocida del objetivo (de su alerta SOS), si existe.
  final double? latitude;
  final double? longitude;
  final MeshPlatformService? platform;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with TickerProviderStateMixin {
  late final _platform = widget.platform ?? MeshPlatformService();
  final _processor = RadarSignalProcessor();
  final _sweepEstimator = SweepEstimator();
  final _calibrationGate = CompassCalibrationGate();
  final _headingFilter = CircularHeadingFilter();
  final _acousticCapture = AcousticSonarCapture();

  StreamSubscription<Map<Object?, Object?>>? _events;
  StreamSubscription<Position>? _positions;
  StreamSubscription<CompassEvent>? _compassEvents;
  Timer? _ticker;
  Timer? _acousticTimeout;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  RadarReading? _reading;
  bool _stale = false;
  bool _permissionExpired = false;
  bool _tentativeSignal = false;
  bool _sweepActive = false;
  bool _compassUnavailable = false;
  bool _compassNeedsCalibration = false;
  bool _sweepExpired = false;
  String? _startError;
  double? _gpsDistanceMeters;
  double? _headingDegrees;
  Position? _localPosition;
  double? _targetLatitude;
  double? _targetLongitude;
  double? _targetAccuracyMeters;
  DateTime? _targetPositionAt;
  SweepEstimate? _directionEstimate;
  RadarSweepAnchor? _directionAnchor;
  DateTime _lastCompassUiAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHaptic = DateTime.fromMillisecondsSinceEpoch(0);
  String? _beaconRequestId;
  String? _beaconStatus;
  DateTime? _beaconRequestExpiresAt;
  bool _requestingBeacon = false;
  bool _radioRangingAvailable = false;
  bool _radioRangingActive = false;
  bool _acousticActive = false;
  bool _acousticInitiator = false;
  Uint8List? _acousticNonce;
  int _acousticRound = 0;
  AcousticRoundObservation? _localAcousticObservation;
  AcousticRoundObservation? _remoteAcousticObservation;
  final List<AcousticDistanceMeasurement> _acousticMeasurements = [];
  double? _precisionDistanceMeters;
  double? _precisionDistanceErrorMeters;
  double _precisionDistanceConfidence = 0;
  RadarPrecisionSource? _precisionSource;

  @override
  void initState() {
    super.initState();
    _targetLatitude = widget.latitude;
    _targetLongitude = widget.longitude;
    unawaited(_startRadar());
    _events = _platform.events.listen(_onEvent);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    _startCompassTracking();
    _watchGps();
    unawaited(_loadRangingCapabilities());
  }

  Future<void> _startRadar() async {
    try {
      await _platform.startRadar(widget.peerId);
    } on PlatformException catch (error) {
      DiagnosticsLog.instance.error('radar.ble.start_failed', error: error);
      if (!mounted) return;
      setState(() => _startError = error.message ?? error.code);
    }
  }

  Future<void> _loadRangingCapabilities() async {
    try {
      final capabilities = await _platform.getRangingCapabilities();
      if (!mounted) return;
      setState(() {
        _radioRangingAvailable = capabilities['available'] == true;
      });
    } catch (error, stackTrace) {
      // El radar BLE y el sonar acústico siguen disponibles.
      DiagnosticsLog.instance.warning(
        'radar.radio.capabilities_unavailable',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onEvent(Map<Object?, Object?> event) {
    if (event['type'] == 'rangingMeasurement' &&
        (event['peerId'] as String?)?.toLowerCase() ==
            widget.peerId.toLowerCase()) {
      final meters = (event['meters'] as num?)?.toDouble();
      if (!mounted || meters == null || !meters.isFinite || meters < 0) return;
      setState(() {
        _radioRangingActive = true;
        _precisionDistanceMeters = meters;
        _precisionDistanceErrorMeters = (event['errorMeters'] as num?)
            ?.toDouble();
        _precisionDistanceConfidence =
            ((event['confidence'] as num?)?.toDouble() ?? 0)
                .clamp(0, 1)
                .toDouble();
        _precisionSource = RadarPrecisionSource.radio;
      });
      return;
    }
    if (event['type'] == 'radioRangingState') {
      final state = event['state'] as String?;
      if (!mounted) return;
      setState(
        () => _radioRangingActive = state == 'active' || state == 'opened',
      );
      return;
    }
    if (event['type'] == 'rangingControl' &&
        (event['peerId'] as String?)?.toLowerCase() ==
            widget.peerId.toLowerCase()) {
      final raw = event['payload'];
      if (raw is Uint8List) {
        final control = RangingControlProtocol.decode(raw);
        if (control != null &&
            control.technology == RangingTechnology.acoustic) {
          unawaited(_handleAcousticControl(control));
        }
      }
      return;
    }
    if (event['type'] == 'beaconState' &&
        event['scope'] == 'remote' &&
        (event['peerId'] as String?)?.toLowerCase() ==
            widget.peerId.toLowerCase()) {
      if (!mounted) return;
      setState(() {
        _beaconRequestId = event['requestId'] as String? ?? _beaconRequestId;
        _beaconStatus = event['status'] as String?;
        final expiresAt = (event['expiresAt'] as num?)?.toInt() ?? 0;
        _beaconRequestExpiresAt = expiresAt > 0
            ? DateTime.fromMillisecondsSinceEpoch(expiresAt)
            : null;
        _requestingBeacon = false;
      });
      return;
    }
    if (event['type'] == 'message') {
      final rawMessage = event['message'];
      if (rawMessage is Map<Object?, Object?>) {
        _handleLocationMessage(MeshMessage.fromMap(rawMessage));
      }
      return;
    }
    if (event['type'] == 'radarExpired' &&
        (event['peerId'] as String?)?.toLowerCase() ==
            widget.peerId.toLowerCase()) {
      if (mounted) setState(() => _permissionExpired = true);
      return;
    }
    if (event['type'] != 'rssi') return;
    if ((event['peerId'] as String?)?.toLowerCase() !=
        widget.peerId.toLowerCase()) {
      return;
    }
    final rssi = event['rssi'] as int?;
    if (rssi == null) return;
    final reading = _processor.addSample(rssi, DateTime.now());
    final heading = _headingDegrees;
    if (_sweepActive && heading != null) {
      _sweepEstimator.addSample(
        headingDegrees: heading,
        // El suavizado global introduce retraso angular mientras la persona
        // gira. El estimador aplica su propio filtro robusto por sector.
        rssi: rssi.toDouble(),
      );
      if (_sweepEstimator.isComplete) {
        _sweepActive = false;
        _directionEstimate = _sweepEstimator.estimate;
        _directionAnchor = RadarSweepAnchor(
          capturedAt: DateTime.now(),
          latitude: _localPosition?.latitude,
          longitude: _localPosition?.longitude,
        );
        _sweepExpired = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _reading = reading;
      _stale = false;
      _tentativeSignal = event['tentative'] as bool? ?? false;
    });
    _pulse.forward(from: 0);
  }

  void _startDirectionSweep() {
    if (_compassEvents == null) {
      setState(() => _compassUnavailable = true);
      return;
    }
    _sweepEstimator.reset();
    setState(() {
      _sweepActive = true;
      _directionEstimate = null;
      _directionAnchor = null;
      _sweepExpired = false;
    });
  }

  Future<void> _toggleRadioRanging() async {
    try {
      if (_radioRangingActive) {
        await _platform.stopRadioRanging();
        if (mounted) setState(() => _radioRangingActive = false);
      } else {
        await _platform.startRadioRanging(widget.peerId);
        if (mounted) setState(() => _radioRangingActive = true);
      }
    } on PlatformException catch (error) {
      DiagnosticsLog.instance.warning('radar.radio.start_failed', error: error);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
    }
  }

  Future<void> _toggleAcousticSonar() async {
    if (_acousticActive) {
      await _stopAcousticSonar(notifyPeer: true);
      return;
    }
    final nonce = RangingControlProtocol.randomNonce();
    _acousticNonce = nonce;
    _acousticInitiator = true;
    _acousticRound = 0;
    _acousticMeasurements.clear();
    _localAcousticObservation = null;
    _remoteAcousticObservation = null;
    if (!await _acousticCapture.start()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.radarSonarMicrophoneRequired)),
      );
      return;
    }
    if (mounted) setState(() => _acousticActive = true);
    _armAcousticTimeout();
    await _sendAcoustic(RangingControlAction.request);
  }

  Future<void> _handleAcousticControl(RangingControlMessage control) async {
    _armAcousticTimeout();
    if (control.action == RangingControlAction.request) {
      await _acousticCapture.cancel();
      _acousticNonce = control.sessionNonce;
      _acousticInitiator = false;
      _acousticRound = control.round;
      _localAcousticObservation = null;
      _remoteAcousticObservation = null;
      if (!await _acousticCapture.start()) {
        await _sendAcoustic(RangingControlAction.error);
        return;
      }
      if (mounted) setState(() => _acousticActive = true);
      await _sendAcoustic(RangingControlAction.accept);
      return;
    }
    final nonce = _acousticNonce;
    if (nonce == null || !_bytesEqual(nonce, control.sessionNonce)) return;
    if (control.action == RangingControlAction.accept && _acousticInitiator) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!_acousticActive) return;
      await _acousticCapture.emitChirp();
      await _sendAcoustic(RangingControlAction.acousticChirp, value: 0);
      return;
    }
    if (control.action == RangingControlAction.acousticChirp &&
        control.value == 0 &&
        !_acousticInitiator) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!_acousticActive) return;
      await _acousticCapture.emitChirp();
      await _sendAcoustic(RangingControlAction.acousticChirp, value: 1);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await _finishAcousticCapture(selfChirpFirst: false);
      return;
    }
    if (control.action == RangingControlAction.acousticChirp &&
        control.value == 1 &&
        _acousticInitiator) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await _finishAcousticCapture(selfChirpFirst: true);
      return;
    }
    if (control.action == RangingControlAction.acousticObservation) {
      _remoteAcousticObservation = AcousticRoundObservation(
        selfChirpSample: 0,
        remoteChirpSample: control.value.round(),
        confidence: control.confidence,
      );
      await _tryFinalizeAcousticRound();
      return;
    }
    if (control.action == RangingControlAction.result) {
      if (!mounted) return;
      setState(() {
        _precisionDistanceMeters = control.value;
        _precisionDistanceErrorMeters = control.errorMeters;
        _precisionDistanceConfidence = control.confidence;
        _precisionSource = RadarPrecisionSource.acoustic;
        _acousticActive = false;
      });
      _acousticTimeout?.cancel();
      await _acousticCapture.cancel();
      return;
    }
    if (control.action == RangingControlAction.stop ||
        control.action == RangingControlAction.error) {
      await _stopAcousticSonar(notifyPeer: false);
    }
  }

  Future<void> _finishAcousticCapture({required bool selfChirpFirst}) async {
    final detections = await _acousticCapture.stopAndAnalyze();
    if (detections.length < 2) {
      await _sendAcoustic(RangingControlAction.error);
      await _stopAcousticSonar(notifyPeer: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.radarSonarTooNoisy)),
        );
      }
      return;
    }
    final first = detections[0];
    final second = detections[1];
    _localAcousticObservation = AcousticRoundObservation(
      selfChirpSample: selfChirpFirst ? first.sampleIndex : second.sampleIndex,
      remoteChirpSample: selfChirpFirst
          ? second.sampleIndex
          : first.sampleIndex,
      confidence: math.min(first.confidence, second.confidence),
    );
    await _sendAcoustic(
      RangingControlAction.acousticObservation,
      value: _localAcousticObservation!.signedDeltaSamples.toDouble(),
      confidence: _localAcousticObservation!.confidence,
    );
    await _tryFinalizeAcousticRound();
  }

  Future<void> _tryFinalizeAcousticRound() async {
    final local = _localAcousticObservation;
    final remote = _remoteAcousticObservation;
    if (local == null || remote == null) return;
    final measurement = AcousticSonarDsp.combineRound(
      local: local,
      remote: remote,
    );
    if (measurement == null) {
      await _sendAcoustic(RangingControlAction.error);
      await _stopAcousticSonar(notifyPeer: false);
      return;
    }
    _acousticMeasurements.add(measurement);
    if (_acousticInitiator && _acousticRound < 2) {
      _acousticRound += 1;
      _localAcousticObservation = null;
      _remoteAcousticObservation = null;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!await _acousticCapture.start()) {
        await _stopAcousticSonar(notifyPeer: true);
        return;
      }
      await _sendAcoustic(RangingControlAction.request);
      return;
    }
    if (!_acousticInitiator) return;
    final aggregate = AcousticSonarDsp.aggregate(_acousticMeasurements)!;
    await _sendAcoustic(
      RangingControlAction.result,
      value: aggregate.distanceMeters,
      errorMeters: aggregate.errorMeters,
      confidence: aggregate.confidence,
    );
    _acousticTimeout?.cancel();
    if (!mounted) return;
    setState(() {
      _precisionDistanceMeters = aggregate.distanceMeters;
      _precisionDistanceErrorMeters = aggregate.errorMeters;
      _precisionDistanceConfidence = aggregate.confidence;
      _precisionSource = RadarPrecisionSource.acoustic;
      _acousticActive = false;
    });
  }

  Future<void> _sendAcoustic(
    RangingControlAction action, {
    double value = 0,
    double errorMeters = 0,
    double confidence = 0,
  }) async {
    final nonce = _acousticNonce;
    if (nonce == null) return;
    await _platform.sendRangingControl(
      widget.peerId,
      RangingControlProtocol.encode(
        action: action,
        technology: RangingTechnology.acoustic,
        sessionNonce: nonce,
        round: _acousticRound,
        value: value,
        errorMeters: errorMeters,
        confidence: confidence,
      ),
    );
  }

  Future<void> _stopAcousticSonar({required bool notifyPeer}) async {
    if (notifyPeer && _acousticNonce != null) {
      await _sendAcoustic(RangingControlAction.stop);
    }
    await _acousticCapture.cancel();
    _acousticTimeout?.cancel();
    _acousticTimeout = null;
    _acousticNonce = null;
    _localAcousticObservation = null;
    _remoteAcousticObservation = null;
    if (mounted) setState(() => _acousticActive = false);
  }

  bool _bytesEqual(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  void _armAcousticTimeout() {
    _acousticTimeout?.cancel();
    _acousticTimeout = Timer(const Duration(seconds: 15), () {
      if (!_acousticActive) return;
      unawaited(_stopAcousticSonar(notifyPeer: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.radarSonarTooNoisy)),
        );
      }
    });
  }

  bool get _canRequestBeacon {
    final proximity = _reading?.proximity;
    return !_permissionExpired &&
        widget.consentExpiresAt.isAfter(DateTime.now()) &&
        !_stale &&
        (proximity == RadarProximity.close ||
            proximity == RadarProximity.veryClose);
  }

  Future<void> _toggleRemoteBeacon() async {
    if (_requestingBeacon) return;
    setState(() => _requestingBeacon = true);
    try {
      if (_beaconStatus == 'active' && _beaconRequestId != null) {
        await _platform.stopRemoteBeacon(
          peerId: widget.peerId,
          requestId: _beaconRequestId!,
        );
      } else {
        final requestId = await _platform.requestRemoteBeacon(widget.peerId);
        if (mounted) {
          setState(() {
            _beaconRequestId = requestId;
            _beaconStatus = 'requested';
            _beaconRequestExpiresAt = DateTime.now().add(
              BeaconControlProtocol.maximumDuration,
            );
          });
        }
      }
    } on PlatformException catch (error) {
      DiagnosticsLog.instance.warning(
        'radar.beacon.request_failed',
        error: error,
      );
      if (mounted) {
        final message = error.message ?? error.code;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _requestingBeacon = false);
    }
  }

  void _startCompassTracking() {
    final compassStream = FlutterCompass.events;
    if (compassStream == null) {
      _compassUnavailable = true;
      return;
    }
    _compassEvents = compassStream.listen(
      (event) {
        if (!mounted) return;
        final rawHeading = event.heading;
        final heading = rawHeading == null || !rawHeading.isFinite
            ? null
            : _headingFilter.add(rawHeading);
        final rawAccuracy = event.accuracy;
        final accuracy =
            rawAccuracy == null || rawAccuracy < 0 || !rawAccuracy.isFinite
            ? null
            : rawAccuracy;
        final now = DateTime.now();
        final calibration = _calibrationGate.update(accuracy, now);
        final unavailable = heading == null;
        final previousHeading = _headingDegrees;
        final headingChanged =
            previousHeading == null ||
            heading == null ||
            RadarFusion.angularDistance(previousHeading, heading) >= 2;
        final stateChanged =
            calibration != _compassNeedsCalibration ||
            unavailable != _compassUnavailable;
        _headingDegrees = heading;
        _compassNeedsCalibration = calibration;
        _compassUnavailable = unavailable;
        if (stateChanged ||
            (headingChanged &&
                now.difference(_lastCompassUiAt) >=
                    const Duration(milliseconds: 100))) {
          _lastCompassUiAt = now;
          setState(() {});
        }
      },
      onError: (_) {
        if (mounted) setState(() => _compassUnavailable = true);
      },
    );
  }

  void _tick() {
    if (!mounted) return;
    if (!_permissionExpired &&
        !widget.consentExpiresAt.isAfter(DateTime.now())) {
      _permissionExpired = true;
      unawaited(_platform.stopRadar());
      setState(() {});
      return;
    }
    final stale = _processor.isStale(DateTime.now());
    final anchor = _directionAnchor;
    if (_directionEstimate != null &&
        anchor != null &&
        !anchor.isFresh(
          now: DateTime.now(),
          currentLatitude: _localPosition?.latitude,
          currentLongitude: _localPosition?.longitude,
        )) {
      _directionEstimate = null;
      _directionAnchor = null;
      _sweepExpired = true;
      setState(() {});
    }
    if (_beaconStatus == 'requested' &&
        _beaconRequestExpiresAt?.isAfter(DateTime.now()) == false) {
      _beaconStatus = null;
      _beaconRequestId = null;
      _beaconRequestExpiresAt = null;
      setState(() {});
    }
    if (stale != _stale) setState(() => _stale = stale);
    _maybeVibrate();
  }

  /// Vibración tipo contador Geiger: más frecuente e intensa cuanto más cerca.
  void _maybeVibrate() {
    final reading = _reading;
    if (reading == null || _stale) return;
    final (interval, feedback) = switch (reading.proximity) {
      RadarProximity.veryClose => (
        const Duration(milliseconds: 250),
        HapticFeedback.heavyImpact,
      ),
      RadarProximity.close => (
        const Duration(milliseconds: 500),
        HapticFeedback.mediumImpact,
      ),
      RadarProximity.inRange => (
        const Duration(milliseconds: 1000),
        HapticFeedback.lightImpact,
      ),
      RadarProximity.far => (
        const Duration(milliseconds: 2000),
        HapticFeedback.selectionClick,
      ),
    };
    final now = DateTime.now();
    if (now.difference(_lastHaptic) >= interval) {
      _lastHaptic = now;
      unawaited(feedback());
    }
  }

  /// Mantiene la posición del rescatista aun si el radar se abrió sin un SOS:
  /// una actualización privada HB-LOC puede aportar luego el objetivo.
  Future<void> _watchGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      _positions =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            ),
          ).listen((position) {
            if (!mounted) return;
            setState(() {
              _localPosition = position;
              _updateGpsDistance();
            });
          });
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) {
        setState(() {
          _localPosition = current;
          _updateGpsDistance();
        });
      }
    } catch (error, stackTrace) {
      // Sin GPS disponible el radar BLE sigue funcionando.
      DiagnosticsLog.instance.warning(
        'radar.gps.unavailable',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleLocationMessage(MeshMessage message) {
    if (message.senderPeerId.toLowerCase() != widget.peerId.toLowerCase()) {
      return;
    }
    final radarLocation = message.radarLocation;
    if (radarLocation != null) {
      final now = DateTime.now();
      if (radarLocation.timestamp.isAfter(
        now.add(const Duration(minutes: 2)),
      )) {
        return;
      }
      _applyTargetLocation(
        latitude: radarLocation.latitude,
        longitude: radarLocation.longitude,
        accuracyMeters: radarLocation.accuracyMeters,
        timestamp: radarLocation.timestamp,
      );
      return;
    }
    final checkIn = message.checkIn;
    if (checkIn?.latitude != null && checkIn?.longitude != null) {
      _applyTargetLocation(
        latitude: checkIn!.latitude!,
        longitude: checkIn.longitude!,
        timestamp: checkIn.timestamp,
      );
      return;
    }
    final latitude = message.sosLatitude;
    final longitude = message.sosLongitude;
    if (message.isSos && latitude != null && longitude != null) {
      _applyTargetLocation(
        latitude: latitude,
        longitude: longitude,
        timestamp: message.timestamp,
      );
    }
  }

  void _applyTargetLocation({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double? accuracyMeters,
  }) {
    final previous = _targetPositionAt;
    if (previous != null && timestamp.isBefore(previous)) return;
    if (!mounted) return;
    setState(() {
      _targetLatitude = latitude;
      _targetLongitude = longitude;
      _targetAccuracyMeters = accuracyMeters;
      _targetPositionAt = timestamp;
      _updateGpsDistance();
    });
  }

  void _updateGpsDistance() {
    final local = _localPosition;
    final latitude = _targetLatitude;
    final longitude = _targetLongitude;
    _gpsDistanceMeters = local == null || latitude == null || longitude == null
        ? null
        : Geolocator.distanceBetween(
            local.latitude,
            local.longitude,
            latitude,
            longitude,
          );
  }

  @override
  void dispose() {
    unawaited(_platform.stopRadar());
    unawaited(_platform.stopRadioRanging());
    unawaited(_acousticCapture.dispose());
    _events?.cancel();
    _positions?.cancel();
    _compassEvents?.cancel();
    _ticker?.cancel();
    _acousticTimeout?.cancel();
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    final searching = reading == null;
    final fusion = _fusionResult();
    return Scaffold(
      backgroundColor: const Color(0xFF07120D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.l10n.radarTitle(widget.nickname)),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = _buildRadarColumn(
              reading: reading,
              searching: searching,
              fusion: fusion,
              compact: constraints.maxHeight < 700,
            );
            if (constraints.maxHeight >= 520) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: content,
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(height: 520, child: content),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRadarColumn({
    required RadarReading? reading,
    required bool searching,
    required RadarFusionResult fusion,
    required bool compact,
  }) {
    return Column(
      children: [
        _buildBannerSlot(fusion),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final radarSide = math.min(
                420.0,
                math.min(constraints.maxWidth, constraints.maxHeight),
              );
              return Center(
                child: SizedBox.square(
                  key: const ValueKey('radar-canvas'),
                  dimension: radarSide,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AnimatedRadarCanvas(
                        sweep: _sweep,
                        pulse: _pulse,
                        strength: _stale ? null : reading?.strength,
                        directionSweepSectors: _sweepEstimator.sectorCoverage,
                        estimatedDirectionRadians: _bleDirectionRadians(fusion),
                        gpsDirectionRadians: _gpsDirectionRadians(fusion),
                      ),
                      if (_sweepActive) _buildSweepOverlay(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        _buildPanel(reading, searching, fusion, compact: compact),
        const SizedBox(height: 6),
        _buildActionRow(),
        const SizedBox(height: 4),
        Text(
          '${_consentLabel()} · ${context.l10n.radarConsentExpires(_formatExpiry())}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildBannerSlot(RadarFusionResult fusion) {
    final kind = resolveRadarBanner(
      permissionExpired: _permissionExpired,
      hasStartError: _startError != null,
      signalLost: _stale,
      compassNeedsCalibration: _compassNeedsCalibration,
      sourcesDisagree: fusion.sourcesDisagree,
      sweepExpired: _sweepExpired,
      tentativeSignal: _tentativeSignal,
    );
    final (icon, color, message) = switch (kind) {
      RadarBannerKind.permissionExpired => (
        Icons.lock_clock_outlined,
        const Color(0xFFF87171),
        context.l10n.radarPermissionExpired,
      ),
      RadarBannerKind.startError => (
        Icons.error_outline,
        const Color(0xFFF87171),
        _startError!,
      ),
      RadarBannerKind.signalLost => (
        Icons.wifi_off,
        const Color(0xFFF87171),
        context.l10n.radarSignalLostHint,
      ),
      RadarBannerKind.compassCalibration => (
        Icons.screen_rotation_alt_outlined,
        const Color(0xFFFBBF24),
        context.l10n.radarCompassCalibration,
      ),
      RadarBannerKind.sourcesDisagree => (
        Icons.compare_arrows,
        const Color(0xFFFBBF24),
        context.l10n.radarSourcesDisagree,
      ),
      RadarBannerKind.sweepExpired => (
        Icons.refresh,
        const Color(0xFFFBBF24),
        context.l10n.radarSweepExpired,
      ),
      RadarBannerKind.tentativeSignal => (
        Icons.bluetooth_searching,
        const Color(0xFF94A3B8),
        context.l10n.radarTentativeSignal,
      ),
      null => (Icons.info_outline, Colors.transparent, ''),
    };
    return SizedBox(
      key: const ValueKey('radar-banner-slot'),
      height: 58,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: kind == null
            ? const SizedBox.expand(key: ValueKey('empty-radar-banner'))
            : Container(
                key: ValueKey(kind),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: .4)),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSweepOverlay() {
    const green = Color(0xFF4ADE80);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF07120D).withValues(alpha: .9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: green.withValues(alpha: .5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _SweepHoldingGuide(animation: _sweep, active: true),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _sweepEstimator.progress,
                color: green,
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.radarSweepProgress(
                  (_sweepEstimator.progress * 100).round(),
                ),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    final estimate = _directionEstimate;
    final directionButton = OutlinedButton.icon(
      onPressed: _compassUnavailable || _sweepActive
          ? null
          : _startDirectionSweep,
      icon: const Icon(Icons.explore_outlined),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          estimate == null
              ? context.l10n.radarSweepStart
              : context.l10n.radarSweepRestart,
        ),
      ),
    );
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: directionButton),
          if (_radioRangingAvailable) ...[
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: _radioRangingActive
                  ? context.l10n.radarRadioStop
                  : context.l10n.radarRadioStart,
              onPressed: _toggleRadioRanging,
              icon: Icon(
                _radioRangingActive ? Icons.radar : Icons.social_distance,
              ),
            ),
          ],
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: _acousticActive
                ? context.l10n.radarSonarStop
                : context.l10n.radarSonarStart,
            onPressed: _toggleAcousticSonar,
            icon: Icon(
              _acousticActive ? Icons.hearing_disabled : Icons.graphic_eq,
            ),
          ),
          if (_canRequestBeacon || _beaconStatus == 'active') ...[
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: _beaconStatus == 'active'
                  ? context.l10n.beaconStopRemote
                  : context.l10n.beaconRequestRemote,
              onPressed: _requestingBeacon || _beaconStatus == 'requested'
                  ? null
                  : _toggleRemoteBeacon,
              icon: Icon(
                _beaconStatus == 'active'
                    ? Icons.flashlight_off_outlined
                    : Icons.flashlight_on_outlined,
              ),
            ),
          ],
        ],
      ),
    );
  }

  RadarFusionResult _fusionResult() {
    final local = _localPosition;
    return RadarFusion.evaluate(
      proximity: _stale ? null : _reading?.proximity,
      bleEstimate: _stale ? null : _directionEstimate,
      // Una brújula marcada como imprecisa no debe seguir alimentando un
      // rombo que parece autoritativo: ocultamos dirección hasta calibrarla.
      headingDegrees: _compassNeedsCalibration ? null : _headingDegrees,
      localLatitude: local?.latitude,
      localLongitude: local?.longitude,
      localAccuracyMeters: local?.accuracy,
      targetLatitude: _targetLatitude,
      targetLongitude: _targetLongitude,
      targetAccuracyMeters: _targetAccuracyMeters,
      gpsDistanceMeters: _gpsDistanceMeters,
      bleApproxDistanceMeters: _stale ? null : _reading?.approxDistanceMeters,
      precisionDistanceMeters: _precisionDistanceMeters,
      precisionDistanceErrorMeters: _precisionDistanceErrorMeters,
      precisionDistanceConfidence: _precisionDistanceConfidence,
      precisionSource: _precisionSource,
    );
  }

  double? _bleDirectionRadians(RadarFusionResult fusion) {
    final estimate = _directionEstimate;
    final heading = _headingDegrees;
    if (!fusion.showBleSector || estimate == null || heading == null) {
      return null;
    }
    return RadarFusion.signedAngularDelta(heading, estimate.headingDegrees) *
        math.pi /
        180;
  }

  double? _gpsDirectionRadians(RadarFusionResult fusion) {
    final relative = fusion.gpsRelativeDegrees;
    if (fusion.source != RadarDirectionSource.gps || relative == null) {
      return null;
    }
    return relative * math.pi / 180;
  }

  Widget _buildPanel(
    RadarReading? reading,
    bool searching,
    RadarFusionResult fusion, {
    required bool compact,
  }) {
    const green = Color(0xFF4ADE80);
    const red = Color(0xFFF87171);
    const dim = Color(0xFF94A3B8);
    final height = compact ? 142.0 : 170.0;
    Widget content;
    if (_permissionExpired || _startError != null) {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_clock_outlined, color: red, size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.l10n.radarPermissionExpired,
              textAlign: TextAlign.center,
              style: const TextStyle(color: red, fontSize: 16),
            ),
          ),
        ],
      );
    } else if (_stale) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.l10n.radarSignalLost,
            style: const TextStyle(
              color: red,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          if (_gpsDistanceMeters != null) ...[
            const SizedBox(height: 8),
            _statusMetric(
              Icons.gps_fixed,
              _gpsDistanceLabel(_gpsDistanceMeters!),
              dim,
            ),
          ],
        ],
      );
    } else if (searching) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3, color: green),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.radarSearching,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.radarSearchingHint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: dim, fontSize: 11),
          ),
        ],
      );
    } else {
      final (trendIcon, trendColor) = switch (reading!.trend) {
        RadarTrend.approaching => (Icons.trending_up, green),
        RadarTrend.receding => (Icons.trending_down, red),
        RadarTrend.steady => (Icons.trending_flat, dim),
        RadarTrend.unknown => (Icons.more_horiz, dim),
      };
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _proximityLabel(context.l10n, reading.proximity),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Text(
                fusion.hasMeasuredDistance
                    ? _measuredDistanceLabel(fusion)
                    : _distanceLabel(
                        context.l10n,
                        fusion.preferredDistanceMeters ??
                            reading.approxDistanceMeters,
                      ),
                style: TextStyle(
                  color: fusion.hasMeasuredDistance
                      ? const Color(0xFF60A5FA)
                      : dim,
                  fontSize: 14,
                  fontWeight: fusion.hasMeasuredDistance
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: reading.strength,
              minHeight: 7,
              backgroundColor: Colors.white12,
              color: Color.lerp(red, green, reading.strength),
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 5,
            children: [
              _statusMetric(
                trendIcon,
                _trendLabel(context.l10n, reading.trend),
                trendColor,
              ),
              _statusMetric(
                Icons.bluetooth,
                context.l10n.radarDbm(reading.smoothedRssi.round()),
                dim,
              ),
              if (_gpsDistanceMeters != null)
                _statusMetric(
                  Icons.gps_fixed,
                  _gpsDistanceLabel(_gpsDistanceMeters!),
                  const Color(0xFF60A5FA),
                ),
            ],
          ),
          if (_directionSummary(fusion) case final summary?) ...[
            const SizedBox(height: 5),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: dim, fontSize: 11),
            ),
          ],
        ],
      );
    }
    return SizedBox(
      height: height,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: content,
      ),
    );
  }

  Widget _statusMetric(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }

  String _gpsDistanceLabel(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)} km'
      : '${meters.round()} m GPS';

  String _measuredDistanceLabel(RadarFusionResult fusion) {
    final meters = fusion.preferredDistanceMeters!;
    final error = fusion.distanceErrorMeters;
    final value = meters < 10
        ? meters.toStringAsFixed(1)
        : meters.round().toString();
    final margin = error == null ? '' : ' ±${error.toStringAsFixed(1)}';
    return context.l10n.radarMeasuredDistance('$value$margin m');
  }

  String? _directionSummary(RadarFusionResult fusion) {
    final estimate = _directionEstimate;
    if (_compassUnavailable) return context.l10n.radarCompassUnavailable;
    if (fusion.bleSuppressedVeryClose) {
      return context.l10n.radarDirectionVeryClose;
    }
    if (fusion.source == RadarDirectionSource.gps) {
      return context.l10n.radarDirectionGps;
    }
    if (fusion.source == RadarDirectionSource.ble && estimate != null) {
      return '${context.l10n.radarSweepResult(estimate.headingDegrees.round())} · '
          '${context.l10n.radarSweepConfidence((fusion.adjustedBleConfidence * 100).round())}';
    }
    if (estimate != null) return context.l10n.radarSweepInconclusive;
    return null;
  }

  String _consentLabel() => widget.consentSource == 'sos'
      ? context.l10n.radarConsentSos
      : context.l10n.radarConsentTemporary;

  String _formatExpiry() => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(widget.consentExpiresAt.toLocal()));

  String _proximityLabel(AppLocalizations l10n, RadarProximity proximity) =>
      switch (proximity) {
        RadarProximity.veryClose => l10n.proximityVeryClose,
        RadarProximity.close => l10n.proximityClose,
        RadarProximity.inRange => l10n.proximityInRange,
        RadarProximity.far => l10n.proximityFar,
      };

  String _trendLabel(AppLocalizations l10n, RadarTrend trend) =>
      switch (trend) {
        RadarTrend.approaching => l10n.trendApproaching,
        RadarTrend.receding => l10n.trendReceding,
        RadarTrend.steady => l10n.trendSteady,
        RadarTrend.unknown => l10n.trendUnknown,
      };

  /// Distancia orientativa legible: nunca prometemos precisión de metro.
  String _distanceLabel(AppLocalizations l10n, double meters) {
    if (meters < 1.5) return l10n.distanceVeryNear;
    if (meters < 5) return l10n.distanceApprox(meters.round());
    if (meters < 15) return l10n.distanceApprox((meters / 5).round() * 5);
    return l10n.distanceFar;
  }
}

class _AnimatedRadarCanvas extends StatefulWidget {
  const _AnimatedRadarCanvas({
    required this.sweep,
    required this.pulse,
    required this.strength,
    required this.directionSweepSectors,
    required this.estimatedDirectionRadians,
    required this.gpsDirectionRadians,
  });

  final Animation<double> sweep;
  final Animation<double> pulse;
  final double? strength;
  final List<bool> directionSweepSectors;
  final double? estimatedDirectionRadians;
  final double? gpsDirectionRadians;

  @override
  State<_AnimatedRadarCanvas> createState() => _AnimatedRadarCanvasState();
}

class _AnimatedRadarCanvasState extends State<_AnimatedRadarCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _directionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  Tween<double>? _bleTween;
  Tween<double>? _gpsTween;
  double? _bleAngle;
  double? _gpsAngle;

  @override
  void initState() {
    super.initState();
    _bleAngle = widget.estimatedDirectionRadians;
    _gpsAngle = widget.gpsDirectionRadians;
  }

  @override
  void didUpdateWidget(covariant _AnimatedRadarCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    var changed = false;
    if (widget.estimatedDirectionRadians !=
        oldWidget.estimatedDirectionRadians) {
      _bleTween = _angularTween(
        _current(_bleTween, _bleAngle),
        widget.estimatedDirectionRadians,
      );
      _bleAngle = widget.estimatedDirectionRadians;
      changed = true;
    }
    if (widget.gpsDirectionRadians != oldWidget.gpsDirectionRadians) {
      _gpsTween = _angularTween(
        _current(_gpsTween, _gpsAngle),
        widget.gpsDirectionRadians,
      );
      _gpsAngle = widget.gpsDirectionRadians;
      changed = true;
    }
    if (changed) _directionController.forward(from: 0);
  }

  double? _current(Tween<double>? tween, double? fallback) {
    if (tween == null || !_directionController.isAnimating) return fallback;
    return tween.transform(_directionController.value);
  }

  Tween<double>? _angularTween(double? from, double? to) {
    if (to == null) return null;
    final begin = from ?? to;
    final delta = ((to - begin + math.pi * 3) % (math.pi * 2)) - math.pi;
    return Tween<double>(begin: begin, end: begin + delta);
  }

  @override
  void dispose() {
    _directionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.sweep,
        widget.pulse,
        _directionController,
      ]),
      builder: (context, _) => CustomPaint(
        painter: _RadarPainter(
          sweepProgress: widget.sweep.value,
          pulseProgress: widget.pulse.value,
          strength: widget.strength,
          directionSweepSectors: widget.directionSweepSectors,
          estimatedDirectionRadians: widget.estimatedDirectionRadians == null
              ? null
              : (_bleTween?.transform(_directionController.value) ??
                    widget.estimatedDirectionRadians),
          gpsDirectionRadians: widget.gpsDirectionRadians == null
              ? null
              : (_gpsTween?.transform(_directionController.value) ??
                    widget.gpsDirectionRadians),
        ),
      ),
    );
  }
}

class _SweepHoldingGuide extends StatelessWidget {
  const _SweepHoldingGuide({required this.animation, required this.active});

  final Animation<double> animation;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4ADE80);
    const dim = Color(0xFF94A3B8);
    return Row(
      children: [
        SizedBox(
          width: 68,
          height: 68,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _SweepGuidePainter(
                rotationProgress: active ? animation.value : 0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.radarSweepHoldTitle,
                style: const TextStyle(
                  color: green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.radarSweepInstruction,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: dim, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SweepGuidePainter extends CustomPainter {
  const _SweepGuidePainter({required this.rotationProgress});

  final double rotationProgress;

  @override
  void paint(Canvas canvas, Size size) {
    const green = Color(0xFF4ADE80);
    const amber = Color(0xFFFBBF24);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.4;
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi * 0.72;
    const sweep = math.pi * 1.55;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = green.withValues(alpha: 0.8);
    canvas.drawArc(arcRect, start, sweep, false, arcPaint);

    final end = start + sweep;
    final tip = center + Offset(math.cos(end), math.sin(end)) * radius;
    final tangent = Offset(-math.sin(end), math.cos(end));
    final normal = Offset(math.cos(end), math.sin(end));
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx + tangent.dx * 7, tip.dy + tangent.dy * 7)
        ..lineTo(
          tip.dx - tangent.dx * 5 + normal.dx * 5,
          tip.dy - tangent.dy * 5 + normal.dy * 5,
        )
        ..lineTo(
          tip.dx - tangent.dx * 5 - normal.dx * 5,
          tip.dy - tangent.dy * 5 - normal.dy * 5,
        )
        ..close(),
      Paint()..color = green,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationProgress * 2 * math.pi);
    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 25, height: 46),
      const Radius.circular(5),
    );
    canvas.drawRRect(phone, Paint()..color = const Color(0xFF17241E));
    canvas.drawRRect(
      phone,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.drawLine(
      const Offset(-6, -16),
      const Offset(6, -16),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = amber,
    );
    canvas.drawCircle(const Offset(0, 15), 2, Paint()..color = green);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepGuidePainter oldDelegate) =>
      oldDelegate.rotationProgress != rotationProgress;
}

/// Pinta el sonar: anillos concéntricos, barrido giratorio y un punto que se
/// acerca al centro a medida que la señal se hace más fuerte.
class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweepProgress,
    required this.pulseProgress,
    required this.strength,
    required this.directionSweepSectors,
    required this.estimatedDirectionRadians,
    required this.gpsDirectionRadians,
  });

  final double sweepProgress;
  final double pulseProgress;

  /// null cuando no hay señal utilizable (sin blip).
  final double? strength;
  final List<bool> directionSweepSectors;
  final double? estimatedDirectionRadians;
  final double? gpsDirectionRadians;

  static const _green = Color(0xFF4ADE80);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _green.withValues(alpha: 0.25);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }
    final sectorAngle = 2 * math.pi / directionSweepSectors.length;
    final directionProgressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = _green;
    for (var index = 0; index < directionSweepSectors.length; index++) {
      if (!directionSweepSectors[index]) continue;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 3),
        -math.pi / 2 + index * sectorAngle + 0.04,
        sectorAngle - 0.08,
        false,
        directionProgressPaint,
      );
    }
    final crossPaint = Paint()
      ..strokeWidth = 1
      ..color = _green.withValues(alpha: 0.15);
    canvas.drawLine(
      center - Offset(radius, 0),
      center + Offset(radius, 0),
      crossPaint,
    );
    canvas.drawLine(
      center - Offset(0, radius),
      center + Offset(0, radius),
      crossPaint,
    );

    // Barrido giratorio con gradiente que se desvanece.
    final sweepAngle = sweepProgress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [_green.withValues(alpha: 0.0), _green.withValues(alpha: 0.35)],
        stops: const [0.7, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // Punto central: el rescatista.
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);

    final direction = estimatedDirectionRadians;
    if (direction != null) {
      const halfSector = math.pi / 6;
      final sectorRect = Rect.fromCircle(center: center, radius: radius * 0.74);
      final sectorPath = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          sectorRect,
          direction - math.pi / 2 - halfSector,
          halfSector * 2,
          false,
        )
        ..close();
      canvas.drawPath(
        sectorPath,
        Paint()..color = const Color(0xFFFBBF24).withValues(alpha: 0.22),
      );
      canvas.drawArc(
        sectorRect,
        direction - math.pi / 2 - halfSector,
        halfSector * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFBBF24),
      );
    }

    final gpsDirection = gpsDirectionRadians;
    if (gpsDirection != null) {
      const blue = Color(0xFF60A5FA);
      final angle = gpsDirection - math.pi / 2;
      final unit = Offset(math.cos(angle), math.sin(angle));
      final marker = center + unit * radius * 0.82;
      canvas.drawLine(
        center,
        marker,
        Paint()
          ..strokeWidth = 2
          ..color = blue.withValues(alpha: 0.35),
      );
      final tangent = Offset(-unit.dy, unit.dx);
      final diamond = Path()
        ..moveTo(marker.dx + unit.dx * 10, marker.dy + unit.dy * 10)
        ..lineTo(marker.dx + tangent.dx * 7, marker.dy + tangent.dy * 7)
        ..lineTo(marker.dx - unit.dx * 10, marker.dy - unit.dy * 10)
        ..lineTo(marker.dx - tangent.dx * 7, marker.dy - tangent.dy * 7)
        ..close();
      canvas.drawPath(diamond, Paint()..color = blue);
      canvas.drawPath(
        diamond,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }

    final currentStrength = strength;
    if (currentStrength != null) {
      // El objetivo se dibuja arriba; su distancia al centro refleja la
      // fuerza de señal (el BLE no da dirección, solo cercanía).
      final blipRadius = (1 - currentStrength) * radius * 0.85 + radius * 0.08;
      final blip = center - Offset(0, blipRadius);
      final glowRadius = 10 + pulseProgress * 22;
      canvas.drawCircle(
        blip,
        glowRadius,
        Paint()..color = _green.withValues(alpha: (1 - pulseProgress) * 0.4),
      );
      canvas.drawCircle(blip, 8, Paint()..color = _green);
      canvas.drawCircle(
        blip,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.sweepProgress != sweepProgress ||
      oldDelegate.pulseProgress != pulseProgress ||
      oldDelegate.strength != strength ||
      oldDelegate.directionSweepSectors != directionSweepSectors ||
      oldDelegate.estimatedDirectionRadians != estimatedDirectionRadians ||
      oldDelegate.gpsDirectionRadians != gpsDirectionRadians;
}
