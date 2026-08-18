import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';
import 'peer_transfer_button.dart';

class PeerActionBar extends StatelessWidget {
  const PeerActionBar({
    required this.peer,
    required this.online,
    required this.onOpenRadar,
    required this.onUnavailableAction,
    required this.onSendFile,
    required this.onSendSealed,
    required this.onSendApk,
    super.key,
  });

  final MeshPeer peer;
  final bool online;
  final VoidCallback onOpenRadar;
  final ValueChanged<String> onUnavailableAction;
  final VoidCallback onSendFile;
  final VoidCallback onSendSealed;
  final VoidCallback onSendApk;

  @override
  Widget build(BuildContext context) {
    final secure = online && peer.secure;
    final radarAvailable = online && peer.radarAllowed;
    final radarStatus = !online
        ? context.l10n.peerOffline
        : peer.radarAllowed
        ? context.l10n.tooltipRadar
        : context.l10n.radarConsentRequired;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: radarStatus,
            color: radarAvailable ? colors.primary : colors.outline,
            onPressed: radarAvailable
                ? onOpenRadar
                : () => onUnavailableAction(radarStatus),
            icon: const Icon(Icons.radar),
          ),
          PeerTransferButton(
            peer: peer,
            online: online,
            onSendFile: onSendFile,
            onSendSealed: onSendSealed,
            onSendApk: onSendApk,
          ),
          Tooltip(
            message: secure
                ? context.l10n.peerSecure
                : context.l10n.peerTapToEncrypt,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                secure ? Icons.lock : Icons.lock_open,
                color: secure ? colors.primary : colors.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
