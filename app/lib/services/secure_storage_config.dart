import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configuración única para secretos HearthBit.
///
/// No cambia prefijos ni namespaces para conservar los valores creados por
/// versiones anteriores. Android usa los algoritmos mantenidos por v11 y una
/// migración con respaldo resistente a interrupciones.
const hearthBitSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  ),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  ),
);
