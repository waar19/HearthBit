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
}
