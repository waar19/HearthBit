import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/diagnostics_log.dart';

class _SensitiveError implements Exception {
  @override
  String toString() => 'message=help peer=alice latitude=4.6 key=secret';
}

void main() {
  test('keeps a bounded ring buffer', () {
    var second = 0;
    final log = DiagnosticsLog(
      maximumEntries: 2,
      persist: false,
      clock: () => DateTime.utc(2026, 8, 13, 12, 0, second++),
    );

    log.info('mesh.started');
    log.info('mesh.active');
    log.warning('mesh.degraded');

    expect(log.entries.map((entry) => entry.event), [
      'mesh.active',
      'mesh.degraded',
    ]);
  });

  test('does not export messages, identities, keys, coordinates or errors', () {
    final log = DiagnosticsLog(persist: false);
    log.error(
      'flutter uncaught',
      error: _SensitiveError(),
      stackTrace: StackTrace.fromString(
        '#0 package:hearth_bit/controllers/mesh_controller.dart:1:1\n'
        '#1 file:///C:/Users/person/private.dart:2:2',
      ),
      data: {
        'message': 'help',
        'peerId': 'alice',
        'latitude': 4.6,
        'keyMaterial': 'secret',
        'macAddress': 'AA:BB:CC:DD:EE:FF',
        'senderId': 'sender-sensitive',
        'recipient': '+56912345678',
        'status': 'degraded',
      },
    );

    final exported = log.exportText();
    expect(exported, contains('_SensitiveError'));
    expect(exported, contains('flutter_uncaught'));
    expect(exported, contains('"status":"degraded"'));
    expect(exported, isNot(contains('help')));
    expect(exported, isNot(contains('alice')));
    expect(exported, isNot(contains('4.6')));
    expect(exported, isNot(contains('secret')));
    expect(exported, isNot(contains('AA:BB')));
    expect(exported, isNot(contains('sender-sensitive')));
    expect(exported, isNot(contains('+569')));
    expect(exported, isNot(contains('Users/person')));
  });

  test('persists and restores only the bounded recent entries', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hearthbit-diagnostics-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    Future<Directory> directoryProvider() async => directory;
    final first = DiagnosticsLog(
      maximumEntries: 2,
      supportDirectory: directoryProvider,
      temporaryDirectory: directoryProvider,
    );
    await first.initialize();
    first.info('first');
    first.info('second');
    first.info('third');
    await first.flush();

    final restored = DiagnosticsLog(
      maximumEntries: 2,
      supportDirectory: directoryProvider,
      temporaryDirectory: directoryProvider,
    );
    await restored.initialize();

    expect(restored.entries.map((entry) => entry.event), ['second', 'third']);
    final exported = await restored.createExportFile();
    expect(await exported.readAsString(), contains('third'));
  });

  test('panic clear removes persisted and exported diagnostics', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hearthbit-diagnostics-wipe-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    Future<Directory> directoryProvider() async => directory;
    final log = DiagnosticsLog(
      supportDirectory: directoryProvider,
      temporaryDirectory: directoryProvider,
    );
    await log.initialize();
    log.warning('before.wipe');
    final export = await log.createExportFile();
    expect(await export.exists(), isTrue);

    await log.clear();

    expect(log.entries, isEmpty);
    expect(await export.exists(), isFalse);
    final restored = DiagnosticsLog(
      supportDirectory: directoryProvider,
      temporaryDirectory: directoryProvider,
    );
    await restored.initialize();
    expect(restored.entries, isEmpty);
  });
}
