import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/controllers/emergency_gateway_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/l10n/generated/app_localizations.dart';
import 'package:hearth_bit/screens/emergency_gateway_card.dart';
import 'package:hearth_bit/services/app_preferences.dart';
import 'package:hearth_bit/services/tls_peer_verifier.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeGatewayController extends EmergencyGatewayController {
  _FakeGatewayController(this.testPreferences)
    : super(
        mesh: MeshController(preferences: testPreferences),
        preferences: testPreferences,
      );

  final AppPreferences testPreferences;
  EmergencyGatewayConfig? savedConfig;
  var resetCalls = 0;

  @override
  Future<void> saveConfig(EmergencyGatewayConfig value, String secret) async {
    savedConfig = value;
    config = value;
    notifyListeners();
  }

  @override
  Future<void> resetTofuTrust(EmergencyGatewayConfig config) async {
    resetCalls += 1;
  }
}

const _fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

EmergencyGatewayConfig _config({
  TlsTrustMode trustMode = TlsTrustMode.system,
  String? fingerprint,
  bool content = false,
  bool coordinates = false,
}) => EmergencyGatewayConfig(
  kind: EmergencyGatewayKind.matrix,
  server: 'https://matrix.example.org',
  destination: '!rescue:example.org',
  username: '',
  port: 443,
  tls: true,
  trustMode: trustMode,
  certificateSha256: fingerprint,
  includeSensitiveContent: content,
  includeCoordinates: coordinates,
);

void main() {
  late AppPreferences preferences;
  late _FakeGatewayController controller;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = AppPreferences();
    controller = _FakeGatewayController(preferences);
  });

  tearDown(() {
    controller.dispose();
    controller.mesh.dispose();
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EmergencyGatewayCard(
            controller: controller,
            preferences: preferences,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('privacidad permanece desactivada por defecto', (tester) async {
    controller.config = _config();
    await pumpCard(tester);

    final content = tester.widget<SwitchListTile>(
      find.byKey(const Key('gateway-sensitive-consent')),
    );
    final coordinates = tester.widget<SwitchListTile>(
      find.byKey(const Key('gateway-coordinates-consent')),
    );

    expect(content.value, isFalse);
    expect(coordinates.value, isFalse);
  });

  testWidgets('Pinned exige una huella válida', (tester) async {
    controller.config = _config();
    await pumpCard(tester);

    await tapAndSettle(tester, find.text('Pinned'));
    await tapAndSettle(tester, find.byKey(const Key('gateway-save')));

    expect(find.textContaining('64-character SHA-256'), findsOneWidget);
    expect(controller.savedConfig, isNull);
  });

  testWidgets('editar conserva confianza, huella y consentimientos', (
    tester,
  ) async {
    controller.config = _config(
      trustMode: TlsTrustMode.pinned,
      fingerprint: _fingerprint,
      content: true,
      coordinates: true,
    );
    await pumpCard(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('gateway-fingerprint')))
          .controller!
          .text,
      _fingerprint,
    );
    await tapAndSettle(tester, find.byKey(const Key('gateway-save')));

    expect(controller.savedConfig?.trustMode, TlsTrustMode.pinned);
    expect(controller.savedConfig?.certificateSha256, _fingerprint);
    expect(controller.savedConfig?.includeSensitiveContent, isTrue);
    expect(controller.savedConfig?.includeCoordinates, isTrue);
  });

  testWidgets('reset TOFU delega al controlador', (tester) async {
    controller.config = _config(trustMode: TlsTrustMode.tofu);
    await pumpCard(tester);

    await tapAndSettle(tester, find.byKey(const Key('gateway-reset-tofu')));

    expect(controller.resetCalls, 1);
    expect(
      find.text('The saved TOFU certificate was removed.'),
      findsOneWidget,
    );
  });

  testWidgets('los consentimientos se guardan por separado', (tester) async {
    controller.config = _config();
    await pumpCard(tester);

    await tapAndSettle(
      tester,
      find.byKey(const Key('gateway-sensitive-consent')),
    );
    await tapAndSettle(tester, find.byKey(const Key('gateway-save')));

    expect(controller.savedConfig?.includeSensitiveContent, isTrue);
    expect(controller.savedConfig?.includeCoordinates, isFalse);
  });
}
