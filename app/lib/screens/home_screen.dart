import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/mesh_controller.dart';
import '../controllers/emergency_gateway_controller.dart';
import '../controllers/family_controller.dart';
import '../controllers/lan_gateway_controller.dart';
import '../controllers/transfer_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../models/transfer_models.dart';
import '../models/voice_note.dart';
import '../services/apk_share_service.dart';
import '../services/app_preferences.dart';
import '../services/diagnostics_export_service.dart';
import '../services/diagnostics_log.dart';
import '../services/emergency_shortcut_service.dart';
import '../services/invite_share_service.dart';
import '../services/photo_profile.dart';
import '../services/secure_database.dart';
import '../services/voice_note_audio_controller.dart';
import '../utils/message_chronology.dart';
import '../widgets/empty_state.dart';
import '../widgets/list_section_title.dart';
import '../widgets/message_composer.dart';
import '../widgets/nickname_dialog.dart';
import '../widgets/voice_waveform.dart';
import 'emergency_screen.dart';
import 'family_screen.dart';
import 'mesh_health_card.dart';
import 'map_screen.dart';
import 'optical_receive_screen.dart';
import 'optical_send_screen.dart';
import 'radar_screen.dart';
import 'transfers_tab.dart';

enum _AppMenuAction { family, changeNickname, support, about, panicWipe }

