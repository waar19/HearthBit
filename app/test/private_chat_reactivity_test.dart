import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';
import 'package:hearth_bit/controllers/family_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/transfer_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/screens/home_screen.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/message_repository.dart';

class _ReactivePlatform extends MeshPlatformService {
  final StreamController<Map<Object?, Object?>> _events =
      StreamController.broadcast();
  final List<String> privateMessages = [];
  final List<bool> genericPresenceScanStates = [];
  Object? privateMessageError;

  void emit(Map<Object?, Object?> event) => _events.add(event);

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  @override
  Future<Map<Object?, Object?>> getCapabilities() async => const {};

  @override
  Future<Map<Object?, Object?>> getPowerStatus() async => const {};

  @override
  Future<String> sendPrivate(
    String peerId,
    String content, {
    String? messageId,
  }) async {
    privateMessages.add(content);
    final error = privateMessageError;
    if (error != null) throw error;
    return messageId ?? 'sent-${privateMessages.length}';
  }

  @override
  Future<void> ensurePrivateChannel(String peerId) async {}

  @override
  Future<void> setGenericPresenceScanEnabled(bool enabled) async {
    genericPresenceScanStates.add(enabled);
  }
}

class _MemoryMessageRepository extends MessageRepository {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ReactivePlatform platform;
  late MeshController mesh;
  late TransferController transfers;
  late AppPreferences preferences;
  late EmergencyGatewayController gateway;
  late FamilyController family;
  late StreamController<void> emergencyOpens;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = _ReactivePlatform();
    mesh = MeshController(
      platform: platform,
      repository: _MemoryMessageRepository(),
    );
    await mesh.initialize();
    transfers = TransferController(platform);
    preferences = AppPreferences();
    gateway = EmergencyGatewayController(mesh: mesh, preferences: preferences);
    family = FamilyController(mesh: mesh);
    emergencyOpens = StreamController<void>.broadcast();
  });

  tearDown(() {
    gateway.dispose();
    family.dispose();
    transfers.dispose();
    mesh.dispose();
    preferences.dispose();
    unawaited(emergencyOpens.close());
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          controller: mesh,
          transfers: transfers,
          preferences: preferences,
          gateway: gateway,
          family: family,
          emergencyOpens: emergencyOpens.stream,
          consumeInitialEmergencyOpen: () async => false,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shortcut vuelve directamente a la pestaña SOS', (tester) async {
    await pumpHome(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Channel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emergency-hold-button')), findsNothing);

    emergencyOpens.add(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emergency-hold-button')), findsOneWidget);
  });

  Map<Object?, Object?> snapshot({
    required bool secure,
    required String nickname,
  }) {
    return {
      'type': 'snapshot',
      'status': 'active',
      'nickname': 'Me',
      'peerId': 'local',
      'role': 'PHONE_RELAY',
      'peers': [
        {
          'id': 'remote-peer-1234',
          'nickname': nickname,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'secure': secure,
          'role': 'PHONE_RELAY',
          'radarAllowedUntil': DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        },
      ],
    };
  }

  testWidgets('tocar la conversación cierra el teclado del canal', (
    tester,
  ) async {
    await pumpHome(tester);
    platform.emit(snapshot(secure: false, nickname: 'Nearby peer'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Channel'),
      ),
    );
    await tester.pumpAndSettle();

    final composer = find.byType(TextField);
    await tester.tap(composer);
    await tester.enterText(composer, 'Draft');
    final editableText = find.byType(EditableText);
    expect(
      tester.widget<EditableText>(editableText).focusNode.hasFocus,
      isTrue,
    );

    await tester.tap(find.text('No messages yet'));
    await tester.pump();

    expect(
      tester.widget<EditableText>(editableText).focusNode.hasFocus,
      isFalse,
    );
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('escanea presencias genéricas solo en Cercanos y foreground', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(platform.genericPresenceScanStates, [false]);

    await tester.tap(find.text('Nearby'));
    await tester.pump();
    expect(platform.genericPresenceScanStates, [false, true]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.genericPresenceScanStates, [false, true, false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.genericPresenceScanStates, [false, true, false, true]);

    await tester.tap(find.text('Channel'));
    await tester.pump();
    expect(platform.genericPresenceScanStates, [
      false,
      true,
      false,
      true,
      false,
    ]);
  });

  testWidgets('el sheet actualiza peer y canal seguro sin cerrarse', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);
    platform.emit(snapshot(secure: false, nickname: 'Initial'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.hub_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Initial'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Initial'));
    await tester.pumpAndSettle();

    expect(
      find.text('Waiting for the encrypted channel to become available.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    platform.emit(snapshot(secure: true, nickname: 'Updated'));
    await tester.pumpAndSettle();

    expect(find.text('Initial'), findsNothing);
    expect(find.text('Updated'), findsWidgets);
    expect(find.byIcon(Icons.lock), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conserva el borrador cuando el envío falla', (tester) async {
    await pumpHome(tester);
    platform.emit(snapshot(secure: true, nickname: 'Rescue'));
    await tester.pump();
    await tester.tap(find.text('Nearby'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rescue'));
    await tester.pumpAndSettle();
    platform.privateMessageError = StateError('closed session');

    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('Keep this draft'), findsOneWidget);
    expect(find.textContaining('closed session'), findsWidgets);
    expect(platform.privateMessages, ['Keep this draft']);
  });
}
