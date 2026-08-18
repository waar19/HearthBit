import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/mesh_controller.dart';
import '../controllers/rescue_case_controller.dart';
import '../controllers/swept_zone_controller.dart';
import '../l10n/l10n.dart';
import '../models/rescue_case_models.dart';
import '../models/swept_zone_models.dart';
import '../services/offline_tile_cache.dart';
import '../services/peer_location_tracker.dart';
import '../services/rescue_case_clusterer.dart';
import '../services/rescue_export_service.dart';

enum MapCaseFilter { active, unassigned, assigned, closed }

class MapScreen extends StatefulWidget {
  const MapScreen({
    required this.controller,
    required this.rescueCases,
    required this.sweptZones,
    super.key,
  });

  final MeshController controller;
  final RescueCaseController rescueCases;
  final SweptZoneController sweptZones;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _planner = TileDownloadPlanner();

  final MapController _mapController = MapController();
  final MapTileSource _tileSource = MapTileSource.fromEnvironment();
  OfflineTileCache? _tileCache;
  OfflineTileProvider? _tileProvider;
  StreamSubscription<Position>? _positionSubscription;
  Position? _localPosition;
  String? _initializationError;
  Object? _lastTileError;
  MapCaseFilter _filter = MapCaseFilter.active;
  double _zoom = 14;
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

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _refreshLocalPosition({bool moveMap = false}) async {
    try {
      if (!await _ensureLocationPermission()) return;
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
      // Cached tiles, rescue cases, and team zones remain usable without GPS.
    }
  }

  LatLng? get _initialCenter {
    final local = _localPosition;
    if (local != null) return LatLng(local.latitude, local.longitude);
    for (final rescueCase in widget.rescueCases.cases) {
      if (rescueCase.latitude != null && rescueCase.longitude != null) {
        return LatLng(rescueCase.latitude!, rescueCase.longitude!);
      }
    }
    for (final zone in widget.sweptZones.zones) {
      if (zone.points.isNotEmpty) {
        return LatLng(zone.points.first.latitude, zone.points.first.longitude);
      }
    }
    final peer = widget.controller.peerLocations.latestLocations.firstOrNull;
    return peer == null ? null : LatLng(peer.latitude, peer.longitude);
  }

  List<RescueCase> get _filteredCases => widget.rescueCases.cases
      .where(
        (rescueCase) => switch (_filter) {
          MapCaseFilter.active => rescueCase.state != RescueCaseState.closed,
          MapCaseFilter.unassigned =>
            rescueCase.state == RescueCaseState.newCase &&
                rescueCase.assigneePeerId == null,
          MapCaseFilter.assigned =>
            rescueCase.state == RescueCaseState.assigned ||
                rescueCase.state == RescueCaseState.enRoute ||
                rescueCase.state == RescueCaseState.attended,
          MapCaseFilter.closed => rescueCase.state == RescueCaseState.closed,
        },
      )
      .toList(growable: false);

