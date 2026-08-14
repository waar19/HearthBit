import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/emergency_directory.dart';
import '../services/app_preferences.dart';
import '../services/emergency_directory_service.dart';

typedef EmergencyUriLauncher = Future<bool> Function(Uri uri);

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({
    required this.preferences,
    this.service,
    this.countryResolver,
    this.uriLauncher,
    super.key,
  });

  final AppPreferences preferences;
  final EmergencyDirectoryService? service;
  final EmergencyCountryResolver? countryResolver;
  final EmergencyUriLauncher? uriLauncher;

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  late final EmergencyDirectoryService _service;
  late final EmergencyCountryResolver _countryResolver;
  late final EmergencyUriLauncher _uriLauncher;
  Future<_EmergencyContactsViewData>? _future;
  String? _localeKey;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EmergencyDirectoryService();
    _countryResolver = widget.countryResolver ?? EmergencyCountryResolver();
    _uriLauncher =
        widget.uriLauncher ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    final key = '${locale.languageCode}-${locale.countryCode ?? ''}';
    if (_localeKey == key) return;
    _localeKey = key;
    _future = _load(locale);
  }

  Future<_EmergencyContactsViewData> _load(Locale locale) async {
    final result = await _service.load(locale.languageCode);
    final selectedCountry = await _countryResolver.resolve(
      availableCountryCodes: EmergencyDirectory.countryCodes,
      overrideCountry: widget.preferences.emergencyCountryOverride,
      localeCountry: locale.countryCode,
    );
    return _EmergencyContactsViewData(
      loadResult: result,
      selectedCountry: selectedCountry,
    );
  }

  Future<void> _selectCountry(
    String? override,
    EmergencyDirectory directory,
  ) async {
    await widget.preferences.setEmergencyCountryOverride(override);
    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    setState(() {
      if (override != null) {
        _future = Future.value(
          _EmergencyContactsViewData(
            loadResult: EmergencyDirectoryLoadResult(
              directory: directory,
              usedFallback: directory.locale != locale.languageCode,
            ),
            selectedCountry: override,
          ),
        );
      } else {
        _future = _load(locale);
      }
    });
  }

  Future<void> _open(Uri uri) async {
    var opened = false;
    try {
      opened = await _uriLauncher(uri);
    } on Object {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.emergencyContactsOpenError)),
      );
    }
  }

  void _retry() {
    setState(() {
      _future = _load(Localizations.localeOf(context));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.emergencyContactsTitle)),
    body: FutureBuilder<_EmergencyContactsViewData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(onRetry: _retry);
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _DirectoryContent(
          data: data,
          automaticSelection:
              widget.preferences.emergencyCountryOverride == null,
          onCountryChanged: (country) =>
              _selectCountry(country, data.loadResult.directory),
          onOpen: _open,
        );
      },
    ),
  );
}

class _DirectoryContent extends StatelessWidget {
  const _DirectoryContent({
    required this.data,
    required this.automaticSelection,
    required this.onCountryChanged,
    required this.onOpen,
  });

  final _EmergencyContactsViewData data;
  final bool automaticSelection;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<Uri> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final directory = data.loadResult.directory;
    final selected = directory.country(data.selectedCountry);
    final theme = Theme.of(context);
    final countries =
        directory.countries
            .where((country) => country.code != 'INT')
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));
    final selectorValue = automaticSelection ? '' : selected.code;

    return ListView(
      key: const Key('emergency-contacts-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.phone_in_talk_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.emergencyContactsSafetyNotice,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (data.loadResult.usedFallback) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.translate_outlined),
              title: Text(l10n.emergencyContactsFallback),
            ),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('emergency-country-$selectorValue'),
          initialValue: selectorValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.emergencyContactsCountry,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(l10n.emergencyContactsAutomatic(selected.name)),
            ),
            ...countries.map(
              (country) => DropdownMenuItem(
                value: country.code,
                child: Text(country.name),
              ),
            ),
            DropdownMenuItem(
              value: 'INT',
              child: Text(directory.country('INT').name),
            ),
          ],
          onChanged: (value) =>
              onCountryChanged(value == null || value.isEmpty ? null : value),
        ),
        const SizedBox(height: 16),
        Text(
          selected.name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(selected.callingNote),
        const SizedBox(height: 20),
        _SectionTitle(
          icon: Icons.emergency_outlined,
          text: l10n.emergencyContactsNumbers,
        ),
        const SizedBox(height: 8),
        ...selected.numbers.map(
          (number) => _EmergencyNumberCard(number: number, onOpen: onOpen),
        ),
        if (selected.organizations.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.account_balance_outlined,
            text: l10n.emergencyContactsOrganizations,
          ),
          const SizedBox(height: 8),
          ...selected.organizations.map(
            (organization) =>
                _OrganizationCard(organization: organization, onOpen: onOpen),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(directory.disclaimer),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const Key('emergency-contacts-sources'),
          leading: const Icon(Icons.fact_check_outlined),
          title: Text(l10n.emergencyContactsSources),
          subtitle: Text(l10n.emergencyContactsReviewed(directory.reviewedAt)),
          children: directory.sources
              .map(
                (source) => ListTile(
                  title: Text(source.title),
                  subtitle: Text(source.publisher),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => onOpen(Uri.parse(source.url)),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    ],
  );
}

class _EmergencyNumberCard extends StatelessWidget {
  const _EmergencyNumberCard({required this.number, required this.onOpen});

  final EmergencyNumber number;
  final ValueChanged<Uri> onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            number.label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          SelectableText(
            number.number,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(number.note),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => onOpen(number.telephoneUri),
            icon: const Icon(Icons.call_outlined),
            label: Text(context.l10n.emergencyContactsCall),
          ),
        ],
      ),
    ),
  );
}

class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard({required this.organization, required this.onOpen});

  final EmergencyOrganization organization;
  final ValueChanged<Uri> onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            organization.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(organization.note),
          if (organization.phone != null) ...[
            const SizedBox(height: 8),
            SelectableText(organization.phone!),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (organization.telephoneUri case final telephone?)
                FilledButton.tonalIcon(
                  onPressed: () => onOpen(telephone),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(context.l10n.emergencyContactsCall),
                ),
              OutlinedButton.icon(
                onPressed: () => onOpen(organization.websiteUri),
                icon: const Icon(Icons.open_in_new),
                label: Text(context.l10n.emergencyContactsWebsite),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            context.l10n.emergencyContactsLoadError,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10n.emergencyContactsRetry),
          ),
        ],
      ),
    ),
  );
}

class _EmergencyContactsViewData {
  const _EmergencyContactsViewData({
    required this.loadResult,
    required this.selectedCountry,
  });

  final EmergencyDirectoryLoadResult loadResult;
  final String selectedCountry;
}
