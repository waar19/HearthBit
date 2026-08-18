import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/authority_announcement_models.dart';

void main() {
  test('codifica y decodifica cuerpo UTF-8 en HB-AUTH versionado', () {
    final announcement = _announcement(body: 'Evacuar sector norte 🚨');

    final encoded = AuthorityAnnouncementCodec.encode(announcement);
    final decoded = AuthorityAnnouncementCodec.tryDecode(
      encoded,
      callsign: 'Alcaldía',
    );

    expect(encoded, startsWith('[HB-AUTH|1|'));
    expect(decoded?.announcementId, announcement.announcementId);
    expect(decoded?.priority, AuthorityAnnouncementPriority.evacuate);
    expect(decoded?.body, announcement.body);
    expect(decoded?.callsign, 'Alcaldía');
  });

  test(
    'rechaza campos alterados, duración excesiva y cuerpo sobredimensionado',
    () {
      final valid = AuthorityAnnouncementCodec.encode(_announcement());
      final fields = valid
          .substring(AuthorityAnnouncementCodec.marker.length, valid.length - 1)
          .split('|');
      final tampered = [...fields]..[3] = 'otro';

      expect(
        AuthorityAnnouncementCodec.tryDecode(
          '${AuthorityAnnouncementCodec.marker}${tampered.join('|')}]',
        ),
        isNull,
      );
      expect(
        () => AuthorityAnnouncementCodec.encode(
          _announcement(lifetime: const Duration(hours: 25)),
        ),
        throwsFormatException,
      );
      expect(
        () => AuthorityAnnouncementCodec.encode(
          _announcement(body: utf8.decode(List.filled(513, 65))),
        ),
        throwsFormatException,
      );
    },
  );
}

AuthorityAnnouncement _announcement({
  String body = 'Evacuar ahora',
  Duration lifetime = const Duration(hours: 1),
}) {
  final issuedAt = DateTime.utc(2026, 8, 18, 12);
  return AuthorityAnnouncement(
    version: AuthorityAnnouncementCodec.version,
    announcementId: '0123456789abcdef0123456789abcdef',
    teamId: 'ffeeddccbbaa99887766554433221100',
    actorPeerId: '0011223344556677',
    priority: AuthorityAnnouncementPriority.evacuate,
    issuedAt: issuedAt,
    expiresAt: issuedAt.add(lifetime),
    body: body,
    callsign: 'Alcaldía',
  );
}
