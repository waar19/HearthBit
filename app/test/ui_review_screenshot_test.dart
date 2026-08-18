// Arnés temporal de revisión visual y de accesibilidad.
// Genera capturas PNG en build/ui_review/ y un reporte de accesibilidad
// (a11y_report.txt) usando las guías integradas de flutter_test.
// No forma parte de la suite permanente: se elimina tras la revisión.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';
import 'package:hearth_bit/controllers/family_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/transfer_controller.dart';
import 'package:hearth_bit/l10n/l10n.dart';
import 'package:hearth_bit/main.dart' show buildAppTheme;
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/screens/emergency_contacts_screen.dart';
import 'package:hearth_bit/screens/emergency_screen.dart';
import 'package:hearth_bit/screens/family_screen.dart';
import 'package:hearth_bit/screens/home_screen.dart';
import 'package:hearth_bit/screens/onboarding_screen.dart';
import 'package:hearth_bit/screens/radar_screen.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:hearth_bit/services/emergency_directory_service.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/message_repository.dart';

final Directory _outDir = Directory('build/ui_review');
final File _a11yReport = File('build/ui_review/a11y_report.txt');

class _ReviewPlatform extends MeshPlatformService {
  _ReviewPlatform({this.radioAvailable = false});

  final bool radioAvailable;
  final _events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);

  void emit(Map<Object?, Object?> event) => _events.add(event);

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  @override
  Future<Map<Object?, Object?>> getCapabilities() async => const {};

  @override
  Future<Map<Object?, Object?>> getPowerStatus() async => const {};

  @override
  Future<String> sendPublic(String content, {String? channel}) async =>
      'public-1';

  @override
  Future<String> sendPrivate(
    String peerId,
    String content, {
    String? messageId,
  }) async => messageId ?? 'private-1';

  @override
  Future<void> ensurePrivateChannel(String peerId) async {}

  @override
  Future<void> setGenericPresenceScanEnabled(bool enabled) async {}

  @override
  Future<String> sendSos({
    required String content,
    double? latitude,
    double? longitude,
  }) async => 'sos-1';

  @override
  Future<void> setRadarConsent({
    required bool enabled,
    int minutes = 15,
  }) async {}

  @override
  Future<void> startLocalBeacon({
    int flags = 0x07,
    Duration duration = const Duration(minutes: 5),
  }) async {}

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

  @override
  Future<String?> getSimCountry() async => 'CO';

  void emitRssi(int rssi, {String peerId = '0011223344556677'}) {
    _events.add({
      'type': 'rssi',
      'peerId': peerId,
      'rssi': rssi,
      'tentative': false,
    });
  }

  Future<void> disposeEvents() => _events.close();
}

class _MemoryRepo extends MessageRepository {
  _MemoryRepo({this.messages = const []});

  final List<MeshMessage> messages;

  @override
  Future<List<MeshMessage>> load() async => messages;

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
  Future<SosOperationalMetrics> loadSosOperationalMetrics() async =>
      const SosOperationalMetrics();

  @override
  Future<void> expireEmergencyDeliveries(DateTime now) async {}

  @override
  Future<void> save(MeshMessage message) async {}

  @override
  Future<void> saveKnownPeers(Iterable<MeshPeer> peers) async {}
}

Future<ByteData> _readFont(String directory, String file) async {
  final bytes = await File(
    '$directory${Platform.pathSeparator}$file',
  ).readAsBytes();
  return ByteData.sublistView(bytes);
}

Future<void> _loadFontIfAvailable(
  String family,
  String directory,
  List<String> files,
) async {
  final paths = files.map((file) => '$directory${Platform.pathSeparator}$file');
  if (!paths.every((path) => File(path).existsSync())) {
    debugPrint('[ui-review] skip-font:$family');
    return;
  }
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(_readFont(directory, file));
  }
  await loader.load();
}

