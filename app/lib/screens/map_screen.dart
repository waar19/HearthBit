import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/mesh_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../services/offline_tile_cache.dart';
import '../services/peer_location_tracker.dart';
import '../services/rescue_export_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({required this.controller, super.key});

  final MeshController controller;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _planner = TileDownloadPlanner();

  final MapController _mapController = MapController();
  final MapTileSource _tileSource = MapTileSource.fromEnvironment();
  OfflineTileCache? _tileCache;
  OfflineTileProvider? _tileProvider;
  Position? _localPosition;
  String? _initializationError;
  Object? _lastTileError;
  bool _downloading = false;
  int _downloaded = 0;
  int _downloadTotal = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final cache = await OfflineTileCache.create(source: _tileSource);
      if (!mounted) {
        unawaited(cache.close());
        return;
      }
      setState(() {
        _tileCache = cache;
        _tileProvider = OfflineTileProvider(cache);
      });
      await _refreshLocalPosition(moveMap: true);
    } catch (error) {
      if (mounted) setState(() => _initializationError = '$error');
    }
  }

  Future<void> _refreshLocalPosition({bool moveMap = false}) async {
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
      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
      if (!mounted) return;
      setState(() => _localPosition = position);
      if (moveMap) {
        _mapController.move(LatLng(position.latitude, position.longitude), 14);
      }
    } catch (_) {
      // The map remains useful with peer markers and cached tiles.
    }
  }

  LatLng? get _initialCenter {
    final local = _localPosition;
    if (local != null) return LatLng(local.latitude, local.longitude);
    final peer = widget.controller.peerLocations.latestLocations.firstOrNull;
    return peer == null ? null : LatLng(peer.latitude, peer.longitude);
  }

  List<RescueIncident> get _incidents => RescueIncidentList.fromMessages(
    widget.controller.messages,
    originLatitude: _localPosition?.latitude,
    originLongitude: _localPosition?.longitude,
  );

  Future<void> _downloadVisibleArea() async {
    final cache = _tileCache;
    if (cache == null || _downloading) return;
    try {
      final camera = _mapController.camera;
      final bounds = camera.visibleBounds;
      final currentZoom = camera.zoom.floor().clamp(
        _planner.minimumZoom,
        _planner.maximumZoom,
      );
      final tiles = _planner.plan(
        bounds: GeographicBounds(
          south: bounds.south,
          west: bounds.west,
          north: bounds.north,
          east: bounds.east,
        ),
        fromZoom: currentZoom,
        toZoom: (currentZoom + 1).clamp(
          _planner.minimumZoom,
          _planner.maximumZoom,
        ),
      );
      setState(() {
        _downloading = true;
        _downloaded = 0;
        _downloadTotal = tiles.length;
      });
      await cache.download(
        tiles,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _downloaded = completed;
            _downloadTotal = total;
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.mapDownloadComplete(tiles.length))),
      );
    } on TileDownloadLimitException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.mapDownloadTooLarge(error.maximum)),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.mapDownloadError('$error'))),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _shareCsv() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.locationExportConfirmTitle),
        content: Text(context.l10n.locationExportConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.locationExportConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final renderBox = context.findRenderObject() as RenderBox?;
      await RescueExportService.share(
        incidents: _incidents,
        anchor: renderBox,
        subject: context.l10n.rescueExportSubject,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.rescueExportError('$error'))),
      );
    }
  }

  Future<void> _openExternalUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _handleTileError(Object error) {
    if (!mounted || _lastTileError?.runtimeType == error.runtimeType) return;
    setState(() => _lastTileError = error);
  }

  @override
  void dispose() {
    _mapController.dispose();
    final cache = _tileCache;
    if (cache != null) unawaited(cache.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.mapTitle),
          actions: [
            IconButton(
              tooltip: context.l10n.mapMyLocation,
              onPressed: () => _refreshLocalPosition(moveMap: true),
              icon: const Icon(Icons.my_location),
            ),
            if (_tileSource.allowsBulkDownload)
              IconButton(
                tooltip: context.l10n.mapDownloadVisible,
                onPressed: _downloading ? null : _downloadVisibleArea,
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
            IconButton(
              tooltip: context.l10n.rescueExportCsv,
              onPressed: _incidents.isEmpty ? null : _shareCsv,
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(flex: 3, child: _buildMap(context)),
            if (_downloading)
              LinearProgressIndicator(
                value: _downloadTotal == 0
                    ? null
                    : _downloaded / _downloadTotal,
              ),
            if (_downloading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  context.l10n.mapDownloading(_downloaded, _downloadTotal),
                ),
              ),
            if (_tileSource.isPublicOpenStreetMap)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.offline_pin_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.mapPassiveCacheInfo,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _openExternalUrl(Uri.parse(osmTilePolicyUrl)),
                        child: Text(context.l10n.mapTilePolicyAction),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(flex: 2, child: _buildIncidentList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final provider = _tileProvider;
    if (_initializationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.mapCacheError(_initializationError!),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (provider == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final initialCenter = _initialCenter;
    if (initialCenter == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.mapNoLocationTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(context.l10n.mapNoLocationBody, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final markers = <Marker>[
      if (_localPosition case final position?)
        Marker(
          point: LatLng(position.latitude, position.longitude),
          width: 48,
          height: 48,
          child: Tooltip(
            message: context.l10n.mapYouAreHere,
            child: const Icon(Icons.my_location, color: Colors.blue, size: 34),
          ),
        ),
      ...widget.controller.peerLocations.latestLocations.map(
        (location) => Marker(
          point: LatLng(location.latitude, location.longitude),
          width: 52,
          height: 52,
          child: Tooltip(
            message: _peerName(location.peerId),
            child: Icon(
              location.source == PeerLocationSource.live
                  ? Icons.near_me
                  : Icons.location_on,
              color: location.source == PeerLocationSource.live
                  ? Colors.purple
                  : Colors.red,
              size: 40,
            ),
          ),
        ),
      ),
    ];
    final trails = widget.controller.peerLocations.latestLocations
        .map(
          (location) =>
              widget.controller.peerLocations.trailFor(location.peerId),
        )
        .where((trail) => trail.length > 1)
        .map(
          (trail) => Polyline(
            points: trail
                .map((point) => LatLng(point.latitude, point.longitude))
                .toList(growable: false),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            strokeWidth: 3,
          ),
        )
        .toList(growable: false);
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 14,
            minZoom: 2,
            maxZoom: _planner.maximumZoom.toDouble(),
          ),
          children: [
            TileLayer(
              urlTemplate: _tileSource.urlTemplate,
              userAgentPackageName: 'com.hearthbit.app',
              tileProvider: provider,
              maxNativeZoom: _planner.maximumZoom,
              errorTileCallback: (_, error, _) => _handleTileError(error),
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
            ),
            if (trails.isNotEmpty) PolylineLayer(polylines: trails),
            MarkerLayer(markers: markers),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  _tileSource.attribution,
                  onTap: () => _openExternalUrl(_tileSource.attributionUri),
                ),
              ],
            ),
          ],
        ),
        if (_lastTileError != null)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    const Icon(Icons.map_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lastTileError is TileAccessBlockedException
                            ? context.l10n.mapTileBlockedHint
                            : context.l10n.mapOfflineHint,
                        textAlign: TextAlign.left,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => setState(() => _lastTileError = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIncidentList(BuildContext context) {
    final incidents = _incidents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            context.l10n.rescueListTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: incidents.isEmpty
              ? Center(child: Text(context.l10n.rescueListEmpty))
              : ListView.builder(
                  itemCount: incidents.length,
                  itemBuilder: (context, index) {
                    final incident = incidents[index];
                    final color = _incidentColor(incident);
                    return ListTile(
                      leading: Icon(
                        incident.kind == RescueIncidentKind.sos
                            ? Icons.crisis_alert
                            : Icons.health_and_safety,
                        color: color,
                      ),
                      title: Text(incident.sender),
                      subtitle: Text(
                        '${incident.message}\n'
                        '${_incidentDistance(context, incident)} · '
                        '${_formatTime(context, incident.timestamp)}',
                      ),
                      isThreeLine: true,
                      trailing:
                          incident.latitude == null ||
                              incident.longitude == null
                          ? null
                          : IconButton(
                              tooltip: context.l10n.mapShowOnMap,
                              onPressed: () => _mapController.move(
                                LatLng(incident.latitude!, incident.longitude!),
                                15,
                              ),
                              icon: const Icon(Icons.center_focus_strong),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _peerName(String peerId) =>
      widget.controller.knownPeerById(peerId)?.nickname ??
      widget.controller.peerById(peerId)?.nickname ??
      (peerId.length > 8 ? peerId.substring(0, 8) : peerId);

  Color _incidentColor(RescueIncident incident) {
    return switch (incident.kind) {
      RescueIncidentKind.sos => Colors.red,
      RescueIncidentKind.checkIn => switch (incident.checkInStatus) {
        CheckInStatus.ok => Colors.green,
        CheckInStatus.needsHelp => Colors.orange,
        CheckInStatus.injured => Colors.red,
        null => Colors.grey,
      },
    };
  }

  String _incidentDistance(BuildContext context, RescueIncident incident) {
    final distance = incident.distanceMeters;
    if (distance == null) return context.l10n.rescueDistanceUnknown;
    if (distance < 1000) {
      return context.l10n.rescueDistanceMeters(distance.round());
    }
    return context.l10n.rescueDistanceKilometers(
      (distance / 1000).toStringAsFixed(1),
    );
  }

  String _formatTime(BuildContext context, DateTime timestamp) {
    final local = timestamp.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(local)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}
