import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/authority_announcement_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/models/authority_announcement_models.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';

const _team = 'ffeeddccbbaa99887766554433221100';
const _otherTeam = '00112233445566778899aabbccddeeff';
const _authority = '0011223344556677';
const _responder = '8899aabbccddeeff';

class _Mesh extends MeshController {
  final List<MeshMessage> storedMessages = [];
  String? sentContent;
  String? sentChannel;

  @override
  List<MeshMessage> get messages => List.unmodifiable(storedMessages);

  @override
  Future<String?> sendPublic(String content, {String? channel}) async {
    sentContent = content;
    sentChannel = channel;
    return 'sent-message';
  }

  void emit(MeshMessage message) {
    storedMessages.add(message);
    notifyListeners();
  }
}

class _Roster extends RescueRosterController {
  _Roster({required super.mesh, required this.current}) {
    loading = false;
  }

  RescueTeamRoster? current;

  @override
  RescueTeamRoster? get activeRoster => current;

  @override
  List<RescueRosterMember> get members =>
      current?.members ?? const <RescueRosterMember>[];

  void activate(RescueTeamRoster? roster) {
    current = roster;
    notifyListeners();
  }
}

void main() {
  test('rechaza rol, equipo, actor y expiración; deduplica por ID', () async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final mesh = _Mesh();
    final roster = _Roster(mesh: mesh, current: _roster());
    final controller = AuthorityAnnouncementController(
      mesh: mesh,
      roster: roster,
      now: () => now,
    );
    await controller.initialize();

    mesh.emit(
      _message(
        id: 'not-authority',
        sender: _responder,
        announcement: _announcement(actor: _responder, issuedAt: now),
      ),
    );
    mesh.emit(
      _message(
        id: 'team-mismatch',
        sender: _authority,
        announcement: _announcement(team: _otherTeam, issuedAt: now),
      ),
    );
    mesh.emit(
      _message(
        id: 'actor-mismatch',
        sender: _responder,
        announcement: _announcement(issuedAt: now),
      ),
    );
    mesh.emit(
      _message(
        id: 'expired',
        sender: _authority,
        announcement: _announcement(
          issuedAt: now.subtract(const Duration(hours: 2)),
          lifetime: const Duration(hours: 1),
        ),
      ),
    );
    mesh.emit(
      _message(
        id: 'excessive-future',
        sender: _authority,
        announcement: _announcement(
          issuedAt: now.add(const Duration(minutes: 6)),
        ),
      ),
    );
    final accepted = _announcement(issuedAt: now);
    mesh.emit(
      _message(id: 'accepted', sender: _authority, announcement: accepted),
    );
    mesh.emit(
      _message(id: 'duplicate', sender: _authority, announcement: accepted),
    );
    mesh.emit(
      _message(
        id: 'external',
        sender: _authority,
        announcement: _announcement(
          issuedAt: now,
          announcementId: 'fedcba9876543210fedcba9876543210',
          body: 'No debe aceptarse',
        ),
        external: true,
      ),
    );
    await _settle();

    expect(controller.announcements, hasLength(1));
    expect(controller.activeAnnouncement?.body, 'Orden oficial');

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });

  test('emite localmente solo con rol authority en canal firmado', () async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final key = Uint8List.fromList(List.generate(32, (index) => index + 1));
    final mesh = _Mesh()
      ..peerId = _authority
      ..signingPublicKey = key;
    final roster = _Roster(
      mesh: mesh,
      current: _roster(authorityKey: key),
    );
    final controller = AuthorityAnnouncementController(
      mesh: mesh,
      roster: roster,
      secureRandom: Random(4),
      now: () => now,
    );
    await controller.initialize();

    final result = await controller.issue(
      priority: AuthorityAnnouncementPriority.warning,
      body: '  Evitar puente central  ',
      lifetime: const Duration(minutes: 15),
    );

    expect(controller.canIssue, isTrue);
    expect(mesh.sentChannel, AuthorityAnnouncementController.channel);
    expect(mesh.sentContent, startsWith(AuthorityAnnouncementCodec.marker));
    expect(result.body, 'Evitar puente central');
    expect(controller.announcements, [same(result)]);

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });

  test('reintenta el anuncio aunque no haya roster activo', () async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final mesh = _Mesh();
    final roster = _Roster(mesh: mesh, current: null)..loading = false;
    final controller = AuthorityAnnouncementController(
      mesh: mesh,
      roster: roster,
      now: () => now,
    );
    await controller.initialize();
    mesh.emit(
      _message(
        id: 'pending-roster',
        sender: _authority,
        announcement: _announcement(issuedAt: now),
      ),
    );
    await _settle();
    expect(controller.announcements, isEmpty);

    roster.activate(_roster());
    await _settle();
    expect(controller.announcements, hasLength(1));

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });

  test('reprocesa anuncio de A recibido mientras B está activo', () async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final mesh = _Mesh();
    final roster = _Roster(
      mesh: mesh,
      current: _roster(teamId: _otherTeam),
    );
    final controller = AuthorityAnnouncementController(
      mesh: mesh,
      roster: roster,
      now: () => now,
    );
    await controller.initialize();
    mesh.emit(
      _message(
        id: 'team-a-under-b',
        sender: _authority,
        announcement: _announcement(issuedAt: now),
      ),
    );
    await _settle();
    expect(controller.announcements, isEmpty);

    roster.activate(_roster());
    await _settle();
    expect(controller.announcements, hasLength(1));

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

MeshMessage _message({
  required String id,
  required String sender,
  required AuthorityAnnouncement announcement,
  bool external = false,
}) => MeshMessage(
  id: id,
  sender: 'Origen',
  content: AuthorityAnnouncementCodec.encode(announcement),
  senderPeerId: sender,
  isPrivate: false,
  isMine: false,
  timestamp: announcement.issuedAt,
  channel: AuthorityAnnouncementController.channel,
  external: external,
);

AuthorityAnnouncement _announcement({
  String actor = _authority,
  String team = _team,
  required DateTime issuedAt,
  Duration lifetime = const Duration(hours: 1),
  String announcementId = '0123456789abcdef0123456789abcdef',
  String body = 'Orden oficial',
}) => AuthorityAnnouncement(
  version: AuthorityAnnouncementCodec.version,
  announcementId: announcementId,
  teamId: team,
  actorPeerId: actor,
  priority: AuthorityAnnouncementPriority.evacuate,
  issuedAt: issuedAt,
  expiresAt: issuedAt.add(lifetime),
  body: body,
  callsign: 'Autoridad',
);

RescueTeamRoster _roster({Uint8List? authorityKey, String teamId = _team}) =>
    RescueTeamRoster(
      teamId: teamId,
      name: 'Equipo',
      createdAt: DateTime.utc(2026),
      leaderPeerId: '7777777777777777',
      members: [
        RescueRosterMember(
          peerId: '7777777777777777',
          callsign: 'Líder',
          role: RescueRosterRole.leader,
          signingPublicKey: Uint8List(32),
        ),
        RescueRosterMember(
          peerId: _authority,
          callsign: 'Autoridad',
          role: RescueRosterRole.authority,
          signingPublicKey: authorityKey ?? Uint8List(32),
        ),
        RescueRosterMember(
          peerId: _responder,
          callsign: 'Rescatista',
          role: RescueRosterRole.responder,
          signingPublicKey: Uint8List(32),
        ),
      ],
      signature: Uint8List(64),
    );
