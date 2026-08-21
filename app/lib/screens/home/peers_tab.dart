import 'package:flutter/material.dart';

import '../../controllers/lan_gateway_controller.dart';
import '../../controllers/mesh_controller.dart';
import '../../controllers/rescue_roster_controller.dart';
import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';
import '../../utils/avatar_utils.dart';
import '../../utils/conversation_time.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/list_section_title.dart';
import '../mesh_health_card.dart';
import 'peer_action_bar.dart';
import 'peer_capability_badges.dart';

class PeersTab extends StatelessWidget {
  const PeersTab({
    required this.controller,
    this.rescueRoster,
    required this.lanGateway,
    required this.onShareInvite,
    required this.onOpenPrivateChat,
    required this.onOpenAnchorAdmin,
    required this.onOpenRadar,
    required this.onUnavailableAction,
    required this.onSendFile,
    required this.onSendSealed,
    required this.onSendApk,
    super.key,
  });

  final MeshController controller;
  final RescueRosterController? rescueRoster;
  final LanGatewayController? lanGateway;
  final void Function(BuildContext anchorContext) onShareInvite;
  final void Function(MeshPeer peer) onOpenPrivateChat;
  final void Function(MeshPeer peer) onOpenAnchorAdmin;
  final void Function(MeshPeer peer) onOpenRadar;
  final ValueChanged<String> onUnavailableAction;
  final void Function(MeshPeer peer) onSendFile;
  final void Function(MeshPeer peer) onSendSealed;
  final void Function(MeshPeer peer) onSendApk;

  @override
  Widget build(BuildContext context) {
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
              lanGateway: lanGateway,
            ),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.portable_wifi_off,
              title: context.l10n.emptyPeersTitle,
              description: context.l10n.emptyPeersBody,
              action: Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: () => onShareInvite(buttonContext),
                  icon: const Icon(Icons.ios_share),
                  label: Text(context.l10n.shareInviteButton),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final itemCount =
        2 +
        (conversations.isEmpty ? 0 : conversations.length + 1) +
        (newNearbyPeers.isEmpty ? 0 : newNearbyPeers.length + 1) +
        (genericPresences.isEmpty ? 0 : 2);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return MeshHealthCard(controller: controller, lanGateway: lanGateway);
        }
        if (index == 1) return const SizedBox(height: 8);
        var offset = 2;
        if (conversations.isNotEmpty) {
          if (index == offset) {
            return ListSectionTitle(title: context.l10n.recentChatsTitle);
          }
          offset += 1;
          if (index < offset + conversations.length) {
            return _conversationCard(context, conversations[index - offset]);
          }
          offset += conversations.length;
        }
        if (newNearbyPeers.isNotEmpty) {
          if (index == offset) {
            return ListSectionTitle(title: context.l10n.nearbyPeopleTitle);
          }
          offset += 1;
          if (index < offset + newNearbyPeers.length) {
            return _nearbyPeerCard(context, newNearbyPeers[index - offset]);
          }
          offset += newNearbyPeers.length;
        }
        if (index == offset) {
          return ListSectionTitle(
            title: context.l10n.genericPresenceSectionTitle,
          );
        }
        return _genericPresencesCard(context, genericPresences);
      },
    );
  }

  Widget _conversationCard(
    BuildContext context,
    MeshConversation conversation,
  ) {
    final peer = conversation.peer;
    final message = conversation.lastMessage;
    final chatAvailable = controller.canChatWithPeer(peer);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: chatAvailable ? () => onOpenPrivateChat(peer) : null,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(child: Text(avatarLetter(peer.nickname))),
                title: Text(peer.nickname),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    PeerCapabilityBadges(peer: peer),
                    _verifiedRescuerBadge(context, peer),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatConversationTime(context, message.timestamp)),
                    const SizedBox(height: 4),
                    Text(
                      conversation.isOnline
                          ? context.l10n.peerOnline
                          : context.l10n.peerOffline,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: conversation.isOnline
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (chatAvailable)
                PeerActionBar(
                  peer: peer,
                  online: conversation.isOnline,
                  onOpenRadar: () => onOpenRadar(peer),
                  onUnavailableAction: onUnavailableAction,
                  onSendFile: () => onSendFile(peer),
                  onSendSealed: () => onSendSealed(peer),
                  onSendApk: () => onSendApk(peer),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nearbyPeerCard(BuildContext context, MeshPeer peer) {
    final chatAvailable = controller.canChatWithPeer(peer);
    final anchorAdminAvailable =
        peer.role == MeshNodeRole.infraDataAnchor ||
        peer.role == MeshNodeRole.infraRelay;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(child: Text(avatarLetter(peer.nickname))),
            title: Text(peer.nickname),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${peer.id.substring(0, 8)} · '
                  '${chatAvailable ? (peer.secure ? context.l10n.peerSecure : context.l10n.peerTapToEncrypt) : context.l10n.externalPresenceNoChat}',
                ),
                PeerCapabilityBadges(peer: peer),
                _verifiedRescuerBadge(context, peer),
              ],
            ),
            onTap: chatAvailable
                ? () => onOpenPrivateChat(peer)
                : anchorAdminAvailable
                ? () => onOpenAnchorAdmin(peer)
                : null,
          ),
          if (chatAvailable)
            PeerActionBar(
              peer: peer,
              online: true,
              onOpenRadar: () => onOpenRadar(peer),
              onUnavailableAction: onUnavailableAction,
              onSendFile: () => onSendFile(peer),
              onSendSealed: () => onSendSealed(peer),
              onSendApk: () => onSendApk(peer),
            ),
        ],
      ),
    );
  }

  Widget _genericPresencesCard(
    BuildContext context,
    List<GenericBlePresence> genericPresences,
  ) {
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.sensors)),
        title: Text(
          context.l10n.genericPresenceSummary(
            genericPresences.length,
            genericPresences
                .map((presence) => presence.rssi)
                .reduce((first, second) => first > second ? first : second),
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
    );
  }

  Widget _verifiedRescuerBadge(BuildContext context, MeshPeer peer) {
    final member = rescueRoster?.verifiedMember(
      peerId: peer.id,
      signingPublicKey: peer.signingPublicKey,
    );
    if (member == null) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Tooltip(
        message: member.callsign,
        child: Chip(
          avatar: const Icon(Icons.verified, size: 16),
          label: Text(context.l10n.verifiedRescuerBadge),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
