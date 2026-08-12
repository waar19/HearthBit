import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Perfil de emergencia para fotos: reduce resolución y peso antes de
/// transferirlas, ahorrando tiempo de radio y batería en la malla.
class PhotoEmergencyProfile {
  static const int maxDimension = 1600;
  static const int jpegQuality = 70;

  /// Por debajo de este tamaño no vale la pena recomprimir.
  static const int compressThresholdBytes = 1024 * 1024;

  static bool isPhoto(String fileName) {
    final extension = p.extension(fileName).toLowerCase();
    return extension == '.jpg' ||
        extension == '.jpeg' ||
        extension == '.png' ||
        extension == '.webp' ||
        extension == '.bmp';
  }

  /// Comprime la foto en un isolate y devuelve la ruta del JPEG resultante,
  /// o null si el archivo no pudo decodificarse como imagen.
  static Future<String?> compress(String sourcePath) async {
    final directory = await getTemporaryDirectory();
    final targetPath = p.join(
      directory.path,
      'hb_${DateTime.now().millisecondsSinceEpoch}_'
      '${p.basenameWithoutExtension(sourcePath)}.jpg',
    );
    final success = await compute(_compressSync, [sourcePath, targetPath]);
    return success ? targetPath : null;
  }

  static bool _compressSync(List<String> args) {
    final decoded = img.decodeImage(File(args[0]).readAsBytesSync());
    if (decoded == null) return false;
    final oversized =
        decoded.width > maxDimension || decoded.height > maxDimension;
    final resized = oversized
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxDimension : null,
            height: decoded.height > decoded.width ? maxDimension : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    File(
      args[1],
    ).writeAsBytesSync(img.encodeJpg(resized, quality: jpegQuality));
    return true;
  }
}