Future<void> _loadRealFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter-sdk';
  final fontsDir =
      '$flutterRoot${Platform.pathSeparator}bin'
      '${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts'
      '${Platform.pathSeparator}material_fonts';
  await _loadFontIfAvailable('Roboto', fontsDir, const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-italic.ttf',
  ]);
  await _loadFontIfAvailable('MaterialIcons', fontsDir, const [
    'materialicons-regular.otf',
  ]);
}

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(411, 870),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
  bool highContrast = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot-boundary'),
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(
          brightness,
          amoled: false,
          highContrast: highContrast,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _shoot(WidgetTester tester, String name) async {
  debugPrint('[ui-review] shoot:$name');
  await tester.pump(const Duration(milliseconds: 50));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot-boundary')),
  );
  late final Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
    image.dispose();
  });
  File(
    '${_outDir.path}${Platform.pathSeparator}$name.png',
  ).writeAsBytesSync(bytes);
}

Future<void> _audit(WidgetTester tester, String name) async {
  final buffer = StringBuffer();
  final guidelines = <AccessibilityGuideline>[
    androidTapTargetGuideline,
    labeledTapTargetGuideline,
    textContrastGuideline,
  ];
  for (final guideline in guidelines) {
    debugPrint('[ui-review] audit:$name guideline:${guideline.description}');
    Evaluation result;
    try {
      result = await guideline.evaluate(tester);
    } on Object catch (error) {
      buffer.writeln('== [$name] ${guideline.description}: ERROR $error\n');
      continue;
    }
    if (!result.passed) {
      buffer.writeln('== [$name] ${guideline.description}');
      buffer.writeln((result.reason ?? '(sin detalle)').trim());
      buffer.writeln();
    }
  }
  if (buffer.isNotEmpty) {
    _a11yReport.writeAsStringSync(buffer.toString(), mode: FileMode.append);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_outDir.existsSync()) {
      _outDir.deleteSync(recursive: true);
    }
    _outDir.createSync(recursive: true);
    await _loadRealFonts();
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const mutedChannels = [
      MethodChannel('com.llfbandit.record/messages'),
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers.global/events'),
    ];
    for (final channel in mutedChannels) {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final playerId =
              ((call.arguments as Map?)?['playerId'] as String?) ?? '';
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$playerId'),
            (event) async => null,
          );
        }
        return null;
      },
    );
  });

  testWidgets('onboarding', (tester) async {
    final handle = tester.ensureSemantics();
    final mesh = MeshController();
    addTearDown(mesh.dispose);

    await _pumpApp(
      tester,
      OnboardingScreen(controller: mesh, onFinished: () async {}),
    );
    await _shoot(tester, 'onboarding_1_dark');
    await _audit(tester, 'onboarding_1');

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    await _shoot(tester, 'onboarding_2_dark');
    await _audit(tester, 'onboarding_2');
    handle.dispose();
  });

  testWidgets('onboarding 200%', (tester) async {
    final mesh = MeshController();
    addTearDown(mesh.dispose);
    await _pumpApp(
      tester,
      OnboardingScreen(controller: mesh, onFinished: () async {}),
      textScale: 2,
    );
    await _shoot(tester, 'onboarding_1_dark_200');
    expect(tester.takeException(), isNull);
  });

  testWidgets('home con malla activa', (tester) async {
    debugPrint('[ui-review] home:start');
    final handle = tester.ensureSemantics();
    final platform = _ReviewPlatform();
    final now = DateTime.now();
    final mesh = MeshController(
      platform: platform,
      repository: _MemoryRepo(
        messages: [
          MeshMessage(
            id: 'm1',
            sender: 'Ana',
            content: '¿Todos bien por la zona norte?',
            senderPeerId: '00112233445566aa',
            isPrivate: false,
            isMine: false,
            timestamp: now.subtract(const Duration(minutes: 9)),
          ),
          MeshMessage(
            id: 'm2',
            sender: 'Yo',
            content: 'Sí, seguimos en el punto de encuentro.',
            senderPeerId: 'self',
            isPrivate: false,
            isMine: true,
            timestamp: now.subtract(const Duration(minutes: 7)),
          ),
        ],
      ),
    );
    final preferences = AppPreferences();
    await tester.runAsync(() async {
      await mesh.initialize();
      await preferences.initialize();
    });
    debugPrint('[ui-review] home:init');
    final transfers = TransferController(platform);
    final gateway = EmergencyGatewayController(
      mesh: mesh,
      preferences: preferences,
    );
    final family = FamilyController(mesh: mesh);
    debugPrint('[ui-review] home:controllers');
    addTearDown(() {
      gateway.dispose();
      family.dispose();
      transfers.dispose();
      mesh.dispose();
      preferences.dispose();
    });

    platform.emit({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    platform.emit({
      'type': 'peers',
      'peers': [
        {
          'id': '00112233445566aa',
          'nickname': 'Ana',
          'lastSeen': now.millisecondsSinceEpoch,
          'secure': true,
          'online': true,
          'supportsTransfers': true,
          'role': 'PHONE_RELAY',
        },
        {
          'id': '00112233445566bb',
          'nickname': 'Luis',
          'lastSeen': now.millisecondsSinceEpoch,
          'secure': false,
          'online': true,
          'role': 'PHONE_RELAY',
        },
      ],
    });
    await tester.pump();
    debugPrint('[ui-review] home:events');

    await _pumpApp(
      tester,
      HomeScreen(
        controller: mesh,
        transfers: transfers,
        preferences: preferences,
        gateway: gateway,
        family: family,
      ),
    );
    debugPrint('[ui-review] home:pumped');
    await _shoot(tester, 'home_tab0_dark');
    await _audit(tester, 'home_tab0');

    final destinations = find.byType(NavigationDestination);
    final total = destinations.evaluate().length;
    for (var index = 1; index < total; index++) {
      await tester.tap(destinations.at(index), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));
      final error = tester.takeException();
      if (error != null) {
        _a11yReport.writeAsStringSync(
          '== [home_tab$index] excepción al abrir pestaña: $error\n\n',
          mode: FileMode.append,
        );
      }
      await _shoot(tester, 'home_tab${index}_dark');
      await _audit(tester, 'home_tab$index');
    }
    handle.dispose();
  });

  testWidgets('home en claro', (tester) async {
    final platform = _ReviewPlatform();
    final mesh = MeshController(platform: platform, repository: _MemoryRepo());
    final preferences = AppPreferences();
    await tester.runAsync(() async {
      await mesh.initialize();
      await preferences.initialize();
    });
    final transfers = TransferController(platform);
    final gateway = EmergencyGatewayController(
      mesh: mesh,
      preferences: preferences,
    );
    final family = FamilyController(mesh: mesh);
    addTearDown(() {
      gateway.dispose();
      family.dispose();
      transfers.dispose();
      mesh.dispose();
      preferences.dispose();
    });
    platform.emit({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    await tester.pump();

    await _pumpApp(
      tester,
      HomeScreen(
        controller: mesh,
        transfers: transfers,
        preferences: preferences,
        gateway: gateway,
        family: family,
      ),
      brightness: Brightness.light,
    );
    await _shoot(tester, 'home_tab0_light');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pantalla de emergencia', (tester) async {
    final handle = tester.ensureSemantics();
    final platform = _ReviewPlatform();
    final mesh = MeshController(platform: platform, repository: _MemoryRepo());
    final preferences = AppPreferences();
    await tester.runAsync(() async {
      await mesh.initialize();
      await preferences.initialize();
    });
    final gateway = EmergencyGatewayController(
      mesh: mesh,
      preferences: preferences,
    );
    final family = FamilyController(mesh: mesh);
    addTearDown(() {
      gateway.dispose();
      family.dispose();
      mesh.dispose();
      preferences.dispose();
    });
    platform.emit({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    await tester.pump();

    await _pumpApp(
      tester,
      Scaffold(
        body: EmergencyScreen(
          controller: mesh,
          preferences: preferences,
          gateway: gateway,
          family: family,
        ),
      ),
    );
    await _shoot(tester, 'emergency_dark');
    await _audit(tester, 'emergency');
    handle.dispose();
  });

  testWidgets('pantalla de emergencia 200%', (tester) async {
    final platform = _ReviewPlatform();
    final mesh = MeshController(platform: platform, repository: _MemoryRepo());
    final preferences = AppPreferences();
    await tester.runAsync(() async {
      await mesh.initialize();
      await preferences.initialize();
    });
    final gateway = EmergencyGatewayController(
      mesh: mesh,
      preferences: preferences,
    );
    final family = FamilyController(mesh: mesh);
    addTearDown(() {
      gateway.dispose();
      family.dispose();
      mesh.dispose();
      preferences.dispose();
    });
    platform.emit({
      'type': 'status',
      'status': 'active',
      'role': 'PHONE_RELAY',
    });
    await tester.pump();

    await _pumpApp(
      tester,
      Scaffold(
        body: EmergencyScreen(
          controller: mesh,
          preferences: preferences,
          gateway: gateway,
          family: family,
        ),
      ),
      textScale: 2,
    );
    await _shoot(tester, 'emergency_dark_200');
    expect(tester.takeException(), isNull);
  });

  testWidgets('grupo familiar', (tester) async {
    final handle = tester.ensureSemantics();
    final mesh = MeshController();
    final family = FamilyController(mesh: mesh);
    addTearDown(() {
      family.dispose();
      mesh.dispose();
    });
    await _pumpApp(tester, FamilyScreen(controller: family));
    await _shoot(tester, 'family_dark');
    await _audit(tester, 'family');
    handle.dispose();
  });

  testWidgets('directorio de emergencia', (tester) async {
    final handle = tester.ensureSemantics();
    final preferences = AppPreferences();
    await tester.runAsync(preferences.initialize);
    addTearDown(preferences.dispose);
    await _pumpApp(
      tester,
      EmergencyContactsScreen(
        preferences: preferences,
        countryResolver: EmergencyCountryResolver(platform: _ReviewPlatform()),
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'directory_dark');
    await _audit(tester, 'directory');
    handle.dispose();
  });

  testWidgets('radar buscando y con señal', (tester) async {
    final handle = tester.ensureSemantics();
    final platform = _ReviewPlatform(radioAvailable: true);
    final compassEvents = StreamController<CompassEvent>.broadcast(sync: true);
    addTearDown(platform.disposeEvents);
    addTearDown(compassEvents.close);

    await _pumpApp(
      tester,
      RadarScreen(
        peerId: '0011223344556677',
        nickname: 'Rescate',
        consentExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
        consentSource: 'sos',
        platform: platform,
        compassEvents: compassEvents.stream,
      ),
    );
    await _shoot(tester, 'radar_search_dark');
    await _audit(tester, 'radar_search');

    platform.emitRssi(-65);
    compassEvents.add(CompassEvent.fromList([40, 40, 5]));
    await tester.pump(const Duration(milliseconds: 400));
    await _shoot(tester, 'radar_active_dark');
    await _audit(tester, 'radar_active');

    await tester.tap(find.byIcon(Icons.explore_outlined), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await _shoot(tester, 'radar_sweep_dark');
    await _audit(tester, 'radar_sweep');
    handle.dispose();
  });

  testWidgets('radar con señal al 200%', (tester) async {
    final platform = _ReviewPlatform(radioAvailable: true);
    final compassEvents = StreamController<CompassEvent>.broadcast(sync: true);
    addTearDown(platform.disposeEvents);
    addTearDown(compassEvents.close);
    await _pumpApp(
      tester,
      RadarScreen(
        peerId: '0011223344556677',
        nickname: 'Rescate',
        consentExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
        consentSource: 'sos',
        platform: platform,
        compassEvents: compassEvents.stream,
      ),
      textScale: 2,
    );
    platform.emitRssi(-65);
    await tester.pump(const Duration(milliseconds: 400));
    await _shoot(tester, 'radar_active_dark_200');
    expect(tester.takeException(), isNull);
  });
}
