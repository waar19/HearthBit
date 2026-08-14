import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:hearth_bit/l10n/generated/app_localizations.dart';
import 'package:hearth_bit/models/emergency_directory.dart';
import 'package:hearth_bit/screens/emergency_contacts_screen.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:hearth_bit/services/emergency_directory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String spanishAsset;

  setUpAll(() async {
    spanishAsset = await rootBundle.loadString(
      'assets/emergency_contacts/emergency_contacts_es.json',
    );
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('loads and strictly validates all six localized directories', () async {
    final service = EmergencyDirectoryService();
    final english = (await service.load('en')).directory;

    for (final locale in EmergencyDirectoryService.supportedLocales) {
      final result = await service.load(locale);

      expect(result.usedFallback, isFalse);
      expect(result.directory.locale, locale);
      expect(
        result.directory.countries.map((country) => country.code).toSet(),
        EmergencyDirectory.countryCodes,
      );
      expect(result.directory.country('CO').numbers, isNotEmpty);
      expect(result.directory.sources, isNotEmpty);
      for (final countryCode in EmergencyDirectory.countryCodes) {
        expect(
          result.directory
              .country(countryCode)
              .numbers
              .map((number) => number.id)
              .toSet(),
          english
              .country(countryCode)
              .numbers
              .map((number) => number.id)
              .toSet(),
          reason: '$locale must contain the same $countryCode numbers',
        );
        expect(
          result.directory
              .country(countryCode)
              .organizations
              .map((organization) => organization.id)
              .toSet(),
          english
              .country(countryCode)
              .organizations
              .map((organization) => organization.id)
              .toSet(),
          reason: '$locale must contain the same $countryCode organizations',
        );
      }
    }
  });

  test('rejects unknown fields and incomplete country data', () async {
    final raw = await rootBundle.loadString(
      'assets/emergency_contacts/emergency_contacts_en.json',
    );
    final json = jsonDecode(raw) as Map<String, Object?>;
    json['unexpected'] = true;

    expect(
      () => EmergencyDirectory.fromJson(json, expectedLocale: 'en'),
      throwsFormatException,
    );
  });

  test('falls back to the complete English directory', () async {
    final english = await rootBundle.loadString(
      'assets/emergency_contacts/emergency_contacts_en.json',
    );
    final bundle = _StringBundle({
      'assets/emergency_contacts/emergency_contacts_es.json':
          '{"schemaVersion":1}',
      'assets/emergency_contacts/emergency_contacts_en.json': english,
    });

    final result = await EmergencyDirectoryService(bundle: bundle).load('es');

    expect(result.usedFallback, isTrue);
    expect(result.directory.locale, 'en');
    expect(result.directory.countries, hasLength(9));

    final unsupported = await EmergencyDirectoryService(
      bundle: _StringBundle({
        'assets/emergency_contacts/emergency_contacts_en.json': english,
      }),
    ).load('pt');
    expect(unsupported.usedFallback, isTrue);
    expect(unsupported.directory.locale, 'en');
  });

  test('country resolution honors override, SIM, region, then fallback', () {
    const countries = EmergencyDirectory.countryCodes;

    expect(
      EmergencyCountryResolver.resolveCandidates(
        availableCountryCodes: countries,
        overrideCountry: 'mx',
        simCountry: 'co',
        localeCountry: 'US',
      ),
      'MX',
    );
    expect(
      EmergencyCountryResolver.resolveCandidates(
        availableCountryCodes: countries,
        simCountry: 'co',
        localeCountry: 'US',
      ),
      'CO',
    );
    expect(
      EmergencyCountryResolver.resolveCandidates(
        availableCountryCodes: countries,
        simCountry: 'BR',
        localeCountry: 'jp',
      ),
      'JP',
    );
    expect(
      EmergencyCountryResolver.resolveCandidates(
        availableCountryCodes: countries,
        simCountry: 'BR',
        localeCountry: 'IT',
      ),
      'INT',
    );
  });

  test('persists and clears the manual emergency country', () async {
    final preferences = AppPreferences();
    await preferences.initialize();
    await preferences.setEmergencyCountryOverride('co');

    final restored = AppPreferences();
    await restored.initialize();
    expect(restored.emergencyCountryOverride, 'CO');

    await restored.setEmergencyCountryOverride(null);
    final cleared = AppPreferences();
    await cleared.initialize();
    expect(cleared.emergencyCountryOverride, isNull);

    preferences.dispose();
    restored.dispose();
    cleared.dispose();
  });

  testWidgets('directory remains usable at 200 percent text scale', (
    tester,
  ) async {
    final preferences = AppPreferences();
    await preferences.initialize();
    await preferences.setEmergencyCountryOverride('CO');
    final opened = <Uri>[];
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(preferences.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'CO'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: EmergencyContactsScreen(
          preferences: preferences,
          service: EmergencyDirectoryService(
            bundle: _StringBundle({
              'assets/emergency_contacts/emergency_contacts_es.json':
                  spanishAsset,
            }),
          ),
          countryResolver: _FixedCountryResolver('CO'),
          uriLauncher: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('emergency-contacts-list')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('emergency-contacts-list')),
      const Offset(0, -600),
    );
    await tester.pump();
    expect(find.text('Colombia'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(opened, isEmpty);
  });
}

class _FixedCountryResolver extends EmergencyCountryResolver {
  _FixedCountryResolver(this.country);

  final String country;

  @override
  Future<String> resolve({
    required Set<String> availableCountryCodes,
    String? overrideCountry,
    String? localeCountry,
  }) async => country;
}

class _StringBundle extends AssetBundle {
  _StringBundle(this.values);

  final Map<String, String> values;

  @override
  Future<ByteData> load(String key) {
    final value = values[key];
    if (value == null) throw FlutterError('Missing test asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(value));
    return Future.value(ByteData.sublistView(bytes));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = values[key];
    if (value == null) throw FlutterError('Missing test asset: $key');
    return value;
  }
}
