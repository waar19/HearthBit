import 'package:hearth_bit/models/mesh_models.dart';
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

  test('solo ofrece archivos a un peer HearthBit conectado', () {
    final hearthBitPeer = MeshPeer(
      id: '0123456789abcdef',
      nickname: 'Ana',
      lastSeen: DateTime.now(),
      secure: true,
      supportsTransfers: true,
    );
    final bitChatPeer = MeshPeer(
      id: 'fedcba9876543210',
      nickname: 'Bob',
      lastSeen: DateTime.now(),
      secure: true,
    );

    expect(canOfferFileToPeer(hearthBitPeer, isOnline: true), isTrue);
    expect(canOfferFileToPeer(hearthBitPeer, isOnline: false), isFalse);
    expect(canOfferFileToPeer(bitChatPeer, isOnline: true), isFalse);
  });

  test('interpreta los cuatro roles del protocolo', () {
    expect(MeshNodeRole.fromWire('PHONE_RELAY'), MeshNodeRole.phoneRelay);
    expect(MeshNodeRole.fromWire('PHONE_BEACON'), MeshNodeRole.phoneBeacon);
    expect(MeshNodeRole.fromWire('INFRA_RELAY'), MeshNodeRole.infraRelay);
    expect(
      MeshNodeRole.fromWire('INFRA_DATA_ANCHOR'),
      MeshNodeRole.infraDataAnchor,
    );
    expect(MeshNodeRole.phoneRelay.canChat, isTrue);
    expect(MeshNodeRole.infraRelay.canChat, isFalse);
  });

  test('presencia BLE genérica queda marcada sin chat', () {
    final presence = GenericBlePresence.fromMap({
      'id': 'aabbccddeeff001122334455',
      'role': 'PHONE_BEACON',
      'kind': 'genericBle',
      'chatAvailable': false,
      'rssi': -72,
      'lastSeen': 1234,
    });

    expect(presence.role, MeshNodeRole.phoneBeacon);
    expect(presence.chatAvailable, isFalse);
    expect(presence.rssi, -72);
    expect(presence.id, hasLength(24));
  });
}
