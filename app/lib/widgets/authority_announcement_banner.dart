import 'package:flutter/material.dart';

import '../controllers/authority_announcement_controller.dart';
import '../l10n/l10n.dart';
import '../models/authority_announcement_models.dart';

class AuthorityAnnouncementBanner extends StatelessWidget {
  const AuthorityAnnouncementBanner({
    required this.controller,
    this.onTap,
    super.key,
  });

  final AuthorityAnnouncementController controller;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final announcement = controller.activeAnnouncement;
    if (announcement == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, foreground) = switch (announcement.priority) {
      AuthorityAnnouncementPriority.info => (
        Icons.info_outline,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      AuthorityAnnouncementPriority.warning => (
        Icons.warning_amber_rounded,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      AuthorityAnnouncementPriority.evacuate => (
        Icons.campaign,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
    final expires = announcement.expiresAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final expiration =
        '${material.formatShortDate(expires)} · '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(expires))}';
    return Semantics(
      liveRegion: true,
      label: context.l10n.authorityBannerSemantics,
      child: Material(
        key: const Key('authority-announcement-banner'),
        color: color,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_priorityLabel(context, announcement.priority)} · '
                        '${announcement.callsign}',
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        announcement.body,
                        style: TextStyle(color: foreground),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.authorityExpires(expiration),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: foreground),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) Icon(Icons.chevron_right, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _priorityLabel(
    BuildContext context,
    AuthorityAnnouncementPriority priority,
  ) {
    return switch (priority) {
      AuthorityAnnouncementPriority.info => context.l10n.authorityPriorityInfo,
      AuthorityAnnouncementPriority.warning =>
        context.l10n.authorityPriorityWarning,
      AuthorityAnnouncementPriority.evacuate =>
        context.l10n.authorityPriorityEvacuate,
    };
  }
}
