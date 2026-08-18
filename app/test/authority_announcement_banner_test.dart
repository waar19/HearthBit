import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/authority_announcement_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/models/authority_announcement_models.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/widgets/authority_announcement_banner.dart';

class _Roster extends RescueRosterController {
  _Roster({required super.mesh});

  @override
  RescueTeamRoster? get activeRoster => null;

  @override
  List<RescueRosterMember> get members => const [];
}

class _Controller extends AuthorityAnnouncementController {
  _Controller({required super.mesh, required super.roster});

  AuthorityAnnouncement? current;

  @override
  AuthorityAnnouncement? get activeAnnouncement => current;
}

void main() {
  testWidgets('muestra banner diferenciado con origen y expiración', (
    tester,
  ) async {
    final mesh = MeshController();
    final roster = _Roster(mesh: mesh);
    final controller = _Controller(mesh: mesh, roster: roster)
      ..current = AuthorityAnnouncement(
        version: 1,
        announcementId: List.filled(32, '0').join(),
        teamId: List.filled(32, '1').join(),
        actorPeerId: List.filled(16, '2').join(),
        priority: AuthorityAnnouncementPriority.evacuate,
        issuedAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        body: 'Evacuar hacia el norte',
        callsign: 'Defensa Civil',
      );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AuthorityAnnouncementBanner(controller: controller),
        ),
      ),
    );

    expect(find.byKey(const Key('authority-announcement-banner')), findsOne);
    expect(find.textContaining('Evacuar hacia el norte'), findsOne);
    expect(find.textContaining('Defensa Civil'), findsOne);
    expect(find.byIcon(Icons.campaign), findsOne);

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });
}
