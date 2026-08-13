import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/first_aid_guide.dart';
import '../services/first_aid_guide_service.dart';

class FirstAidGuideScreen extends StatefulWidget {
  const FirstAidGuideScreen({
    this.service = const FirstAidGuideService(),
    super.key,
  });

  final FirstAidGuideService service;

  @override
  State<FirstAidGuideScreen> createState() => _FirstAidGuideScreenState();
}

class _FirstAidGuideScreenState extends State<FirstAidGuideScreen> {
  Future<FirstAidGuideLoadResult>? _guide;
  String? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (_locale != locale) {
      _locale = locale;
      _guide = widget.service.load(locale);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.firstAidTitle)),
      body: Column(
        children: [
          const _PersistentDisclaimer(),
          Expanded(
            child: FutureBuilder<FirstAidGuideLoadResult>(
              future: _guide,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _LoadError(
                    onRetry: () => setState(() {
                      _guide = widget.service.load(_locale ?? 'en');
                    }),
                  );
                }
                final result = snapshot.requireData;
                return _GuideList(result: result);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersistentDisclaimer extends StatelessWidget {
  const _PersistentDisclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: context.l10n.firstAidDisclaimer,
      child: Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.firstAidDisclaimer,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideList extends StatelessWidget {
  const _GuideList({required this.result});

  final FirstAidGuideLoadResult result;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('first-aid-topic-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (result.usedFallback) ...[
          Semantics(
            container: true,
            child: Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.l10n.firstAidEnglishFallback),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          context.l10n.firstAidChooseTopic,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final topic in result.guide.topics)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              button: true,
              label: '${topic.title}. ${topic.summary}',
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                minVerticalPadding: 12,
                leading: Icon(_topicIcon(topic.id), size: 32),
                title: Text(
                  topic.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(topic.summary),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        FirstAidTopicScreen(guide: result.guide, topic: topic),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        _SourceMetadata(guide: result.guide),
      ],
    );
  }
}

class FirstAidTopicScreen extends StatelessWidget {
  const FirstAidTopicScreen({
    required this.guide,
    required this.topic,
    super.key,
  });

  final FirstAidGuide guide;
  final FirstAidTopic topic;

  @override
  Widget build(BuildContext context) {
    final sources = guide.sources
        .where((source) => topic.sourceIds.contains(source.id))
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(topic.title)),
      body: Column(
        children: [
          const _PersistentDisclaimer(),
          Expanded(
            child: ListView(
              key: const Key('first-aid-topic-detail'),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                Text(
                  topic.summary,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                Text(
                  context.l10n.firstAidSteps,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < topic.steps.length; index++)
                  _NumberedStep(number: index + 1, text: topic.steps[index]),
                if (topic.warnings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.firstAidWarnings,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final warning in topic.warnings) _Warning(text: warning),
                ],
                const SizedBox(height: 20),
                _SourceMetadata(guide: guide, sources: sources),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '$number. $text',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: Text(
                '$number',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceMetadata extends StatelessWidget {
  const _SourceMetadata({required this.guide, this.sources});

  final FirstAidGuide guide;
  final List<FirstAidSource>? sources;

  @override
  Widget build(BuildContext context) {
    final displayedSources = sources ?? guide.sources;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(context.l10n.firstAidSources),
      subtitle: Text(context.l10n.firstAidReviewed(guide.reviewedAt)),
      children: [
        for (final source in displayedSources)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(source.title),
            subtitle: SelectableText(
              '${source.publisher} · ${source.published}\n${source.url}',
            ),
          ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(context.l10n.firstAidLoadError, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.actionRetry),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _topicIcon(String id) {
  return switch (id) {
    'scene-safety' => Icons.health_and_safety_outlined,
    'unresponsive-not-breathing' => Icons.monitor_heart_outlined,
    'severe-bleeding' => Icons.bloodtype_outlined,
    'burns' => Icons.local_fire_department_outlined,
    'choking' => Icons.air,
    'earthquake-debris' => Icons.landslide_outlined,
    _ => Icons.medical_services_outlined,
  };
}
