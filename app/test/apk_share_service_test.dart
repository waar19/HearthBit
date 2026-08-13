import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/apk_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test('interpreta una copia universal preparada por Android', () async {
    final service = ApkShareService(
      prepare: () async => {
        'status': 'ready',
        'path': r'C:\cache\HearthBit-1.0.0.apk',
        'fileName': 'HearthBit-1.0.0.apk',
        'size': 4096,
        'version': '1.0.0',
      },
    );

    final result = await service.prepareInstalledApk();

    expect(result.status, ApkPreparationStatus.ready);
    expect(result.isReady, isTrue);
    expect(result.size, 4096);
    expect(result.fileName, 'HearthBit-1.0.0.apk');
  });

  test('no presenta una instalación split como APK compartible', () async {
    final service = ApkShareService(
      prepare: () async => {'status': 'splitInstallation', 'splitCount': 3},
    );

    final result = await service.prepareInstalledApk();

    expect(result.status, ApkPreparationStatus.splitInstallation);
    expect(result.isReady, isFalse);
    expect(result.path, isNull);
  });

  test('comparte con MIME APK y anclaje seguro para iPad', () async {
    ShareParams? captured;
    final service = ApkShareService(
      share: (params) async {
        captured = params;
        return ShareResult.unavailable;
      },
    );
    final preparation = ApkSharePreparation.fromMap({
      'status': 'ready',
      'path': '/cache/HearthBit-1.0.0.apk',
      'fileName': 'HearthBit-1.0.0.apk',
      'size': 4096,
    });

    final result = await service.sharePreparedApk(
      preparation: preparation,
      anchor: null,
      subject: 'HearthBit',
      message: 'Install carefully',
    );

    expect(result, ShareResult.unavailable);
    expect(captured?.files, hasLength(1));
    expect(
      captured?.files?.single.mimeType,
      ApkShareService.androidPackageMimeType,
    );
    expect(captured?.text, 'Install carefully');
    expect(captured?.sharePositionOrigin, const Rect.fromLTWH(0, 0, 1, 1));
  });

  test('rechaza respuestas ready incompletas', () {
    final result = ApkSharePreparation.fromMap({
      'status': 'ready',
      'path': '/cache/file.apk',
      'size': 0,
    });

    expect(result.status, ApkPreparationStatus.failed);
  });
}
