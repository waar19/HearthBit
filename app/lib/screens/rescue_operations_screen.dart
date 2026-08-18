import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/rescue_case_controller.dart';
import '../l10n/l10n.dart';
import '../models/mesh_models.dart';
import '../models/rescue_case_models.dart';

class RescueOperationsScreen extends StatelessWidget {
  const RescueOperationsScreen({required this.controller, super.key});

  final RescueCaseController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.rescueOperationsTitle)),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final cases = controller.cases;
          if (controller.lastError != null && cases.isEmpty) {
            return _CenteredMessage(
              icon: Icons.error_outline,
              message: context.l10n.rescueOperationsError(
                controller.lastError!,
              ),
            );
          }
          if (cases.isEmpty) {
            return _CenteredMessage(
              icon: Icons.health_and_safety_outlined,
              message: context.l10n.rescueOperationsEmpty,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: cases.length + (controller.lastError == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (controller.lastError != null && index == 0) {
                return MaterialBanner(
                  content: Text(
                    context.l10n.rescueOperationsError(controller.lastError!),
                  ),
                  leading: const Icon(Icons.warning_amber_rounded),
                  actions: const [SizedBox.shrink()],
                );
              }
              final caseIndex = controller.lastError == null
                  ? index
                  : index - 1;
              return _RescueCaseCard(
                rescueCase: cases[caseIndex],
                controller: controller,
              );
            },
          );
        },
      ),
    );
  }
}

class _RescueCaseCard extends StatelessWidget {
  const _RescueCaseCard({required this.rescueCase, required this.controller});

  final RescueCase rescueCase;
  final RescueCaseController controller;

  @override
  Widget build(BuildContext context) {
    final assignee = rescueCase.assigneePeerId;
    String? callsign;
    if (assignee != null) {
      for (final member in controller.roster.members) {
        if (member.peerId == assignee) {
          callsign = member.callsign;
          break;
        }
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rescueCase.victim,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(_stateLabel(context, rescueCase.state))),
              ],
            ),
            const SizedBox(height: 6),
            Text(rescueCase.message),
            if (rescueCase.triage != null) ...[
              const SizedBox(height: 8),
              Text(
                _triageLabel(context, rescueCase.triage!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (rescueCase.latitude != null &&
                rescueCase.longitude != null) ...[
              const SizedBox(height: 6),
              Text(
                '${rescueCase.latitude!.toStringAsFixed(5)}, '
                '${rescueCase.longitude!.toStringAsFixed(5)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              context.l10n.rescueOperationsReceivedAt(
                DateFormat.yMd().add_Hm().format(rescueCase.createdAt),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (assignee != null) ...[
              const SizedBox(height: 4),
              Text(
                context.l10n.rescueOperationsAssignee(
                  callsign ?? assignee.substring(0, 8),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _actions(context)),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final actions = <Widget>[];
    if (controller.canAssignToMe(rescueCase)) {
      actions.add(
        FilledButton.icon(
          onPressed: () =>
              _run(context, () => controller.assignToMe(rescueCase.caseHash)),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(context.l10n.rescueOperationsAssignMe),
        ),
      );
    }
    for (final state in const [
      RescueCaseState.enRoute,
      RescueCaseState.attended,
      RescueCaseState.closed,
    ]) {
      if (!controller.canAdvanceTo(rescueCase, state)) continue;
      actions.add(
        FilledButton.tonal(
          onPressed: () => _run(
            context,
            () => controller.advance(rescueCase.caseHash, state),
          ),
          child: Text(_actionLabel(context, state)),
        ),
      );
    }
    if (actions.isEmpty) {
      actions.add(Text(context.l10n.rescueOperationsNoActions));
    }
    return actions;
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.rescueOperationsError('$error'))),
      );
    }
  }

  String _stateLabel(BuildContext context, RescueCaseState state) =>
      switch (state) {
        RescueCaseState.newCase => context.l10n.rescueCaseStateNew,
        RescueCaseState.assigned => context.l10n.rescueCaseStateAssigned,
        RescueCaseState.enRoute => context.l10n.rescueCaseStateEnRoute,
        RescueCaseState.attended => context.l10n.rescueCaseStateAttended,
        RescueCaseState.closed => context.l10n.rescueCaseStateClosed,
      };

  String _actionLabel(BuildContext context, RescueCaseState state) =>
      switch (state) {
        RescueCaseState.enRoute => context.l10n.rescueOperationsEnRoute,
        RescueCaseState.attended => context.l10n.rescueOperationsAttended,
        RescueCaseState.closed => context.l10n.rescueOperationsClose,
        RescueCaseState.newCase ||
        RescueCaseState.assigned => context.l10n.rescueOperationsNoActions,
      };

  String _triageLabel(BuildContext context, SosTriage triage) {
    final need = switch (triage.primaryNeed) {
      SosPrimaryNeed.medical => context.l10n.rescueTriageMedical,
      SosPrimaryNeed.water => context.l10n.rescueTriageWater,
      SosPrimaryNeed.extraction => context.l10n.rescueTriageExtraction,
      SosPrimaryNeed.shelter => context.l10n.rescueTriageShelter,
      SosPrimaryNeed.other => context.l10n.rescueTriageOther,
    };
    return context.l10n.rescueOperationsTriage(
      need,
      triage.peopleCount?.toString() ?? '—',
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
