import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/l10n/generated/app_localizations.dart';
import 'package:hearth_bit/models/first_aid_guide.dart';
import 'package:hearth_bit/screens/first_aid_guide_screen.dart';
import 'package:hearth_bit/services/first_aid_guide_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String spanishAsset;

  setUpAll(() async {
    spanishAsset = await rootBundle.loadString(
      'assets/first_aid/first_aid_es.json',
    );
  });

  test('carga y valida los seis assets locales', () async {
    final service = FirstAidGuideService();

    for (final locale in FirstAidGuideService.supportedLocales) {
      final result = await service.load(locale);

      expect(result.guide.locale, locale);
      expect(
        result.guide.topics.map((topic) => topic.id).toSet(),
        FirstAidGuide.topicIds,
      );
      expect(result.guide.sources, isNotEmpty);
      expect(result.usedFallback, isFalse);
    }
  });

  test('rechaza campos desconocidos y temas incompletos', () async {
    final raw = await rootBundle.loadString(
      'assets/first_aid/first_aid_en.json',
    );
    final json = jsonDecode(raw) as Map<String, Object?>;
    json['unexpected'] = true;

    expect(
      () => FirstAidGuide.fromJson(json, expectedLocale: 'en'),
      throwsFormatException,
    );
  });

  test('usa inglés completo cuando el locale solicitado es inválido', () async {
    final english = await rootBundle.loadString(
      'assets/first_aid/first_aid_en.json',
    );
    final bundle = _StringBundle({
      'assets/first_aid/first_aid_es.json': '{"schemaVersion": 1}',
      'assets/first_aid/first_aid_en.json': english,
    });

    final result = await FirstAidGuideService(bundle: bundle).load('es');

    expect(result.usedFallback, isTrue);
    expect(result.guide.locale, 'en');
    expect(result.guide.topics, hasLength(6));
  });

  testWidgets('lista y detalle no desbordan con texto al 200 %', (
    tester,
  ) async {
    final service = FirstAidGuideService(
      bundle: _StringBundle({
        'assets/first_aid/first_aid_es.json': spanishAsset,
      }),
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
        home: FirstAidGuideScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('first-aid-topic-list')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final firstTopic = find.text('Seguridad de la escena y pedir ayuda');
    await tester.ensureVisible(firstTopic);
    await tester.pumpAndSettle();
    await tester.tap(firstTopic);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('first-aid-topic-detail')), findsOneWidget);
    expect(find.text('Seguridad de la escena y pedir ayuda'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _StringBundle extends AssetBundle {
  _StringBundle(this.values);

  final Map<String, String> values;

  @override
  Future<ByteData> load(String key) {
    final value = values[key];
    if (value == null) {
      throw FlutterError('Missing test asset: $key');
    }
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