enum _PeerTransferAction { file, apk }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.controller,
    required this.transfers,
    required this.preferences,
    required this.gateway,
    required this.family,
    this.lanGateway,
    this.emergencyOpens,
    this.consumeInitialEmergencyOpen,
    super.key,
  });

  final MeshController controller;
  final TransferController transfers;
  final AppPreferences preferences;
  final EmergencyGatewayController gateway;
  final FamilyController family;
  final LanGatewayController? lanGateway;
  final Stream<void>? emergencyOpens;
  final Future<bool> Function()? consumeInitialEmergencyOpen;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _apkShare = ApkShareService();
  final _diagnosticsExport = DiagnosticsExportService();
  int _tab = 0;
  int _publicMessageCount = 0;
  bool _scrollScheduled = false;
  bool _appInForeground = true;
  bool? _genericPresenceScanRequested;
  StreamSubscription<void>? _emergencyShortcutSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _publicMessageCount = _countPublicMessages();
    widget.controller.addListener(_handleMeshUpdate);
    _listenForEmergencyShortcuts();
    final consumeInitialOpen =
        widget.consumeInitialEmergencyOpen ??
        EmergencyShortcutService.consumeInitialOpen;
    consumeInitialOpen().then((open) {
      if (open) _openEmergencyTab();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncGenericPresenceScan(force: true);
    });
    _scrollToBottom(animate: false);
  }

  void _openEmergencyTab() {
    if (!mounted) return;
    setState(() => _tab = 0);
    _syncGenericPresenceScan();
  }

  void _listenForEmergencyShortcuts() {
    final opens = widget.emergencyOpens ?? EmergencyShortcutService.opens;
    _emergencyShortcutSubscription = opens.listen((_) => _openEmergencyTab());
  }

  void _syncGenericPresenceScan({bool force = false}) {
    final enabled = _appInForeground && _tab == 2;
    if (!force && _genericPresenceScanRequested == enabled) return;
    _genericPresenceScanRequested = enabled;
    unawaited(widget.controller.setGenericPresenceScanEnabled(enabled));
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emergencyOpens != widget.emergencyOpens) {
      unawaited(_emergencyShortcutSubscription?.cancel());
      _listenForEmergencyShortcuts();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleMeshUpdate);
      unawaited(oldWidget.controller.setGenericPresenceScanEnabled(false));
      widget.controller.addListener(_handleMeshUpdate);
      _genericPresenceScanRequested = null;
      _syncGenericPresenceScan(force: true);
      _publicMessageCount = _countPublicMessages();
      _scrollToBottom(animate: false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncGenericPresenceScan();
    // Al volver de Ajustes (batería/ubicación) se refresca el estado real.
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshPowerStatus();
    }
  }

  int get _pendingOffers => widget.transfers.transfers
      .where(
        (record) =>
            record.direction == TransferDirection.incoming &&
            record.state == TransferState.offered,
      )
      .length;

  Future<void> _sendFileTo(MeshPeer peer) async {
    if (!peer.supportsTransfers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.peerDoesNotSupportTransfers),
          action: SnackBarAction(
            label: context.l10n.sendByQr,
            onPressed: _startOpticalSend,
          ),
        ),
      );
      return;
    }
    final file = await openFile();
    if (file == null || !mounted) return;
    var path = file.path;
    var name = file.name;
    if (PhotoEmergencyProfile.isPhoto(name)) {
      final size = await File(path).length();
      if (size > PhotoEmergencyProfile.compressThresholdBytes && mounted) {
        final compress = await _askCompressPhoto(size);
        if (compress == null || !mounted) return;
        if (compress) {
          final compressed = await PhotoEmergencyProfile.compress(path);
          if (compressed != null) {
            path = compressed;
            name = p.basename(compressed);
          }
        }
      }
    }
    if (!mounted) return;
    try {
      await widget.transfers.sendFile(
        peer: peer,
        filePath: path,
        fileName: name,
      );
      if (!mounted) return;
      setState(() => _tab = 2);
      _syncGenericPresenceScan();
    } catch (error) {
      if (!mounted) return;
      final detail = error is StateError ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.offerFileError(detail))),
      );
    }
  }

  Future<void> _startOpticalSend() async {
    final file = await openFile();
    if (file == null || !mounted) return;
    var path = file.path;
    var name = file.name;
    if (PhotoEmergencyProfile.isPhoto(name)) {
      final size = await File(path).length();
      if (size > PhotoEmergencyProfile.compressThresholdBytes && mounted) {
        final compress = await _askCompressPhoto(size);
        if (compress == null || !mounted) return;
        if (compress) {
          final compressed = await PhotoEmergencyProfile.compress(path);
          if (compressed != null) {
            path = compressed;
            name = p.basename(compressed);
          }
        }
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpticalSendScreen(
          filePath: path,
          fileName: name,
          senderPeerId: widget.controller.peerId,
        ),
      ),
    );
  }

  Future<void> _startOpticalReceive() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpticalReceiveScreen(
          transfers: widget.transfers,
          mesh: widget.controller,
        ),
      ),
    );
  }

  Future<void> _openRadar({
    required String peerId,
    required String nickname,
    required DateTime consentExpiresAt,
    required String consentSource,
    double? latitude,
    double? longitude,
  }) {
    final knownLocation = widget.controller.peerLocations.latestFor(peerId);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RadarScreen(
          peerId: peerId,
          nickname: nickname,
          consentExpiresAt: consentExpiresAt,
          consentSource: consentSource,
          latitude: latitude ?? knownLocation?.latitude,
          longitude: longitude ?? knownLocation?.longitude,
        ),
      ),
    );
  }

  Future<bool?> _askCompressPhoto(int size) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.photoProfileTitle),
        content: Text(
          context.l10n.photoProfileBody(
            (size / (1024 * 1024)).toStringAsFixed(1),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.actionSendOriginal),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.actionCompress),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.controller.setGenericPresenceScanEnabled(false));
    widget.controller.removeListener(_handleMeshUpdate);
    _emergencyShortcutSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.transfers,
        widget.gateway,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.appTitle),
            actions: [
              IconButton(
                tooltip: context.l10n.mapOpen,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MapScreen(controller: controller),
                  ),
                ),
                icon: const Icon(Icons.map_outlined),
              ),
              IconButton(
                tooltip: context.l10n.tooltipAppearance,
                onPressed: _showAppearance,
                icon: const Icon(Icons.contrast),
              ),
              IconButton(
                tooltip: context.l10n.nodeModeTooltip,
                onPressed: () => _showNodeMode(controller),
                icon: Icon(
                  controller.localRole == MeshNodeRole.phoneBeacon
                      ? Icons.sensors
                      : Icons.hub_outlined,
                ),
              ),
              PopupMenuButton<_AppMenuAction>(
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                onSelected: (action) => _handleAppMenu(action, controller),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _AppMenuAction.family,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.family_restroom),
                      title: Text(context.l10n.familyTitle),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AppMenuAction.changeNickname,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(context.l10n.tooltipChangeName),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AppMenuAction.support,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.favorite_outline),
                      title: Text(context.l10n.tooltipSupport),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AppMenuAction.about,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline),
                      title: Text(context.l10n.aboutTitle),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _AppMenuAction.panicWipe,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      textColor: Theme.of(context).colorScheme.error,
                      iconColor: Theme.of(context).colorScheme.error,
                      leading: const Icon(Icons.delete_forever_outlined),
                      title: Text(context.l10n.tooltipPanicWipe),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StatusBanner(controller: controller),
                if (controller.lastError != null)
                  MaterialBanner(
                    content: Text(controller.lastError!),
                    leading: const Icon(Icons.warning_amber_rounded),
                    actions: [
                      TextButton(
                        onPressed: () => controller.start(),
                        child: Text(context.l10n.actionRetry),
                      ),
                    ],
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      EmergencyScreen(
                        controller: controller,
                        preferences: widget.preferences,
                        gateway: widget.gateway,
                        family: widget.family,
                      ),
                      _buildChat(controller),
                      _buildPeers(controller),
                      TransfersTab(
                        transfers: widget.transfers,
                        onSendOptical: _startOpticalSend,
                        onReceiveOptical: _startOpticalReceive,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) {
              setState(() => _tab = value);
              _syncGenericPresenceScan();
              if (value == 1) _scrollToBottom(animate: false);
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.emergency_outlined),
                selectedIcon: const Icon(Icons.emergency),
                label: context.l10n.tabEmergency,
              ),
              NavigationDestination(
                icon: const Icon(Icons.forum_outlined),
                selectedIcon: const Icon(Icons.forum),
                label: context.l10n.tabChannel,
              ),
              NavigationDestination(
                icon: const Icon(Icons.hub_outlined),
                selectedIcon: const Icon(Icons.hub),
                label: context.l10n.tabNearby,
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: _pendingOffers > 0,
                  label: Text('$_pendingOffers'),
                  child: const Icon(Icons.folder_shared_outlined),
                ),
                selectedIcon: const Icon(Icons.folder_shared),
                label: context.l10n.tabFiles,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAppearance() {
    return showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.preferences,
        builder: (context, _) => AlertDialog(
          title: Text(context.l10n.appearanceTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: widget.preferences.amoledTheme,
                onChanged: widget.preferences.setAmoledTheme,
                title: Text(context.l10n.appearanceAmoled),
                subtitle: Text(context.l10n.appearanceAmoledBody),
              ),
              SwitchListTile(
                value: widget.preferences.highContrast,
                onChanged: widget.preferences.setHighContrast,
                title: Text(context.l10n.appearanceHighContrast),
                subtitle: Text(context.l10n.appearanceHighContrastBody),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.actionClose),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(MeshController controller) {
    final publicMessages = controller.messages
        .where((message) => !message.isPrivate)
        .toList(growable: false);
    final timeline = _messageTimelineEntries(publicMessages);
    return Column(
      children: [
        Expanded(
          child: publicMessages.isEmpty
              ? EmptyState(
                  icon: Icons.bluetooth_searching,
                  title: context.l10n.emptyChatTitle,
                  description: context.l10n.emptyChatBody,
                )
              : ListView.builder(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(12),
                  itemCount: timeline.length,
                  itemBuilder: (context, index) => _buildMessageTimelineEntry(
                    context,
                    timeline[index],
                    compactSos: true,
                  ),
                ),
        ),
        MessageComposer(
          controller: _messageController,
          enabled: controller.canSend,
          hint: context.l10n.composerPublicHint,
          onSend: () async {
            final text = _messageController.text;
            _messageController.clear();
            await controller.sendPublic(text);
            _scrollToBottom();
          },
        ),
      ],
    );
  }

  Widget _buildPeers(MeshController controller) {
    final conversations = controller.conversations;
    final conversationIds = conversations
        .map((conversation) => conversation.peer.id)
        .toSet();
    final newNearbyPeers = controller.peers
        .where((peer) => !conversationIds.contains(peer.id))
        .toList(growable: false);
    final genericPresences = controller.genericPresences;
    if (conversations.isEmpty &&
        newNearbyPeers.isEmpty &&
        genericPresences.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: MeshHealthCard(
              controller: controller,
              lanGateway: widget.lanGateway,
            ),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.portable_wifi_off,
              title: context.l10n.emptyPeersTitle,
              description: context.l10n.emptyPeersBody,
              action: Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: () => _shareInvite(buttonContext),
                  icon: const Icon(Icons.ios_share),
                  label: Text(context.l10n.shareInviteButton),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        MeshHealthCard(controller: controller, lanGateway: widget.lanGateway),
        const SizedBox(height: 8),
        if (conversations.isNotEmpty) ...[
          ListSectionTitle(title: context.l10n.recentChatsTitle),
          ...conversations.map((conversation) {
            final peer = conversation.peer;
            final message = conversation.lastMessage;
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: peer.role.canChat
                    ? () => _openPrivateChat(controller, peer)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_avatarLetter(peer.nickname)),
                        ),
                        title: Text(peer.nickname),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            _peerCapabilityBadges(peer),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatConversationTime(message.timestamp)),
                            const SizedBox(height: 4),
                            Text(
                              conversation.isOnline
                                  ? context.l10n.peerOnline
                                  : context.l10n.peerOffline,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: conversation.isOnline
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      _peerControls(
                        controller,
                        peer,
                        online: conversation.isOnline,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
        if (newNearbyPeers.isNotEmpty) ...[
          ListSectionTitle(title: context.l10n.nearbyPeopleTitle),
          ...newNearbyPeers.map(
            (peer) => Card(
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(_avatarLetter(peer.nickname)),
                    ),
                    title: Text(peer.nickname),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${peer.id.substring(0, 8)} · '
                          '${peer.role.canChat ? (peer.secure ? context.l10n.peerSecure : context.l10n.peerTapToEncrypt) : context.l10n.genericPresenceNoChat}',
                        ),
                        _peerCapabilityBadges(peer),
                      ],
                    ),
                    onTap: peer.role.canChat
                        ? () => _openPrivateChat(controller, peer)
                        : null,
                  ),
                  _peerControls(controller, peer, online: true),
                ],
              ),
            ),
          ),
        ],
        if (genericPresences.isNotEmpty) ...[
          ListSectionTitle(title: context.l10n.genericPresenceSectionTitle),
          Card(
            child: ExpansionTile(
              leading: const CircleAvatar(child: Icon(Icons.sensors)),
              title: Text(
                context.l10n.genericPresenceSummary(
                  genericPresences.length,
                  genericPresences
                      .map((presence) => presence.rssi)
                      .reduce(
                        (first, second) => first > second ? first : second,
                      ),
                ),
              ),
              subtitle: Text(context.l10n.genericPresenceExpand),
              children: genericPresences
                  .map(
                    (presence) => ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(context.l10n.genericPresenceNoChat),
                      subtitle: Text(
                        context.l10n.genericPresenceSignal(presence.rssi),
                      ),
                      enabled: false,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }

  Widget _peerCapabilityBadges(MeshPeer peer) {
    final badges = <({IconData icon, String label})>[
      if (peer.role == MeshNodeRole.infraRelay)
        (icon: Icons.router_outlined, label: context.l10n.peerRoleInfraRelay),
      if (peer.role == MeshNodeRole.infraDataAnchor)
        (
          icon: Icons.inventory_2_outlined,
          label: context.l10n.peerRoleStorageAnchor,
        ),
      if (peer.hasLongRangeTrunk)
        (
          icon: Icons.settings_input_antenna,
          label: context.l10n.peerLongRangeTrunkActive,
        ),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 4,
          runSpacing: 4,
          children: badges
              .map(
                (badge) => ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Chip(
                    avatar: Icon(badge.icon, size: 16),
                    label: Text(
                      badge.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _peerControls(
    MeshController controller,
    MeshPeer peer, {
    required bool online,
  }) {
    final secure = online && peer.secure;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: !online
                ? context.l10n.peerOffline
                : peer.radarAllowed
                ? context.l10n.tooltipRadar
                : context.l10n.radarConsentRequired,
            onPressed: online && peer.radarAllowed
                ? () => _openRadar(
                    peerId: peer.id,
                    nickname: peer.nickname,
                    consentExpiresAt: peer.radarAllowedUntil!,
                    consentSource: peer.radarConsentSource ?? 'temporary',
                  )
                : null,
            icon: const Icon(Icons.radar),
          ),
          _peerTransferButton(peer, online: online),
          Tooltip(
            message: secure
                ? context.l10n.peerSecure
                : context.l10n.peerTapToEncrypt,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(secure ? Icons.lock : Icons.lock_open),
            ),
          ),
        ],
      ),
    );
  }

  Widget _peerTransferButton(MeshPeer peer, {required bool online}) {
    final enabled = canOfferFileToPeer(peer, isOnline: online);
    final tooltip = !online
        ? context.l10n.peerOffline
        : peer.supportsTransfers
        ? context.l10n.tooltipSendFile
        : context.l10n.peerDoesNotSupportTransfers;
    if (!ApkShareService.isSupportedPlatform) {
      return IconButton(
        tooltip: tooltip,
        onPressed: enabled ? () => _sendFileTo(peer) : null,
        icon: const Icon(Icons.attach_file),
      );
    }
    return PopupMenuButton<_PeerTransferAction>(
      tooltip: tooltip,
      enabled: enabled,
      icon: const Icon(Icons.attach_file),
      onSelected: (action) {
        switch (action) {
          case _PeerTransferAction.file:
            _sendFileTo(peer);
          case _PeerTransferAction.apk:
            _sendApkTo(peer);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _PeerTransferAction.file,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(context.l10n.tooltipSendFile),
          ),
        ),
        PopupMenuItem(
          value: _PeerTransferAction.apk,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.android),
            title: Text(context.l10n.sendApkToPeer),
          ),
        ),
      ],
    );
  }

  String _avatarLetter(String nickname) =>
      nickname.isEmpty ? '?' : nickname.characters.first.toUpperCase();

  String _formatConversationTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    }
    return MaterialLocalizations.of(context).formatShortDate(local);
  }

  Future<void> _openPrivateChat(
    MeshController controller,
    MeshPeer peer,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PrivateChatSheet(
        controller: controller,
        transfers: widget.transfers,
        peer: peer,
        onOpenRadar: (currentPeer) => _openRadar(
          peerId: currentPeer.id,
          nickname: currentPeer.nickname,
          consentExpiresAt: currentPeer.radarAllowedUntil!,
          consentSource: currentPeer.radarConsentSource ?? 'temporary',
        ),
      ),
    );
  }

  Future<void> _changeNickname(MeshController controller) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) =>
          NicknameDialog(initialNickname: controller.nickname),
    );
    if (value != null) await controller.updateNickname(value);
  }

  Future<void> _handleAppMenu(
    _AppMenuAction action,
    MeshController controller,
  ) async {
    switch (action) {
      case _AppMenuAction.family:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FamilyScreen(controller: widget.family),
          ),
        );
        return;
      case _AppMenuAction.changeNickname:
        await _changeNickname(controller);
        return;
      case _AppMenuAction.support:
        await _openExternal(InviteShareService.donationUri);
        return;
      case _AppMenuAction.about:
        await _showAbout();
        return;
      case _AppMenuAction.panicWipe:
        await _confirmWipe(controller);
        return;
    }
  }

  Future<void> _showNodeMode(MeshController controller) async {
    final selected = await showDialog<MeshNodeRole>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.nodeModeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                controller.localRole == MeshNodeRole.phoneRelay
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(context.l10n.nodeModeRelayTitle),
              subtitle: Text(context.l10n.nodeModeRelayBody),
              onTap: () =>
                  Navigator.pop(dialogContext, MeshNodeRole.phoneRelay),
            ),
            ListTile(
              leading: Icon(
                controller.localRole == MeshNodeRole.phoneBeacon
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(context.l10n.nodeModeBeaconTitle),
              subtitle: Text(context.l10n.nodeModeBeaconBody),
              onTap: () =>
                  Navigator.pop(dialogContext, MeshNodeRole.phoneBeacon),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.actionCancel),
          ),
        ],
      ),
    );
    if (selected != null && selected != controller.localRole) {
      await controller.updateNodeRole(selected);
    }
  }

  Future<void> _showAbout() async {
    var version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // La información de paquete no está disponible en algunos tests.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/icon/hearthbit.png',
            width: 64,
            height: 64,
          ),
        ),
        title: Text(context.l10n.aboutTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.aboutBody),
            if (version.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.aboutVersion(version),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.actionClose),
          ),
          TextButton.icon(
            onPressed: () => _openExternal(InviteShareService.repositoryUri),
            icon: const Icon(Icons.code),
            label: Text(context.l10n.aboutSourceCode),
          ),
          Builder(
            builder: (buttonContext) => TextButton.icon(
              onPressed: () => _shareInvite(buttonContext),
              icon: const Icon(Icons.ios_share),
              label: Text(context.l10n.shareInviteButton),
            ),
          ),
          Builder(
            builder: (buttonContext) => TextButton.icon(
              onPressed: () => _shareDiagnostics(buttonContext),
              icon: const Icon(Icons.bug_report_outlined),
              label: Text(context.l10n.diagnosticsExportButton),
            ),
          ),
          if (ApkShareService.isSupportedPlatform)
            Builder(
              builder: (buttonContext) => TextButton.icon(
                onPressed: () => _shareInstalledApk(buttonContext),
                icon: const Icon(Icons.android),
                label: Text(context.l10n.shareApkButton),
              ),
            ),
          FilledButton.icon(
            onPressed: () => _openExternal(InviteShareService.donationUri),
            icon: const Icon(Icons.local_cafe_outlined),
            label: Text(context.l10n.supportButton),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmApkSafety({String? peerName}) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.apkSafetyTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (peerName != null) ...[
                    Text(context.l10n.apkSendToPeerWarning(peerName)),
                    const SizedBox(height: 12),
                  ],
                  Text(context.l10n.apkInstallWarning),
                  const SizedBox(height: 12),
                  Text(context.l10n.apkSignatureWarning),
                  if (peerName != null) ...[
                    const SizedBox(height: 12),
                    Text(context.l10n.apkTransportWarning),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.apkConfirmShare),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<ApkSharePreparation?> _prepareInstalledApk({String? peerName}) async {
    if (!await _confirmApkSafety(peerName: peerName) || !mounted) return null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.apkPreparing)));
    final preparation = await _apkShare.prepareInstalledApk();
    if (!mounted) return null;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    switch (preparation.status) {
      case ApkPreparationStatus.ready:
        return preparation;
      case ApkPreparationStatus.splitInstallation:
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.shareApkButton),
            content: Text(context.l10n.apkSplitUnavailable),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.actionClose),
              ),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: () async {
                    await _shareInvite(buttonContext);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  icon: const Icon(Icons.ios_share),
                  label: Text(context.l10n.shareInviteButton),
                ),
              ),
            ],
          ),
        );
        return null;
      case ApkPreparationStatus.unsupported:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.apkUnsupported)));
        return null;
      case ApkPreparationStatus.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.apkShareError(
                preparation.message ?? context.l10n.errorUnknown,
              ),
            ),
          ),
        );
        return null;
    }
  }

  Future<void> _shareInstalledApk(BuildContext anchorContext) async {
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    final preparation = await _prepareInstalledApk();
    if (preparation == null || !mounted) return;
    try {
      await _apkShare.sharePreparedApk(
        preparation: preparation,
        anchor: anchor,
        subject: context.l10n.appTitle,
        message: context.l10n.apkShareMessage,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.apkShareError('$error'))),
      );
    }
  }

  Future<void> _sendApkTo(MeshPeer peer) async {
    final preparation = await _prepareInstalledApk(peerName: peer.nickname);
    if (preparation == null || !mounted) return;
    try {
      await widget.transfers.sendFile(
        peer: peer,
        filePath: preparation.path!,
        fileName: preparation.fileName!,
        mimeType: ApkShareService.androidPackageMimeType,
      );
      if (!mounted) return;
      setState(() => _tab = 3);
      _syncGenericPresenceScan();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.apkOfferSent(peer.nickname))),
      );
    } catch (error) {
      if (!mounted) return;
      final detail = error is StateError ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.offerFileError(detail))),
      );
    }
  }

  Future<void> _shareInvite(BuildContext anchorContext) async {
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    try {
      await InviteShareService.share(
        anchor: anchor,
        message: context.l10n.shareInviteMessage(
          InviteShareService.repositoryUri.toString(),
        ),
        subject: context.l10n.appTitle,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.shareInviteError)));
    }
  }

  Future<void> _shareDiagnostics(BuildContext anchorContext) async {
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    try {
      DiagnosticsLog.instance.info('diagnostics.export.requested');
      await _diagnosticsExport.share(
        anchor: anchor,
        subject: context.l10n.diagnosticsExportSubject,
      );
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.warning(
        'diagnostics.export.failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.diagnosticsExportError)),
      );
    }
  }

  Future<void> _openExternal(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.openLinkError)));
    }
  }

  Future<void> _confirmWipe(MeshController controller) async {
    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches =
              confirmationController.text.trim().toUpperCase() == 'BORRAR';
          return AlertDialog(
            title: Text(context.l10n.wipeDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.wipeDialogBody),
                const SizedBox(height: 16),
                Text(context.l10n.wipeDialogInstruction),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmationController,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.wipeDialogKeyword,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.actionCancel),
              ),
              FilledButton(
                onPressed: matches
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(context.l10n.actionWipe),
              ),
            ],
          );
        },
      ),
    );
    confirmationController.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await widget.transfers.wipe();
      await widget.family.panicWipe();
      await widget.gateway.panicWipe();
      await widget.lanGateway?.panicWipe();
      await controller.panicWipe();
      await DiagnosticsLog.instance.clear();
      await SecureDatabaseKeyStore.destroy();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.wipeDialogComplete)));
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.error(
        'privacy.panic_wipe.failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.wipeDialogError)));
    }
  }

  int _countPublicMessages() =>
      widget.controller.messages.where((message) => !message.isPrivate).length;

  void _handleMeshUpdate() {
    final count = _countPublicMessages();
    if (count > _publicMessageCount && _tab == 1) {
      _scrollToBottom();
    }
    _publicMessageCount = count;
  }

  void _scrollToBottom({bool animate = true}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final target = _scrollController.position.maxScrollExtent;
        if (animate) {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(target);
        }
      }
    });
  }
}

