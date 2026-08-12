import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/l10n.dart';
import '../services/mesh_platform_service.dart';
import '../services/radar_signal.dart';

/// Radar de rescate estilo AirTag: mide la intensidad de la señal BLE del
/// dispositivo objetivo y guía a la persona con proximidad, tendencia
/// («te estás acercando» / «la señal se debilita») y vibración tipo Geiger.
class RadarScreen extends StatefulWidget {
  const RadarScreen({
    required this.peerId,
    required this.nickname,
    this.latitude,
    this.longitude,
    super.key,
  });

  final String peerId;
  final String nickname;

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

  StreamSubscription<Map<Object?, Object?>>? _events;
  StreamSubscription<Position>? _positions;
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
  double? _gpsDistanceMeters;
  DateTime _lastHaptic = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_platform.startRadar(widget.peerId));
    _events = _platform.events.listen(_onEvent);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    _watchGps();
  }

  void _onEvent(Map<Object?, Object?> event) {
    if (event['type'] != 'rssi') return;
    if ((event['peerId'] as String?)?.toLowerCase() !=
        widget.peerId.toLowerCase()) {
      return;
    }
    final rssi = event['rssi'] as int?;
    if (rssi == null) return;
    final reading = _processor.addSample(rssi, DateTime.now());
    if (!mounted) return;
    setState(() {
      _reading = reading;
      _stale = false;
    });
    _pulse.forward(from: 0);
  }

  void _tick() {
    if (!mounted) return;
    final stale = _processor.isStale(DateTime.now());
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

  /// Si el SOS traía coordenadas, muestra la distancia en línea recta desde
  /// la posición actual del rescatista (complementa al radar BLE de corto
  /// alcance para la aproximación inicial).
  Future<void> _watchGps() async {
    final lat = widget.latitude;
    final lon = widget.longitude;
    if (lat == null || lon == null) return;
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
              _gpsDistanceMeters = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                lat,
                lon,
              );
            });
          });
    } catch (_) {
      // Sin GPS disponible el radar BLE sigue funcionando.
    }
  }

  @override
  void dispose() {
    unawaited(_platform.stopRadar());
    _events?.cancel();
    _positions?.cancel();
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
    return Scaffold(
      backgroundColor: const Color(0xFF07120D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.l10n.radarTitle(widget.nickname)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_sweep, _pulse]),
                    builder: (context, _) => CustomPaint(
                      painter: _RadarPainter(
                        sweepProgress: _sweep.value,
                        pulseProgress: _pulse.value,
                        strength: _stale ? null : reading?.strength,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: _buildPanel(theme, reading, searching),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(ThemeData theme, RadarReading? reading, bool searching) {
    const green = Color(0xFF4ADE80);
    const red = Color(0xFFF87171);
    const dim = Color(0xFF94A3B8);
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
        if (_gpsDistanceMeters != null) _gpsRow(dim),
      ],
    );
  }

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

/// Pinta el sonar: anillos concéntricos, barrido giratorio y un punto que se
/// acerca al centro a medida que la señal se hace más fuerte.
class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweepProgress,
    required this.pulseProgress,
    required this.strength,
  });

  final double sweepProgress;
  final double pulseProgress;

  /// null cuando no hay señal utilizable (sin blip).
  final double? strength;

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
        colors: [
          _green.withValues(alpha: 0.0),
          _green.withValues(alpha: 0.35),
        ],
        stops: const [0.7, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // Punto central: el rescatista.
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);

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
      oldDelegate.strength != strength;
}
