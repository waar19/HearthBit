import 'package:flutter/material.dart';

import '../controllers/authority_announcement_controller.dart';
import '../l10n/l10n.dart';
import '../models/authority_announcement_models.dart';

class AuthorityAnnouncementsScreen extends StatefulWidget {
  const AuthorityAnnouncementsScreen({required this.controller, super.key});

  final AuthorityAnnouncementController controller;

  @override
  State<AuthorityAnnouncementsScreen> createState() =>
      _AuthorityAnnouncementsScreenState();
}

class _AuthorityAnnouncementsScreenState
    extends State<AuthorityAnnouncementsScreen> {
  final _body = TextEditingController();
  AuthorityAnnouncementPriority _priority = AuthorityAnnouncementPriority.info;
  Duration _lifetime = const Duration(hours: 1);
  bool _sending = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_body.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.controller.issue(
        priority: _priority,
        body: _body.text,
        lifetime: _lifetime,
      );
      _body.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.authoritySent)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.authoritySendError('$error'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.authorityTitle)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(context.l10n.authorityTrustBody),
            if (widget.controller.canIssue) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.l10n.authorityCreate,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AuthorityAnnouncementPriority>(
                        initialValue: _priority,
                        decoration: InputDecoration(
                          labelText: context.l10n.authorityPriority,
                        ),
                        items: AuthorityAnnouncementPriority.values
                            .map(
                              (priority) => DropdownMenuItem(
                                value: priority,
                                child: Text(_priorityLabel(context, priority)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (priority) {
                          if (priority != null) {
                            setState(() => _priority = priority);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _body,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: AuthorityAnnouncementCodec.maximumBodyBytes,
                        decoration: InputDecoration(
                          labelText: context.l10n.authorityBody,
                        ),
                      ),
                      DropdownButtonFormField<Duration>(
                        initialValue: _lifetime,
                        decoration: InputDecoration(
                          labelText: context.l10n.authorityDuration,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: const Duration(minutes: 15),
                            child: Text(
                              context.l10n.authorityDurationMinutes(15),
                            ),
                          ),
                          DropdownMenuItem(
                            value: const Duration(hours: 1),
                            child: Text(context.l10n.authorityDurationHours(1)),
                          ),
                          DropdownMenuItem(
                            value: const Duration(hours: 6),
                            child: Text(context.l10n.authorityDurationHours(6)),
                          ),
                        ],
                        onChanged: (duration) {
                          if (duration != null) {
                            setState(() => _lifetime = duration);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('authority-send'),
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.campaign_outlined),
                        label: Text(context.l10n.authoritySend),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              context.l10n.authorityHistory,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (widget.controller.announcements.isEmpty)
              Text(context.l10n.authorityHistoryEmpty)
            else
              ...widget.controller.announcements.map(
                (announcement) => _AnnouncementCard(announcement: announcement),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final AuthorityAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final expired = !announcement.expiresAt.isAfter(DateTime.now().toUtc());
    return Card(
      child: ListTile(
        leading: Icon(switch (announcement.priority) {
          AuthorityAnnouncementPriority.info => Icons.info_outline,
          AuthorityAnnouncementPriority.warning => Icons.warning_amber_rounded,
          AuthorityAnnouncementPriority.evacuate => Icons.campaign,
        }),
        title: Text(
          '${_priorityLabel(context, announcement.priority)} · '
          '${announcement.callsign}',
        ),
        subtitle: Text(
          '${announcement.body}\n'
          '${expired ? context.l10n.authorityExpired : context.l10n.authorityActive}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

String _priorityLabel(
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
