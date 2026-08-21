import 'package:hearth_bit/models/anchor_admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

AnchorAdminStatus _status({
  int received = 0,
  int forwarded = 0,
  int deduplicated = 0,
  int rejected = 0,
  int mailboxUsed = 0,
  int mailboxCapacity = 100,
  int? freeHeap,
  int? minFreeHeap,
}) {
  return AnchorAdminStatus(
    claimed: true,
    firmwareVersion: 7,
    protocolVersion: 1,
    uptimeMs: 1000,
    bootCount: 1,
    packetsReceived: received,
    packetsForwarded: forwarded,
    packetsStored: 0,
    packetsDelivered: 0,
    packetsDeduplicated: deduplicated,
    packetsExpired: 0,
    packetsRejected: rejected,
    lastActivityUptimeMs: 1000,
    mailboxUsed: mailboxUsed,
    mailboxCapacity: mailboxCapacity,
    mailboxAvailable: true,
    clockValid: true,
    clockAuthoritative: true,
    nickname: 'Anchor',
    freeHeap: freeHeap,
    minFreeHeap: minFreeHeap,
  );
}

void main() {
  test('calcula deltas y conserva mediciones directas', () {
    final history = AnchorActivityHistory();
    history.add(
      _status(received: 10, forwarded: 4, deduplicated: 2, rejected: 1),
    );
    history.add(
      _status(
        received: 15,
        forwarded: 7,
        deduplicated: 6,
        rejected: 3,
        mailboxUsed: 25,
        freeHeap: 512000,
        minFreeHeap: 480000,
      ),
    );

    final sample = history.samples.last;
    expect(sample.received, 5);
    expect(sample.forwarded, 3);
    expect(sample.deduplicated, 4);
    expect(sample.rejected, 2);
    expect(sample.mailboxPercent, 25);
    expect(sample.freeHeap, 512000);
    expect(sample.minFreeHeap, 480000);
  });

  test('satura deltas a cero cuando los contadores se reinician', () {
    final history = AnchorActivityHistory();
    history.add(_status(received: 100, forwarded: 50, rejected: 20));
    history.add(_status(received: 2, forwarded: 1, rejected: 0));

    final sample = history.samples.last;
    expect(sample.received, 0);
    expect(sample.forwarded, 0);
    expect(sample.rejected, 0);
  });

  test('descarta las muestras más antiguas al alcanzar la capacidad', () {
    final history = AnchorActivityHistory(capacity: 2);
    history.add(_status(received: 1));
    history.add(_status(received: 3));
    history.add(_status(received: 6));

    expect(history.samples, hasLength(2));
    expect(history.samples.first.received, 2);
    expect(history.samples.last.received, 3);
  });
}
