import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/transfer_models.dart';
import 'transfer_repository.dart';

class ManagedTransferFile {
  const ManagedTransferFile({
    required this.path,
    required this.bytes,
    required this.modifiedAt,
  });

  final String path;
  final int bytes;
  final DateTime modifiedAt;
}

class TransferRetentionPlan {
  const TransferRetentionPlan({
    required this.recordIds,
    required this.filePaths,
  });

  final Set<String> recordIds;
  final Set<String> filePaths;
}

TransferRetentionPlan planTransferRetention({
  required Iterable<TransferRecord> records,
  required Iterable<ManagedTransferFile> files,
  required Map<String, String> recordIdByManagedPath,
  required DateTime now,
  Set<String> activeManagedPaths = const {},
  Duration terminalLifetime = const Duration(days: 30),
  int maximumHistory = 500,
  int maximumManagedBytes = 2 * 1024 * 1024 * 1024,
}) {
  final allRecords = records.toList(growable: false);
  final recordIds = <String>{};
  final filePaths = <String>{};
  final terminalCutoff = now.subtract(terminalLifetime);

  bool expiresByAge(TransferRecord record) =>
      (record.state == TransferState.completed ||
          record.state == TransferState.failed ||
          record.state == TransferState.cancelled) &&
      record.updatedAt.isBefore(terminalCutoff);

  for (final record in allRecords) {
    if (!record.isActive && expiresByAge(record)) {
      recordIds.add(record.id);
    }
  }

  final history = allRecords.where((record) => !record.isActive).toList()
    ..sort((first, second) {
      final updatedOrder = second.updatedAt.compareTo(first.updatedAt);
      if (updatedOrder != 0) return updatedOrder;
      return second.id.compareTo(first.id);
    });
  for (final record in history.skip(maximumHistory < 0 ? 0 : maximumHistory)) {
    recordIds.add(record.id);
  }

  final activePaths = <String>{
    ...activeManagedPaths,
    for (final record in allRecords)
      if (record.isActive && record.filePath != null) record.filePath!,
  };
  final managedFiles = files.toList(growable: false);
  for (final file in managedFiles) {
    final recordId = recordIdByManagedPath[file.path];
    if (recordId != null && recordIds.contains(recordId)) {
      filePaths.add(file.path);
    }
  }

  var retainedBytes = managedFiles
      .where((file) => !filePaths.contains(file.path))
      .fold<int>(0, (total, file) => total + file.bytes);
  if (retainedBytes > maximumManagedBytes) {
    final removableFiles =
        managedFiles
            .where(
              (file) =>
                  !filePaths.contains(file.path) &&
                  !activePaths.contains(file.path),
            )
            .toList()
          ..sort((first, second) {
            final ageOrder = first.modifiedAt.compareTo(second.modifiedAt);
            if (ageOrder != 0) return ageOrder;
            return first.path.compareTo(second.path);
          });
    for (final file in removableFiles) {
      if (retainedBytes <= maximumManagedBytes) break;
      filePaths.add(file.path);
      retainedBytes -= file.bytes;
      final recordId = recordIdByManagedPath[file.path];
      if (recordId != null) recordIds.add(recordId);
    }
  }

  return TransferRetentionPlan(
    recordIds: Set.unmodifiable(recordIds),
    filePaths: Set.unmodifiable(filePaths),
  );
}

class TransferRetentionService {
  TransferRetentionService({
    required this.repository,
    required this.managedDirectories,
    DateTime Function()? clock,
    this.terminalLifetime = const Duration(days: 30),
    this.maximumHistory = 500,
    this.maximumManagedBytes = 2 * 1024 * 1024 * 1024,
  }) : _clock = clock ?? DateTime.now;

  final TransferRepository repository;
  final Future<List<Directory>> Function() managedDirectories;
  final DateTime Function() _clock;
  final Duration terminalLifetime;
  final int maximumHistory;
  final int maximumManagedBytes;

  Future<TransferRetentionPlan> purge() async {
    final roots = await managedDirectories();
    final canonicalRoots = await _canonicalRoots(roots);
    final records = await repository.loadAllForRetention();
    final files = await _scanManagedFiles(roots, canonicalRoots);
    final recordIdByManagedPath = <String, String>{};
    final activeManagedPaths = <String>{};
    for (final record in records) {
      final filePath = record.filePath;
      if (filePath == null) continue;
      final canonical = await canonicalManagedPath(
        filePath,
        canonicalRoots: canonicalRoots,
      );
      if (canonical != null) {
        recordIdByManagedPath[canonical] = record.id;
        if (record.isActive) activeManagedPaths.add(canonical);
      }
    }

    final plan = planTransferRetention(
      records: records,
      files: files,
      recordIdByManagedPath: recordIdByManagedPath,
      now: _clock(),
      activeManagedPaths: activeManagedPaths,
      terminalLifetime: terminalLifetime,
      maximumHistory: maximumHistory,
      maximumManagedBytes: maximumManagedBytes,
    );

    for (final path in plan.filePaths) {
      final canonical = await canonicalManagedPath(
        path,
        canonicalRoots: canonicalRoots,
      );
      if (canonical == null) continue;
      final file = File(canonical);
      if (await file.exists()) await file.delete();
    }
    await repository.deleteMany(plan.recordIds);
    return plan;
  }

  static Future<String?> canonicalManagedPath(
    String candidate, {
    required Iterable<String> canonicalRoots,
  }) async {
    final file = File(candidate);
    if (!await file.exists()) return null;
    final resolved = _normalize(await file.resolveSymbolicLinks());
    for (final root in canonicalRoots) {
      if (p.equals(root, resolved) || p.isWithin(root, resolved)) {
        return resolved;
      }
    }
    return null;
  }

  static Future<bool> isManagedPath(
    String candidate, {
    required Iterable<Directory> roots,
  }) async {
    final canonicalRoots = await _canonicalRoots(roots);
    return await canonicalManagedPath(
          candidate,
          canonicalRoots: canonicalRoots,
        ) !=
        null;
  }

  static Future<bool> deleteManagedFile(
    String candidate, {
    required Iterable<Directory> roots,
  }) async {
    final canonicalRoots = await _canonicalRoots(roots);
    final canonical = await canonicalManagedPath(
      candidate,
      canonicalRoots: canonicalRoots,
    );
    if (canonical == null) return false;
    await File(canonical).delete();
    return true;
  }

  static Future<List<String>> _canonicalRoots(Iterable<Directory> roots) async {
    final canonical = <String>[];
    for (final root in roots) {
      if (!await root.exists()) continue;
      canonical.add(_normalize(await root.resolveSymbolicLinks()));
    }
    return canonical;
  }

  static Future<List<ManagedTransferFile>> _scanManagedFiles(
    Iterable<Directory> roots,
    List<String> canonicalRoots,
  ) async {
    final files = <ManagedTransferFile>[];
    final seen = <String>{};
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final canonical = await canonicalManagedPath(
          entity.path,
          canonicalRoots: canonicalRoots,
        );
        if (canonical == null || !seen.add(canonical)) continue;
        final stat = await File(canonical).stat();
        files.add(
          ManagedTransferFile(
            path: canonical,
            bytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      }
    }
    return files;
  }

  static String _normalize(String value) {
    final normalized = p.normalize(p.absolute(value));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
