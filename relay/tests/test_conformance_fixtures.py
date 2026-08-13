from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from hearthbit_relay.protocol import (
    FragmentReassembler,
    PacketError,
    canonical_packet_bytes,
    decode_courier_envelope,
    decode_extension_envelope,
    decode_fragment_payload,
    decode_gcs,
    decode_packet,
    decode_sync_request,
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
    assert result.ttl == 0
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
