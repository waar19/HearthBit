import 'package:flutter/material.dart';

import 'controllers/mesh_controller.dart';
import 'controllers/transfer_controller.dart';
import 'l10n/l10n.dart';
import 'screens/home_screen.dart';
import 'services/mesh_platform_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HearthBitApp());
}

class HearthBitApp extends StatefulWidget {
  const HearthBitApp({super.key});

  @override
  State<HearthBitApp> createState() => _HearthBitAppState();
}

class _HearthBitAppState extends State<HearthBitApp> {
  late final MeshController _controller;
  late final TransferController _transfers;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    final platform = MeshPlatformService();
    _controller = MeshController(platform: platform);
    _transfers = TransferController(platform);
    _initialization = Future.wait([
      _controller.initialize(),
      _transfers.initialize(),
    ]);
  }

  @override
  void dispose() {
    _transfers.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006C4C),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5ADBAA),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
          return HomeScreen(controller: _controller, transfers: _transfers);
        },
      ),
    );
  }
}
