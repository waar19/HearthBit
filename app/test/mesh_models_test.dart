import 'package:emergency_com/models/mesh_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conserva un mensaje SOS al persistirlo', () {
    final original = MeshMessage(
      id: 'message-1',
      sender: 'Casa 12',
      content: 'SOS|Necesito ayuda|4.7|-74.1',
      senderPeerId: '0123456789abcdef',
      isPrivate: false,
      isMine: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1234),
      channel: 'sos',
    );

    final restored = MeshMessage.fromDatabase(original.toDatabase());

    expect(restored.id, original.id);
    expect(restored.content, original.content);
    expect(restored.isSos, isTrue);
  });
}
