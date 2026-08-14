import 'package:flutter/services.dart';

class BackupProtection {
  BackupProtection._();

  static const _methods = MethodChannel('com.hearthbit.mesh/methods');

  static Future<void> exclude(String path) async {
    try {
      await _methods.invokeMethod<void>('excludeFromBackup', {'path': path});
    } on MissingPluginException {
      // Android ya bloquea backup globalmente; tests no registran el plugin.
    } on PlatformException {
      // Defensa en profundidad: no debe impedir una operación de emergencia.
    }
  }
}
