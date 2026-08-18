import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';
import '../../services/apk_share_service.dart';

enum PeerTransferAction { file, sealed, apk }

class PeerTransferButton extends StatelessWidget {
  const PeerTransferButton({
    required this.peer,
    required this.online,
    required this.onSendFile,
    required this.onSendSealed,
    required this.onSendApk,
    super.key,
  });

  final MeshPeer peer;
  final bool online;
  final VoidCallback onSendFile;
  final VoidCallback onSendSealed;
  final VoidCallback onSendApk;

  @override
  Widget build(BuildContext context) {
    final liveTransferEnabled = canOfferFileToPeer(peer, isOnline: online);
    final sealedEnabled = peer.hearthbitVerified;
    final tooltip = liveTransferEnabled
        ? context.l10n.tooltipSendFile
        : sealedEnabled
        ? context.l10n.sealedTransferSend
        : !online
        ? context.l10n.peerOffline
        : context.l10n.peerDoesNotSupportTransfers;
    return PopupMenuButton<PeerTransferAction>(
      tooltip: tooltip,
      enabled: liveTransferEnabled || sealedEnabled,
      icon: const Icon(Icons.attach_file),
      onSelected: (action) {
        switch (action) {
          case PeerTransferAction.file:
            onSendFile();
          case PeerTransferAction.sealed:
            onSendSealed();
          case PeerTransferAction.apk:
            onSendApk();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: PeerTransferAction.file,
          enabled: liveTransferEnabled,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(context.l10n.tooltipSendFile),
          ),
        ),
        PopupMenuItem(
          value: PeerTransferAction.sealed,
          enabled: peer.hearthbitVerified,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(context.l10n.sealedTransferSend),
          ),
        ),
        if (ApkShareService.isSupportedPlatform)
          PopupMenuItem(
            value: PeerTransferAction.apk,
            enabled: liveTransferEnabled,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.android),
              title: Text(context.l10n.sendApkToPeer),
            ),
          ),
      ],
    );
  }
}
