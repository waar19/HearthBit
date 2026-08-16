import 'package:flutter/material.dart';

import '../../models/mesh_models.dart';

class CompactSosMessage extends StatelessWidget {
  const CompactSosMessage({required this.message, super.key});

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
