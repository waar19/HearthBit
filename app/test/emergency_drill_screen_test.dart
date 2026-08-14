import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';
import 'package:hearth_bit/controllers/family_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/screens/emergency_screen.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/message_repository.dart';

class _DrillPlatform extends MeshPlatformService {
  final eventsController = StreamController<Map<Object?, Object?>>.broadcast();
  final publicMessages = <({String content, String? channel})>[];
  var sosCalls = 0;
  var radarCalls = 0;
  var beaconCalls = 0;

  @override
  Stream<Map<Object?, Object?>> get events => eventsController.stream;

  @override
  Future<Map<Object?, Object?>> getCapabilities() async => const {};

  @override
  Future<Map<Object?, Object?>> getPowerStatus() async => const {};

  @override
  Future<String> sendPublic(String content, {String? channel}) async {
    publicMessages.add((content: content, channel: channel));
    return 'public-${publicMessages.length}';
  }

  @override
  Future<String> sendSos({
    required String content,
    double? latitude,
    double? longitude,
  }) async {
    sosCalls += 1;
    return 'sos-$sosCalls';
  }

  @override
  Future<void> setRadarConsent({
    required bool enabled,
    int minutes = 15,
  }) async {
    radarCalls += 1;
  }

  @override
  Future<void> startLocalBeacon({
    int flags = 0x07,
    Duration duration = const Duration(minutes: 5),
  }) async {
    beaconCalls += 1;
  }
}

class _DrillMessages extends MessageRepository {
  @override
  Future<List<MeshMessage>> load() async => const [];

  @override
  Future<List<MeshPeer>> loadKnownPeers() async => const [];

  @override
  Future<List<PendingPrivateMessage>> listPendingPrivateMessages() async =>
      const [];

  @override
  Future<void> expirePrivateMessageOutbox(DateTime now) async {}

  @override
  Future<List<EmergencyDelivery>> loadEmergencyDeliveries() async => const [];

  @override
  Future<void> expireEmergencyDeliveries(DateTime now) async {}

  @override
  Future<void> save(MeshMessage message) async {}

  @override
  Future<void> saveKnownPeers(Iterable<MeshPeer> peers) async {}
}

class _EmergencyActionController extends MeshController {
  _EmergencyActionController({
    required this.testPlatform,
    required MessageRepository repository,
    required AppPreferences preferences,
  }) : super(
         platform: testPlatform,
         repository: repository,
         preferences: preferences,
       );

  final _DrillPlatform testPlatform;
  var emergencyActivations = 0;

