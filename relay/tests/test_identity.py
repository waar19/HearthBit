import os
import stat

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from hearthbit_relay.identity import (
    ANNOUNCEMENT_CLOCK_WINDOW_MS,
    NodeRole,
    RelayIdentity,
    canonical_packet_bytes,
    decode_announcement,
    peer_id_from_noise_key,
    validate_announcement,
    verify_packet_signature,
)
from hearthbit_relay.protocol import (
    TYPE_ANNOUNCE,
    TYPE_NODE_CAPABILITY,
    decode_packet,
)


def test_identity_persists_keys_peer_id_and_restrictive_permissions(tmp_path) -> None:
    path = tmp_path / "private" / "identity.json"

    created = RelayIdentity.load_or_create(path)
    loaded = RelayIdentity.load_or_create(path)

    assert loaded.noise_public_key == created.noise_public_key
    assert loaded.signing_public_key == created.signing_public_key
    assert loaded.peer_id == created.peer_id
    assert created.peer_id == peer_id_from_noise_key(created.noise_public_key)
    if os.name != "nt":
        assert stat.S_IMODE(path.stat().st_mode) & 0o077 == 0
        assert stat.S_IMODE(path.parent.stat().st_mode) & 0o077 == 0


def test_announcement_is_bound_to_noise_key_and_signed_canonically(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    raw = identity.build_announcement(
        nickname="Relay Sierra",
        timestamp_ms=1_234,
    )
    packet = decode_packet(raw)

    announcement = validate_announcement(packet, now_ms=1_234)

    assert packet.message_type == TYPE_ANNOUNCE
    assert packet.sender_id == identity.peer_id
    assert announcement is not None
    assert announcement.nickname == "Relay Sierra"
    assert announcement.noise_public_key == identity.noise_public_key
    assert announcement.signing_public_key == identity.signing_public_key
    assert announcement.is_infrastructure
    Ed25519PublicKey.from_public_bytes(identity.signing_public_key).verify(
        packet.signature,
        canonical_packet_bytes(packet),
    )


def test_tampered_announcement_signature_is_rejected(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    raw = bytearray(
        identity.build_announcement(nickname="Relay", timestamp_ms=1_234)
    )
    raw[-1] ^= 0x01

    assert validate_announcement(bytes(raw), now_ms=1_234) is None


def test_announcement_clock_rejects_past_and_future_outside_window(
    tmp_path,
) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    now_ms = 10_000_000
    past = identity.build_announcement(
        nickname="Past",
        timestamp_ms=now_ms - ANNOUNCEMENT_CLOCK_WINDOW_MS - 1,
    )
    future = identity.build_announcement(
        nickname="Future",
        timestamp_ms=now_ms + ANNOUNCEMENT_CLOCK_WINDOW_MS + 1,
    )

    assert validate_announcement(past, now_ms=now_ms) is None
    assert validate_announcement(future, now_ms=now_ms) is None


def test_announcement_clock_accepts_boundaries_and_current_time(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    now_ms = 10_000_000

    for timestamp_ms in (
        now_ms - ANNOUNCEMENT_CLOCK_WINDOW_MS,
        now_ms,
        now_ms + ANNOUNCEMENT_CLOCK_WINDOW_MS,
    ):
        raw = identity.build_announcement(
            nickname="Boundary",
            timestamp_ms=timestamp_ms,
        )
        assert validate_announcement(raw, now_ms=now_ms) is not None


def test_node_capability_roles_are_authenticated_and_wire_compatible(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")

    expected = {
        NodeRole.INFRA_RELAY: b"\x01\x03\x01",
        NodeRole.INFRA_DATA_ANCHOR: b"\x01\x04\x05",
    }
    for role, payload in expected.items():
        packet = decode_packet(
            identity.build_node_capability(
                role=role,
                timestamp_ms=2_000 + role.code,
            )
        )
        assert packet.message_type == TYPE_NODE_CAPABILITY
        assert packet.payload == payload
        assert verify_packet_signature(packet, identity.signing_public_key)


def test_announcement_decoder_rejects_truncated_keys() -> None:
    assert decode_announcement(b"\x01\x01R\x02\x01x\x03\x01y") is None


def test_signature_verification_rejects_wrong_key(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "one.json")
    other = RelayIdentity.load_or_create(tmp_path / "two.json")
    packet = decode_packet(
        identity.build_node_capability(
            role=NodeRole.INFRA_RELAY,
            timestamp_ms=1,
        )
    )

    assert not verify_packet_signature(packet, other.signing_public_key)
    try:
        Ed25519PublicKey.from_public_bytes(other.signing_public_key).verify(
            packet.signature,
            canonical_packet_bytes(packet),
        )
    except InvalidSignature:
        pass
    else:
        raise AssertionError("a foreign Ed25519 key accepted the signature")
