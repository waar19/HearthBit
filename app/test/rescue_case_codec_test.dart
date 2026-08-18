import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/rescue_case_models.dart';

void main() {
  const hash =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const actor = '0011223344556677';
  const team = '00112233445566778899aabbccddeeff';

  test('codifica y decodifica una actualización compacta versionada', () {
    final update = RescueCaseUpdate(
      teamId: team,
      caseHash: hash,
      previousState: RescueCaseState.newCase,
      state: RescueCaseState.assigned,
      actorPeerId: actor,
      assigneePeerId: actor,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        1700000000000,
        isUtc: true,
      ),
    );

    final encoded = RescueCaseUpdateCodec.encode(update);
    final decoded = RescueCaseUpdateCodec.tryDecode(encoded);

    expect(encoded, '[HB-CASE|2|$team|$hash|N|A|$actor|$actor|1700000000000]');
    expect(decoded?.eventId, update.eventId);
  });

  test('rechaza versión, hash, actor, estado y timestamp malformados', () {
    final valid = '[HB-CASE|2|$team|$hash|N|A|$actor|$actor|1700000000000]';
    expect(
      RescueCaseUpdateCodec.tryDecode(valid.replaceFirst('|2|', '|1|')),
      isNull,
    );
    expect(
      RescueCaseUpdateCodec.tryDecode(valid.replaceFirst(hash, 'abc')),
      isNull,
    );
    expect(
      RescueCaseUpdateCodec.tryDecode(valid.replaceFirst(actor, 'peer')),
      isNull,
    );
    expect(
      RescueCaseUpdateCodec.tryDecode(valid.replaceFirst('|A|', '|X|')),
      isNull,
    );
    expect(
      RescueCaseUpdateCodec.tryDecode(
        valid.replaceFirst('1700000000000', '-1'),
      ),
      isNull,
    );
    expect(
      RescueCaseUpdateCodec.tryDecode(
        '[HB-CASE|2|$team|$hash|N|N|$actor|$actor|1700000000000]',
      ),
      isNull,
    );
  });
}
