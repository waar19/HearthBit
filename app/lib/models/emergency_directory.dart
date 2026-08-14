class EmergencyDirectory {
  const EmergencyDirectory({
    required this.schemaVersion,
    required this.locale,
    required this.reviewedAt,
    required this.disclaimer,
    required this.countries,
    required this.sources,
  });

  static const countryCodes = <String>{
    'INT',
    'CO',
    'US',
    'MX',
    'ES',
    'DE',
    'FR',
    'CN',
    'JP',
  };

  final int schemaVersion;
  final String locale;
  final String reviewedAt;
  final String disclaimer;
  final List<EmergencyCountry> countries;
  final List<EmergencyDirectorySource> sources;

  EmergencyCountry country(String code) {
    final normalized = code.trim().toUpperCase();
    return countries.firstWhere(
      (country) => country.code == normalized,
      orElse: () => countries.firstWhere((country) => country.code == 'INT'),
    );
  }

  factory EmergencyDirectory.fromJson(
    Map<String, Object?> json, {
    required String expectedLocale,
  }) {
    _requireExactKeys(json, const {
      'schemaVersion',
      'locale',
      'reviewedAt',
      'disclaimer',
      'countries',
      'sources',
    }, 'directory');
    final schemaVersion = _integer(json, 'schemaVersion');
    if (schemaVersion != 1) {
      throw const FormatException(
        'Unsupported emergency-directory schema version',
      );
    }
    final locale = _text(json, 'locale');
    if (locale != expectedLocale) {
      throw FormatException(
        'Directory locale "$locale" does not match "$expectedLocale"',
      );
    }
    final reviewedAt = _text(json, 'reviewedAt');
    if (DateTime.tryParse(reviewedAt) == null) {
      throw const FormatException('reviewedAt must be an ISO-8601 date');
    }
    final sources = _objects(
      json,
      'sources',
      maxLength: 80,
    ).map(EmergencyDirectorySource.fromJson).toList(growable: false);
    if (sources.isEmpty) {
      throw const FormatException('At least one source is required');
    }
    final sourceIds = sources.map((source) => source.id).toSet();
    if (sourceIds.length != sources.length) {
      throw const FormatException('Source IDs must be unique');
    }
    final countries = _objects(json, 'countries', maxLength: 20)
        .map(
          (country) =>
              EmergencyCountry.fromJson(country, allowedSourceIds: sourceIds),
        )
        .toList(growable: false);
    final countryCodes = countries.map((country) => country.code).toSet();
    if (countryCodes.length != countries.length ||
        countryCodes.length != EmergencyDirectory.countryCodes.length ||
        !countryCodes.containsAll(EmergencyDirectory.countryCodes)) {
      throw const FormatException(
        'Directory must contain every required country exactly once',
      );
    }
    return EmergencyDirectory(
      schemaVersion: schemaVersion,
      locale: locale,
      reviewedAt: reviewedAt,
      disclaimer: _text(json, 'disclaimer'),
      countries: countries,
      sources: sources,
    );
  }
}

class EmergencyCountry {
  const EmergencyCountry({
    required this.code,
    required this.name,
    required this.callingNote,
    required this.numbers,
    required this.organizations,
  });

  final String code;
  final String name;
  final String callingNote;
  final List<EmergencyNumber> numbers;
  final List<EmergencyOrganization> organizations;

  factory EmergencyCountry.fromJson(
    Map<String, Object?> json, {
    required Set<String> allowedSourceIds,
  }) {
    _requireExactKeys(json, const {
      'code',
      'name',
      'callingNote',
      'numbers',
      'organizations',
    }, 'country');
    final code = _text(json, 'code').toUpperCase();
    if (!EmergencyDirectory.countryCodes.contains(code)) {
      throw FormatException('Unknown emergency country "$code"');
    }
    final numbers = _objects(json, 'numbers', maxLength: 12)
        .map(
          (number) => EmergencyNumber.fromJson(
            number,
            allowedSourceIds: allowedSourceIds,
          ),
        )
        .toList(growable: false);
    if (numbers.isEmpty) {
      throw FormatException('Country "$code" must have emergency numbers');
    }
    final numberIds = numbers.map((number) => number.id).toSet();
    if (numberIds.length != numbers.length) {
      throw FormatException('Country "$code" has duplicate number IDs');
    }
    final organizations = _objects(json, 'organizations', maxLength: 12)
        .map(
          (organization) => EmergencyOrganization.fromJson(
            organization,
            allowedSourceIds: allowedSourceIds,
          ),
        )
        .toList(growable: false);
    final organizationIds = organizations
        .map((organization) => organization.id)
        .toSet();
    if (organizationIds.length != organizations.length) {
      throw FormatException('Country "$code" has duplicate organization IDs');
    }
    return EmergencyCountry(
      code: code,
      name: _text(json, 'name'),
      callingNote: _text(json, 'callingNote'),
      numbers: numbers,
      organizations: organizations,
    );
  }
}

class EmergencyNumber {
  const EmergencyNumber({
    required this.id,
    required this.kind,
    required this.label,
    required this.number,
    required this.note,
    required this.sourceIds,
  });

