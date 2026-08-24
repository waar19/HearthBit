import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:hearth_bit/services/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('persiste el modo simulacro entre instancias', () async {
    final first = AppPreferences();
    await first.initialize();
    await first.setDrillModeEnabled(true);

    final restored = AppPreferences();
    await restored.initialize();

    expect(restored.drillModeEnabled, isTrue);
    first.dispose();
    restored.dispose();
  });

  test('persiste la intención de mantener la malla activa', () async {
    final first = AppPreferences();
    await first.initialize();
    await first.setMeshDesiredActive(true);

    final restored = AppPreferences();
    await restored.initialize();

    expect(restored.meshDesiredActive, isTrue);
    await restored.setMeshDesiredActive(false);

    final stopped = AppPreferences();
    await stopped.initialize();
    expect(stopped.meshDesiredActive, isFalse);

    first.dispose();
    restored.dispose();
    stopped.dispose();
  });

  test('modo privado es predeterminado e interop BitChat es opt-in', () async {
    final defaults = AppPreferences();
    await defaults.initialize();
    expect(defaults.privacyPrivateMode, isTrue);
    expect(defaults.bitchatInteropEnabled, isFalse);
    expect(defaults.meshtasticEnabled, isFalse);

    await defaults.setBitchatInteropEnabled(true);
    await defaults.setMeshtasticEnabled(true);
    final restored = AppPreferences();
    await restored.initialize();
    expect(restored.privacyPrivateMode, isFalse);
    expect(restored.bitchatInteropEnabled, isTrue);
    expect(restored.meshtasticEnabled, isTrue);

    await restored.setPrivacyPrivateMode(true);
    final privateAgain = AppPreferences();
    await privateAgain.initialize();
    expect(privateAgain.privacyPrivateMode, isTrue);
    expect(privateAgain.bitchatInteropEnabled, isFalse);

    defaults.dispose();
    restored.dispose();
    privateAgain.dispose();
  });

  test('panic wipe restablece preferencias privadas seguras', () async {
    final preferences = AppPreferences();
    await preferences.initialize();
    await preferences.finishOnboarding();
    await preferences.setAmoledTheme(true);
    await preferences.setGatewayOptIn(true);
    await preferences.setEmergencyCountryOverride('CO');
    await preferences.setBitchatInteropEnabled(true);
    await preferences.setMeshtasticEnabled(true);

    await preferences.panicWipe();

    final restored = AppPreferences();
    await restored.initialize();
    expect(restored.onboardingComplete, isFalse);
    expect(restored.amoledTheme, isFalse);
    expect(restored.gatewayOptIn, isFalse);
    expect(restored.emergencyCountryOverride, isNull);
    expect(restored.privacyPrivateMode, isTrue);
    expect(restored.bitchatInteropEnabled, isFalse);
    expect(restored.meshtasticEnabled, isFalse);

    preferences.dispose();
    restored.dispose();
  });

  // Spec Hueco 7: AppPreferences.panicWipe debe ser idempotente. Ver
  // docs/superpowers/specs/2026-08-24-panic-wipe-sqlite-cipher-design.md.
  // Cubre reintento por crash mid-wipe y doble pulsación de la UI.
  test('panicWipe is idempotent', () async {
    final preferences = AppPreferences();
    await preferences.initialize();
    await preferences.finishOnboarding();
    await preferences.setAmoledTheme(true);
    await preferences.setGatewayOptIn(true);
    await preferences.setHighContrast(true);
    await preferences.setMeshtasticEnabled(true);

    // Primer wipe: datos persistentes creados arriba.
    await preferences.panicWipe();
    expect(preferences.onboardingComplete, isFalse);
    expect(preferences.amoledTheme, isFalse);
    expect(preferences.gatewayOptIn, isFalse);
    expect(preferences.highContrast, isFalse);
    expect(preferences.meshtasticEnabled, isFalse);

    // Segundo wipe sobre estado ya vacío: no debe lanzar y debe dejar el
    // mismo estado final.
    await preferences.panicWipe();
    expect(preferences.onboardingComplete, isFalse);
    expect(preferences.amoledTheme, isFalse);
    expect(preferences.gatewayOptIn, isFalse);
    expect(preferences.highContrast, isFalse);
    expect(preferences.meshtasticEnabled, isFalse);
    expect(preferences.privacyPrivateMode, isTrue);
    expect(preferences.bitchatInteropEnabled, isFalse);

    // Una instancia nueva que arranca desde el mismo store no debe ver
    // residuos de la primera: la segunda llamada no reescribió nada.
    final restored = AppPreferences();
    await restored.initialize();
    expect(restored.onboardingComplete, isFalse);
    expect(restored.amoledTheme, isFalse);
    expect(restored.gatewayOptIn, isFalse);
    expect(restored.highContrast, isFalse);
    expect(restored.meshtasticEnabled, isFalse);

    preferences.dispose();
    restored.dispose();
  });
}
