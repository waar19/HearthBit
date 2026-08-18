from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from hearthbit_relay.protocol import (
    FragmentReassembler,
    FLAG_DRILL,
    PacketError,
    TYPE_BEACON_CONTROL,
    TYPE_EMERGENCY_ACK,
    TYPE_EMERGENCY_CAPABILITY,
    TYPE_HBT_CAPABILITY,
    TYPE_KEY_ROTATION,
    TYPE_LEGACY_HBT_CAPABILITY,
    TYPE_RANGING_CONTROL,
    canonical_packet_bytes,
    decode_courier_envelope,
    decode_extension_envelope,
    decode_fragment_payload,
    decode_gcs,
    decode_key_rotation,
    decode_packet,
    decode_sync_request,
    is_drill_public_packet,
    relay_fingerprint,
)

ROOT = Path(__file__).resolve().parents[2] / "tests" / "conformance"
MANIFEST = json.loads((ROOT / "fixtures.v1.json").read_text(encoding="utf-8"))
FIXTURES = {entry["id"]: entry for entry in MANIFEST["fixtures"]}


def fixture(fixture_id: str) -> bytes:
    path = ROOT / FIXTURES[fixture_id]["blob"]
    return bytes.fromhex(path.read_text(encoding="ascii"))


def test_manifest_pins_the_profile_source() -> None:
    assert MANIFEST["schemaVersion"] == 1
    assert (
        MANIFEST["upstreamCommit"]
        == "5156f7de89ec9f6a3429630d90f709b68f6fd7fd"
    )


def test_packet_frames_v1_v2_compression_and_negative_inputs() -> None:
    v1 = decode_packet(fixture("packet.v1.message"))
    assert (v1.version, v1.message_type, v1.ttl, v1.payload) == (1, 2, 7, b"abc")

    drill = decode_packet(fixture("packet.v1.drill_message"))
    assert drill.flags & FLAG_DRILL
    assert drill.is_drill
    assert is_drill_public_packet(drill)

    v2 = decode_packet(fixture("packet.v2.route_signed"))
    assert v2.version == 2
    assert v2.route == (
        bytes.fromhex("1011121314151617"),
        bytes.fromhex("2021222324252627"),
    )
    assert v2.signature == b"\x55" * 64

    expected = bytes(index % 6 for index in range(180))
    assert decode_packet(fixture("packet.v1.raw_deflate")).payload == expected
    assert decode_packet(fixture("packet.v1.zlib_read")).payload == expected

    for fixture_id in sorted(FIXTURES):
        if fixture_id.startswith("packet.invalid."):
            with pytest.raises(PacketError, match="."):
                decode_packet(fixture(fixture_id))


def test_canonical_signature_bytes_and_padding() -> None:
    expected = fixture("signature.canonical.v1_announce")
    packet = decode_packet(expected)
    actual = canonical_packet_bytes(packet)

    assert actual == expected
    assert actual[2] == 0
    assert hashlib.sha256(actual).hexdigest() == (
        "db232b00f54f6c161ab71e8756af799b2165d9f021cd4309aeb9ab203f2028af"
    )


def test_relay_fingerprint_matches_shared_v1_v2_vectors() -> None:
    for fixture_id in (
        "fingerprint.v1.message",
        "fingerprint.v2.route_signed",
    ):
        entry = FIXTURES[fixture_id]
        packet = decode_packet(fixture(fixture_id))
        actual = relay_fingerprint(packet)
        assert actual.hex() == entry["expect"]["relay16"]
        assert actual[:8].hex() == entry["expect"]["firmware8"]


def test_fragment_payload_limits_and_out_of_order_reassembly() -> None:
    fragment = decode_fragment_payload(fixture("fragment.payload.valid"))
    assert (fragment.index, fragment.total, fragment.data) == (
        0x0102,
        0x0304,
        b"\x55\x66",
    )
    for fixture_id in (
        "fragment.invalid.total_zero",
        "fragment.invalid.index_equal_total",
    ):
        with pytest.raises(PacketError, match="fragment"):
            decode_fragment_payload(fixture(fixture_id))

    reassembler = FragmentReassembler()
    second = decode_packet(fixture("fragment.reassemble.out_of_order.1"))
    first = decode_packet(fixture("fragment.reassemble.out_of_order.0"))
    assert reassembler.accept(second) is None
    result = reassembler.accept(first)
    assert result is not None
    assert result.ttl == 7
    assert result.payload == b"abc"