  Future<void> _downloadVisibleArea() async {
    final cache = _tileCache;
    if (cache == null || _downloading) return;
    try {
      final bounds = _mapController.camera.visibleBounds;
      final currentZoom = _mapController.camera.zoom.floor().clamp(
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.mapDownloadComplete(tiles.length)),
          ),
        );
      }
    } on TileDownloadLimitException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.mapDownloadTooLarge(error.maximum)),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.mapDownloadError('$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _ensureLocationPermission()) {
        if (!mounted) return;
        throw StateError(context.l10n.mapZoneLocationRequired);
      }
      widget.sweptZones.startRecording();
      await _positionSubscription?.cancel();
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            ),
          ).listen(
            (position) {
              widget.sweptZones.addRecordedPoint(
                latitude: position.latitude,
                longitude: position.longitude,
                accuracyMeters: position.accuracy,
                recordedAt: position.timestamp,
              );
              if (widget.sweptZones.draftPoints.length >=
                  SweptZoneCodec.maximumPoints) {
                unawaited(_positionSubscription?.cancel());
                _positionSubscription = null;
              }
            },
            onError: (Object error) {
              widget.sweptZones.cancelRecording();
              _positionSubscription = null;
              if (mounted) _showZoneError(error);
            },
          );
    } catch (error) {
      if (mounted) _showZoneError(error);
    }
  }

  Future<void> _finishRecording() async {
    _positionSubscription?.pause();
    try {
      await widget.sweptZones.finishAndPublish();
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.mapZonePublished)));
      }
    } catch (error) {
      _positionSubscription?.resume();
      if (mounted) _showZoneError(error);
    }
  }

  Future<void> _cancelRecording() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    widget.sweptZones.cancelRecording();
  }

  void _showZoneError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.mapZoneError('$error'))),
    );
  }

  Future<void> _openExternalUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _exportOperationalData(BuildContext anchorContext) async {
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    final format = await showDialog<RescueExportFormat>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.mapExportFormatTitle),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, RescueExportFormat.csv),
            child: ListTile(
              leading: const Icon(Icons.table_view_outlined),
              title: Text(context.l10n.mapExportCsv),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, RescueExportFormat.geoJson),
            child: ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(context.l10n.mapExportGeoJson),
            ),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.privacy_tip_outlined),
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
      await RescueExportService.shareOperational(
        format: format,
        cases: RescueExportPolicy.operationalCases(widget.rescueCases.cases),
        zones: widget.sweptZones.zones,
        anchor: anchor,
        subject: context.l10n.mapExportSubject,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.mapExportError('$error'))),
      );
    }
  }

  void _handleTileError(Object error) {
    if (!mounted || _lastTileError?.runtimeType == error.runtimeType) return;
    setState(() => _lastTileError = error);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    if (widget.sweptZones.isRecording) widget.sweptZones.cancelRecording();
    _mapController.dispose();
    final cache = _tileCache;
    if (cache != null) unawaited(cache.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.rescueCases,
        widget.sweptZones,
      ]),
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
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: context.l10n.mapExport,
                onPressed: () => _exportOperationalData(buttonContext),
                icon: const Icon(Icons.ios_share_outlined),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildFilters(context),
            Expanded(flex: 3, child: _buildMap(context)),
            if (_downloading)
              LinearProgressIndicator(
                value: _downloadTotal == 0
                    ? null
                    : _downloaded / _downloadTotal,
              ),
            if (_downloading)
              Text(context.l10n.mapDownloading(_downloaded, _downloadTotal)),
            _buildRecordingControls(context),
            if (_tileSource.isPublicOpenStreetMap) _buildTilePolicy(context),
            Expanded(flex: 2, child: _buildCaseList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SegmentedButton<MapCaseFilter>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: MapCaseFilter.active,
            label: Text(context.l10n.mapFilterActive),
          ),
          ButtonSegment(
            value: MapCaseFilter.unassigned,
            label: Text(context.l10n.mapFilterUnassigned),
          ),
          ButtonSegment(
            value: MapCaseFilter.assigned,
            label: Text(context.l10n.mapFilterAssigned),
          ),
          ButtonSegment(
            value: MapCaseFilter.closed,
            label: Text(context.l10n.mapFilterClosed),
          ),
        ],
        selected: {_filter},
        onSelectionChanged: (selection) {
          setState(() => _filter = selection.single);
        },
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final provider = _tileProvider;
    if (_initializationError != null) {
      return Center(
        child: Text(context.l10n.mapCacheError(_initializationError!)),
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
          child: Text(
            context.l10n.mapNoLocationBody,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final clusters = RescueCaseClusterer.cluster(_filteredCases, zoom: _zoom);
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: _zoom,
            minZoom: 2,
            maxZoom: _planner.maximumZoom.toDouble(),
            onMapEvent: (event) {
              final nextZoom = event.camera.zoom;
              if ((nextZoom - _zoom).abs() >= 0.01 && mounted) {
                setState(() => _zoom = nextZoom);
              }
            },
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
            PolylineLayer(polylines: _zonePolylines(context)),
            MarkerLayer(markers: _markers(context, clusters)),
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
        if (_lastTileError != null) _buildTileError(context),
      ],
    );
  }

  List<Marker> _markers(
    BuildContext context,
    List<RescueCaseCluster> clusters,
  ) => [
    if (_localPosition case final position?)
      Marker(
        point: LatLng(position.latitude, position.longitude),
        width: 44,
        height: 44,
        child: Tooltip(
          message: context.l10n.mapYouAreHere,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 32),
        ),
      ),
    ...widget.controller.peerLocations.latestLocations.map(
      (location) => Marker(
        point: LatLng(location.latitude, location.longitude),
        width: 44,
        height: 44,
        child: Tooltip(
          message: _peerName(location.peerId),
          child: Icon(
            location.source == PeerLocationSource.live
                ? Icons.near_me
                : Icons.location_on,
            color: location.source == PeerLocationSource.live
                ? Colors.purple
                : Colors.red,
            size: 34,
          ),
        ),
      ),
    ),
    ...clusters.map((cluster) => _clusterMarker(context, cluster)),
  ];

  Marker _clusterMarker(BuildContext context, RescueCaseCluster cluster) {
    final priorityColor = _priorityColor(cluster.maximumPriority);
    if (cluster.isCluster) {
      return Marker(
        point: LatLng(cluster.latitude, cluster.longitude),
        width: 58,
        height: 58,
        child: Tooltip(
          message: context.l10n.mapClusterTooltip(
            cluster.cases.length,
            _priorityLabel(context, cluster.maximumPriority),
          ),
          child: Semantics(
            button: true,
            label: context.l10n.mapClusterTooltip(
              cluster.cases.length,
              _priorityLabel(context, cluster.maximumPriority),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _mapController.move(
                LatLng(cluster.latitude, cluster.longitude),
                (_zoom + 2)
                    .clamp(2, _planner.maximumZoom.toDouble())
                    .toDouble(),
              ),
              child: CircleAvatar(
                backgroundColor: priorityColor,
                foregroundColor: Colors.white,
                child: Text(
                  '${cluster.cases.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final rescueCase = cluster.cases.single;
    return Marker(
      point: LatLng(cluster.latitude, cluster.longitude),
      width: 52,
      height: 52,
      child: Tooltip(
        message:
            '${rescueCase.victim} · ${_caseStateLabel(context, rescueCase.state)} · '
            '${_priorityLabel(context, cluster.maximumPriority)}',
        child: Container(
          decoration: BoxDecoration(
            color: _stateColor(rescueCase.state),
            shape: BoxShape.circle,
            border: Border.all(color: priorityColor, width: 4),
          ),
          child: Icon(
            _priorityIcon(cluster.maximumPriority),
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  List<Polyline> _zonePolylines(BuildContext context) {
    final polylines = <Polyline>[
      ...widget.controller.peerLocations.latestLocations
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
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
              strokeWidth: 2,
            ),
          ),
      ...widget.sweptZones.zones.map(
        (zone) => Polyline(
          points: zone.points
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList(growable: false),
          color: zone.actorPeerId == widget.controller.peerId.toLowerCase()
              ? Colors.teal
              : _actorColor(zone.actorPeerId),
          strokeWidth: 5,
        ),
      ),
    ];
    if (widget.sweptZones.draftPoints.length > 1) {
      polylines.add(
        Polyline(
          points: widget.sweptZones.draftPoints
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList(growable: false),
          color: Colors.orange,
          strokeWidth: 6,
        ),
      );
    }
    return polylines;
  }

  Widget _buildRecordingControls(BuildContext context) {
    final zones = widget.sweptZones;
    if (!zones.isRecording) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.route_outlined),
          title: Text(context.l10n.mapZoneConsent),
          trailing: FilledButton.icon(
            onPressed: zones.localMember == null ? null : _startRecording,
            icon: const Icon(Icons.fiber_manual_record),
            label: Text(context.l10n.mapZoneStart),
          ),
        ),
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.location_searching),
        title: Text(
          context.l10n.mapZoneRecording(
            zones.draftPoints.length,
            SweptZoneCodec.maximumPoints,
          ),
        ),
        subtitle: Text(context.l10n.mapZoneVisibleOnly),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: context.l10n.actionCancel,
              onPressed: zones.publishing ? null : _cancelRecording,
              icon: const Icon(Icons.close),
            ),
            IconButton.filled(
              tooltip: context.l10n.mapZoneFinish,
              onPressed:
                  zones.publishing ||
                      zones.draftPoints.length < SweptZoneCodec.minimumPoints
                  ? null
                  : _finishRecording,
              icon: zones.publishing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTilePolicy(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.offline_pin_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.mapPassiveCacheInfo,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => _openExternalUrl(Uri.parse(osmTilePolicyUrl)),
              child: Text(context.l10n.mapTilePolicyAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTileError(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.map_outlined),
          title: Text(
            _lastTileError is TileAccessBlockedException
                ? context.l10n.mapTileBlockedHint
                : context.l10n.mapOfflineHint,
          ),
          trailing: IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => setState(() => _lastTileError = null),
            icon: const Icon(Icons.close),
          ),
        ),
      ),
    );
  }

  Widget _buildCaseList(BuildContext context) {
    final cases = _filteredCases;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            context.l10n.mapOperationalCases(cases.length),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: widget.rescueCases.loading
              ? const Center(child: CircularProgressIndicator())
              : widget.rescueCases.lastError != null
              ? Center(
                  child: Text(
                    context.l10n.rescueOperationsError(
                      widget.rescueCases.lastError!,
                    ),
                  ),
                )
              : cases.isEmpty
              ? Center(child: Text(context.l10n.mapCasesEmpty))
              : ListView.builder(
                  itemCount: cases.length,
                  itemBuilder: (context, index) {
                    final rescueCase = cases[index];
                    final priority = RescueCaseClusterer.priorityForTriage(
                      rescueCase.triage,
                    );
                    final hasCoordinates =
                        rescueCase.latitude != null &&
                        rescueCase.longitude != null;
                    return ListTile(
                      leading: Icon(
                        _priorityIcon(priority),
                        color: _stateColor(rescueCase.state),
                      ),
                      title: Text(rescueCase.victim),
                      subtitle: Text(
                        '${_caseStateLabel(context, rescueCase.state)} · '
                        '${_priorityLabel(context, priority)}\n'
                        '${rescueCase.message}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: hasCoordinates
                            ? context.l10n.mapShowOnMap
                            : context.l10n.mapCaseNoCoordinates,
                        onPressed: hasCoordinates
                            ? () => _mapController.move(
                                LatLng(
                                  rescueCase.latitude!,
                                  rescueCase.longitude!,
                                ),
                                16,
                              )
                            : null,
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

  String _caseStateLabel(BuildContext context, RescueCaseState state) {
    return switch (state) {
      RescueCaseState.newCase => context.l10n.rescueCaseStateNew,
      RescueCaseState.assigned => context.l10n.rescueCaseStateAssigned,
      RescueCaseState.enRoute => context.l10n.rescueCaseStateEnRoute,
      RescueCaseState.attended => context.l10n.rescueCaseStateAttended,
      RescueCaseState.closed => context.l10n.rescueCaseStateClosed,
    };
  }

  String _priorityLabel(BuildContext context, RescuePriority priority) {
    return switch (priority) {
      RescuePriority.low => context.l10n.mapPriorityLow,
      RescuePriority.medium => context.l10n.mapPriorityMedium,
      RescuePriority.high => context.l10n.mapPriorityHigh,
      RescuePriority.critical => context.l10n.mapPriorityCritical,
    };
  }

  static Color _stateColor(RescueCaseState state) {
    return switch (state) {
      RescueCaseState.newCase => Colors.red,
      RescueCaseState.assigned => Colors.deepOrange,
      RescueCaseState.enRoute => Colors.blue,
      RescueCaseState.attended => Colors.green,
      RescueCaseState.closed => Colors.grey,
    };
  }

  static Color _priorityColor(RescuePriority priority) {
    return switch (priority) {
      RescuePriority.low => Colors.blueGrey,
      RescuePriority.medium => Colors.amber.shade800,
      RescuePriority.high => Colors.deepOrange,
      RescuePriority.critical => Colors.red.shade900,
    };
  }

  static IconData _priorityIcon(RescuePriority priority) {
    return switch (priority) {
      RescuePriority.low => Icons.sos_outlined,
      RescuePriority.medium => Icons.warning_amber,
      RescuePriority.high => Icons.crisis_alert,
      RescuePriority.critical => Icons.emergency,
    };
  }

  static Color _actorColor(String actorPeerId) {
    const colors = [
      Colors.indigo,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.lightGreen,
    ];
    var hash = 0;
    for (final codeUnit in actorPeerId.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }
}
