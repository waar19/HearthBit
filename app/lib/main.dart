import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'controllers/mesh_controller.dart';
import 'controllers/emergency_gateway_controller.dart';
import 'controllers/family_controller.dart';
import 'controllers/lan_gateway_controller.dart';
import 'controllers/rescue_case_controller.dart';
import 'controllers/transfer_controller.dart';
import 'controllers/rescue_roster_controller.dart';
import 'l10n/l10n.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/app_preferences.dart';
import 'services/diagnostics_log.dart';
import 'services/mesh_platform_service.dart';
import 'services/transport_diagnostics.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      final diagnostics = DiagnosticsLog.instance;
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        diagnostics.error(
          'flutter.framework.uncaught',
          error: details.exception,
          stackTrace: details.stack,
        );
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        diagnostics.error(
          'flutter.platform.uncaught',
          error: error,
          stackTrace: stackTrace,
        );
        return true;
      };
      unawaited(diagnostics.initialize());
      runApp(const HearthBitApp());
    },
    (error, stackTrace) {
      DiagnosticsLog.instance.error(
        'dart.zone.uncaught',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

TextTheme scaleDefinedTextTheme(TextTheme theme, double factor) {
  TextStyle? scale(TextStyle? style) {
    final fontSize = style?.fontSize;
    return fontSize == null
        ? style
        : style!.copyWith(fontSize: fontSize * factor);
  }

  return theme.copyWith(
    displayLarge: scale(theme.displayLarge),
    displayMedium: scale(theme.displayMedium),
    displaySmall: scale(theme.displaySmall),
    headlineLarge: scale(theme.headlineLarge),
    headlineMedium: scale(theme.headlineMedium),
    headlineSmall: scale(theme.headlineSmall),
    titleLarge: scale(theme.titleLarge),
    titleMedium: scale(theme.titleMedium),
    titleSmall: scale(theme.titleSmall),
    bodyLarge: scale(theme.bodyLarge),
    bodyMedium: scale(theme.bodyMedium),
    bodySmall: scale(theme.bodySmall),
    labelLarge: scale(theme.labelLarge),
    labelMedium: scale(theme.labelMedium),
    labelSmall: scale(theme.labelSmall),
  );
}

ThemeData buildAppTheme(
  Brightness brightness, {
  required bool amoled,
  required bool highContrast,
}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: dark ? const Color(0xFF5ADBAA) : const Color(0xFF006C4C),
    brightness: brightness,
  );
  var theme = ThemeData(colorScheme: scheme, useMaterial3: true);
  if (amoled && dark) {
    theme = theme.copyWith(
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      cardColor: const Color(0xFF0E0E0E),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0E0E0E)),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF080808),
      ),
    );
  }
  theme = theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(textStyle: theme.textTheme.labelLarge),
    ),
  );
  if (highContrast) {
    final scaledText = scaleDefinedTextTheme(theme.textTheme, 1.12);
    theme = theme.copyWith(
      textTheme: scaledText,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(56, 52),
          textStyle: scaledText.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(56, 52)),
      ),
    );
  }
  return theme;
}

class HearthBitApp extends StatefulWidget {
  const HearthBitApp({super.key});

  @override
  State<HearthBitApp> createState() => _HearthBitAppState();
}

class _HearthBitAppState extends State<HearthBitApp> {
  late final MeshController _controller;
  late final TransferController _transfers;
  late final AppPreferences _preferences;
  late final EmergencyGatewayController _gateway;
  late final FamilyController _family;
  late final RescueRosterController _rescueRoster;
  late final RescueCaseController _rescueCases;
  late final LanGatewayController _lanGateway;
  late final TransportDiagnostics _transportDiagnostics;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    final platform = MeshPlatformService();
    _transportDiagnostics = TransportDiagnostics.instance;
    _preferences = AppPreferences();
    _controller = MeshController(
      platform: platform,
      preferences: _preferences,
      transportDiagnostics: _transportDiagnostics,
    );
    _transfers = TransferController(
      platform,
      transportDiagnostics: _transportDiagnostics,
    );
    _gateway = EmergencyGatewayController(
      mesh: _controller,
      preferences: _preferences,
    );
    _family = FamilyController(mesh: _controller);
    _rescueRoster = RescueRosterController(
      mesh: _controller,
      platform: platform,
    );
    _rescueCases = RescueCaseController(
      mesh: _controller,
      roster: _rescueRoster,
    );
    _lanGateway = LanGatewayController();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    // SQLCipher serializa parte de su arranque nativo. Abrir varias bases en
    // paralelo puede dejar una conexión a medio cerrar tras un kill/reinicio.
    await _transportDiagnostics.initialize();
    await _preferences.initialize();
    await _controller.initialize();
    await _transfers.initialize();
    await _gateway.initialize();
    await _lanGateway.initialize();
    await _family.initialize();
    await _rescueRoster.initialize();
    await _rescueCases.initialize();
  }

  @override
  void dispose() {
    _gateway.dispose();
    _family.dispose();
    _rescueCases.dispose();
    _rescueRoster.dispose();
    _lanGateway.dispose();
    _transfers.dispose();
    _controller.dispose();
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _preferences,
        _controller,
        _transfers,
        _lanGateway,
        _rescueRoster,
        _rescueCases,
      ]),
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => context.l10n.appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              _BeaconConsentOverlay(controller: _controller),
              _SealedImportOverlay(transfers: _transfers),
            ],
          ),
        ),
        theme: buildAppTheme(
          Brightness.light,
          amoled: _preferences.amoledTheme,
          highContrast: _preferences.highContrast || _controller.rescueMode,
        ),
        darkTheme: buildAppTheme(
          Brightness.dark,
          amoled: _preferences.amoledTheme,
          highContrast: _preferences.highContrast || _controller.rescueMode,
        ),
        themeMode: _preferences.amoledTheme ? ThemeMode.dark : ThemeMode.system,
        home: FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.storageOpenError('${snapshot.error}'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            if (!_preferences.onboardingComplete) {
              return OnboardingScreen(
                controller: _controller,
                onFinished: _preferences.finishOnboarding,
              );
            }
            return HomeScreen(
              controller: _controller,
              transfers: _transfers,
              preferences: _preferences,
              gateway: _gateway,
              family: _family,
              rescueRoster: _rescueRoster,
              rescueCases: _rescueCases,
              lanGateway: _lanGateway,
            );
          },
        ),
      ),
    );
  }
}

class _BeaconConsentOverlay extends StatelessWidget {
  const _BeaconConsentOverlay({required this.controller});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final request = controller.pendingBeaconRequest;
    if (request == null || !request.expiresAt.isAfter(DateTime.now())) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.paddingOf(context).top + 8,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.beaconRequestTitle(request.nickname),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(context.l10n.beaconRequestBody),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => controller.respondToBeaconRequest(false),
                    child: Text(context.l10n.actionReject),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => controller.respondToBeaconRequest(true),
                    child: Text(context.l10n.actionAccept),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SealedImportOverlay extends StatelessWidget {
  const _SealedImportOverlay({required this.transfers});

  final TransferController transfers;

  @override
  Widget build(BuildContext context) {
    final pending = transfers.pendingSealedImport;
    if (pending == null) return const SizedBox.shrink();
    final metadata = pending.metadata;
    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.paddingOf(context).bottom + 12,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.sealedImportTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.sealedImportBody(
                  metadata.fileName,
                  metadata.senderPeerId.substring(0, 8),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: transfers.rejectPendingSealedImport,
                    child: Text(context.l10n.actionReject),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: transfers.acceptPendingSealedImport,
                    child: Text(context.l10n.actionAccept),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