class _PrivateChatSheet extends StatefulWidget {
  const _PrivateChatSheet({
    required this.controller,
    required this.transfers,
    required this.peer,
    required this.onOpenRadar,
  });

  final MeshController controller;
  final TransferController transfers;
  final MeshPeer peer;
  final Future<void> Function(MeshPeer peer) onOpenRadar;

  @override
  State<_PrivateChatSheet> createState() => _PrivateChatSheetState();
}

class _PrivateChatSheetState extends State<_PrivateChatSheet> {
  late final TextEditingController _textController;
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final VoiceNoteAudioController _voiceAudio = VoiceNoteAudioController();
  final List<double> _recordingWaveform = [];
  var _privateMessageCount = 0;
  var _scrollScheduled = false;
  var _recording = false;
  var _sending = false;
  String? _sendError;
  DateTime? _recordingStarted;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingLimitTimer;
  Timer? _recordingUiTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _privateMessageCount = _countPrivateMessages();
    widget.controller.addListener(_handleControllerUpdate);
    widget.transfers.addListener(_handleTransferUpdate);
    _scrollToBottom(animate: false);
  }

  @override
  void didUpdateWidget(covariant _PrivateChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerUpdate);
      widget.controller.addListener(_handleControllerUpdate);
      _privateMessageCount = _countPrivateMessages();
      _scrollToBottom(animate: false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerUpdate);
    widget.transfers.removeListener(_handleTransferUpdate);
    _recordingLimitTimer?.cancel();
    _recordingUiTimer?.cancel();
    unawaited(_amplitudeSubscription?.cancel());
    _audioRecorder.dispose();
    _voiceAudio.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int _countPrivateMessages() => widget.controller.messages
      .where(
        (message) =>
            message.isPrivate && message.senderPeerId == widget.peer.id,
      )
      .length;

  void _handleControllerUpdate() {
    final count = _countPrivateMessages();
    if (!mounted) return;
    final hasNewMessage = count > _privateMessageCount;
    setState(() => _privateMessageCount = count);
    if (hasNewMessage) _scrollToBottom();
  }

  void _handleTransferUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoiceRecording(MeshPeer peer) async {
    if (_recording) {
      await _stopVoiceRecording();
      return;
    }
    if (!peer.supportsTransfers) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.voiceUnsupported)));
      return;
    }
    if (!await _audioRecorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.voiceMicrophoneRequired),
          action: SnackBarAction(
            label: context.l10n.actionOpenSettings,
            onPressed: Geolocator.openAppSettings,
          ),
        ),
      );
      return;
    }
    await _voiceAudio.stop();
    final directory = await getTemporaryDirectory();
    final path = p.join(
      directory.path,
      'hearthbit_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 20000,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        audioInterruption: AudioInterruptionMode.pauseResume,
      ),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordingStarted = DateTime.now();
      _recordingElapsed = Duration.zero;
      _recordingWaveform.clear();
      _sendError = null;
    });
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen(_recordAmplitude);
    _recordingUiTimer?.cancel();
    _recordingUiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_recording || _recordingStarted == null) return;
      setState(() {
        _recordingElapsed = DateTime.now().difference(_recordingStarted!);
      });
    });
    _recordingLimitTimer?.cancel();
    _recordingLimitTimer = Timer(
      const Duration(seconds: 20),
      _stopVoiceRecording,
    );
  }

  void _recordAmplitude(Amplitude amplitude) {
    if (!mounted || !_recording) return;
    final decibels = amplitude.current.clamp(-60.0, 0.0);
    final linear = ((decibels + 60) / 60).clamp(0.0, 1.0);
    final normalized = math.sqrt(linear).clamp(0.08, 1.0);
    setState(() {
      _recordingWaveform.add(normalized);
    });
  }

  Future<void> _stopVoiceRecording() async {
    if (!_recording) return;
    _recordingLimitTimer?.cancel();
    _recordingUiTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final elapsed = DateTime.now().difference(
      _recordingStarted ?? DateTime.now(),
    );
    final duration = (elapsed.inMilliseconds / 1000).ceil().clamp(1, 20);
    final waveform = VoiceNoteEnvelope.resample(_recordingWaveform);
    final path = await _audioRecorder.stop();
    await _voiceAudio.resetPlaybackSession();
    if (mounted) {
      setState(() {
        _recording = false;
        _recordingStarted = null;
        _recordingElapsed = Duration.zero;
      });
    }
    if (path == null || !mounted) return;
    final peer =
        widget.controller.peerById(widget.peer.id) ??
        widget.controller.knownPeerById(widget.peer.id) ??
        widget.peer;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    String? transferId;
    try {
      transferId = await widget.transfers.sendFile(
        peer: peer,
        filePath: path,
        fileName: p.basename(path),
        mimeType: TransferController.voiceNoteMimeType,
      );
      final result = await widget.controller.sendPrivate(
        peer,
        VoiceNoteEnvelope(
          transferId: transferId,
          durationSeconds: duration,
          waveform: waveform,
        ).encode(),
      );
      if (!result.accepted) {
        throw StateError(result.error ?? currentL10n.errorUnknown);
      }
      _scrollToBottom();
    } catch (error) {
      if (transferId != null) {
        await widget.transfers.cancel(transferId);
      }
      if (mounted) {
        setState(() => _sendError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recording) return;
    _recordingLimitTimer?.cancel();
    _recordingUiTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    await _audioRecorder.cancel();
    await _voiceAudio.resetPlaybackSession();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingStarted = null;
      _recordingElapsed = Duration.zero;
      _recordingWaveform.clear();
    });
  }

  Future<void> _sendMessage(MeshPeer peer) async {
    if (_sending) return;
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    PrivateMessageSendResult result;
    try {
      result = await widget.controller.sendPrivate(peer, text);
    } catch (error) {
      result = PrivateMessageSendResult.failed(error.toString());
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.accepted) {
        _textController.clear();
      } else {
        _sendError = result.error ?? context.l10n.errorUnknown;
      }
    });
    if (result.accepted) _scrollToBottom();
  }

  void _scrollToBottom({bool animate = true}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final peer =
        widget.controller.peerById(widget.peer.id) ??
        widget.controller.knownPeerById(widget.peer.id) ??
        widget.peer;
    final isOnline = widget.controller.isPeerOnline(peer.id);
    final secure = isOnline && peer.secure;
    final canUseLivePrivateChannel =
        isOnline && secure && widget.controller.canSend && !_sending;
    final canQueueText =
        peer.role.canChat && widget.controller.canSend && !_sending;
    final privateMessages = widget.controller.messages
        .where(
          (message) =>
              message.isPrivate && message.senderPeerId == widget.peer.id,
        )
        .toList(growable: false);
    final timeline = _messageTimelineEntries(privateMessages);
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom - 32;
    final sheetHeight = math.min(
      mediaQuery.size.height * .65,
      math.max(160, availableHeight),
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: mediaQuery.viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: sheetHeight.toDouble(),
        child: Column(
          children: [
            Row(
              children: [
                Icon(secure ? Icons.lock : Icons.lock_open),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    peer.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: peer.radarAllowed
                      ? context.l10n.tooltipRadar
                      : context.l10n.radarConsentRequired,
                  onPressed: isOnline && peer.radarAllowed
                      ? () => widget.onOpenRadar(peer)
                      : null,
                  icon: const Icon(Icons.radar),
                ),
              ],
            ),
            const Divider(),
            if (!isOnline || !secure)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      isOnline
                          ? Icons.lock_clock_outlined
                          : Icons.cloud_off_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOnline
                            ? context.l10n.secureChatUnavailableHint
                            : context.l10n.offlineChatHint,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: privateMessages.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.privateChatIntro,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: timeline.length,
                      itemBuilder: (context, index) =>
                          _buildMessageTimelineEntry(
                            context,
                            timeline[index],
                            transfers: widget.transfers,
                            voiceAudio: _voiceAudio,
                          ),
                    ),
            ),
            if (_sendError case final error?)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.privateMessageSendError(error),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_recording)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: context.l10n.actionCancel,
                      onPressed: _cancelVoiceRecording,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatVoiceDuration(_recordingElapsed),
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VoiceWaveform(
                        samples: VoiceNoteEnvelope.resample(
                          _recordingWaveform,
                          bars: 40,
                        ),
                        progress: 1,
                        activeColor: Theme.of(context).colorScheme.error,
                        inactiveColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: context.l10n.voiceStop,
                      onPressed: _stopVoiceRecording,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: context.l10n.voiceRecord,
                    onPressed:
                        canUseLivePrivateChannel && peer.supportsTransfers
                        ? () => _toggleVoiceRecording(peer)
                        : null,
                    icon: const Icon(Icons.mic),
                  ),
                  Expanded(
                    child: MessageComposer(
                      controller: _textController,
                      enabled: canQueueText,
                      hint: context.l10n.composerPrivateHint,
                      onSend: () => _sendMessage(peer),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = controller.status;
    final displayNickname =
        controller.nickname.trim().isEmpty ||
            isDefaultMeshNickname(controller.nickname)
        ? context.l10n.statusBannerYou
        : controller.nickname;
    final (color, accent, icon, label) = switch (status) {
      MeshConnectionStatus.active => (
        scheme.surfaceContainerHigh,
        scheme.primary,
        Icons.bluetooth_connected,
        context.l10n.statusActiveLabel(
          displayNickname,
          controller.peers.length,
        ),
      ),
      MeshConnectionStatus.degraded => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.bluetooth_searching,
        context.l10n.statusDegradedLabel(displayNickname),
      ),
      MeshConnectionStatus.starting => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.bluetooth_searching,
        context.l10n.statusStarting,
      ),
      MeshConnectionStatus.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.bluetooth_disabled,
        context.l10n.statusError,
      ),
      MeshConnectionStatus.stopped => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.bluetooth_disabled,
        context.l10n.statusStopped,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: accent),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            if (status == MeshConnectionStatus.starting)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (status == MeshConnectionStatus.active)
              FilledButton.tonal(
                onPressed: controller.stop,
                child: Text(context.l10n.actionStop),
              )
            else if (status == MeshConnectionStatus.degraded)
              FilledButton.tonal(
                onPressed: controller.start,
                child: Text(context.l10n.actionRestart),
              )
            else
              FilledButton.tonal(
                onPressed: controller.start,
                child: Text(context.l10n.actionActivate),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.transfers,
    this.voiceAudio,
  });

  final MeshMessage message;
  final TransferController? transfers;
  final VoiceNoteAudioController? voiceAudio;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isMine
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final color = message.isDrill
        ? Theme.of(context).colorScheme.tertiaryContainer
        : message.isSos
        ? Theme.of(context).colorScheme.errorContainer
        : message.isMine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final status = message.isPending
        ? context.l10n.privateMessagePending
        : message.isExpired
        ? context.l10n.deliveryExpired
        : message.isMine
        ? context.l10n.deliveryRelayed
        : '';
    final semanticLabel = [
      if (!message.isMine) message.sender,
      message.content.replaceFirst('SOS|', 'SOS: '),
      if (status.isNotEmpty) status,
      MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(message.timestamp.toLocal())),
    ].join(', ');
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Align(
          alignment: alignment,
          child: Container(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.sizeOf(context).width *
                  (textScale >= 1.5 ? 0.92 : 0.78),
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!message.isMine || message.isPrivate) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isPrivate) ...[
                        const Icon(Icons.lock, size: 14),
                        const SizedBox(width: 4),
                      ],
                      if (!message.isMine)
                        Flexible(
                          child: Text(
                            message.sender,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (message.isVoiceNote)
                  _VoiceNoteContent(
                    message: message,
                    transfers: transfers,
                    voiceAudio: voiceAudio,
                  )
                else if (message.isDrill)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.drillBadge,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message.drill?.readableMessage ??
                            context.l10n.drillInvalidMessage,
                      ),
                    ],
                  )
                else
                  Text(message.content.replaceFirst('SOS|', 'SOS: ')),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (message.isPending) ...[
                        const Icon(Icons.schedule, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          context.l10n.privateMessagePending,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (message.isExpired) ...[
                        const Icon(Icons.timer_off_outlined, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          context.l10n.deliveryExpired,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (message.isMine &&
                          !message.isPending &&
                          !message.isExpired) ...[
                        const Icon(Icons.campaign_outlined, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          context.l10n.deliveryRelayed,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(message.timestamp.toLocal()),
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _MessageTimelineEntry = ({DateTime? day, MeshMessage? message});

List<_MessageTimelineEntry> _messageTimelineEntries(
  List<MeshMessage> messages,
) {
  final entries = <_MessageTimelineEntry>[];
  DateTime? previousDay;
  for (final message in messages) {
    final day = localCalendarDay(message.timestamp);
    if (previousDay != day) {
      entries.add((day: day, message: null));
      previousDay = day;
    }
    entries.add((day: null, message: message));
  }
  return entries;
}

Widget _buildMessageTimelineEntry(
  BuildContext context,
  _MessageTimelineEntry entry, {
  TransferController? transfers,
  VoiceNoteAudioController? voiceAudio,
  bool compactSos = false,
}) {
  final day = entry.day;
  if (day != null) {
    return _DateSeparator(label: _formatDayLabel(context, day));
  }
  final message = entry.message!;
  return compactSos && message.isSos
      ? _CompactSosMessage(message: message)
      : _MessageBubble(
          message: message,
          transfers: transfers,
          voiceAudio: voiceAudio,
        );
}

class _CompactSosMessage extends StatelessWidget {
  const _CompactSosMessage({required this.message});

  final MeshMessage message;

  @override
  Widget build(BuildContext context) {
    final latitude = message.sosLatitude;
    final longitude = message.sosLongitude;
    final coordinates = latitude == null || longitude == null
        ? null
        : '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}';
    final scheme = Theme.of(context).colorScheme;
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(message.timestamp.toLocal()));
    return Semantics(
      label: '${message.sender}: ${message.sosDescription}',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${message.sender} · ${message.sosDescription}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (coordinates != null)
                    Text(
                      coordinates,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(time, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _VoiceNoteContent extends StatelessWidget {
  const _VoiceNoteContent({
    required this.message,
    required this.transfers,
    required this.voiceAudio,
  });

  final MeshMessage message;
  final TransferController? transfers;
  final VoiceNoteAudioController? voiceAudio;

  @override
  Widget build(BuildContext context) {
    TransferRecord? record;
    final transferId = message.voiceTransferId;
    if (transferId != null && transfers != null) {
      for (final item in transfers!.transfers) {
        if (item.id == transferId) {
          record = item;
          break;
        }
      }
    }
    final playbackPath = record?.filePath;
    final localFileAvailable =
        playbackPath != null && File(playbackPath).existsSync();
    final ready =
        localFileAvailable &&
        (record?.direction == TransferDirection.outgoing ||
            record?.state == TransferState.completed);
    final failed =
        record?.state == TransferState.failed ||
        record?.state == TransferState.rejected ||
        record?.state == TransferState.cancelled;
    final transferKey = transferId ?? message.id;
    final fallbackDuration = Duration(
      seconds: message.voiceDurationSeconds ?? 0,
    );
    final samples = message.voiceWaveform.isEmpty
        ? fallbackVoiceWaveform()
        : message.voiceWaveform;
    final controller = voiceAudio;
    final contentWidth = math.min(
      240.0,
      MediaQuery.sizeOf(context).width * .66,
    );
    return AnimatedBuilder(
      animation: controller ?? const _NoopListenable(),
      builder: (context, _) {
        final active = controller?.isActive(transferKey) ?? false;
        final playing = controller?.isPlaying(transferKey) ?? false;
        final progress =
            controller?.progressFor(transferKey, fallbackDuration) ?? 0;
        final position = active
            ? controller?.position ?? Duration.zero
            : Duration.zero;
        final playbackError = active ? controller?.error : null;
        final tooltip = failed && !ready
            ? (record?.error ?? context.l10n.errorUnknown)
            : playbackError ??
                  (playing ? context.l10n.voicePause : context.l10n.voicePlay);
        return SizedBox(
          width: contentWidth,
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: tooltip,
                onPressed: ready && controller != null
                    ? () => controller.toggle(
                        transferId: transferKey,
                        filePath: playbackPath,
                      )
                    : null,
                icon: ready
                    ? Icon(playing ? Icons.pause : Icons.play_arrow)
                    : failed
                    ? Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      )
                    : const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: VoiceWaveform(
                  samples: samples,
                  progress: progress,
                  onSeek: ready && active && controller != null
                      ? (value) => controller.seek(
                          transferId: transferKey,
                          progress: value,
                          fallbackDuration: fallbackDuration,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatVoiceDuration(
                  active && position > Duration.zero
                      ? position
                      : fallbackDuration,
                ),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (playbackError != null || (failed && ready)) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message:
                      playbackError ??
                      record?.error ??
                      context.l10n.errorUnknown,
                  child: Icon(
                    Icons.error_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoopListenable implements Listenable {
  const _NoopListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

String _formatVoiceDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 5999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatDayLabel(BuildContext context, DateTime day) {
  return switch (relativeMessageDay(day)) {
    RelativeMessageDay.today => context.l10n.dateToday,
    RelativeMessageDay.yesterday => context.l10n.dateYesterday,
    RelativeMessageDay.other => MaterialLocalizations.of(
      context,
    ).formatMediumDate(day),
  };
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}
