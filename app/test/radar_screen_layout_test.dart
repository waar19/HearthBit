import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/screens/radar_screen.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';

class _RadarPlatform extends MeshPlatformService {
  _RadarPlatform({this.radioAvailable = false});

  final bool radioAvailable;
  final _events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  @override
  Future<void> startRadar(String peerId) async {}

  @override
  Future<void> stopRadar() async {}

  @override
  Future<void> stopRadioRanging() async {}

  @override
  Future<String> requestRemoteBeacon(
    String peerId, {
    int flags = 0,
    Duration duration = Duration.zero,
  }) async => 'request-1';

  @override
  Future<Map<Object?, Object?>> getRangingCapabilities() async => {
    'available': radioAvailable,
  };

  void emitRssi(int rssi) {
    _events.add({
      'type': 'rssi',
      'peerId': '0011223344556677',
      'rssi': rssi,
      'tentative': false,
    });
  }

  Future<void> disposeEvents() => _events.close();
}

void main() {
  Future<(_RadarPlatform, StreamController<CompassEvent>)> pumpRadar(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
    bool radioAvailable = false,
  }) async {
    final platform = _RadarPlatform(radioAvailable: radioAvailable);
    final compassEvents = StreamController<CompassEvent>.broadcast(sync: true);
    addTearDown(platform.disposeEvents);
    addTearDown(compassEvents.close);
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
          platform: platform,
          compassEvents: compassEvents.stream,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return (platform, compassEvents);
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
    final (platform, _) = await pumpRadar(
      tester,
      size: const Size(411, 870),
      textScale: 2,
    );
    platform.emitRssi(-65);
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'tras recibir señal al 200%',
    );

    expect(find.byKey(const ValueKey('radar-canvas')), findsOneWidget);
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    expect(find.text('Dirección'), findsOneWidget);
    expect(find.text('Sonar'), findsOneWidget);
    expect(find.text('Baliza'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Baliza')).dy,
      greaterThan(tester.getTopLeft(find.text('Dirección')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('muestra etiquetas comprensibles en las acciones disponibles', (
    tester,
  ) async {
    final (platform, _) = await pumpRadar(
      tester,
      size: const Size(320, 700),
      radioAvailable: true,
    );
    platform.emitRssi(-65);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'tras recibir señal');

    expect(find.text('Dirección'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Sonar'), findsOneWidget);
    expect(find.text('Baliza'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'al iniciar barrido');
    expect(find.text('Barrido'), findsOneWidget);
    final instruction = tester.widget<Text>(
      find.text(
        'Mantenlo plano frente al pecho, con la pantalla hacia arriba y el '
        'borde superior apuntando al frente. Gira lentamente todo el cuerpo.',
      ),
    );
    expect(instruction.maxLines, isNull);
    expect(instruction.overflow, isNull);

    await tester.tap(find.byIcon(Icons.flashlight_on_outlined));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'al pedir baliza');
    expect(find.text('Esperando'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('barrido inconcluso no desborda con texto al 200%', (
    tester,
  ) async {
    final (platform, compassEvents) = await pumpRadar(
      tester,
      size: const Size(411, 870),
      textScale: 2,
    );
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pump();

    for (final heading in <double>[
      0,
      30,
      60,
      90,
      120,
      150,
      180,
      210,
      240,
      270,
      300,
      330,
      359,
    ]) {
      for (var sample = 0; sample < 12; sample++) {
        compassEvents.add(CompassEvent.fromList([heading, heading, 5]));
        platform.emitRssi(-70);
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          tester.takeException(),
          isNull,
          reason: 'durante barrido en $heading°, muestra $sample',
        );
      }
    }

    expect(
      find.text(
        'No se encontró un sector confiable. Gira más despacio y aléjate '
        'de metales o equipos electrónicos.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
