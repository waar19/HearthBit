import pytest

from hearthbit_relay.protocol import (
    EPHEMERAL_MESSAGE_TYPES,
    FLAG_ROUTE,
    FLAG_DRILL,
    FLAG_RSR,
    TYPE_EMERGENCY_ACK,
    TYPE_FRAGMENT,
    TYPE_GROUP_MESSAGE,
    TYPE_HBT_CAPABILITY,
    TYPE_KEY_ROTATION,
    TYPE_LEGACY_EMERGENCY_ACK,
    TYPE_LEGACY_HBT_CAPABILITY,
    TYPE_NODE_CAPABILITY,
    TYPE_PREKEY_BUNDLE,
    FragmentReassembler,
    PacketError,
    decode_packet,
    encode_packet,
    relay_fingerprint,
)


def test_codec_matches_v1_layout_and_preserves_extension_flags() -> None:
    encoded = encode_packet(
        message_type=0x11,
        ttl=7,
        timestamp_ms=0x0102030405060708,
        sender_id=bytes(range(0x20, 0x28)),
        recipient_id=bytes(range(0x10, 0x18)),
        payload=b"\x01\x02\x03\x04",
        signature=bytes(range(0xAA, 0xEA)),
        extra_flags=FLAG_RSR,
    )

    assert encoded[:14].hex() == "0111070102030405060708130004"
    decoded = decode_packet(encoded)
    assert decoded.sender_id == bytes(range(0x20, 0x28))
    assert decoded.recipient_id == bytes(range(0x10, 0x18))
    assert decoded.payload == b"\x01\x02\x03\x04"
    assert decoded.signature == bytes(range(0xAA, 0xEA))
    assert decoded.flags & FLAG_RSR


def test_codec_matches_v2_layout_with_route_and_preserves_flags() -> None:
    route = (
        bytes.fromhex("0102030405060708"),
        bytes.fromhex("1112131415161718"),
    )
    encoded = encode_packet(
        version=2,
        message_type=0x11,
        ttl=7,
        timestamp_ms=0x0102030405060708,
        sender_id=bytes(range(0x20, 0x28)),
        recipient_id=bytes(range(0x10, 0x18)),
        route=route,
        payload=b"\x01\x02\x03\x04",
        signature=bytes(range(0xAA, 0xEA)),
        extra_flags=FLAG_RSR | 0x80,
    )

    assert encoded[:16].hex() == "02110701020304050607089b00000004"
    decoded = decode_packet(encoded)
    assert decoded.version == 2
    assert decoded.sender_id == bytes(range(0x20, 0x28))
    assert decoded.recipient_id == bytes(range(0x10, 0x18))
    assert decoded.route == route
    assert decoded.payload == b"\x01\x02\x03\x04"
    assert decoded.signature == bytes(range(0xAA, 0xEA))
    assert decoded.flags & FLAG_ROUTE
    assert decoded.flags & FLAG_RSR
    assert decoded.flags & 0x80


def test_v1_ignores_route_flag_like_android_ios_and_vendor() -> None:
    encoded = bytearray(
        encode_packet(
            message_type=0x02,
            ttl=3,
            timestamp_ms=123,
            sender_id=b"sender01",
            payload=b"mensaje",
        )
    )
    encoded[11] |= FLAG_ROUTE

    decoded = decode_packet(bytes(encoded))

    assert decoded.version == 1
    assert decoded.flags & FLAG_ROUTE
    assert decoded.route == ()
    assert decoded.payload == b"mensaje"


def test_drill_flag_is_signed_versioned_and_fail_closed() -> None:
    content = b"SIMULACRO\n[HB-DRILL|1|CHECKIN|HELP|1700000000000]"
    encoded = encode_packet(
        message_type=0x02,
        ttl=7,
        timestamp_ms=1,
        sender_id=b"sender01",
        payload=content,
        signature=b"\x55" * 64,
        extra_flags=FLAG_DRILL,
    )
    assert decode_packet(encoded).is_drill

    without_flag = bytearray(encoded)
    without_flag[11] &= ~FLAG_DRILL
    with pytest.raises(PacketError, match="drill marker"):
        decode_packet(bytes(without_flag))

    unsigned = bytearray(encoded[:-64])
    unsigned[11] &= ~0x02
    with pytest.raises(PacketError, match="drill"):
        decode_packet(bytes(unsigned))


def test_v2_rejects_truncated_route() -> None:
    encoded = bytearray(
        encode_packet(
            version=2,
            message_type=0x02,
            ttl=3,
            timestamp_ms=123,
            sender_id=b"sender01",
            route=[b"route001"],
            payload=b"x",
        )
    )
    encoded[24] = 2

    with pytest.raises(PacketError, match="route"):
        decode_packet(bytes(encoded))


def test_v1_encoder_rejects_source_route() -> None:
    with pytest.raises(PacketError, match="version 2"):
        encode_packet(
            version=1,
            message_type=0x02,
            ttl=3,
            timestamp_ms=123,
            sender_id=b"sender01",
            route=[b"route001"],
            payload=b"x",
        )


def test_padding_is_validated_and_ignored_by_fingerprint() -> None:
    plain = encode_packet(
        message_type=0x02,
        ttl=7,
        timestamp_ms=123,
        sender_id=b"sender01",
        payload=b"hola",
    )
    padded = encode_packet(
        message_type=0x02,
        ttl=7,
        timestamp_ms=123,
        sender_id=b"sender01",
        payload=b"hola",
        pad=True,
    )

    assert len(padded) == 256
    assert relay_fingerprint(decode_packet(plain)) == relay_fingerprint(
        decode_packet(padded)
    )
    with pytest.raises(PacketError, match="padding"):
        decode_packet(plain + b"\x02\x03")


