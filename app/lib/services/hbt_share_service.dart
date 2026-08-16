import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import 'hbt_package.dart';

typedef HbtShareInvoker = Future<ShareResult> Function(ShareParams params);

class HbtShareService {
  HbtShareService({HbtShareInvoker? share})
    : _share = share ?? SharePlus.instance.share;

  final HbtShareInvoker _share;

  Future<ShareResult> share({
    required String path,
    required String fileName,
    Rect? origin,
  }) {
    return _share(
      ShareParams(
        files: [
          XFile(path, mimeType: HbtPackageProtocol.mimeType, name: fileName),
        ],
        subject: fileName,
        title: fileName,
        sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
  }
}
