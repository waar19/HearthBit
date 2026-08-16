import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';

class PeerCapabilityBadges extends StatelessWidget {
  const PeerCapabilityBadges({required this.peer, super.key});

  final MeshPeer peer;

  @override
  Widget build(BuildContext context) {
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
}
