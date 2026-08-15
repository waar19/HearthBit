import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/acoustic_sonar.dart';
import '../services/acoustic_sonar_session.dart';
import '../services/beacon_control_protocol.dart';
import '../services/compass_calibration_gate.dart';
import '../services/diagnostics_log.dart';
import '../services/mesh_native_event.dart';
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
    this.compassEvents,
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
  final Stream<CompassEvent>? compassEvents;

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
  late final AcousticSonarSession _acousticSession;

  StreamSubscription<MeshNativeEvent>? _events;
  StreamSubscription<Position>? _positions;
  StreamSubscription<CompassEvent>? _compassEvents;
  Timer? _ticker;

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
  bool _noSignalHint = false;
  final DateTime _searchStartedAt = DateTime.now();
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
  double? _precisionDistanceMeters;
  double? _precisionDistanceErrorMeters;
  double _precisionDistanceConfidence = 0;
  RadarPrecisionSource? _precisionSource;

  @override
  void initState() {
    super.initState();
    _acousticSession = AcousticSonarSession(
      capture: AcousticSonarCapture(),
      sendControl: (payload) =>
          _platform.sendRangingControl(widget.peerId, payload),
      onStateChanged: _onAcousticStateChanged,
      onMeasurement: _onAcousticMeasurement,
      onFailure: _onAcousticFailure,
    );
    _targetLatitude = widget.latitude;
    _targetLongitude = widget.longitude;
    unawaited(_startRadar());
    _events = _platform.nativeEvents.listen(_onEvent);
    _scheduleTick();
    if (_hasTargetCoordinates) _startCompassTracking();
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

  void _onEvent(MeshNativeEvent event) {
    switch (event) {
      case MeshRangingMeasurementEvent():
        if (!_isTarget(event.peerId)) return;
        final meters = event.meters;
        if (!mounted || meters == null || !meters.isFinite || meters < 0)
          return;
        setState(() {
          _radioRangingActive = true;
          _precisionDistanceMeters = meters;
          _precisionDistanceErrorMeters = event.errorMeters;
          _precisionDistanceConfidence = (event.confidence ?? 0)
              .clamp(0, 1)
              .toDouble();
          _precisionSource = RadarPrecisionSource.radio;
        });
        return;
      case MeshRadioRangingStateEvent():
        if (!mounted) return;
        setState(
          () => _radioRangingActive =
              event.state == 'active' || event.state == 'opened',
        );
        return;
      case MeshRangingControlEvent():
        if (!_isTarget(event.peerId)) return;
        final payload = event.payload;
        if (payload != null) {
          final control = RangingControlProtocol.decode(payload);
          if (control != null &&
              control.technology == RangingTechnology.acoustic) {
            unawaited(_handleAcousticControl(control));
          }
        }
        return;
      case MeshBeaconStateEvent():
        if (event.scope != 'remote' || !_isTarget(event.peerId) || !mounted) {
          return;
        }
        setState(() {
          _beaconRequestId = event.requestId ?? _beaconRequestId;
          _beaconStatus = event.status;
          final expiresAt = event.expiresAt ?? 0;
          _beaconRequestExpiresAt = expiresAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(expiresAt)
              : null;
          _requestingBeacon = false;
        });
        return;
      case MeshMessageEvent():
        final message = event.message;
        if (message != null) _handleLocationMessage(message);
        return;
      case MeshRadarExpiredEvent():
        if (_isTarget(event.peerId) && mounted) {
          setState(() => _permissionExpired = true);
        }
        return;
      case MeshRadarDiagnosticEvent():
        if (_isTarget(event.peerId) &&
            mounted &&
            _reading == null &&
            !_noSignalHint) {
          setState(() => _noSignalHint = true);
        }
        return;
      case MeshRssiEvent():
        if (!_isTarget(event.peerId)) return;
        final rssi = event.rssi;
        if (rssi == null) return;
        _handleRssi(event, rssi);
        return;
      default:
        return;
    }
  }

  bool _isTarget(String? peerId) {
    return peerId?.toLowerCase() == widget.peerId.toLowerCase();
  }

  void _handleRssi(MeshRssiEvent event, int rssi) {
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
      _noSignalHint = false;
      _tentativeSignal = event.tentative;
    });
    _pulse.forward(from: 0);
  }

  void _startDirectionSweep() {
    _startCompassTracking();
    if (_compassUnavailable) {
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
      await _acousticSession.stop();
      return;
    }
    await _acousticSession.startInitiator();
  }

  Future<void> _handleAcousticControl(RangingControlMessage control) async {
    await _acousticSession.handle(control);
  }

  void _onAcousticStateChanged(AcousticSonarSessionState state) {
    if (!mounted) return;
    final active =
        state != AcousticSonarSessionState.idle &&
        state != AcousticSonarSessionState.completed &&
        state != AcousticSonarSessionState.failed;
    setState(() => _acousticActive = active);
  }

  void _onAcousticMeasurement(AcousticDistanceMeasurement measurement) {
    if (!mounted) return;
    setState(() {
      _precisionDistanceMeters = measurement.distanceMeters;
      _precisionDistanceErrorMeters = measurement.errorMeters;
      _precisionDistanceConfidence = measurement.confidence;
      _precisionSource = RadarPrecisionSource.acoustic;
      _acousticActive = false;
    });
  }

  void _onAcousticFailure(AcousticSonarFailure failure) {
    if (!mounted) return;
    final requiresSettings =
        failure == AcousticSonarFailure.microphonePermission;
    final message = switch (failure) {
      AcousticSonarFailure.microphonePermission =>
        context.l10n.radarSonarMicrophoneRequired,
      AcousticSonarFailure.remoteMicrophonePermission =>
        context.l10n.radarSonarRemoteMicrophoneRequired,
      AcousticSonarFailure.selfChirpMissing =>
        context.l10n.radarSonarSelfChirpMissing,
      AcousticSonarFailure.tooNoisy ||
      AcousticSonarFailure.timeout ||
      AcousticSonarFailure.invalidMeasurement =>
        context.l10n.radarSonarTooNoisy,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: requiresSettings
            ? SnackBarAction(
                label: context.l10n.actionOpenSettings,
                onPressed: Geolocator.openAppSettings,
              )
            : null,
      ),
    );
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
    if (_compassEvents != null) return;
    final compassStream = widget.compassEvents ?? FlutterCompass.events;
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
    if (!_noSignalHint &&
        _reading == null &&
        DateTime.now().difference(_searchStartedAt) >
            const Duration(seconds: 12)) {
      setState(() => _noSignalHint = true);
    }
    if (!_hasTargetCoordinates &&
        !_sweepActive &&
        _directionEstimate == null &&
        _compassEvents != null) {
      unawaited(_compassEvents?.cancel());
      _compassEvents = null;
      _headingDegrees = null;
    }
    _maybeVibrate();
  }

  bool get _hasTargetCoordinates =>
      _targetLatitude != null && _targetLongitude != null;

  bool get _highActivity =>
      _sweepActive ||
      _radioRangingActive ||
      _acousticActive ||
      (_reading != null && !_stale);

  bool get _resourceSaverActive => !_highActivity;

  void _scheduleTick() {
    _ticker?.cancel();
    _ticker = Timer(
      _highActivity
          ? const Duration(milliseconds: 200)
          : const Duration(seconds: 1),
      () {
        _tick();
        if (mounted) _scheduleTick();
      },
    );
  }

  /// Vibración tipo contador Geiger: más frecuente e intensa cuanto más cerca.
  void _maybeVibrate() {
    final reading = _reading;
    if (reading == null || _stale) return;
    final (interval, feedback) = switch (reading.proximity) {
      RadarProximity.veryClose => (
        const Duration(milliseconds: 500),
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
            locationSettings: LocationSettings(
              accuracy: _hasTargetCoordinates
                  ? LocationAccuracy.high
                  : LocationAccuracy.medium,
              distanceFilter: _hasTargetCoordinates ? 3 : 10,
            ),
          ).listen((position) {
            if (!mounted) return;
            setState(() {
              _localPosition = position;
              _updateGpsDistance();
            });
          });
      final current = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: _hasTargetCoordinates
              ? LocationAccuracy.high
              : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
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
    final hadTarget = _hasTargetCoordinates;
    setState(() {
      _targetLatitude = latitude;
      _targetLongitude = longitude;
      _targetAccuracyMeters = accuracyMeters;
      _targetPositionAt = timestamp;
      _updateGpsDistance();
    });
    if (!hadTarget) {
      _startCompassTracking();
      unawaited(_positions?.cancel());
      _positions = null;
      unawaited(_watchGps());
    }
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
    final localPosition = _localPosition;
    DiagnosticsLog.instance.info(
      'radar.resource.stats',
      data: {
        'gpsFixAgeMs': localPosition == null
            ? -1
            : DateTime.now().difference(localPosition.timestamp).inMilliseconds,
        'adaptiveSaver': _resourceSaverActive,
      },
    );
    unawaited(_platform.stopRadar());
    unawaited(_platform.stopRadioRanging());
    unawaited(_acousticSession.dispose());
    _events?.cancel();
    _positions?.cancel();
    _compassEvents?.cancel();
    _ticker?.cancel();
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
        actions: [
          if (_resourceSaverActive)
            Tooltip(
              message: context.l10n.adaptivePowerSaving,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.battery_saver_outlined),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
            final content = _buildRadarColumn(
              reading: reading,
              searching: searching,
              fusion: fusion,
              compact: constraints.maxHeight < 700,
              fixedRadarHeight: largeText
                  ? math.min(260, constraints.maxWidth)
                  : null,
            );
            if (largeText) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: content,
              );
            }
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
    double? fixedRadarHeight,
  }) {
    final radar = LayoutBuilder(
      builder: (context, constraints) {
        final radarSide = math.min(
          420.0,
          math.min(constraints.maxWidth, constraints.maxHeight),
        );
        return Center(
          child: Semantics(
            image: true,
            liveRegion: true,
            label: searching
                ? context.l10n.radarSearching
                : _stale
                ? context.l10n.radarSignalLost
                : _proximityLabel(context.l10n, reading!.proximity),
            child: ExcludeSemantics(
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
            ),
          ),
        );
      },
    );
    return Column(
      children: [
        _buildBannerSlot(fusion),
        const SizedBox(height: 6),
        if (fixedRadarHeight case final height?)
          SizedBox(height: height, child: radar)
        else
          Expanded(child: radar),
        const SizedBox(height: 6),
        _buildPanel(reading, searching, fusion, compact: compact),
        const SizedBox(height: 6),
        _buildActionRow(),
        const SizedBox(height: 4),
        Text(
          '${_consentLabel()}\n'
          '${context.l10n.radarConsentExpires(_formatExpiry())}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildBannerSlot(RadarFusionResult fusion) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
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
      height: 58 + ((textScale - 1).clamp(0, 1) * 44),
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
    final directionLabel = estimate == null
        ? context.l10n.radarSweepStart
        : context.l10n.radarSweepRestart;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final actions = <Widget>[
      _buildRangingAction(
        label: _sweepActive
            ? context.l10n.radarActionSweeping
            : context.l10n.radarActionDirection,
        tooltip: _sweepActive
            ? context.l10n.radarSweepProgress(
                (_sweepEstimator.progress * 100).round(),
              )
            : directionLabel,
        icon: _sweepActive ? Icons.sync : Icons.explore_outlined,
        onPressed: _compassUnavailable || _sweepActive
            ? null
            : _startDirectionSweep,
        outlined: true,
      ),
      if (_radioRangingAvailable)
        _buildRangingAction(
          label: context.l10n.radarActionRadio,
          tooltip: _radioRangingActive
              ? context.l10n.radarRadioStop
              : context.l10n.radarRadioStart,
          icon: _radioRangingActive ? Icons.radar : Icons.social_distance,
          onPressed: _toggleRadioRanging,
        ),
      _buildRangingAction(
        label: context.l10n.radarActionSonar,
        tooltip: _acousticActive
            ? context.l10n.radarSonarStop
            : context.l10n.radarSonarStart,
        icon: _acousticActive ? Icons.hearing_disabled : Icons.graphic_eq,
        onPressed: _toggleAcousticSonar,
      ),
      if (_canRequestBeacon ||
          _beaconStatus == 'requested' ||
          _beaconStatus == 'active')
        _buildRangingAction(
          label: _beaconStatus == 'requested'
              ? context.l10n.radarActionWaiting
              : context.l10n.radarActionBeacon,
          tooltip: _beaconStatus == 'active'
              ? context.l10n.beaconStopRemote
              : context.l10n.beaconRequestRemote,
          icon: _beaconStatus == 'active'
              ? Icons.flashlight_off_outlined
              : Icons.flashlight_on_outlined,
          onPressed: _requestingBeacon || _beaconStatus == 'requested'
              ? null
              : _toggleRemoteBeacon,
          emphasized: true,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        const runSpacing = 4.0;
        final columns = largeText
            ? math.min(2, actions.length)
            : actions.length;
        final actionWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final action in actions)
              SizedBox(
                width: actionWidth,
                height: largeText ? 68 : 64,
                child: action,
              ),
          ],
        );
      },
    );
  }

  Widget _buildRangingAction({
    required String label,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool emphasized = false,
    bool outlined = false,
  }) {
    final disabledStyle = IconButton.styleFrom(
      disabledForegroundColor: const Color(0xFF94A3B8),
      disabledBackgroundColor: Colors.white10,
    );
    final button = outlined
        ? IconButton.outlined(
            onPressed: onPressed,
            icon: Icon(icon),
            constraints: const BoxConstraints.tightFor(width: 42, height: 40),
            padding: EdgeInsets.zero,
            style: disabledStyle,
          )
        : emphasized
        ? IconButton.filled(
            onPressed: onPressed,
            icon: Icon(icon),
            constraints: const BoxConstraints.tightFor(width: 42, height: 40),
            padding: EdgeInsets.zero,
            style: disabledStyle,
          )
        : IconButton.filledTonal(
            onPressed: onPressed,
            icon: Icon(icon),
            constraints: const BoxConstraints.tightFor(width: 42, height: 40),
            padding: EdgeInsets.zero,
            style: disabledStyle,
          );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              button,
              Text(
                label,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onPressed == null
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFFCBD5E1),
                  fontSize: 10,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
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
    const dim = Color(0xFFCBD5E1);
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
              _gpsDistanceLabel(
                _gpsDistanceMeters!,
                accuracyMeters: fusion.combinedGpsAccuracyMeters,
              ),
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
          if (_noSignalHint) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.radarNoSignalHint,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
            ),
          ],
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
              if (_gpsDistanceMeters != null && fusion.gpsDistanceInformative)
                _statusMetric(
                  Icons.gps_fixed,
                  _gpsDistanceLabel(
                    _gpsDistanceMeters!,
                    accuracyMeters: fusion.combinedGpsAccuracyMeters,
                  ),
                  const Color(0xFF60A5FA),
                ),
            ],
          ),
          if (_directionSummary(fusion) case final summary?) ...[
            const SizedBox(height: 5),
            Text(
              summary,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.5),
              textAlign: TextAlign.center,
              style: const TextStyle(color: dim, fontSize: 11),
            ),
          ],
        ],
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 72,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _gpsDistanceLabel(double meters, {double? accuracyMeters}) {
    if (accuracyMeters != null) {
      return context.l10n.radarGpsDistanceMargin(
        _formatGpsDistance(meters),
        _formatGpsDistance(accuracyMeters),
      );
    }
    return '${_formatGpsDistance(meters)} GPS';
  }

  String _formatGpsDistance(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)} km'
      : '${meters.round()} m';

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
    return context.l10n.radarNotDirection;
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
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    if (largeText) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.radarSweepHoldTitle,
              style: const TextStyle(color: green, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.radarSweepInstruction,
              style: const TextStyle(color: dim, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  style: const TextStyle(color: dim, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
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
      final targetRadius =
          (1 - currentStrength) * radius * 0.85 + radius * 0.08;
      final reliableDirection =
          estimatedDirectionRadians ?? gpsDirectionRadians;
      if (reliableDirection == null) {
        // BLE sin barrido solo mide cercanía. Un anillo concéntrico evita
        // sugerir que el objetivo está delante, detrás o a un costado.
        canvas.drawCircle(
          center,
          targetRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = _green.withValues(alpha: 0.8),
        );
        canvas.drawCircle(
          center,
          targetRadius + pulseProgress * 12,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 + (1 - pulseProgress) * 3
            ..color = _green.withValues(alpha: (1 - pulseProgress) * 0.35),
        );
      } else {
        final angle = reliableDirection - math.pi / 2;
        final unit = Offset(math.cos(angle), math.sin(angle));
        final blip = center + unit * targetRadius;
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
