import pytest

from hearthbit_relay.protocol import (
    FLAG_COMPRESSED,
    PacketError,
    decode_packet,
    encode_packet,
    relay_fingerprint,
)


def test_codec_matches_v1_layout_and_preserves_flags() -> None:
    encoded = encode_packet(
        message_type=0x11,
        ttl=7,
        timestamp_ms=0x0102030405060708,
        sender_id=bytes(range(0x20, 0x28)),
        recipient_id=bytes(range(0x10, 0x18)),
        payload=b"\x01\x02\x03\x04",
        signature=bytes(range(0xAA, 0xEA)),
        extra_flags=FLAG_COMPRESSED,
    )

    assert encoded[:14].hex() == "0111070102030405060708070004"
    decoded = decode_packet(encoded)
    assert decoded.sender_id == bytes(range(0x20, 0x28))
    assert decoded.recipient_id == bytes(range(0x10, 0x18))
    assert decoded.payload == b"\x01\x02\x03\x04"
    assert decoded.signature == bytes(range(0xAA, 0xEA))
    assert decoded.flags & FLAG_COMPRESSED


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
