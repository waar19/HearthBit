import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/family_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/screens/family_screen.dart';

void main() {
  testWidgets('no desborda en pantalla estrecha con texto al 200 %', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mesh = MeshController();
    final family = FamilyController(mesh: mesh);
    addTearDown(family.dispose);
    addTearDown(mesh.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: FamilyScreen(controller: family),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Grupo familiar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
