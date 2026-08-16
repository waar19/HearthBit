import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DiagnosticTransport {
  ble,
  lan,
  wifiDirect,
  wifiAware,
  multipeer,
  audio,
  qr,
  external,
}

@immutable
class TransportOutcomeCounters {
  const TransportOutcomeCounters({this.successes = 0, this.failures = 0});

  final int successes;
  final int failures;

  TransportOutcomeCounters copyWith({int? successes, int? failures}) =>
      TransportOutcomeCounters(
        successes: successes ?? this.successes,
        failures: failures ?? this.failures,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportOutcomeCounters &&
          successes == other.successes &&
          failures == other.failures;

  @override
  int get hashCode => Object.hash(successes, failures);
}

/// Totales operativos locales por transporte.
///
/// El esquema es cerrado y solo persiste enteros. No acepta identificadores,
/// rutas, contenido ni metadatos libres que puedan contener PII.
class TransportDiagnostics extends ChangeNotifier {
  factory TransportDiagnostics({SharedPreferencesAsync? preferences}) =>
      TransportDiagnostics._(preferences);

  TransportDiagnostics._(this._preferences);

  static final TransportDiagnostics instance = TransportDiagnostics();

  static const _prefix = 'diagnostics.transport.v1';
  static const _maximumCounter = 0x7fffffffffffffff;

  SharedPreferencesAsync? _preferences;
  final Map<DiagnosticTransport, TransportOutcomeCounters> _counters = {
    for (final transport in DiagnosticTransport.values)
      transport: const TransportOutcomeCounters(),
  };

  Future<void>? _initialization;
  Future<void> _pendingWrite = Future.value();

  Map<DiagnosticTransport, TransportOutcomeCounters> get counters =>
      Map.unmodifiable(_counters);

  TransportOutcomeCounters forTransport(DiagnosticTransport transport) =>
      _counters[transport]!;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    for (final transport in DiagnosticTransport.values) {
      final storedSuccesses = await _readCounter(
        _key(transport, successful: true),
      );
      final storedFailures = await _readCounter(
        _key(transport, successful: false),
      );
      final current = _counters[transport]!;
      _counters[transport] = TransportOutcomeCounters(
        successes: _safeAdd(storedSuccesses, current.successes),
        failures: _safeAdd(storedFailures, current.failures),
      );
    }
    notifyListeners();
  }

  Future<int> _readCounter(String key) async {
    try {
      final value = await _storage.getInt(key);
      return value == null || value < 0 ? 0 : value;
    } on Object {
      return 0;
    }
  }

  void recordSuccess(DiagnosticTransport transport) {
    final current = _counters[transport]!;
    final next = _safeAdd(current.successes, 1);
    _counters[transport] = current.copyWith(successes: next);
    notifyListeners();
    _persist(transport, successful: true);
  }

  void recordFailure(DiagnosticTransport transport) {
    final current = _counters[transport]!;
    final next = _safeAdd(current.failures, 1);
    _counters[transport] = current.copyWith(failures: next);
    notifyListeners();
    _persist(transport, successful: false);
  }

  Map<String, int> exportData() => {
    for (final transport in DiagnosticTransport.values) ...{
      '${transport.name}Success': _counters[transport]!.successes,
      '${transport.name}Failure': _counters[transport]!.failures,
    },
  };

  void _persist(DiagnosticTransport transport, {required bool successful}) {
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await initialize();
        final counters = _counters[transport]!;
        await _storage.setInt(
          _key(transport, successful: successful),
          successful ? counters.successes : counters.failures,
        );
      } on Object {
        // El diagnóstico es best-effort y nunca altera el flujo principal.
      }
    });
  }

  Future<void> flush() async {
    await initialize();
    await _pendingWrite;
  }

  Future<void> clear() async {
    await initialize();
    await _pendingWrite;
    for (final transport in DiagnosticTransport.values) {
      _counters[transport] = const TransportOutcomeCounters();
      try {
        await _storage.remove(_key(transport, successful: true));
        await _storage.remove(_key(transport, successful: false));
      } on Object {
        // El borrado de diagnóstico también es best-effort.
      }
    }
    notifyListeners();
  }

  static int _safeAdd(int left, int right) {
    if (left >= _maximumCounter - right) return _maximumCounter;
    return left + right;
  }

  static String _key(
    DiagnosticTransport transport, {
    required bool successful,
  }) => '$_prefix.${transport.name}.${successful ? 'success' : 'failure'}';

  SharedPreferencesAsync get _storage =>
      _preferences ??= SharedPreferencesAsync();
}
