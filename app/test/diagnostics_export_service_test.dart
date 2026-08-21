import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/diagnostics_export_service.dart';
import 'package:hearth_bit/services/diagnostics_log.dart';

void main() {
  test('includes aggregate operational counters without identities', () {
    final log = DiagnosticsLog(persist: false);
    final service = DiagnosticsExportService(
      log: log,
      share: (_) async => throw StateError('share must not run'),
    );

    service.includeOperationalCounters({
      'openEmergencyRateLimitedKnown': 2,
      'openEmergencyRateLimitedUnknown': 5,
      'relayDampingSuppressed': 3,
      'relayDampingScheduled': 8,
      'relayDampingExpired': 7,
      'trustStoreEvictions': 1,
      'trustConflicts': 4,
    }, lifetime: 'process');
    service.includeSosMetrics(
      const SosOperationalMetrics(
        sosCreated: 4,
        sosRelayedLocal: 3,
        sosAckReceived: 2,
        sosAckCount: 5,
        sosExpired: 1,
        sosDeliveryLatencyMs: 1200,
      ),
    );

    final exported = log.exportText();
    expect(exported, contains('diagnostics.operational_counters'));
    expect(exported, contains('"operationalCountersLifetime":"process"'));
    expect(exported, contains('"openEmergencyRateLimitedKnown":2'));
    expect(exported, isNot(contains('openSosRateLimitedKnown')));
    expect(exported, contains('"trustConflicts":4'));
    expect(exported, contains('diagnostics.sos_metrics'));
    expect(exported, contains('"scope":"retained_outbox"'));
    expect(exported, contains('"sosDeliveryLatencyMs":1200'));
    expect(exported, contains('"firstRelayObserved":"unavailable"'));
    expect(exported, contains('"relayStateMeaning":"local_native_tx"'));
    expect(exported, contains('"hopCount":"unavailable"'));
    expect(exported, contains('"hopCountReason":"ttl_reset_and_unsigned"'));
    expect(exported, isNot(contains('"firstRelayObserved":0')));
    expect(exported, isNot(contains('"hopCount":0')));
    expect(exported, isNot(contains('"hopCount":7')));
    expect(exported, isNot(contains('peerId')));
    expect(exported, isNot(contains('senderId')));
  });
}
