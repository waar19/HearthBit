import 'package:flutter/material.dart';

import 'controllers/mesh_controller.dart';
import 'controllers/emergency_gateway_controller.dart';
import 'controllers/transfer_controller.dart';
import 'l10n/l10n.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/app_preferences.dart';
import 'services/mesh_platform_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HearthBitApp());
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
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    final platform = MeshPlatformService();
    _controller = MeshController(platform: platform);
    _transfers = TransferController(platform);
    _preferences = AppPreferences();
    _gateway = EmergencyGatewayController(
      mesh: _controller,
      preferences: _preferences,
    );
    _initialization = Future.wait([
      _controller.initialize(),
      _transfers.initialize(),
      _preferences.initialize(),
      _gateway.initialize(),
    ]);
  }

  @override
  void dispose() {
    _gateway.dispose();
    _transfers.dispose();
    _controller.dispose();
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_preferences, _controller]),
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => context.l10n.appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
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
            );
          },
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: dark ? const Color(0xFF5ADBAA) : const Color(0xFF006C4C),
      brightness: brightness,
    );
    var theme = ThemeData(colorScheme: scheme, useMaterial3: true);
    if (_preferences.amoledTheme && dark) {
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
    if (_preferences.highContrast || _controller.rescueMode) {
      theme = theme.copyWith(
        textTheme: scaleDefinedTextTheme(theme.textTheme, 1.12),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(56, 52),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(56, 52)),
        ),
      );
    }
    return theme;
  }
}
