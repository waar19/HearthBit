import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/l10n/generated/app_localizations.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/screens/diagnostics_screen.dart';

class _DiagnosticsController extends MeshController {
  _DiagnosticsController() {
    operationalCounters = const MeshOperationalCounters(
      openSosRateLimitedKnown: 2,
      openSosRateLimitedUnknown: 5,
      relayDampingSuppressed: 3,
      relayDampingScheduled: 8,
      relayDampingExpired: 7,
      trustStoreEvictions: 1,
      trustConflicts: 4,
    );
  }

  @override
  Future<void> refreshPowerStatus() async {}

  @override
  Future<void> refreshDiagnostics({bool notify = true}) async {}
}

void main() {
  testWidgets('shows localized operational counters', (tester) async {
    final controller = _DiagnosticsController();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiagnosticsScreen(controller: controller),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Contadores operativos'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Contadores operativos'), findsOneWidget);
    expect(find.text('SOS desconocidos limitados por tasa'), findsOneWidget);
    expect(find.text('Conflictos de confianza'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}
