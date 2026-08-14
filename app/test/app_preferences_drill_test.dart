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

    await defaults.setBitchatInteropEnabled(true);
    final restored = AppPreferences();
    await restored.initialize();
    expect(restored.privacyPrivateMode, isFalse);
    expect(restored.bitchatInteropEnabled, isTrue);

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

    await preferences.panicWipe();

    final restored = AppPreferences();
    await restored.initialize();
    expect(restored.onboardingComplete, isFalse);
    expect(restored.amoledTheme, isFalse);
    expect(restored.gatewayOptIn, isFalse);
    expect(restored.emergencyCountryOverride, isNull);
    expect(restored.privacyPrivateMode, isTrue);
    expect(restored.bitchatInteropEnabled, isFalse);

    preferences.dispose();
    restored.dispose();
  });
}
