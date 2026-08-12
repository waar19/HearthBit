import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

typedef ShareInvoker = Future<ShareResult> Function(ShareParams params);

class InviteShareService {
  InviteShareService._();

  static final Uri repositoryUri = Uri.parse(
    'https://github.com/waar19/HearthBit',
  );
  static final Uri donationUri = Uri.parse(
    'https://buymeacoffee.com/wilmeralzal',
  );

  static Future<ShareResult> share({
    required RenderBox? anchor,
    required String message,
    required String subject,
    ShareInvoker? invoke,
  }) {
    final origin = anchor == null || !anchor.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : anchor.localToGlobal(Offset.zero) & anchor.size;
    final params = ShareParams(
      text: message,
      subject: subject,
      title: subject,
      sharePositionOrigin: origin,
    );
    return (invoke ?? SharePlus.instance.share)(params);
  }
}
