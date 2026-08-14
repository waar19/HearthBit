import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/emergency_directory.dart';
import 'mesh_platform_service.dart';

class EmergencyDirectoryLoadResult {
  const EmergencyDirectoryLoadResult({
    required this.directory,
    required this.usedFallback,
  });

  final EmergencyDirectory directory;
  final bool usedFallback;
}

class EmergencyDirectoryService {
  EmergencyDirectoryService({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const supportedLocales = {'en', 'es', 'de', 'fr', 'zh', 'ja'};

  final AssetBundle _bundle;

  Future<EmergencyDirectoryLoadResult> load(String locale) async {
    final requested = supportedLocales.contains(locale) ? locale : 'en';
    if (requested != 'en') {
      try {
        return EmergencyDirectoryLoadResult(
          directory: await _loadValidated(requested),
          usedFallback: false,
        );
      } on Object {
        // Never expose a partially translated or malformed emergency directory.
      }
    }
    return EmergencyDirectoryLoadResult(
      directory: await _loadValidated('en'),
      usedFallback: requested != 'en',
    );
  }

  Future<EmergencyDirectory> _loadValidated(String locale) async {
    final raw = await _bundle.loadString(
      'assets/emergency_contacts/emergency_contacts_$locale.json',
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Emergency-directory asset must be a JSON object',
      );
    }
    return EmergencyDirectory.fromJson(decoded, expectedLocale: locale);
  }
}

class EmergencyCountryResolver {
  EmergencyCountryResolver({MeshPlatformService? platform})
    : _platform = platform ?? MeshPlatformService();

  final MeshPlatformService _platform;

  Future<String> resolve({
    required Set<String> availableCountryCodes,
    String? overrideCountry,
    String? localeCountry,
  }) async {
    final normalizedOverride = overrideCountry?.trim().toUpperCase();
    if (normalizedOverride != null &&
        availableCountryCodes.contains(normalizedOverride)) {
      return normalizedOverride;
    }
    final simCountry = await _platform.getSimCountry();
    return resolveCandidates(
      availableCountryCodes: availableCountryCodes,
      overrideCountry: normalizedOverride,
      simCountry: simCountry,
      localeCountry: localeCountry,
    );
  }

  static String resolveCandidates({
    required Set<String> availableCountryCodes,
    String? overrideCountry,
    String? simCountry,
    String? localeCountry,
  }) {
    for (final candidate in [
      overrideCountry,
      simCountry,
      localeCountry,
      'INT',
    ]) {
      final normalized = candidate?.trim().toUpperCase();
      if (normalized != null &&
          normalized.isNotEmpty &&
          availableCountryCodes.contains(normalized)) {
        return normalized;
      }
    }
    return 'INT';
  }
}
