import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _onboardingKey = 'onboarding.completed.v1';
  static const _amoledKey = 'appearance.amoled';
  static const _highContrastKey = 'appearance.highContrast';
  static const _gatewayOptInKey = 'gateway.optIn';
  static const _drillModeKey = 'emergency.drillModeEnabled.v1';

  final SharedPreferencesAsync _preferences;

  bool initialized = false;
  bool onboardingComplete = false;
  bool amoledTheme = false;
  bool highContrast = false;
  bool gatewayOptIn = false;
  bool drillModeEnabled = false;

  Future<void> initialize() async {
    onboardingComplete = await _preferences.getBool(_onboardingKey) ?? false;
    amoledTheme = await _preferences.getBool(_amoledKey) ?? false;
    highContrast = await _preferences.getBool(_highContrastKey) ?? false;
    gatewayOptIn = await _preferences.getBool(_gatewayOptInKey) ?? false;
    drillModeEnabled = await _preferences.getBool(_drillModeKey) ?? false;
    initialized = true;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboardingComplete = true;
    await _preferences.setBool(_onboardingKey, true);
    notifyListeners();
  }

  Future<void> setAmoledTheme(bool enabled) async {
    amoledTheme = enabled;
    await _preferences.setBool(_amoledKey, enabled);
    notifyListeners();
  }

  Future<void> setHighContrast(bool enabled) async {
    highContrast = enabled;
    await _preferences.setBool(_highContrastKey, enabled);
    notifyListeners();
  }

  Future<void> setGatewayOptIn(bool enabled) async {
    gatewayOptIn = enabled;
    await _preferences.setBool(_gatewayOptInKey, enabled);
    notifyListeners();
  }

  Future<void> setDrillModeEnabled(bool enabled) async {
    if (drillModeEnabled == enabled) return;
    drillModeEnabled = enabled;
    await _preferences.setBool(_drillModeKey, enabled);
    notifyListeners();
  }
}
