import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/l10n/generated/app_localizations.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/screens/diagnostics_screen.dart';
import 'package:hearth_bit/services/diagnostics_export_service.dart';

class _DiagnosticsController extends MeshController {
  _DiagnosticsController() {
    operationalCounters = const MeshOperationalCounters(
      openEmergencyRateLimitedKnown: 2,
      openEmergencyRateLimitedUnknown: 5,
      relayDampingSuppressed: 3,
      relayDampingScheduled: 8,
      relayDampingExpired: 7,
      trustStoreEvictions: 1,
      trustConflicts: 4,
      packetsReceived: 20,
      packetsAccepted: 12,
      packetsRejected: 3,
      packetsForwarded: 4,
      packetsDeduplicated: 5,
      packetsDroppedRateLimit: 2,
      packetsDroppedTtl: 1,
      packetsFailedTransport: 6,
    );
    operationalCountersLifetime = 'process';
    sosOperationalMetrics = const SosOperationalMetrics(
      sosCreated: 4,
      sosRelayedLocal: 3,
      sosAckReceived: 2,
      sosAckCount: 5,
      sosExpired: 1,
      sosDeliveryLatencyMs: 1200,
    );
  }

  int refreshCalls = 0;
  bool updateOnRefresh = false;
  bool failOnRefresh = false;

  @override
  Future<void> refreshPowerStatus() async {}

  @override
  Future<void> refreshDiagnostics({bool notify = true}) async {
    refreshCalls += 1;
    if (failOnRefresh) throw StateError('refresh failed');
    if (updateOnRefresh) {
      operationalCounters = const MeshOperationalCounters(
        openEmergencyRateLimitedKnown: 9,
        openEmergencyRateLimitedUnknown: 11,
      );
      operationalCountersLifetime = 'process';
      if (notify) notifyListeners();
    }
  }
}

class _RecordingExportService extends DiagnosticsExportService {
  int calls = 0;
  Map<String, int>? counters;
  String? lifetime;
  SosOperationalMetrics? sosMetrics;

  @override
  Future<ShareResult> share({
    required RenderBox? anchor,
    required String subject,
    Map<String, int> operationalCounters = const {},
    String operationalCountersLifetime = 'unknown',
    SosOperationalMetrics sosMetrics = const SosOperationalMetrics(),
  }) async {
    calls += 1;
    counters = Map.of(operationalCounters);
    lifetime = operationalCountersLifetime;
    this.sosMetrics = sosMetrics;
    return ShareResult.unavailable;
  }
}

void main() {
  Widget app(
    _DiagnosticsController controller, {
    DiagnosticsExportService? exportService,
  }) => MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DiagnosticsScreen(
      controller: controller,
      exportService: exportService,
    ),
  );

  testWidgets('shows localized operational counters', (tester) async {
    final controller = _DiagnosticsController();
    await tester.pumpWidget(app(controller));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Contadores operativos'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Contadores operativos'), findsOneWidget);
    expect(
      find.text('Frames de emergencia desconocidos limitados por tasa'),
      findsOneWidget,
    );
    expect(find.text('Conflictos de confianza'), findsOneWidget);
    expect(find.text('Desde el inicio de este proceso'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('4'), findsWidgets);
    expect(find.text('Paquetes recibidos en ingress'), findsOneWidget);
    expect(find.text('Intentos de enlace fallidos'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Alcance de las métricas'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Métricas de entrega SOS · outbox retenido'),
      findsOneWidget,
    );
    expect(find.text('Alcance de las métricas'), findsOneWidget);
    expect(
      find.text('Outbox retenido (hasta 200 emergencias)'),
      findsOneWidget,
    );
  });

  testWidgets('shows unavailable relay observation and hop count honestly', (
    tester,
  ) async {
    final controller = _DiagnosticsController();
    await tester.pumpWidget(app(controller));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Primera retransmisión remota observada'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Primera retransmisión remota observada'), findsOneWidget);
    expect(find.text('Conteo de saltos'), findsOneWidget);
    expect(find.text('No disponible'), findsNWidgets(2));
    expect(
      find.text(
        'El estado retransmitido solo confirma una transmisión local aceptada '
        'por el sistema nativo.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Los reintentos reinician el TTL y el TTL transmitido no está firmado.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('refreshes counters before exporting and reflects new values', (
    tester,
  ) async {
    final controller = _DiagnosticsController();
    final export = _RecordingExportService();
    await tester.pumpWidget(app(controller, exportService: export));
    await tester.pumpAndSettle();
    controller.updateOnRefresh = true;
    await tester.scrollUntilVisible(
      find.text('Exportar diagnóstico'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Exportar diagnóstico'));
    await tester.pumpAndSettle();

    expect(controller.refreshCalls, 2);
    expect(export.calls, 1);
    expect(export.counters?['openEmergencyRateLimitedKnown'], 9);
    expect(export.lifetime, 'process');
    expect(export.sosMetrics?.sosAckCount, 5);
    await tester.scrollUntilVisible(
      find.text('Frames de emergencia conocidos limitados por tasa'),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('9'), findsOneWidget);
  });

  testWidgets('does not export stale counters when refresh fails', (
    tester,
  ) async {
    final controller = _DiagnosticsController();
    final export = _RecordingExportService();
    await tester.pumpWidget(app(controller, exportService: export));
    await tester.pumpAndSettle();
    controller.failOnRefresh = true;
    await tester.scrollUntilVisible(
      find.text('Exportar diagnóstico'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Exportar diagnóstico'));
    await tester.pumpAndSettle();

    expect(export.calls, 0);
    expect(
      find.text(
        'No se pudo actualizar el diagnóstico. No se exportó información.',
      ),
      findsOneWidget,
    );
  });
}
