import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/first_aid_guide.dart';

class FirstAidGuideLoadResult {
  const FirstAidGuideLoadResult({
    required this.guide,
    required this.usedFallback,
  });

  final FirstAidGuide guide;
  final bool usedFallback;
}

class FirstAidGuideService {
  FirstAidGuideService({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const supportedLocales = {'en', 'es', 'de', 'fr', 'zh', 'ja'};

  final AssetBundle _bundle;

  Future<FirstAidGuideLoadResult> load(String locale) async {
    final requested = supportedLocales.contains(locale) ? locale : 'en';
    if (requested != 'en') {
      try {
        return FirstAidGuideLoadResult(
          guide: await _loadValidated(requested),
          usedFallback: false,
        );
      } on Object {
        // A missing or malformed translation must never expose partial advice.
      }
    }
    return FirstAidGuideLoadResult(
      guide: await _loadValidated('en'),
      usedFallback: requested != 'en',
    );
  }

  Future<FirstAidGuide> _loadValidated(String locale) async {
    final raw = await _bundle.loadString(
      'assets/first_aid/first_aid_$locale.json',
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('First-aid asset must be a JSON object');
    }
    return FirstAidGuide.fromJson(decoded, expectedLocale: locale);
  }
}