def test_gcs_and_courier_use_production_parsers() -> None:
    request = decode_sync_request(fixture("gcs.request.two_packets"))
    assert (request.p, request.m, request.filter.hex()) == (7, 256, "80a780")
    assert decode_gcs(request) == (130, 210)
    with pytest.raises(PacketError, match="GCS"):
        decode_sync_request(fixture("gcs.invalid.p_zero"))

    envelope = decode_courier_envelope(fixture("courier.envelope.valid"))
    assert envelope.recipient_tag.hex() == "81570f9c02cad65cc297a85facc44ff7"
    assert envelope.expiry_ms == 1_725_000_060_000
    assert len(envelope.ciphertext) == 96
    assert envelope.copies == 4
    with pytest.raises(PacketError, match="TLV|Courier"):
        decode_courier_envelope(fixture("courier.invalid.truncated"))


def test_extension_envelope_is_bounded_and_exact() -> None:
    envelope = decode_extension_envelope(fixture("extension.envelope.hbit"))
    assert (envelope.namespace, envelope.subtype, envelope.version) == ("HBIT", 1, 1)
    assert envelope.payload == b"\x01"
    with pytest.raises(PacketError, match="extension"):
        decode_extension_envelope(fixture("extension.envelope.truncated"))


def test_emergency_extension_payloads_match_registered_types() -> None:
    ids_and_types = {
        "extension.beacon_control.request": TYPE_BEACON_CONTROL,
        "extension.ranging_control.request": TYPE_RANGING_CONTROL,
        "extension.emergency_capability.v1": TYPE_EMERGENCY_CAPABILITY,
        "extension.hbt_capability.canonical": TYPE_HBT_CAPABILITY,
        "extension.emergency_ack.v1": TYPE_EMERGENCY_ACK,
    }
    for fixture_id, expected_type in ids_and_types.items():
        assert FIXTURES[fixture_id]["expect"]["type"] == expected_type

    beacon = fixture("extension.beacon_control.request")
    assert len(beacon) == 27
    assert (beacon[0], beacon[1], beacon[-1]) == (1, 1, 0x07)

    ranging = fixture("extension.ranging_control.request")
    assert len(ranging) == 41
    assert ranging[:4] == bytes((1, 2, 4, 3))
    assert ranging[-3:] == bytes.fromhex("aabbcc")

    assert fixture("extension.emergency_capability.v1") == b"\x01\x01"
    assert fixture("extension.hbt_capability.canonical") == b"\x01"
    assert fixture("extension.emergency_ack.v1") == b"\x01" + bytes(range(32))


def test_legacy_type_0x24_requires_exact_hbt_shape() -> None:
    assert TYPE_LEGACY_HBT_CAPABILITY == 0x24
    assert fixture("extension.legacy_0x24.hbt_alias") == b"\x01"
    assert fixture("extension.legacy_0x24.prekey_candidate") != b"\x01"


def test_key_rotation_is_parsed_without_changing_relay_trust() -> None:
    rotation = decode_key_rotation(fixture("extension.key_rotation.v1"))
    assert TYPE_KEY_ROTATION == 0x2C
    assert rotation.old_peer_id.hex() == "0102030405060708"
    assert rotation.timestamp_ms == 1_700_000_000_000
    assert rotation.sequence == 1
    assert len(rotation.authorization_signature) == 64
    assert rotation.authorization_bytes.startswith(b"HearthBitKeyRotationV1")
    with pytest.raises(PacketError, match="key rotation"):
        decode_key_rotation(fixture("extension.key_rotation.v1")[1:])
    malformed = bytearray(fixture("extension.key_rotation.v1"))
    malformed[9:41] = bytes(32)
    with pytest.raises(PacketError, match="key rotation"):
        decode_key_rotation(bytes(malformed))
