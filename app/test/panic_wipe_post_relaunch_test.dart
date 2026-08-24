// Spec Hueco 7/8 — panic wipe relaunch.
//
// Verifica que tras un panic wipe, al relanzar la app, la ruta inicial va a
// /onboarding (no /home). El bootstrap de `lib/main.dart:281-298` decide la
// ruta con la condición:
//
//     if (!_preferences.onboardingComplete) {
//       return OnboardingScreen(...);
//     }
//     return HomeScreen(...);
//
// `AppPreferences.panicWipe()` borra la clave de onboarding
// (`onboarding.completed.v1`) y deja `onboardingComplete = false`. El orden
// canónico del panic wipe (Hueco 6) ejecuta `preferences.panicWipe()` al
// final, después de `SecureDatabaseKeyStore.destroy()`. Por tanto, tras un
// wipe completo, el bootstrap siempre ve `onboardingComplete = false` y
// muestra el OnboardingScreen.
//
// Este test monta el widget de routing (que reutiliza la misma decisión que
// `lib/main.dart`) con `AppPreferences` real y `OnboardingScreen` real,
// simula el wipe y vuelve a montar la app para verificar que aparece el
// título del onboarding y no la pantalla principal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/screens/onboarding_screen.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// MeshController mínimo que no toca la plataforma nativa (MethodChannel).
// El OnboardingScreen sólo necesita `start()`, `ensureAlwaysLocation()` y
// el getter `nickname` para esta verificación.
class _RelaunchMeshController extends MeshController {
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

// Wrapper que replica el bootstrap de `lib/main.dart:260-300`. Usa el
// `AppPreferences` real, el `OnboardingScreen` real y un `HomeScreen`
// trivial sólo para detectar la ruta equivocada. Si en el futuro
// `lib/main.dart` migra a un `GoRouter`/`Navigator.initialRoute`, este
// wrapper se actualiza para reflejar el cambio.
class _RelaunchApp extends StatelessWidget {
  const _RelaunchApp({required this.preferences, required this.controller});

  final AppPreferences preferences;
  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: preferences.onboardingComplete
          ? const _FakeHomeScreen()
          : OnboardingScreen(
              controller: controller,
              onFinished: preferences.finishOnboarding,
              requestMicrophonePermission: () async => true,
            ),
    );
  }
}

class _FakeHomeScreen extends StatelessWidget {
  const _FakeHomeScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      // Marcador inequívoco: si esto se ve, la app fue a /home.
      body: Center(child: Text('HOME_SCREEN_MARKER')),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  // Spec Hueco 7/8 — caso principal del task:
  // Setup: app con datos (onboarding completo).
  // Wipe: invoca el panic wipe.
  // Relaunch: monta la app de nuevo.
  // Verifica: aparece el título del onboarding, no el marcador de /home.
  testWidgets(
    'post-wipe relaunch routes to onboarding, not home',
    (tester) async {
      final preferences = AppPreferences();
      await preferences.initialize();
      await preferences.finishOnboarding();
      expect(preferences.onboardingComplete, isTrue);
      final controller = _RelaunchMeshController();
      addTearDown(controller.dispose);

      // Setup: app con datos (HomeScreen visible).
      await tester.pumpWidget(
        _RelaunchApp(preferences: preferences, controller: controller),
      );
      await tester.pumpAndSettle();
      expect(find.text('HOME_SCREEN_MARKER'), findsOneWidget);
      expect(find.text('Communication when networks fail'), findsNothing);

      // Wipe: invoca el panic wipe (el sub-wipe #5 de la cadena documentada
      // en `home_screen.dart:1153-1174`).
      await preferences.panicWipe();
      expect(preferences.onboardingComplete, isFalse);

      // Relaunch: recrea la app desde cero, igual que si el SO la reiniciara
      // tras un panic wipe físico.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _RelaunchApp(preferences: preferences, controller: controller),
      );
      await tester.pumpAndSettle();

      // Verifica: el título del onboarding (en-US) está visible y la app
      // no quedó varada en /home.
      expect(
        find.text('Communication when networks fail'),
        findsOneWidget,
        reason: 'Tras un panic wipe + relaunch, el bootstrap debe enrutar '
            'a OnboardingScreen.',
      );
      expect(
        find.text('HOME_SCREEN_MARKER'),
        findsNothing,
        reason: 'El marcador de HomeScreen no debe verse tras un wipe.',
      );

      preferences.dispose();
    },
  );

  // Sanity check: la ruta inicial es /onboarding también en una instalación
  // limpia (sin wipe previo, sin onboarding completo). Esto garantiza que
  // el cambio para soportar el post-wipe no rompió el primer arranque.
  testWidgets(
    'fresh install routes to onboarding without any prior state',
    (tester) async {
      final preferences = AppPreferences();
      await preferences.initialize();
      expect(preferences.onboardingComplete, isFalse);
      final controller = _RelaunchMeshController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _RelaunchApp(preferences: preferences, controller: controller),
      );
      await tester.pumpAndSettle();

      expect(find.text('Communication when networks fail'), findsOneWidget);
      expect(find.text('HOME_SCREEN_MARKER'), findsNothing);

      preferences.dispose();
    },
  );

  // Sanity check: el ciclo completo onboarding → home → wipe → onboarding
  // se puede recorrer más de una vez sin estado residual. Cubre el caso de
  // un usuario que completa onboarding, hace wipe, completa de nuevo y
  // vuelve a hacer wipe.
  testWidgets(
    'repeated onboarding → wipe cycle always lands on onboarding',
    (tester) async {
      final preferences = AppPreferences();
      await preferences.initialize();
      final controller = _RelaunchMeshController();
      addTearDown(controller.dispose);

      for (var cycle = 0; cycle < 3; cycle++) {
        // Onboarding → home.
        await preferences.finishOnboarding();
        await tester.pumpWidget(
          _RelaunchApp(preferences: preferences, controller: controller),
        );
        await tester.pumpAndSettle();
        expect(find.text('HOME_SCREEN_MARKER'), findsOneWidget);

        // Wipe.
        await preferences.panicWipe();
        expect(preferences.onboardingComplete, isFalse);

        // Relaunch.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          _RelaunchApp(preferences: preferences, controller: controller),
        );
        await tester.pumpAndSettle();
        expect(find.text('Communication when networks fail'), findsOneWidget);
        expect(find.text('HOME_SCREEN_MARKER'), findsNothing);
      }

      preferences.dispose();
    },
  );
}
