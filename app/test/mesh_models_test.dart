import 'package:hearth_bit/models/mesh_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('operational counters accept only aggregate contract fields', () {
    final counters = MeshOperationalCounters.fromNative({
      'openEmergencyRateLimitedKnown': 4,
      'openEmergencyRateLimitedUnknown': -2,
      'relayDampingSuppressed': 3.9,
      'relayDampingScheduled': 8,
      'relayDampingExpired': 7,
      'trustStoreEvictions': 2,
      'trustConflicts': 1,
      'senderId': 'sensitive',
    });

    expect(counters.openEmergencyRateLimitedKnown, 4);
    expect(counters.openEmergencyRateLimitedUnknown, 0);
    expect(counters.relayDampingSuppressed, 3);
    expect(counters.toJson(), isNot(contains('senderId')));
    expect(counters.toJson(), isNot(contains('openSosRateLimitedKnown')));
  });

  test(
    'operational counters read legacy SOS aliases without exporting them',
    () {
      final counters = MeshOperationalCounters.fromNative({
        'openSosRateLimitedKnown': 2,
        'openSosRateLimitedUnknown': 5,
      });

      expect(counters.openEmergencyRateLimitedKnown, 2);
      expect(counters.openEmergencyRateLimitedUnknown, 5);
      expect(counters.toJson(), {
        'openEmergencyRateLimitedKnown': 2,
        'openEmergencyRateLimitedUnknown': 5,
        'relayDampingSuppressed': 0,
        'relayDampingScheduled': 0,
        'relayDampingExpired': 0,
        'trustStoreEvictions': 0,
        'trustConflicts': 0,
      });
    },
  );

  group('triage SOS T1', () {
    const triage = SosTriage(
      peopleCount: 4,
      injuryStatus: SosInjuryStatus.injured,
      injuredCount: 2,
      trappedStatus: SosTrappedStatus.yes,
      primaryNeed: SosPrimaryNeed.extraction,
    );

    test('codifica compacto y conserva los cuatro campos SOS originales', () {
      final content = SosMessageCodec.encode(
        description: 'Ayuda',
        latitude: 4.7,
        longitude: -74.1,
        triage: triage,
      );
      final message = MeshMessage(
        id: 'triage',
        sender: 'Ana',
        content: content,
        senderPeerId: 'peer',
        isPrivate: false,
        isMine: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1234),
        channel: 'sos',
      );

      expect(content, 'SOS|Ayuda|4.7|-74.1|T1|4|2|Y|E');
      expect(content.split('|').sublist(0, 4), [
        'SOS',
        'Ayuda',
        '4.7',
        '-74.1',
      ]);
      expect(message.sosTriage, triage);
      expect(message.sosDescription, 'Ayuda');
      expect(message.sosLatitude, 4.7);
      expect(message.sosLongitude, -74.1);
      expect(triage.copyWith(peopleCount: 5).peopleCount, 5);
    });

    test('mantiene SOS antiguos y descripciones con separadores', () {
      const content = 'SOS|Ayuda|urgente|4.7|-74.1';
      expect(SosMessageCodec.description(content), 'Ayuda|urgente');
      expect(SosMessageCodec.latitude(content), 4.7);
      expect(SosMessageCodec.longitude(content), -74.1);
      expect(SosMessageCodec.triage(content), isNull);
    });

    test('ignora versiones desconocidas y T1 malformado estrictamente', () {
      expect(SosMessageCodec.triage('SOS|Ayuda|4.7|-74.1|T2|4|2|Y|E'), isNull);
      expect(SosMessageCodec.triage('SOS|Ayuda|4.7|-74.1|T1|0|2|Y|E'), isNull);
      expect(
        SosMessageCodec.triage('SOS|Ayuda|4.7|-74.1|T1|4|100|Y|E'),
        isNull,
      );
      expect(SosMessageCodec.triage('SOS|Ayuda|4.7|-74.1|T1|4|N|X|E'), isNull);
      expect(SosMessageCodec.latitude('SOS|Ayuda|4.7|-74.1|T9|future'), 4.7);
    });
  });

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
      external: true,
      canonicalHash:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );

    final restored = MeshMessage.fromDatabase(original.toDatabase());

    expect(restored.id, original.id);
    expect(restored.content, original.content);
    expect(restored.isSos, isTrue);
    expect(restored.external, isTrue);
    expect(restored.canonicalHash, original.canonicalHash);
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

  test('distingue presencia HearthBit de presencia de red externa', () {
    final verified = MeshPeer.fromMap({
      'id': '0123456789abcdef',
      'nickname': 'HearthBit',
      'lastSeen': 1234,
      'supportsTransfers': true,
    });
    final external = MeshPeer.fromMap({
      'id': 'fedcba9876543210',
      'nickname': 'BitChat',
      'lastSeen': 1234,
      'hearthbitVerified': false,
    });

    expect(verified.hearthbitVerified, isTrue);
    expect(external.hearthbitVerified, isFalse);
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