def test_forwarding_changes_only_ttl_and_keeps_dedup_identity() -> None:
    original = decode_packet(
        encode_packet(
            message_type=0x02,
            ttl=3,
            timestamp_ms=456,
            sender_id=b"sender01",
            payload=b"mensaje",
            pad=True,
        )
    )
    forwarded = decode_packet(original.forwarded_bytes())

    assert forwarded.ttl == 2
    assert original.raw[:2] + original.raw[3:] == (
        forwarded.raw[:2] + forwarded.raw[3:]
    )
    assert relay_fingerprint(original) == relay_fingerprint(forwarded)


def test_rsr_transport_flag_does_not_change_canonical_fingerprint() -> None:
    common = {
        "message_type": 0x02,
        "ttl": 3,
        "timestamp_ms": 456,
        "sender_id": b"sender01",
        "payload": b"mensaje",
    }
    live = decode_packet(encode_packet(**common))
    replay = decode_packet(encode_packet(**common, extra_flags=FLAG_RSR, pad=True))

    assert relay_fingerprint(live) == relay_fingerprint(replay)


def test_v2_forwarding_preserves_version_route_flags_and_every_other_byte() -> None:
    original = decode_packet(
        encode_packet(
            version=2,
            message_type=0x02,
            ttl=5,
            timestamp_ms=456,
            sender_id=b"sender01",
            recipient_id=b"target01",
            route=[b"route001", b"route002"],
            payload=b"mensaje",
            signature=b"s" * 64,
            extra_flags=FLAG_RSR | 0x80,
            pad=True,
        )
    )

    forwarded_bytes = original.forwarded_bytes()
    forwarded = decode_packet(forwarded_bytes)

    assert forwarded.version == 2
    assert forwarded.route == original.route
    assert forwarded.flags == original.flags
    assert forwarded_bytes[2] == original.raw[2] - 1
    assert forwarded_bytes[:2] + forwarded_bytes[3:] == (
        original.raw[:2] + original.raw[3:]
    )
    assert relay_fingerprint(original) == relay_fingerprint(forwarded)


def test_extension_type_codes_do_not_collide_with_upstream_or_firmware() -> None:
    assert TYPE_PREKEY_BUNDLE == TYPE_LEGACY_HBT_CAPABILITY == 0x24
    assert TYPE_NODE_CAPABILITY == TYPE_GROUP_MESSAGE == 0x25
    assert TYPE_LEGACY_EMERGENCY_ACK == 0x29
    assert TYPE_HBT_CAPABILITY == 0x2A
    assert TYPE_EMERGENCY_ACK == 0x2B
    assert TYPE_KEY_ROTATION == 0x2C


def test_only_legacy_emergency_ack_remains_ephemeral() -> None:
    assert TYPE_LEGACY_EMERGENCY_ACK in EPHEMERAL_MESSAGE_TYPES
    assert TYPE_EMERGENCY_ACK not in EPHEMERAL_MESSAGE_TYPES
    assert TYPE_KEY_ROTATION in EPHEMERAL_MESSAGE_TYPES


@pytest.mark.parametrize(
    "message_type",
    (
        TYPE_LEGACY_HBT_CAPABILITY,
        TYPE_HBT_CAPABILITY,
        TYPE_LEGACY_EMERGENCY_ACK,
        TYPE_EMERGENCY_ACK,
    ),
)
def test_decoder_accepts_current_and_legacy_extension_types(message_type: int) -> None:
    decoded = decode_packet(
        encode_packet(
            message_type=message_type,
            ttl=7,
            timestamp_ms=123,
            sender_id=b"sender01",
            recipient_id=b"target01",
            payload=b"\x01",
        )
    )

    assert decoded.message_type == message_type


@pytest.mark.parametrize("ttl", [0, 1])
def test_expired_ttl_cannot_be_forwarded(ttl: int) -> None:
    packet = decode_packet(
        encode_packet(
            message_type=0x02,
            ttl=ttl,
            timestamp_ms=1,
            sender_id=b"sender01",
            payload=b"x",
        )
    )
    with pytest.raises(PacketError, match="TTL"):
        packet.forwarded_bytes()


def test_fragment_reassembler_enforces_type_count_and_set_limits() -> None:
    now = [0.0]
    reassembler = FragmentReassembler(monotonic=lambda: now[0])

    def fragment(
        fragment_id: bytes,
        *,
        index: int = 0,
        total: int = 2,
        original_type: int = 0x02,
    ):
        return decode_packet(
            encode_packet(
                message_type=TYPE_FRAGMENT,
                ttl=4,
                timestamp_ms=index,
                sender_id=b"sender01",
                payload=(
                    fragment_id
                    + index.to_bytes(2, "big")
                    + total.to_bytes(2, "big")
                    + bytes((original_type,))
                    + b"x"
                ),
            )
        )

    assert reassembler.accept(
        fragment(b"too-many", total=257)
    ) is None
    assert reassembler.accept(
        fragment(b"nested!!", total=1, original_type=TYPE_FRAGMENT)
    ) is None

    for index in range(65):
        assert reassembler.accept(fragment(index.to_bytes(8, "big"))) is None
    assert len(reassembler._sets) == 64
    assert reassembler._bytes == 64

    now[0] = 31.0
    assert reassembler.accept(fragment((65).to_bytes(8, "big"))) is None
    assert len(reassembler._sets) == 1
    assert reassembler._bytes == 1
