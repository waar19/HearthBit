import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/transfer_controller.dart';

void main() {
  test('autoacepta únicamente notas de voz pequeñas de HearthBit', () {
    expect(
      TransferController.isInlineVoiceNote(
        mimeType: TransferController.voiceNoteMimeType,
        bytes: 1,
      ),
      isTrue,
    );
    expect(
      TransferController.isInlineVoiceNote(
        mimeType: TransferController.voiceNoteMimeType,
        bytes: TransferController.voiceNoteMaxBytes,
      ),
      isTrue,
    );
    expect(
      TransferController.isInlineVoiceNote(
        mimeType: TransferController.voiceNoteMimeType,
        bytes: TransferController.voiceNoteMaxBytes + 1,
      ),
      isFalse,
    );
    expect(
      TransferController.isInlineVoiceNote(mimeType: 'audio/mp4', bytes: 1024),
      isFalse,
    );
  });

  test('nunca ofrece un APK por BLE', () {
    expect(
      TransferController.allowsBleTransfer(
        mimeType: TransferController.androidPackageMimeType,
        bytes: 1024,
      ),
      isFalse,
    );
    expect(
      TransferController.allowsBleTransfer(
        mimeType: 'application/octet-stream',
        bytes: TransferController.bleMaxInlineBytes,
      ),
      isTrue,
    );
    expect(
      TransferController.allowsBleTransfer(
        mimeType: 'application/octet-stream',
        bytes: TransferController.bleMaxInlineBytes + 1,
      ),
      isFalse,
    );
  });
}
