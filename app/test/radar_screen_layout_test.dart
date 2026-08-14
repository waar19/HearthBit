import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/screens/radar_screen.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';

class _RadarPlatform extends MeshPlatformService {
  @override
  Stream<Map<Object?, Object?>> get events => const Stream.empty();

  @override
  Future<void> startRadar(String peerId) async {}

  @override
  Future<void> stopRadar() async {}

  @override
  Future<void> stopRadioRanging() async {}

  @override
  Future<Map<Object?, Object?>> getRangingCapabilities() async => const {
    'available': false,
  };
}

void main() {
  Future<void> pumpRadar(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: RadarScreen(
          peerId: '0011223344556677',
          nickname: 'Rescate',
          consentExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
          consentSource: 'sos',
          platform: _RadarPlatform(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final size in [const Size(320, 568), const Size(411, 870)]) {
    testWidgets('mantiene el círculo visible sin overflow en $size', (
      tester,
    ) async {
      await pumpRadar(tester, size: size);

      expect(tester.takeException(), isNull);
      final banner = tester.getRect(
        find.byKey(const ValueKey('radar-banner-slot')),
      );
      final radar = tester.getRect(find.byKey(const ValueKey('radar-canvas')));
      expect(banner.height, 58);
      expect(radar.height, greaterThan(150));
      expect(radar.top, greaterThanOrEqualTo(banner.bottom));
    });
  }

  testWidgets('mantiene acciones y radar utilizables con texto al 200%', (
    tester,
  ) async {
    await pumpRadar(tester, size: const Size(411, 870), textScale: 2);

    expect(find.byKey(const ValueKey('radar-canvas')), findsOneWidget);
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