  @override
  Future<void> activateEmergency({String? description}) async {
    emergencyActivations += 1;
    await testPlatform.sendSos(content: description ?? 'real emergency');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DrillPlatform platform;
  late AppPreferences preferences;
  late _EmergencyActionController mesh;
  late EmergencyGatewayController gateway;
  late FamilyController family;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = _DrillPlatform();
    preferences = AppPreferences();
    await preferences.initialize();
    mesh = _EmergencyActionController(
      testPlatform: platform,
      repository: _DrillMessages(),
      preferences: preferences,
    );
    await mesh.initialize();
    gateway = EmergencyGatewayController(mesh: mesh, preferences: preferences);
    family = FamilyController(mesh: mesh);
    platform.eventsController.add({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    await pumpEventQueue();
  });

  tearDown(() async {
    gateway.dispose();
    family.dispose();
    mesh.dispose();
    preferences.dispose();
    await platform.eventsController.close();
  });

  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1}) async {
    await tester.binding.setSurfaceSize(const Size(500, 1100));
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
        home: Scaffold(
          body: AnimatedBuilder(
            animation: mesh,
            builder: (context, _) => EmergencyScreen(
              controller: mesh,
              preferences: preferences,
              gateway: gateway,
              family: family,
              emergencyHoldDuration: const Duration(milliseconds: 20),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mantiene el SOS antes de la configuración de simulacro', (
    tester,
  ) async {
    await pumpScreen(tester);

    final sosTop = tester.getTopLeft(find.text('MANTÉN PARA SOS')).dy;
    final drillTop = tester.getTopLeft(find.text('Modo simulacro')).dy;

    expect(sosTop, lessThan(drillTop));
  });

  testWidgets('mantener el botón real ejecuta la acción de SOS', (
    tester,
  ) async {
    await pumpScreen(tester);
    final holdButton = find.byKey(const Key('emergency-hold-button'));
    await tester.ensureVisible(holdButton);

    final semantics = tester.widget<Semantics>(
      find.ancestor(of: holdButton, matching: find.byType(Semantics)).first,
    );
    semantics.properties.onLongPress!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(platform.sosCalls, 1);
    expect(mesh.emergencyActivations, 1);
    expect(platform.publicMessages, isEmpty);
  });

  testWidgets('la acción accesible activa el SOS sin gesto mantenido', (
    tester,
  ) async {
    await pumpScreen(tester);
    final holdButton = find.byKey(const Key('emergency-hold-button'));
    final semantics = tester.widget<Semantics>(
      find.ancestor(of: holdButton, matching: find.byType(Semantics)).first,
    );

    semantics.properties.onTap!();
    await tester.pump();

    expect(mesh.emergencyActivations, 1);
    expect(platform.sosCalls, 1);
  });

  testWidgets('no desborda la pantalla crítica con texto al 200 por ciento', (
    tester,
  ) async {
    await pumpScreen(tester, textScale: 2);

    expect(find.byKey(const Key('emergency-hold-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmación activa banner y envío aislado de simulacro', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.ensureVisible(find.byKey(const Key('drill-mode-switch')));
    await tester.tap(find.byKey(const Key('drill-mode-switch')));
    await tester.pumpAndSettle();
    expect(find.text('¿Activar el modo simulacro?'), findsOneWidget);
    await tester.tap(find.text('ACTIVAR SIMULACRO'));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, 1200), 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill-safety-banner')), findsOneWidget);
    expect(find.text('SIMULACRO - no solicita rescate'), findsOneWidget);
    expect(find.text('Modo rescate'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('drill-hold-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final beaconButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'HACERME VISIBLE'),
    );
    expect(beaconButton.onPressed, isNull);

    await tester.longPress(find.byKey(const Key('drill-hold-button')));
    await tester.pumpAndSettle();

    expect(platform.publicMessages, hasLength(1));
    expect(platform.publicMessages.single.channel, 'drill');
    expect(
      platform.publicMessages.single.content,
      contains(DrillCheckIn.marker),
    );
    expect(platform.sosCalls, 0);
    expect(platform.radarCalls, 0);
    expect(platform.beaconCalls, 0);
  });

  testWidgets('salir del simulacro requiere confirmación', (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(find.byKey(const Key('drill-mode-switch')));
    tester
        .widget<SwitchListTile>(find.byKey(const Key('drill-mode-switch')))
        .onChanged!(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ACTIVAR SIMULACRO'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('drill-mode-switch')));
    tester
        .widget<SwitchListTile>(find.byKey(const Key('drill-mode-switch')))
        .onChanged!(false);
    await tester.pumpAndSettle();

    expect(find.text('¿Finalizar el modo simulacro?'), findsOneWidget);
    expect(mesh.drillModeEnabled, isTrue);
    await tester.tap(find.text('FINALIZAR SIMULACRO'));
    await tester.pumpAndSettle();
    expect(mesh.drillModeEnabled, isFalse);
  });

  testWidgets('mensaje drill aparece separado y no como SOS', (tester) async {
    await pumpScreen(tester);
    platform.eventsController.add({
      'type': 'message',
      'message': {
        'id': 'remote-drill',
        'sender': 'Ana',
        'content':
            'SIMULACRO - no solicita rescate: práctica\n'
            '[HB-DRILL|1|CHECKIN|HELP|1700000000000]',
        'senderPeerId': 'peer-a',
        'private': false,
        'mine': false,
        'timestamp': 1700000000000,
        'channel': 'drill',
      },
    });
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('drill-message-remote-drill')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('SIMULACRO — NO ES UNA EMERGENCIA'), findsOne);
    await tester.scrollUntilVisible(
      find.text('No se han recibido alertas SOS.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No se han recibido alertas SOS.'), findsOneWidget);
    expect(find.byIcon(Icons.crisis_alert), findsNothing);
  });
}
