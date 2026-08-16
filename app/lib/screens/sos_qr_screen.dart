import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/optical_protocol.dart';
import 'optical_send_screen.dart';

class SosQrScreen extends StatelessWidget {
  const SosQrScreen({required this.bundle, super.key});

  final OpticalEmergencyBundle bundle;

  @override
  Widget build(BuildContext context) {
    final encoded = OpticalProtocol.encodeEmergency(bundle);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          bundle.isDrill ? context.l10n.drillBadge : context.l10n.sosQrTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (bundle.isDrill) ...[
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    context.l10n.drillSafetyBanner,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              context.l10n.sosQrShowInstructions,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CustomPaint(painter: QrFramePainter(encoded)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.sosQrFallbackTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              bundle.fallbackText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
