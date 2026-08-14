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

  test('solo expone trunk largo cuando llega el flag nativo', () {
    final advertised = MeshPeer.fromMap({
      'id': '0123456789abcdef',
      'nickname': 'Bitle',
      'lastSeen': 1234,
      'secure': false,
      'role': 'INFRA_RELAY',
      'hasLongRangeTrunk': true,
    });
    final roleOnly = MeshPeer.fromMap({
      'id': 'fedcba9876543210',
      'nickname': 'LoRa Anchor',
      'lastSeen': 1234,
      'secure': false,
      'role': 'INFRA_RELAY',
    });

    expect(advertised.hasLongRangeTrunk, isTrue);
    expect(roleOnly.hasLongRangeTrunk, isFalse);
  });

  test('online es compatible y nunca deja secure en un peer offline', () {
    final legacy = MeshPeer.fromMap({
      'id': '0123456789abcdef',
      'nickname': 'Legacy',
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
      'secure': true,
    });
    final offline = MeshPeer.fromMap({
      'id': 'fedcba9876543210',
      'nickname': 'Offline',
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
      'online': false,
      'secure': true,
    });

    expect(legacy.online, isTrue);
    expect(legacy.secure, isTrue);
    expect(offline.online, isFalse);
    expect(offline.secure, isFalse);
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

  test('tryParse rechaza peers y mensajes malformados sin lanzar', () {
    expect(MeshPeer.tryParse({'id': 7, 'nickname': 'Ana'}), isNull);
    expect(
      MeshPeer.tryParse({'id': 'peer', 'nickname': 'x' * 81, 'lastSeen': 1234}),
      isNull,
    );
    expect(
      MeshMessage.tryParse({
        'id': 'message',
        'sender': 'Ana',
        'content': 'x' * (MeshMessage.maximumContentBytes + 1),
        'senderPeerId': 'peer',
        'timestamp': 1234,
      }),
      isNull,
    );
    expect(
      MeshMessage.tryParse({
        'id': 'message',
        'sender': 'Ana',
        'content': 'ok',
        'senderPeerId': 'peer',
        'timestamp': 'ayer',
      }),
      isNull,
    );
    expect(
      MeshPeer.tryParse({'id': 'peer', 'nickname': '救' * 30, 'lastSeen': 1234}),
      isNull,
      reason: 'el límite se aplica a bytes UTF-8, no a code units',
    );
    expect(
      GenericBlePresence.tryParse({
        'id': 'presence',
        'kind': 'genericBle',
        'rssi': double.nan,
        'lastSeen': 1234,
      }),
      isNull,
    );
    expect(
      GenericBlePresence.tryParse({
        'id': 'presence',
        'kind': 'genericBle',
        'rssi': -70,
        'lastSeen': double.infinity,
      }),
      isNull,
    );
  });
}
