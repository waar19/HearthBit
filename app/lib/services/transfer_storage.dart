import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_protection.dart';

class TransferStorage {
  TransferStorage._();

  static Future<Directory> transfersDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'hearthbit_transfers'));
    await directory.create(recursive: true);
    await BackupProtection.exclude(directory.path);
    return directory;
  }

  static Future<Directory> cacheDirectory() async {
    final temporary = await getTemporaryDirectory();
    final directory = Directory(
      p.join(temporary.path, 'hearthbit_transfers', 'cache'),
    );
    await directory.create(recursive: true);
    await BackupProtection.exclude(directory.path);
    return directory;
  }

  static Future<Directory> exportDirectory() async {
    final temporary = await getTemporaryDirectory();
    final directory = Directory(
      p.join(temporary.path, 'hearthbit_transfers', 'export'),
    );
    await directory.create(recursive: true);
    await BackupProtection.exclude(directory.path);
    return directory;
  }

  static Future<List<Directory>> managedDirectories() async => [
    await transfersDirectory(),
    await cacheDirectory(),
    await exportDirectory(),
  ];
}
