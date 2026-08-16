import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/emergency_gateway_controller.dart';
import '../controllers/family_controller.dart';
import '../controllers/lan_gateway_controller.dart';
import '../controllers/mesh_controller.dart';
import '../controllers/transfer_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../models/transfer_models.dart';
import '../services/apk_share_service.dart';
import '../services/app_preferences.dart';
import '../services/diagnostics_export_service.dart';
import '../services/diagnostics_log.dart';
import '../services/emergency_shortcut_service.dart';
import '../services/invite_share_service.dart';
import '../services/photo_send_preparation.dart';
import '../services/privacy_data_eraser.dart';
import '../services/secure_database.dart';
import '../utils/scroll_to_bottom.dart';
import '../widgets/nickname_dialog.dart';
import 'diagnostics_screen.dart';
import 'emergency_screen.dart';
import 'family_screen.dart';
import 'home/mesh_status_banner.dart';
import 'home/peers_tab.dart';
import 'home/photo_compress_dialog.dart';
import 'home/private_chat_sheet.dart';
import 'home/public_chat_tab.dart';
import 'map_screen.dart';
import 'optical_receive_screen.dart';
import 'optical_send_screen.dart';
import 'radar_screen.dart';
import 'transfers_tab.dart';

enum _AppMenuAction {
  family,
  diagnostics,
  changeNickname,
  privacy,
  support,
  about,
  panicWipe,
}

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

  Future<PreparedPhotoSend?> _pickPreparedPhoto() async {
    final file = await openFile();
    if (file == null || !mounted) return null;
    return preparePhotoForSend(
      path: file.path,
      name: file.name,
      askCompress: (size) => showPhotoCompressDialog(context, size),
    );
  }

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
    final prepared = await _pickPreparedPhoto();
    if (prepared == null || !mounted) return;
    try {
      await widget.transfers.sendFile(
        peer: peer,
        filePath: prepared.path,
        fileName: prepared.name,
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

  Future<void> _sendSealedFileTo(MeshPeer peer) async {
    final file = await openFile();
    if (file == null || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await widget.transfers.shareSealedFile(
        peer: peer,
        filePath: file.path,
        fileName: file.name,
        origin: origin,
      );
      if (!mounted) return;
      setState(() => _tab = 2);
    } catch (error) {
      if (!mounted) return;
      final detail = error is StateError ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.offerFileError(detail))),
      );
    }
  }

  Future<void> _startOpticalSend() async {
    final prepared = await _pickPreparedPhoto();
    if (prepared == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpticalSendScreen(
          filePath: prepared.path,
          fileName: prepared.name,
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

  void _openRadarForPeer(MeshPeer peer) {
    unawaited(
      _openRadar(
        peerId: peer.id,
        nickname: peer.nickname,
        consentExpiresAt: peer.radarAllowedUntil!,
        consentSource: peer.radarConsentSource ?? 'temporary',
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
                    value: _AppMenuAction.diagnostics,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.monitor_heart_outlined),
                      title: Text(context.l10n.diagnosticsTitle),
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
                    value: _AppMenuAction.privacy,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: Text(context.l10n.privacyTitle),
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
                MeshStatusBanner(controller: controller),
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
                      PublicChatTab(
                        controller: controller,
                        messageController: _messageController,
                        scrollController: _scrollController,
                        onSend: () async {
                          final text = _messageController.text;
                          _messageController.clear();
                          await controller.sendPublic(text);
                          _scrollToBottom();
                        },
                      ),
                      PeersTab(
                        controller: controller,
                        lanGateway: widget.lanGateway,
                        onShareInvite: _shareInvite,
                        onOpenPrivateChat: (peer) =>
                            _openPrivateChat(controller, peer),
                        onOpenRadar: _openRadarForPeer,
                        onUnavailableAction: _showUnavailablePeerAction,
                        onSendFile: _sendFileTo,
                        onSendSealed: _sendSealedFileTo,
                        onSendApk: _sendApkTo,
                      ),
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

  void _showUnavailablePeerAction(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPrivateChat(
    MeshController controller,
    MeshPeer peer,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PrivateChatSheet(
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
      case _AppMenuAction.diagnostics:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiagnosticsScreen(controller: controller),
          ),
        );
        return;
      case _AppMenuAction.changeNickname:
        await _changeNickname(controller);
        return;
      case _AppMenuAction.privacy:
        await _showPrivacy(controller);
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

  Future<void> _showPrivacy(MeshController controller) async {
    var interopEnabled = widget.preferences.bitchatInteropEnabled;
    var meshtasticEnabled = widget.preferences.meshtasticEnabled;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.privacy_tip_outlined),
          title: Text(context.l10n.privacyTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.privacyPrivateDefaultBody),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.privacyBitchatInteropTitle),
                  subtitle: Text(
                    interopEnabled
                        ? context.l10n.privacyBitchatInteropWarning
                        : context.l10n.privacyBitchatInteropOffBody,
                  ),
                  value: interopEnabled,
                  onChanged: (enabled) async {
                    await widget.preferences.setBitchatInteropEnabled(enabled);
                    if (!mounted) return;
                    setDialogState(() => interopEnabled = enabled);
                  },
                ),
                if (controller.supportsMeshtastic) ...[
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.meshtasticInteropTitle),
                    subtitle: Text(context.l10n.meshtasticInteropBody),
                    value: meshtasticEnabled,
                    onChanged: (enabled) async {
                      await widget.preferences.setMeshtasticEnabled(enabled);
                      if (!mounted) return;
                      setDialogState(() => meshtasticEnabled = enabled);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.actionClose),
            ),
          ],
        ),
      ),
    );
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
      await PrivacyDataEraser.clearResidualFiles();
      await SecureDatabaseKeyStore.destroy();
      await widget.preferences.panicWipe();
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
    scheduleScrollToBottom(
      _scrollController,
      animate: animate,
      isMounted: () => mounted,
      markScheduled: () => _scrollScheduled,
      setScheduled: (value) => _scrollScheduled = value,
    );
  }
}
