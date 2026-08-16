import 'dart:io';

import 'package:path/path.dart' as p;

import 'photo_profile.dart';

class PreparedPhotoSend {
  const PreparedPhotoSend({required this.path, required this.name});

  final String path;
  final String name;
}

/// Prepara una ruta y nombre de archivo para envío, aplicando compresión
/// opcional cuando la foto supera el umbral de emergencia.
Future<PreparedPhotoSend?> preparePhotoForSend({
  required String path,
  required String name,
  required Future<bool?> Function(int sizeBytes) askCompress,
}) async {
  var resolvedPath = path;
  var resolvedName = name;
  if (!PhotoEmergencyProfile.isPhoto(name)) {
    return PreparedPhotoSend(path: resolvedPath, name: resolvedName);
  }
  final size = await File(path).length();
  if (size <= PhotoEmergencyProfile.compressThresholdBytes) {
    return PreparedPhotoSend(path: resolvedPath, name: resolvedName);
  }
  final compress = await askCompress(size);
  if (compress == null) return null;
  if (compress) {
    final compressed = await PhotoEmergencyProfile.compress(path);
    if (compressed != null) {
      resolvedPath = compressed;
      resolvedName = p.basename(compressed);
    }
  }
  return PreparedPhotoSend(path: resolvedPath, name: resolvedName);
}
