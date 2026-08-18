import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/authority_announcement_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/screens/authority_announcements_screen.dart';

class _Roster extends RescueRosterController {
  _Roster({required super.mesh});

  @override
  List<RescueRosterMember> get members => const [];
}

class _Controller extends AuthorityAnnouncementController {
  _Controller({required super.mesh, required super.roster});

  @override
  bool get canIssue => true;
}

void main() {
  testWidgets('cuenta bytes UTF-8 y bloquea instrucciones excesivas', (
    tester,
  ) async {
    final mesh = MeshController();
    final roster = _Roster(mesh: mesh);
    final controller = _Controller(mesh: mesh, roster: roster);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AuthorityAnnouncementsScreen(controller: controller),
      ),
    );

    await tester.enterText(find.byType(TextField), '🚨' * 128);
    await tester.pump();
    expect(find.text('512/512 bytes UTF-8'), findsOne);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('authority-send')))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(find.byType(TextField), '🚨' * 512);
    await tester.pump();
    expect(find.text('2048/512 bytes UTF-8'), findsOne);
    expect(
      find.text('La instrucción no puede superar 512 bytes UTF-8.'),
      findsOne,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('authority-send')))
          .onPressed,
      isNull,
    );

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });
}
