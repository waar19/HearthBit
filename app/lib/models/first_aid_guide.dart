class FirstAidGuide {
  const FirstAidGuide({
    required this.schemaVersion,
    required this.locale,
    required this.reviewedAt,
    required this.disclaimer,
    required this.topics,
    required this.sources,
  });

  static const topicIds = <String>{
    'scene-safety',
    'unresponsive-not-breathing',
    'severe-bleeding',
    'burns',
    'choking',
    'earthquake-debris',
    'android-earthquake-alerts',
  };

  final int schemaVersion;
  final String locale;
  final String reviewedAt;
  final String disclaimer;
  final List<FirstAidTopic> topics;
  final List<FirstAidSource> sources;

  factory FirstAidGuide.fromJson(
    Map<String, Object?> json, {
    required String expectedLocale,
  }) {
    _requireExactKeys(json, const {
      'schemaVersion',
      'locale',
      'reviewedAt',
      'disclaimer',
      'topics',
      'sources',
    }, 'guide');
    final schemaVersion = _integer(json, 'schemaVersion');
    if (schemaVersion != 1) {
      throw const FormatException('Unsupported first-aid schema version');
    }
    final locale = _text(json, 'locale');
    if (locale != expectedLocale) {
      throw FormatException(
        'Guide locale "$locale" does not match "$expectedLocale"',
      );
    }
    final reviewedAt = _text(json, 'reviewedAt');
    if (DateTime.tryParse(reviewedAt) == null) {
      throw const FormatException('reviewedAt must be an ISO-8601 date');
    }
    final disclaimer = _text(json, 'disclaimer');
    final sources = _objects(
      json,
      'sources',
    ).map(FirstAidSource.fromJson).toList(growable: false);
    if (sources.isEmpty) {
      throw const FormatException('At least one source is required');
    }
    final sourceIds = sources.map((source) => source.id).toSet();
    if (sourceIds.length != sources.length) {
      throw const FormatException('Source IDs must be unique');
    }
    final topics = _objects(json, 'topics')
        .map(
          (value) => FirstAidTopic.fromJson(value, allowedSourceIds: sourceIds),
        )
        .toList(growable: false);
    final topicIds = topics.map((topic) => topic.id).toSet();
    if (topicIds.length != topics.length ||
        topicIds.length != FirstAidGuide.topicIds.length ||
        !topicIds.containsAll(FirstAidGuide.topicIds)) {
      throw const FormatException(
        'Guide must contain every required topic exactly once',
      );
    }
    return FirstAidGuide(
      schemaVersion: schemaVersion,
      locale: locale,
      reviewedAt: reviewedAt,
      disclaimer: disclaimer,
      topics: topics,
      sources: sources,
    );
  }
}

class FirstAidTopic {
  const FirstAidTopic({
    required this.id,
    required this.title,
    required this.summary,
    required this.steps,
    required this.warnings,
    required this.sourceIds,
  });

  final String id;
  final String title;
  final String summary;
  final List<String> steps;
  final List<String> warnings;
  final List<String> sourceIds;

  factory FirstAidTopic.fromJson(
    Map<String, Object?> json, {
    required Set<String> allowedSourceIds,
  }) {
    _requireExactKeys(json, const {
      'id',
      'title',
      'summary',
      'steps',
      'warnings',
      'sourceIds',
    }, 'topic');
    final id = _text(json, 'id');
    if (!FirstAidGuide.topicIds.contains(id)) {
      throw FormatException('Unknown first-aid topic "$id"');
    }
    final steps = _strings(json, 'steps');
    if (steps.isEmpty) {
      throw FormatException('Topic "$id" must have steps');
    }
    final sourceIds = _strings(json, 'sourceIds');
    if (sourceIds.isEmpty ||
        sourceIds.any((sourceId) => !allowedSourceIds.contains(sourceId))) {
      throw FormatException('Topic "$id" has invalid source references');
    }
    return FirstAidTopic(
      id: id,
      title: _text(json, 'title'),
      summary: _text(json, 'summary'),
      steps: steps,
      warnings: _strings(json, 'warnings'),
      sourceIds: sourceIds,
    );
  }
}

class FirstAidSource {
  const FirstAidSource({
    required this.id,
    required this.title,
    required this.publisher,
    required this.url,
    required this.published,
  });

  final String id;
  final String title;
  final String publisher;
  final String url;
  final String published;

  factory FirstAidSource.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'id',
      'title',
      'publisher',
      'url',
      'published',
    }, 'source');
    final url = Uri.tryParse(_text(json, 'url'));
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const FormatException('Source URL must use HTTPS');
    }
    return FirstAidSource(
      id: _text(json, 'id'),
      title: _text(json, 'title'),
      publisher: _text(json, 'publisher'),
      url: url.toString(),
      published: _text(json, 'published'),
    );
  }
}

void _requireExactKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String label,
) {
  if (json.keys.toSet().length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw FormatException('$label has missing or unknown fields');
  }
}

String _text(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > 2000) {
    throw FormatException('"$key" must be non-empty text');
  }
  return value.trim();
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('"$key" must be an integer');
  return value;
}

List<Map<String, Object?>> _objects(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.length > 20) {
    throw FormatException('"$key" must be a bounded list');
  }
  return value
      .map((item) {
        if (item is! Map<String, Object?>) {
          throw FormatException('"$key" contains an invalid item');
        }
        return item;
      })
      .toList(growable: false);
}

List<String> _strings(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.length > 20) {
    throw FormatException('"$key" must be a bounded list');
  }
  return value
      .map((item) {
        if (item is! String || item.trim().isEmpty || item.length > 1000) {
          throw FormatException('"$key" contains invalid text');
        }
        return item.trim();
      })
      .toList(growable: false);
}