  static const kinds = <String>{'general', 'police', 'fire', 'medical'};

  final String id;
  final String kind;
  final String label;
  final String number;
  final String note;
  final List<String> sourceIds;

  Uri get telephoneUri => Uri(scheme: 'tel', path: number);

  factory EmergencyNumber.fromJson(
    Map<String, Object?> json, {
    required Set<String> allowedSourceIds,
  }) {
    _requireExactKeys(json, const {
      'id',
      'kind',
      'label',
      'number',
      'note',
      'sourceIds',
    }, 'number');
    final kind = _text(json, 'kind');
    if (!kinds.contains(kind)) {
      throw FormatException('Unknown emergency-number kind "$kind"');
    }
    final number = _text(json, 'number');
    if (!RegExp(r'^[0-9+*# -]{2,24}$').hasMatch(number)) {
      throw FormatException('Emergency number "$number" is invalid');
    }
    final sourceIds = _sourceIds(
      json,
      allowedSourceIds: allowedSourceIds,
      label: 'number',
    );
    return EmergencyNumber(
      id: _text(json, 'id'),
      kind: kind,
      label: _text(json, 'label'),
      number: number,
      note: _text(json, 'note'),
      sourceIds: sourceIds,
    );
  }
}

class EmergencyOrganization {
  const EmergencyOrganization({
    required this.id,
    required this.kind,
    required this.name,
    required this.phone,
    required this.url,
    required this.note,
    required this.sourceIds,
  });

  static const kinds = <String>{
    'disaster-management',
    'red-cross',
    'missing-persons',
  };

  final String id;
  final String kind;
  final String name;
  final String? phone;
  final String url;
  final String note;
  final List<String> sourceIds;

  Uri get websiteUri => Uri.parse(url);
  Uri? get telephoneUri =>
      phone == null ? null : Uri(scheme: 'tel', path: phone);

  factory EmergencyOrganization.fromJson(
    Map<String, Object?> json, {
    required Set<String> allowedSourceIds,
  }) {
    _requireExactKeys(json, const {
      'id',
      'kind',
      'name',
      'phone',
      'url',
      'note',
      'sourceIds',
    }, 'organization');
    final kind = _text(json, 'kind');
    if (!kinds.contains(kind)) {
      throw FormatException('Unknown emergency-organization kind "$kind"');
    }
    final phone = _nullableText(json, 'phone');
    if (phone != null && !RegExp(r'^[0-9+*#() -]{2,40}$').hasMatch(phone)) {
      throw FormatException('Organization phone "$phone" is invalid');
    }
    final url = Uri.tryParse(_text(json, 'url'));
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const FormatException('Organization URL must use HTTPS');
    }
    return EmergencyOrganization(
      id: _text(json, 'id'),
      kind: kind,
      name: _text(json, 'name'),
      phone: phone,
      url: url.toString(),
      note: _text(json, 'note'),
      sourceIds: _sourceIds(
        json,
        allowedSourceIds: allowedSourceIds,
        label: 'organization',
      ),
    );
  }
}

class EmergencyDirectorySource {
  const EmergencyDirectorySource({
    required this.id,
    required this.title,
    required this.publisher,
    required this.url,
    required this.accessed,
  });

  final String id;
  final String title;
  final String publisher;
  final String url;
  final String accessed;

  factory EmergencyDirectorySource.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'id',
      'title',
      'publisher',
      'url',
      'accessed',
    }, 'source');
    final url = Uri.tryParse(_text(json, 'url'));
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const FormatException('Source URL must use HTTPS');
    }
    final accessed = _text(json, 'accessed');
    if (DateTime.tryParse(accessed) == null) {
      throw const FormatException('Source accessed date must be ISO-8601');
    }
    return EmergencyDirectorySource(
      id: _text(json, 'id'),
      title: _text(json, 'title'),
      publisher: _text(json, 'publisher'),
      url: url.toString(),
      accessed: accessed,
    );
  }
}

void _requireExactKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String label,
) {
  final keys = json.keys.toSet();
  if (keys.length != expected.length || !keys.containsAll(expected)) {
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

String? _nullableText(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.length > 2000) {
    throw FormatException('"$key" must be null or non-empty text');
  }
  return value.trim();
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('"$key" must be an integer');
  return value;
}

List<Map<String, Object?>> _objects(
  Map<String, Object?> json,
  String key, {
  required int maxLength,
}) {
  final value = json[key];
  if (value is! List || value.length > maxLength) {
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

List<String> _strings(
  Map<String, Object?> json,
  String key, {
  int maxLength = 20,
}) {
  final value = json[key];
  if (value is! List || value.length > maxLength) {
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

List<String> _sourceIds(
  Map<String, Object?> json, {
  required Set<String> allowedSourceIds,
  required String label,
}) {
  final sourceIds = _strings(json, 'sourceIds');
  if (sourceIds.isEmpty ||
      sourceIds.any((sourceId) => !allowedSourceIds.contains(sourceId))) {
    throw FormatException('$label has invalid source references');
  }
  return sourceIds;
}
