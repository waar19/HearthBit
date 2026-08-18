import 'package:flutter_test/flutter_test.dart';

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
      'openSosRateLimitedKnown': 2,
      'openSosRateLimitedUnknown': 5,
      'relayDampingSuppressed': 3,
      'relayDampingScheduled': 8,
      'relayDampingExpired': 7,
      'trustStoreEvictions': 1,
      'trustConflicts': 4,
    });

    final exported = log.exportText();
    expect(exported, contains('diagnostics.operational_counters'));
    expect(exported, contains('"trustConflicts":4'));
    expect(exported, isNot(contains('peerId')));
    expect(exported, isNot(contains('senderId')));
  });
}
