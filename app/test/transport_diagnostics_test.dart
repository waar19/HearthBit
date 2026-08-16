import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/transport_diagnostics.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('persists success and failure totals by fixed transport', () async {
    final first = TransportDiagnostics();
    first.recordSuccess(DiagnosticTransport.ble);
    first.recordSuccess(DiagnosticTransport.ble);
    first.recordFailure(DiagnosticTransport.ble);
    first.recordFailure(DiagnosticTransport.external);
    await first.flush();

    final restored = TransportDiagnostics();
    await restored.initialize();

    expect(
      restored.forTransport(DiagnosticTransport.ble),
      const TransportOutcomeCounters(successes: 2, failures: 1),
    );
    expect(
      restored.forTransport(DiagnosticTransport.external),
      const TransportOutcomeCounters(failures: 1),
    );
  });

  test('exports only aggregate counters with a closed safe schema', () async {
    final diagnostics = TransportDiagnostics();
    await diagnostics.initialize();
    diagnostics.recordSuccess(DiagnosticTransport.qr);
    diagnostics.recordFailure(DiagnosticTransport.audio);

    final exported = diagnostics.exportData();

    expect(exported, hasLength(DiagnosticTransport.values.length * 2));
    expect(exported['qrSuccess'], 1);
    expect(exported['audioFailure'], 1);
    expect(
      exported.keys,
      everyElement(
        matches(
          RegExp(
            r'^(ble|lan|wifiDirect|wifiAware|multipeer|audio|qr|external)'
            r'(Success|Failure)$',
          ),
        ),
      ),
    );
    final fieldNames = exported.keys.join(' ');
    expect(fieldNames, isNot(contains('peerId')));
    expect(fieldNames, isNot(contains('path')));
    expect(fieldNames, isNot(contains('content')));
    expect(fieldNames, isNot(contains('message')));
    expect(exported.values, everyElement(isA<int>()));
  });

  test('clear removes persisted counters', () async {
    final first = TransportDiagnostics();
    await first.initialize();
    first.recordSuccess(DiagnosticTransport.lan);
    await first.flush();
    await first.clear();

    final restored = TransportDiagnostics();
    await restored.initialize();

    expect(
      restored.forTransport(DiagnosticTransport.lan),
      const TransportOutcomeCounters(),
    );
  });
}
