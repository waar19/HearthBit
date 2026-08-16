import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

Future<bool?> showPhotoCompressDialog(BuildContext context, int sizeBytes) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.photoProfileTitle),
      content: Text(
        context.l10n.photoProfileBody(
          (sizeBytes / (1024 * 1024)).toStringAsFixed(1),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.actionSendOriginal),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.actionCompress),
        ),
      ],
    ),
  );
}
