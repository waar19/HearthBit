import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'offline_tile_cache.dart';
import 'at_rest_file_cipher.dart';

class PrivacyDataEraser {
  PrivacyDataEraser._();

  static const _temporaryPrefixes = [
    'hearthbit_voice_',
    'hb_',
    'hearthbit-rescue-',
    'hearthbit-diagnostics-',
    'hearthbit_plain_',
  ];

  static Future<void> clearResidualFiles() async {
    await OfflineTileCache.clearAll();
    await AtRestFileCipher.destroyKey();
    final temporary = await getTemporaryDirectory();
    if (!await temporary.exists()) return;
    await for (final entity in temporary.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (!_temporaryPrefixes.any(name.startsWith)) continue;
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // El llamador informa que el wipe falló si quedan otros errores; un
        // archivo temporal abierto por el SO se reintentará en el próximo wipe.
      }
    }
  }
}
