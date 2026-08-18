import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/screens/onboarding_screen.dart';

class _OnboardingController extends MeshController {
  @override
  Future<void> start() async {
    status = MeshConnectionStatus.active;
    notifyListeners();
  }

  @override
  Future<bool> ensureAlwaysLocation() async {
    backgroundLocationGranted = true;
    notifyListeners();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding no desborda en pantalla estrecha con texto grande', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    final controller = _OnboardingController();
    addTearDown(() async {
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: OnboardingScreen(controller: controller, onFinished: () async {}),
      ),
    );

    final title = tester.widget<Text>(
      find.text('Comunicación cuando fallan las redes'),
    );
    expect(title.textScaler?.scale(20), 30);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('PERMITIR Y ACTIVAR MALLA'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(568, 320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding solicita micrófono y lo muestra en el checklist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final controller = _OnboardingController();
    var microphoneRequests = 0;
    addTearDown(() async {
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(
          controller: controller,
          onFinished: () async {},
          requestMicrophonePermission: () async {
            microphoneRequests += 1;
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('PERMITIR MICRÓFONO PARA RESCATE'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(microphoneRequests, 1);
    expect(
      find.text('Las notas de voz y herramientas acústicas están listas.'),
      findsOneWidget,
    );
  });
}
