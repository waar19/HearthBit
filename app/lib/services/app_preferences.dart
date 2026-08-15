import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _onboardingKey = 'onboarding.completed.v1';
  static const _amoledKey = 'appearance.amoled';
  static const _highContrastKey = 'appearance.highContrast';
  static const _gatewayOptInKey = 'gateway.optIn';
  static const _meshDesiredActiveKey = 'mesh.desiredActive.v1';
  static const _drillModeKey = 'emergency.drillModeEnabled.v1';
  static const _drillModeExpiresAtKey = 'emergency.drillModeExpiresAt.v1';
  static const _emergencyCountryKey = 'emergency.countryOverride.v1';
  static const _privacyPrivateModeKey = 'privacy.privateMode.v1';
  static const _bitchatInteropKey = 'privacy.bitchatInterop.v1';
  static const _meshtasticEnabledKey = 'radio.meshtasticEnabled.v1';

  final SharedPreferencesAsync _preferences;

  bool initialized = false;
  bool onboardingComplete = false;
  bool amoledTheme = false;
  bool highContrast = false;
  bool gatewayOptIn = false;
  bool meshDesiredActive = false;
  bool drillModeEnabled = false;
  DateTime? drillModeExpiresAt;
  String? emergencyCountryOverride;
  bool privacyPrivateMode = true;
  bool bitchatInteropEnabled = false;
  bool meshtasticEnabled = false;

  Future<void> initialize() async {
    onboardingComplete = await _preferences.getBool(_onboardingKey) ?? false;
    amoledTheme = await _preferences.getBool(_amoledKey) ?? false;
    highContrast = await _preferences.getBool(_highContrastKey) ?? false;
    gatewayOptIn = await _preferences.getBool(_gatewayOptInKey) ?? false;
    meshDesiredActive =
        await _preferences.getBool(_meshDesiredActiveKey) ?? false;
    drillModeEnabled = await _preferences.getBool(_drillModeKey) ?? false;
    final drillExpiry = await _preferences.getInt(_drillModeExpiresAtKey);
    drillModeExpiresAt = drillExpiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(drillExpiry);
    if (drillModeEnabled &&
        (drillModeExpiresAt == null ||
            !drillModeExpiresAt!.isAfter(DateTime.now()))) {
      drillModeEnabled = false;
      drillModeExpiresAt = null;
      await _preferences.setBool(_drillModeKey, false);
      await _preferences.remove(_drillModeExpiresAtKey);
    }
    emergencyCountryOverride = await _preferences.getString(
      _emergencyCountryKey,
    );
    final storedInterop =
        await _preferences.getBool(_bitchatInteropKey) ?? false;
    final storedPrivateMode =
        await _preferences.getBool(_privacyPrivateModeKey) ?? true;
    meshtasticEnabled =
        await _preferences.getBool(_meshtasticEnabledKey) ?? false;
    // Mantener una sola política efectiva incluso si una versión anterior
    // escribió preferencias contradictorias.
    bitchatInteropEnabled = storedInterop;
    privacyPrivateMode = storedInterop ? false : storedPrivateMode;
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

  Future<void> setMeshDesiredActive(bool enabled) async {
    if (meshDesiredActive == enabled) return;
    meshDesiredActive = enabled;
    await _preferences.setBool(_meshDesiredActiveKey, enabled);
    notifyListeners();
  }

  Future<void> setDrillModeEnabled(bool enabled) async {
    if (drillModeEnabled == enabled) return;
    drillModeEnabled = enabled;
    await _preferences.setBool(_drillModeKey, enabled);
    if (enabled) {
      drillModeExpiresAt = DateTime.now().add(const Duration(hours: 2));
      await _preferences.setInt(
        _drillModeExpiresAtKey,
        drillModeExpiresAt!.millisecondsSinceEpoch,
      );
    } else {
      drillModeExpiresAt = null;
      await _preferences.remove(_drillModeExpiresAtKey);
    }
    notifyListeners();
  }

  Future<void> setEmergencyCountryOverride(String? countryCode) async {
    final normalized = countryCode?.trim().toUpperCase();
    final value = normalized == null || normalized.isEmpty ? null : normalized;
    if (emergencyCountryOverride == value) return;
    emergencyCountryOverride = value;
    if (value == null) {
      await _preferences.remove(_emergencyCountryKey);
    } else {
      await _preferences.setString(_emergencyCountryKey, value);
    }
    notifyListeners();
  }

  Future<void> setPrivacyPrivateMode(bool enabled) async {
    if (privacyPrivateMode == enabled && bitchatInteropEnabled == !enabled) {
      return;
    }
    privacyPrivateMode = enabled;
    bitchatInteropEnabled = !enabled;
    await Future.wait([
      _preferences.setBool(_privacyPrivateModeKey, enabled),
      _preferences.setBool(_bitchatInteropKey, !enabled),
    ]);
    notifyListeners();
  }

  Future<void> setBitchatInteropEnabled(bool enabled) async {
    if (bitchatInteropEnabled == enabled && privacyPrivateMode == !enabled) {
      return;
    }
    bitchatInteropEnabled = enabled;
    privacyPrivateMode = !enabled;
    await Future.wait([
      _preferences.setBool(_bitchatInteropKey, enabled),
      _preferences.setBool(_privacyPrivateModeKey, !enabled),
    ]);
    notifyListeners();
  }

  Future<void> setMeshtasticEnabled(bool enabled) async {
    if (meshtasticEnabled == enabled) return;
    meshtasticEnabled = enabled;
    await _preferences.setBool(_meshtasticEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> panicWipe() async {
    await Future.wait([
      _preferences.remove(_onboardingKey),
      _preferences.remove(_amoledKey),
      _preferences.remove(_highContrastKey),
      _preferences.remove(_gatewayOptInKey),
      _preferences.remove(_meshDesiredActiveKey),
      _preferences.remove(_drillModeKey),
      _preferences.remove(_drillModeExpiresAtKey),
      _preferences.remove(_emergencyCountryKey),
      _preferences.remove(_privacyPrivateModeKey),
      _preferences.remove(_bitchatInteropKey),
      _preferences.remove(_meshtasticEnabledKey),
    ]);
    onboardingComplete = false;
    amoledTheme = false;
    highContrast = false;
    gatewayOptIn = false;
    meshDesiredActive = false;
    drillModeEnabled = false;
    drillModeExpiresAt = null;
    emergencyCountryOverride = null;
    privacyPrivateMode = true;
    bitchatInteropEnabled = false;
    meshtasticEnabled = false;
    notifyListeners();
  }
}
