import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

typedef ApkPreparationInvoker = Future<Map<Object?, Object?>?> Function();
typedef ApkShareInvoker = Future<ShareResult> Function(ShareParams params);

enum ApkPreparationStatus { ready, splitInstallation, unsupported, failed }

class ApkSharePreparation {
  const ApkSharePreparation._({
    required this.status,
    this.path,
    this.fileName,
    this.size,
    this.version,
    this.message,
  });

  factory ApkSharePreparation.fromMap(Map<Object?, Object?> value) {
    final status = switch (value['status']) {
      'ready' => ApkPreparationStatus.ready,
      'splitInstallation' => ApkPreparationStatus.splitInstallation,
      'unsupported' => ApkPreparationStatus.unsupported,
      _ => ApkPreparationStatus.failed,
    };
    final path = value['path'] as String?;
    final fileName = value['fileName'] as String?;
    final size = (value['size'] as num?)?.toInt();
    if (status == ApkPreparationStatus.ready &&
        (path == null ||
            path.isEmpty ||
            fileName == null ||
            fileName.isEmpty ||
            size == null ||
            size <= 0)) {
      return const ApkSharePreparation._(
        status: ApkPreparationStatus.failed,
        message: 'Invalid APK preparation response',
      );
    }
    return ApkSharePreparation._(
      status: status,
      path: path,
      fileName: fileName,
      size: size,
      version: value['version'] as String?,
      message: value['message'] as String?,
    );
  }

  const ApkSharePreparation.unsupported()
    : this._(status: ApkPreparationStatus.unsupported);

  const ApkSharePreparation.failed(String message)
    : this._(status: ApkPreparationStatus.failed, message: message);

  final ApkPreparationStatus status;
  final String? path;
  final String? fileName;
  final int? size;
  final String? version;
  final String? message;

  bool get isReady => status == ApkPreparationStatus.ready;
}

class ApkShareService {
  ApkShareService({ApkPreparationInvoker? prepare, ApkShareInvoker? share})
    : _prepare = prepare ?? _prepareFromPlatform,
      _share = share ?? SharePlus.instance.share;

  static const androidPackageMimeType =
      'application/vnd.android.package-archive';
  static const _methods = MethodChannel('com.hearthbit.mesh/methods');

  final ApkPreparationInvoker _prepare;
  final ApkShareInvoker _share;

  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<ApkSharePreparation> prepareInstalledApk() async {
    try {
      final result = await _prepare();
      if (result == null) {
        return const ApkSharePreparation.failed(
          'The platform returned no APK information',
        );
      }
      return ApkSharePreparation.fromMap(result);
    } on MissingPluginException {
      return const ApkSharePreparation.unsupported();
    } on PlatformException catch (error) {
      return ApkSharePreparation.failed(error.message ?? error.code);
    }
  }

  Future<ShareResult> sharePreparedApk({
    required ApkSharePreparation preparation,
    required RenderBox? anchor,
    required String subject,
    required String message,
  }) {
    if (!preparation.isReady) {
      throw StateError('The installed APK is not ready to share');
    }
    final origin = anchor == null || !anchor.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : anchor.localToGlobal(Offset.zero) & anchor.size;
    return _share(
      ShareParams(
        files: [XFile(preparation.path!, mimeType: androidPackageMimeType)],
        text: message,
        subject: subject,
        title: subject,
        sharePositionOrigin: origin,
      ),
    );
  }

  static Future<Map<Object?, Object?>?> _prepareFromPlatform() {
    return _methods.invokeMapMethod<Object?, Object?>(
      'getInstalledApkForShare',
    );
  }
}
