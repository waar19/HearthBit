import 'package:path/path.dart' as p;

import '../controllers/transfer_controller.dart';

String guessMimeType(String fileName) {
  final extension = p.extension(fileName).toLowerCase();
  return switch (extension) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.mp4' => 'video/mp4',
    '.mp3' => 'audio/mpeg',
    '.m4a' => 'audio/mp4',
    '.pdf' => 'application/pdf',
    '.txt' => 'text/plain',
    '.zip' => 'application/zip',
    '.apk' => TransferController.androidPackageMimeType,
    _ => 'application/octet-stream',
  };
}
