import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_case_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/l10n/generated/app_localizations.dart';
import 'package:hearth_bit/models/rescue_case_models.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/screens/rescue_operations_screen.dart';
import 'package:hearth_bit/services/rescue_case_repository.dart';

const _peerId = '0011223344556677';
const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

class _UiMesh extends MeshController {
  @override
  Future<String?> sendPublic(String content, {String? channel}) async => 'sent';
}

class _UiRoster extends RescueRosterController {
  _UiRoster({required super.mesh, required this.member});

  final RescueRosterMember member;

  @override
  RescueTeamRoster get activeRoster => RescueTeamRoster(
    teamId: '0' * 32,
    name: 'Team',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    leaderPeerId: member.peerId,
    members: [member],
    signature: Uint8List.fromList(List<int>.filled(64, 1)),
  );

  @override
  List<RescueRosterMember> get members => [member];

  @override
  RescueRosterMember? verifiedMember({
    required String peerId,
    required Uint8List? signingPublicKey,
  }) =>
      peerId == member.peerId &&
          signingPublicKey != null &&
          signingPublicKey.length == member.signingPublicKey.length
      ? member
      : null;
}

class _UiRepository extends RescueCaseRepository {
  _UiRepository(this.rescueCase);

  RescueCase rescueCase;

  @override
  Future<void> discardStaleLocalUpdates() async {}

  @override
  Future<List<RescueCase>> loadCases({required String teamId}) async =>
      rescueCase.teamId == teamId ? [rescueCase] : [];

  @override
  Future<bool> stageLocalUpdate(RescueCaseUpdate update) async => true;

  @override
  Future<RescueCaseWriteResult> commitLocalUpdate(
    RescueCaseUpdate update,
  ) async {
    rescueCase = RescueCaseTransition.resolve(rescueCase, update)!;
    return RescueCaseWriteResult(inserted: true, rescueCase: rescueCase);
  }

  @override
  Future<void> discardLocalUpdate(RescueCaseUpdate update) async {}

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('muestra caso y permite asignármelo', (tester) async {
    final key = Uint8List.fromList(List<int>.filled(32, 1));
    final mesh = _UiMesh()
      ..peerId = _peerId
      ..signingPublicKey = key;
    final roster = _UiRoster(
      mesh: mesh,
      member: RescueRosterMember(
        peerId: _peerId,
        callsign: 'Alpha 1',
        role: RescueRosterRole.leader,
        signingPublicKey: key,
      ),
    );
    final repository = _UiRepository(
      RescueCase(
        teamId: '0' * 32,
        caseHash: _hash,
        victimPeerId: '8899aabbccddeeff',
        victim: 'Victim',
        message: 'Need help',
        state: RescueCaseState.newCase,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        lastActorPeerId: '8899aabbccddeeff',
      ),
    );
    final controller = RescueCaseController(
      mesh: mesh,
      roster: roster,
      repository: repository,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RescueOperationsScreen(controller: controller),
      ),
    );
    expect(find.text('Victim'), findsOneWidget);
    expect(find.text('ASSIGN TO ME'), findsOneWidget);

    await tester.tap(find.text('ASSIGN TO ME'));
    await tester.pumpAndSettle();

    expect(find.text('Assigned'), findsOneWidget);
    expect(find.textContaining('Alpha 1'), findsOneWidget);

    controller.dispose();
    roster.dispose();
    mesh.dispose();
  });
}
