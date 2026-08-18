import 'dart:convert';

enum AuthorityAnnouncementPriority {
  info('I'),
  warning('W'),
  evacuate('E');

  const AuthorityAnnouncementPriority(this.wireCode);

  final String wireCode;

  static AuthorityAnnouncementPriority? fromWireCode(String value) {
    for (final priority in values) {
      if (priority.wireCode == value) return priority;
    }
    return null;
  }
}

class AuthorityAnnouncement {
  const AuthorityAnnouncement({
    required this.version,
    required this.announcementId,
    required this.teamId,
    required this.actorPeerId,
    required this.priority,
    required this.issuedAt,
    required this.expiresAt,
    required this.body,
    required this.callsign,
  });

  final int version;
  final String announcementId;
  final String teamId;
  final String actorPeerId;
  final AuthorityAnnouncementPriority priority;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String body;
  final String callsign;

  bool isActiveAt(DateTime now) => expiresAt.isAfter(now.toUtc());
}

abstract final class AuthorityAnnouncementCodec {
  static const String marker = '[HB-AUTH|';
  static const int version = 1;
  static const int maximumBodyBytes = 512;
  static const int maximumPayloadBytes = 1024;
  static const int maximumTimestampMilliseconds = 8640000000000000;
  static const Duration maximumLifetime = Duration(hours: 24);

  static final RegExp _announcementId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _teamId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _peerId = RegExp(r'^[0-9a-f]{16}$');
  static final RegExp _base64Url = RegExp(r'^[A-Za-z0-9_-]+$');

  static String encode(AuthorityAnnouncement announcement) {
    _validate(announcement);
    final encodedBody = base64Url
        .encode(utf8.encode(announcement.body))
        .replaceAll('=', '');
    final encoded =
        '$marker$version|${announcement.announcementId}|'
        '${announcement.teamId}|${announcement.actorPeerId}|'
        '${announcement.priority.wireCode}|'
        '${announcement.issuedAt.toUtc().millisecondsSinceEpoch}|'
        '${announcement.expiresAt.toUtc().millisecondsSinceEpoch}|'
        '$encodedBody]';
    if (utf8.encode(encoded).length > maximumPayloadBytes) {
      throw const FormatException('Authority announcement is too large');
    }
    return encoded;
  }

  static AuthorityAnnouncement? tryDecode(
    String value, {
    String callsign = '',
  }) {
    if (!value.startsWith(marker) ||
        !value.endsWith(']') ||
        utf8.encode(value).length > maximumPayloadBytes) {
      return null;
    }
    final fields = value.substring(marker.length, value.length - 1).split('|');
    if (fields.length != 8 || fields[0] != '$version') return null;
    final priority = AuthorityAnnouncementPriority.fromWireCode(fields[4]);
    final issuedAtMs = int.tryParse(fields[5]);
    final expiresAtMs = int.tryParse(fields[6]);
    if (priority == null ||
        issuedAtMs == null ||
        expiresAtMs == null ||
        fields[7].isEmpty ||
        !_base64Url.hasMatch(fields[7])) {
      return null;
    }
    try {
      final body = utf8.decode(
        base64Url.decode(base64Url.normalize(fields[7])),
        allowMalformed: false,
      );
      final announcement = AuthorityAnnouncement(
        version: version,
        announcementId: fields[1],
        teamId: fields[2],
        actorPeerId: fields[3],
        priority: priority,
        issuedAt: DateTime.fromMillisecondsSinceEpoch(issuedAtMs, isUtc: true),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          expiresAtMs,
          isUtc: true,
        ),
        body: body,
        callsign: callsign,
      );
      _validate(announcement);
      return announcement;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static void _validate(AuthorityAnnouncement announcement) {
    final issuedAt = announcement.issuedAt.toUtc();
    final expiresAt = announcement.expiresAt.toUtc();
    final issuedAtMs = issuedAt.millisecondsSinceEpoch;
    final expiresAtMs = expiresAt.millisecondsSinceEpoch;
    final bodyBytes = utf8.encode(announcement.body);
    if (announcement.version != version ||
        !_announcementId.hasMatch(announcement.announcementId) ||
        !_teamId.hasMatch(announcement.teamId) ||
        !_peerId.hasMatch(announcement.actorPeerId) ||
        announcement.body.isEmpty ||
        announcement.body != announcement.body.trim() ||
        bodyBytes.length > maximumBodyBytes ||
        issuedAtMs <= 0 ||
        issuedAtMs > maximumTimestampMilliseconds ||
        expiresAtMs <= issuedAtMs ||
        expiresAtMs > maximumTimestampMilliseconds ||
        expiresAt.difference(issuedAt) > maximumLifetime) {
      throw const FormatException('Invalid authority announcement');
    }
  }
}
