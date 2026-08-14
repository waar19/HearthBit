import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/beacon_control_protocol.dart';
import '../services/mesh_platform_service.dart';
import '../services/radar_fusion.dart';
import '../services/radar_signal.dart';

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
    super.key,
  });

  final String peerId;
  final String nickname;
  final DateTime consentExpiresAt;
  final String consentSource;

  /// Última posición GPS conocida del objetivo (de su alerta SOS), si existe.
  final double? latitude;
  final double? longitude;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with TickerProviderStateMixin {
  final _platform = MeshPlatformService();
  final _processor = RadarSignalProcessor();
  final _sweepEstimator = SweepEstimator();

  StreamSubscription<Map<Object?, Object?>>? _events;
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
  bool _sweepActive = false;
  bool _compassUnavailable = false;
  String? _startError;
  double? _gpsDistanceMeters;
  double? _headingDegrees;
  double? _compassAccuracyDegrees;
  Position? _localPosition;
  double? _targetLatitude;
  double? _targetLongitude;
  double? _targetAccuracyMeters;
  DateTime? _targetPositionAt;
  SweepEstimate? _directionEstimate;
  DateTime _lastHaptic = DateTime.fromMillisecondsSinceEpoch(0);
  String? _beaconRequestId;
  String? _beaconStatus;
  String? _beaconError;
  DateTime? _beaconRequestExpiresAt;
  bool _requestingBeacon = false;

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
  }

  Future<void> _startRadar() async {
    try {
      await _platform.startRadar(widget.peerId);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _startError = error.message ?? error.code);
    }
  }

  void _onEvent(Map<Object?, Object?> event) {
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
        _beaconError = null;
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
      if (mounted) setState(() => _beaconError = error.message ?? error.code);
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
        final heading = event.heading;
        setState(() {
          _headingDegrees = heading;
          _compassAccuracyDegrees = event.accuracy;
          _compassUnavailable = heading == null;
        });
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
    } catch (_) {
      // Sin GPS disponible el radar BLE sigue funcionando.
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
    final theme = Theme.of(context);
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
            final radarSide = math.min(
              420.0,
              math.max(0.0, constraints.maxWidth - 32),
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: radarSide,
                    height: radarSide,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_sweep, _pulse]),
                      builder: (context, _) => CustomPaint(
                        painter: _RadarPainter(
                          sweepProgress: _sweep.value,
                          pulseProgress: _pulse.value,
                          strength: _stale ? null : reading?.strength,
                          directionSweepSectors: _sweepEstimator.sectorCoverage,
                          estimatedDirectionRadians: _bleDirectionRadians(
                            fusion,
                          ),
                          gpsDirectionRadians: _gpsDirectionRadians(fusion),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPanel(theme, reading, searching, fusion),
                  if (_canRequestBeacon || _beaconStatus == 'active') ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed:
                          _requestingBeacon || _beaconStatus == 'requested'
                          ? null
                          : _toggleRemoteBeacon,
                      icon: Icon(
                        _beaconStatus == 'active'
                            ? Icons.flashlight_off_outlined
                            : Icons.flashlight_on_outlined,
                      ),
                      label: Text(
                        _beaconStatus == 'active'
                            ? context.l10n.beaconStopRemote
                            : context.l10n.beaconRequestRemote,
                      ),
                    ),
                    if (_beaconError != null)
                      Text(
                        _beaconError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.amber),
                      ),
                  ],
                  const SizedBox(height: 10),
                  _buildDirectionSweep(fusion),
                  const SizedBox(height: 10),
                  Text(
                    '${_consentLabel()}\n${context.l10n.radarConsentExpires(_formatExpiry())}\n${context.l10n.radarNotDirection}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDirectionSweep(RadarFusionResult fusion) {
    const green = Color(0xFF4ADE80);
    const dim = Color(0xFF94A3B8);
    final estimate = _directionEstimate;
    final showHoldingGuide =
        !_compassUnavailable && (_sweepActive || estimate == null);
    return _panelCard(
      children: [
        if (showHoldingGuide) ...[
          _SweepHoldingGuide(animation: _sweep, active: _sweepActive),
          const SizedBox(height: 10),
        ],
        if (_compassNeedsCalibration) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: .35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.screen_rotation_alt_outlined,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.radarCompassCalibration,
                    textAlign: TextAlign.left,
                    style: const TextStyle(color: Colors.amber, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_compassUnavailable) ...[
          const Icon(Icons.explore_off_outlined, color: dim),
          const SizedBox(height: 6),
          Text(
            context.l10n.radarCompassUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(color: dim),
          ),
        ] else if (_sweepActive) ...[
          LinearProgressIndicator(
            value: _sweepEstimator.progress,
            color: green,
            backgroundColor: Colors.white12,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.radarSweepProgress(
              (_sweepEstimator.progress * 100).round(),
            ),
            style: const TextStyle(color: dim, fontSize: 12),
          ),
        ] else if (estimate != null) ...[
          if (fusion.bleSuppressedVeryClose) ...[
            const Icon(Icons.vibration, color: Colors.amber),
            const SizedBox(height: 6),
            Text(
              context.l10n.radarDirectionVeryClose,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ] else if (fusion.sourcesDisagree) ...[
            const Icon(Icons.compare_arrows, color: Colors.amber),
            const SizedBox(height: 6),
            Text(
              context.l10n.radarSourcesDisagree,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ] else if (fusion.gpsReliable) ...[
            const Icon(Icons.navigation_outlined, color: Color(0xFF60A5FA)),
            const SizedBox(height: 6),
            Text(
              context.l10n.radarDirectionGps,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ] else if (fusion.adjustedBleConfidence >=
              SweepEstimate.minimumDirectionalConfidence) ...[
            Text(
              context.l10n.radarSweepResult(estimate.headingDegrees.round()),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else ...[
            const Icon(Icons.explore_off_outlined, color: dim),
            const SizedBox(height: 6),
            Text(
              context.l10n.radarSweepInconclusive,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
          if (!fusion.gpsReliable) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.radarSweepConfidence(
                (fusion.adjustedBleConfidence * 100).round(),
              ),
              style: TextStyle(
                color:
                    fusion.adjustedBleConfidence >=
                        SweepEstimate.minimumDirectionalConfidence
                    ? green
                    : dim,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            context.l10n.radarSweepEstimateWarning,
            textAlign: TextAlign.center,
            style: const TextStyle(color: dim, fontSize: 12),
          ),
        ],
        if (!_sweepActive) ...[
          if (estimate != null || _compassUnavailable)
            const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _startDirectionSweep,
            icon: const Icon(Icons.explore_outlined),
            label: Text(
              estimate == null
                  ? context.l10n.radarSweepStart
                  : context.l10n.radarSweepRestart,
            ),
          ),
        ],
      ],
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
    );
  }

  bool get _compassNeedsCalibration {
    final accuracy = _compassAccuracyDegrees;
    return accuracy != null && accuracy > 20;
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
    ThemeData theme,
    RadarReading? reading,
    bool searching,
    RadarFusionResult fusion,
  ) {
    const green = Color(0xFF4ADE80);
    const red = Color(0xFFF87171);
    const dim = Color(0xFF94A3B8);
    if (_permissionExpired || _startError != null) {
      return _panelCard(
        children: [
          const Icon(Icons.lock_clock_outlined, color: red, size: 40),
          const SizedBox(height: 8),
          Text(
            context.l10n.radarPermissionExpired,
            textAlign: TextAlign.center,
            style: const TextStyle(color: red, fontSize: 18),
          ),
        ],
      );
    }
    if (_stale) {
      return _panelCard(
        children: [
          const Icon(Icons.wifi_off, color: red, size: 40),
          const SizedBox(height: 8),
          Text(
            context.l10n.radarSignalLost,
            style: const TextStyle(
              color: red,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.radarSignalLostHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: dim),
          ),
          if (_gpsDistanceMeters != null) _gpsRow(dim),
          if (fusion.source != RadarDirectionSource.none)
            _directionSourceRow(fusion),
        ],
      );
    }
    if (searching) {
      return _panelCard(
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3, color: green),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.radarSearching,
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.radarSearchingHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: dim),
          ),
          if (_gpsDistanceMeters != null) _gpsRow(dim),
          if (fusion.source != RadarDirectionSource.none)
            _directionSourceRow(fusion),
        ],
      );
    }
    final (trendIcon, trendColor) = switch (reading!.trend) {
      RadarTrend.approaching => (Icons.trending_up, green),
      RadarTrend.receding => (Icons.trending_down, red),
      RadarTrend.steady => (Icons.trending_flat, dim),
      RadarTrend.unknown => (Icons.more_horiz, dim),
    };
    return _panelCard(
      children: [
        Text(
          _proximityLabel(context.l10n, reading.proximity),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _distanceLabel(context.l10n, reading.approxDistanceMeters),
          style: const TextStyle(color: dim, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(trendIcon, color: trendColor),
            const SizedBox(width: 8),
            Text(
              _trendLabel(context.l10n, reading.trend),
              style: TextStyle(color: trendColor, fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: reading.strength,
            minHeight: 8,
            backgroundColor: Colors.white12,
            color: Color.lerp(red, green, reading.strength),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.radarDbm(reading.smoothedRssi.round()),
          style: const TextStyle(color: dim, fontSize: 12),
        ),
        if (fusion.source != RadarDirectionSource.none ||
            fusion.bleSuppressedVeryClose)
          _directionSourceRow(fusion),
        if (_tentativeSignal) ...[
          const SizedBox(height: 4),
          Text(
            context.l10n.radarTentativeSignal,
            textAlign: TextAlign.center,
            style: const TextStyle(color: dim, fontSize: 12),
          ),
        ],
        if (_gpsDistanceMeters != null) _gpsRow(dim),
      ],
    );
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

  Widget _gpsRow(Color color) {
    final meters = _gpsDistanceMeters!;
    final label = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '${meters.round()} m';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gps_fixed, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            context.l10n.radarGpsDistance(label),
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _directionSourceRow(RadarFusionResult fusion) {
    const blue = Color(0xFF60A5FA);
    const green = Color(0xFF4ADE80);
    const amber = Color(0xFFFBBF24);
    final (icon, color, label) = switch (fusion.source) {
      RadarDirectionSource.gps => (
        Icons.navigation_outlined,
        blue,
        context.l10n.radarDirectionGps,
      ),
      RadarDirectionSource.ble => (
        Icons.bluetooth_searching,
        green,
        context.l10n.radarDirectionBle,
      ),
      RadarDirectionSource.none => (
        Icons.vibration,
        amber,
        context.l10n.radarDirectionVeryClose,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
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
          width: 92,
          height: 92,
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
