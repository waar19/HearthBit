import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/invite_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test('centraliza los enlaces públicos de HearthBit', () {
    expect(
      InviteShareService.repositoryUri,
      Uri.parse('https://github.com/waar19/HearthBit'),
    );
    expect(
      InviteShareService.donationUri,
      Uri.parse('https://buymeacoffee.com/wilmeralzal'),
    );
  });

  test('comparte la invitación con anclaje seguro para iPad', () async {
    ShareParams? captured;

    final result = await InviteShareService.share(
      anchor: null,
      message: 'Join HearthBit',
      subject: 'HearthBit',
      invoke: (params) async {
        captured = params;
        return ShareResult.unavailable;
      },
    );

    expect(result, ShareResult.unavailable);
    expect(captured?.text, 'Join HearthBit');
    expect(captured?.subject, 'HearthBit');
    expect(captured?.title, 'HearthBit');
    expect(captured?.sharePositionOrigin, const Rect.fromLTWH(0, 0, 1, 1));
  });
}
