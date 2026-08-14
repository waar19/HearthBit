import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum DiagnosticLevel { info, warning, error }

class DiagnosticEntry {
  const DiagnosticEntry({
    required this.timestamp,
    required this.level,
    required this.event,
    this.errorType,
    this.stackFrames = const [],
    this.data = const {},
  });

  factory DiagnosticEntry.fromJson(Map<String, Object?> json) {
    return DiagnosticEntry(
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      level: DiagnosticLevel.values.firstWhere(
        (level) => level.name == json['level'],
        orElse: () => DiagnosticLevel.info,
      ),
      event: json['event'] as String? ?? 'unknown',
      errorType: json['errorType'] as String?,
      stackFrames: switch (json['stackFrames']) {
        final List<Object?> values => values.whereType<String>().toList(),
        _ => const [],
      },
      data: switch (json['data']) {
        final Map<Object?, Object?> values => {
          for (final entry in values.entries)
            if (entry.key is String) entry.key! as String: entry.value,
        },
        _ => const {},
      },
    );
  }

  final DateTime timestamp;
  final DiagnosticLevel level;
  final String event;
  final String? errorType;
  final List<String> stackFrames;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'event': event,
    if (errorType != null) 'errorType': errorType,
    if (stackFrames.isNotEmpty) 'stackFrames': stackFrames,
    if (data.isNotEmpty) 'data': data,
  };
}

/// Registro local y acotado para diagnosticar fallos de campo sin telemetría.
///
/// La API descarta valores sensibles conocidos y nunca serializa `error` con
/// `toString()`: solo conserva su tipo. Los llamadores deben usar códigos de
/// evento estables y datos operativos no identificables.
class DiagnosticsLog {
  DiagnosticsLog({
    this.maximumEntries = 500,
    this.maximumFileBytes = 256 * 1024,
    this.persist = true,
    DateTime Function()? clock,
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : _clock = clock ?? DateTime.now,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static final DiagnosticsLog instance = DiagnosticsLog();

  static const _fileName = 'hearthbit-diagnostics.jsonl';
  static const _forbiddenKeys = <String>{
    'content',
    'coordinate',
    'identity',
    'key',
    'latitude',
    'longitude',
    'message',
    'nickname',
    'payload',
    'peer',
    'private',
    'secret',
    'token',
  };

  final int maximumEntries;
  final int maximumFileBytes;
  final bool persist;
  final DateTime Function() _clock;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final ListQueue<DiagnosticEntry> _entries = ListQueue();

  Future<void>? _initialization;
  Future<void> _pendingWrite = Future.value();
  File? _file;

  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (!persist) return;
    try {
      final directory = await _supportDirectory();
      await directory.create(recursive: true);
      _file = File(p.join(directory.path, _fileName));
      final restored = <DiagnosticEntry>[];
      if (await _file!.exists()) {
        final lines = await _file!.readAsLines();
        for (final line in lines.skip(
          lines.length > maximumEntries ? lines.length - maximumEntries : 0,
        )) {
          try {
            final decoded = jsonDecode(line);
            if (decoded is Map<String, Object?>) {
              restored.add(DiagnosticEntry.fromJson(decoded));
            } else if (decoded is Map) {
              restored.add(
                DiagnosticEntry.fromJson(
                  decoded.map((key, value) => MapEntry(key.toString(), value)),
                ),
              );
            }
          } on FormatException {
            // Una línea dañada no debe impedir que la app arranque.
          }
        }
      }
      final recordedDuringInitialization = _entries.toList(growable: false);
      _entries
        ..clear()
        ..addAll(restored)
        ..addAll(recordedDuringInitialization);
      _trim();
      if (_entries.isNotEmpty) await _rewrite();
    } on Object {
      // El diagnóstico es best-effort y nunca debe bloquear HearthBit.
      _file = null;
    }
  }

  void info(String event, {Map<String, Object?> data = const {}}) {
    _record(DiagnosticLevel.info, event, data: data);
  }

  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    _record(
      DiagnosticLevel.warning,
      event,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
  }

  void error(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    _record(
      DiagnosticLevel.error,
      event,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
  }

  void _record(
    DiagnosticLevel level,
    String event, {
    Object? error,
    StackTrace? stackTrace,
    required Map<String, Object?> data,
  }) {
    final entry = DiagnosticEntry(
      timestamp: _clock().toUtc(),
      level: level,
      event: _safeEvent(event),
      errorType: error?.runtimeType.toString(),
      stackFrames: _safeStack(stackTrace),
      data: _safeData(data),
    );
    _entries.add(entry);
    _trim();
    _scheduleAppend(entry);
  }

  void _trim() {
    while (_entries.length > maximumEntries) {
      _entries.removeFirst();
    }
  }

  void _scheduleAppend(DiagnosticEntry entry) {
    final file = _file;
    if (file == null) return;
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await file.writeAsString(
          '${jsonEncode(entry.toJson())}\n',
          mode: FileMode.append,
          flush: entry.level == DiagnosticLevel.error,
        );
        if (await file.length() > maximumFileBytes) await _rewrite();
      } on Object {
        // No se encadenan errores de diagnóstico hacia la aplicación.
      }
    });
  }

  Future<void> _rewrite() async {
    final file = _file;
    if (file == null) return;
    final contents = _entries
        .map((entry) => jsonEncode(entry.toJson()))
        .join('\n');
    await file.writeAsString(
      contents.isEmpty ? '' : '$contents\n',
      flush: true,
    );
  }

  Future<void> flush() async {
    await initialize();
    await _pendingWrite;
  }

  String exportText() {
    final buffer = StringBuffer()
      ..writeln('HearthBit diagnostics')
      ..writeln('Privacy: no messages, identities, keys, or GPS coordinates.')
      ..writeln();
    for (final entry in _entries) {
      buffer.writeln(jsonEncode(entry.toJson()));
    }
    return buffer.toString();
  }

  Future<File> createExportFile() async {
    await flush();
    final directory = await _temporaryDirectory();
    final timestamp = _clock().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final file = File(
      p.join(directory.path, 'hearthbit-diagnostics-$timestamp.txt'),
    );
    await file.writeAsString(exportText(), flush: true);
    return file;
  }

  static String _safeEvent(String event) {
    final sanitized = event.replaceAll(RegExp('[^a-zA-Z0-9_.-]'), '_');
    return sanitized.substring(
      0,
      sanitized.length > 80 ? 80 : sanitized.length,
    );
  }

  static Map<String, Object?> _safeData(Map<String, Object?> data) {
    final sanitized = <String, Object?>{};
    for (final entry in data.entries) {
      final normalizedKey = entry.key.toLowerCase();
      if (_forbiddenKeys.any(normalizedKey.contains)) continue;
      final value = entry.value;
      if (value is bool || value is int || value is double) {
        sanitized[entry.key] = value;
      } else if (value is Enum) {
        sanitized[entry.key] = value.name;
      } else if (value is String) {
        sanitized[entry.key] = value
            .replaceAll(RegExp(r'[\r\n]'), ' ')
            .substring(0, value.length > 80 ? 80 : value.length);
      }
    }
    return sanitized;
  }

  static List<String> _safeStack(StackTrace? stackTrace) {
    if (stackTrace == null) return const [];
    return stackTrace
        .toString()
        .split('\n')
        .where((line) => line.contains('package:hearth_bit/'))
        .take(8)
        .map((line) => line.trim())
        .toList(growable: false);
  }
}
