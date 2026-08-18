import asyncio
import time
from dataclasses import replace

import pytest

from hearthbit_relay.config import (
    FloodConfig,
    IdentityVerificationConfig,
    RelayConfig,
    StoreConfig,
)
from hearthbit_relay.core import RelayCore
from hearthbit_relay.identity import (
    ANNOUNCEMENT_CLOCK_WINDOW_MS,
    NodeRole,
    RelayIdentity,
    encode_announcement,
    validate_announcement,
    verify_packet_signature,
)
from hearthbit_relay.link import (
    InMemoryRelayLink,
    LinkCapabilities,
    LinkKind,
    LinkReliability,
)
from hearthbit_relay.protocol import (
    EMERGENCY_ACK_RETENTION_SECONDS,
    FLAG_DRILL,
    TYPE_ANNOUNCE,
    TYPE_EMERGENCY_ACK,
    TYPE_FRAGMENT,
    TYPE_HBT_CAPABILITY,
    TYPE_NODE_CAPABILITY,
    TYPE_NOISE_HANDSHAKE,
    TYPE_REQUEST_SYNC,
    canonical_packet_bytes,
    decode_packet,
    encode_packet,
)
from hearthbit_relay.store import PacketStore


class MemoryLink(InMemoryRelayLink):
    def __init__(
        self,
        link_id: str,
        *,
        kind: LinkKind = LinkKind.IN_MEMORY,
    ) -> None:
        super().__init__(
            LinkCapabilities(
                id=link_id,
                kind=kind,
                mtu=2048,
                broadcast=True,
                unicast=True,
                reliability=LinkReliability.ACKNOWLEDGED,
                background=True,
                max_connections=1,
                cost=0,
            )
        )


def relay_config() -> RelayConfig:
    store = replace(
        StoreConfig(),
        path=":memory:",
        max_packets=10,
        max_bytes=10_000,
        replay_batch=10,
    )
    return replace(
        RelayConfig(),
        store=store,
        trust_store_path=":memory:",
    )


def _announcement_clock_ms() -> int:
    return 0


def signed_message(
    identity: RelayIdentity,
    *,
    payload: bytes,
    timestamp_ms: int,
    message_type: int = 0x02,
    version: int = 1,
    route=(),
    extra_flags: int = 0,
) -> bytes:
    unsigned = decode_packet(
        encode_packet(
            version=version,
            message_type=message_type,
            ttl=7,
            timestamp_ms=timestamp_ms,
            sender_id=identity.peer_id,
            payload=payload,
            route=route,
            signature=b"\x00" * 64 if extra_flags & FLAG_DRILL else None,
            extra_flags=extra_flags,
        )
    )
    return encode_packet(
        version=version,
        message_type=message_type,
        ttl=7,
        timestamp_ms=timestamp_ms,
        sender_id=identity.peer_id,
        payload=payload,
        route=route,
        signature=identity.sign(canonical_packet_bytes(unsigned)),
        extra_flags=extra_flags,
        pad=True,
    )


def signed_emergency_ack(
    identity: RelayIdentity,
    *,
    timestamp_ms: int,
    recipient_id: bytes | None = b"target01",
    payload: bytes = b"\x01" + b"h" * 32,
) -> bytes:
    unsigned = decode_packet(
        encode_packet(
            message_type=TYPE_EMERGENCY_ACK,
            ttl=7,
            timestamp_ms=timestamp_ms,
            sender_id=identity.peer_id,
            recipient_id=recipient_id,
            payload=payload,
        )
    )
    return encode_packet(
        message_type=TYPE_EMERGENCY_ACK,
        ttl=7,
        timestamp_ms=timestamp_ms,
        sender_id=identity.peer_id,
        recipient_id=recipient_id,
        payload=payload,
        signature=identity.sign(canonical_packet_bytes(unsigned)),
        pad=True,
    )


def fragment_frames(
    raw: bytes,
    *,
    sender_id: bytes,
    original_type: int,
    count: int = 3,
) -> list[bytes]:
    chunk_size = (len(raw) + count - 1) // count
    chunks = [
        raw[offset : offset + chunk_size]
        for offset in range(0, len(raw), chunk_size)
    ]
    fragment_id = b"fragtest"
    return [
        encode_packet(
            message_type=TYPE_FRAGMENT,
            ttl=4,
            timestamp_ms=100 + index,
            sender_id=sender_id,
            payload=(
                fragment_id
                + index.to_bytes(2, "big")
                + len(chunks).to_bytes(2, "big")
                + bytes((original_type,))
                + chunk
            ),
        )
        for index, chunk in enumerate(chunks)
    ]


async def test_relay_deduplicates_decrements_ttl_and_replays_store(tmp_path) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    source = MemoryLink("source")
    live_peer = MemoryLink("live")
    await core.register_link(source)
    await core.register_link(live_peer)
    remote = RelayIdentity.load_or_create(tmp_path / "remote.json")
    await core.inbound(
        source.id,
        remote.build_announcement(nickname="Remote", timestamp_ms=100),
    )
    live_peer.sent.clear()
    raw = signed_message(remote, payload=b"mensaje", timestamp_ms=123)

    result = await core.inbound(source.id, raw)
    assert result.accepted
    assert result.forwarded == 1
    assert result.stored
    assert decode_packet(live_peer.sent[0]).ttl == 6
    assert source.sent == []

    duplicate = await core.inbound(live_peer.id, live_peer.sent[0])
    assert duplicate.reason == "duplicate"

    later_peer = MemoryLink("later")
    replayed = await core.register_link(later_peer)
    assert replayed == 1
    assert later_peer.sent == live_peer.sent
    store.close()


async def test_drill_stays_off_internet_bridges(tmp_path) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    source = MemoryLink("source")
    mesh_peer = MemoryLink("mesh")
    mqtt = MemoryLink("mqtt:sink", kind=LinkKind.MQTT)
    await core.register_link(source)
    await core.register_link(mesh_peer)
    await core.register_link(mqtt)
    remote = RelayIdentity.load_or_create(tmp_path / "remote-drill.json")
    await core.inbound(
        source.id,
        remote.build_announcement(nickname="Remote", timestamp_ms=100),
    )
    mesh_peer.sent.clear()
    mqtt.sent.clear()
    raw = signed_message(
        remote,
        payload=b"SIMULACRO\n[HB-DRILL|1|CHECKIN|OK|1700000000000]",
        timestamp_ms=123,
        extra_flags=FLAG_DRILL,
    )

    outbound = await core.inbound(source.id, raw)
    assert outbound.accepted and outbound.forwarded == 1
    assert len(mesh_peer.sent) == 1
    assert mqtt.sent == []

    inbound = await core.inbound("mqtt:source", raw)
    assert not inbound.accepted
    assert inbound.reason == "drill-bridge-forbidden"
    store.close()


async def test_current_emergency_ack_is_stored_directed_and_bounded(
    tmp_path,
) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    live_peer = MemoryLink("live")
    await core.register_link(live_peer)
    remote = RelayIdentity.load_or_create(tmp_path / "remote-ack.json")
    await core.inbound(
        "source",
        remote.build_announcement(nickname="Remote", timestamp_ms=100),
    )
    live_peer.sent.clear()
    now_ms = time.time_ns() // 1_000_000
    raw = signed_emergency_ack(remote, timestamp_ms=now_ms)

    result = await core.inbound("source", raw)

    assert result.accepted and result.forwarded == 1 and result.stored
    [pending] = store.pending_for("later", limit=10, now_ms=now_ms)
    assert decode_packet(pending.packet).message_type == TYPE_EMERGENCY_ACK
    assert pending.expires_at_ms <= (
        now_ms + EMERGENCY_ACK_RETENTION_SECONDS * 1000
    )
    later = MemoryLink("later")
    assert await core.register_link(later) == 1
    assert decode_packet(later.sent[0]).message_type == TYPE_EMERGENCY_ACK
    store.close()


@pytest.mark.parametrize(
    ("recipient_id", "payload"),
    [
        (None, b"\x01" + b"h" * 32),
        (b"target01", b"\x02" + b"h" * 32),
        (b"target01", b"\x01short"),
    ],
)
async def test_ineligible_current_emergency_ack_is_not_stored(
    tmp_path,
    recipient_id: bytes | None,
    payload: bytes,
) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    remote = RelayIdentity.load_or_create(
        tmp_path / f"remote-{len(payload)}-{recipient_id is None}.json"
    )
    await core.inbound(
        "source",
        remote.build_announcement(nickname="Remote", timestamp_ms=100),
    )
    raw = signed_emergency_ack(
        remote,
        timestamp_ms=time.time_ns() // 1_000_000,
        recipient_id=recipient_id,
        payload=payload,
    )

    result = await core.inbound("source", raw)

    assert result.accepted
    assert not result.stored
    assert store.packet_count() == 0
    store.close()


async def test_link_local_and_undirected_handshake_are_not_relayed() -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(config, store)
    peer = MemoryLink("peer")
    await core.register_link(peer)

    request_sync = encode_packet(
        message_type=TYPE_REQUEST_SYNC,
        ttl=7,
        timestamp_ms=1,
        sender_id=b"sender01",
        payload=b"sync",
    )
    handshake = encode_packet(
        message_type=TYPE_NOISE_HANDSHAKE,
        ttl=7,
        timestamp_ms=2,
        sender_id=b"sender01",
        payload=b"noise",
    )

    assert (await core.inbound("source", request_sync)).reason == "link-local"
    assert (
        await core.inbound("source", handshake)
    ).reason == "undirected-handshake"
    assert peer.sent == []
    store.close()


async def test_unsigned_packets_relay_live_but_are_not_persisted() -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(config, store)
    peer = MemoryLink("peer")
    await core.register_link(peer)
    packet = encode_packet(
        message_type=0x02,
        ttl=2,
        timestamp_ms=1,
        sender_id=b"sender01",
        payload=b"publico",
    )

    result = await core.inbound("source", packet)
    assert result.accepted and result.forwarded == 1
    assert not result.stored
    assert store.packet_count() == 0
    store.close()


async def test_v2_route_is_relayed_without_changes_other_than_ttl(tmp_path) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)
    remote = RelayIdentity.load_or_create(tmp_path / "remote.json")
    await core.inbound(
        "source",
        remote.build_announcement(nickname="Remote", timestamp_ms=1),
    )
    peer.sent.clear()
    raw = signed_message(
        remote,
        version=2,
        route=(b"route001", b"route002"),
        payload=b"publico",
        timestamp_ms=2,
    )

    result = await core.inbound("source", raw)

    assert result.accepted and result.forwarded == 1 and result.stored
    assert peer.sent[0][2] == raw[2] - 1
    assert peer.sent[0][:2] + peer.sent[0][3:] == raw[:2] + raw[3:]
    forwarded = decode_packet(peer.sent[0])
    assert forwarded.version == 2
    assert forwarded.route == (b"route001", b"route002")
    store.close()


async def test_ephemeral_announcements_and_capabilities_are_never_persisted(
    tmp_path,
) -> None:
    ephemeral_types = frozenset(
        {
            TYPE_ANNOUNCE,
            TYPE_HBT_CAPABILITY,
            TYPE_NODE_CAPABILITY,
        }
    )
    base = relay_config()
    config = replace(
        base,
        store=replace(base.store, message_types=ephemeral_types),
    )
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)

    remote_identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    packets = [
        remote_identity.build_announcement(
            nickname="Relay remoto",
            timestamp_ms=TYPE_ANNOUNCE,
        ),
        signed_message(
            remote_identity,
            message_type=TYPE_HBT_CAPABILITY,
            timestamp_ms=TYPE_HBT_CAPABILITY,
            payload=b"efimero",
        ),
        remote_identity.build_node_capability(
            role=NodeRole.INFRA_RELAY,
            timestamp_ms=TYPE_NODE_CAPABILITY,
            ttl=3,
        ),
    ]
    for raw in packets:
        result = await core.inbound("source", raw)
        assert result.accepted and result.forwarded == 1
        assert not result.stored

    assert len(peer.sent) == len(ephemeral_types)
    assert store.packet_count() == 0
    store.close()


async def test_identity_is_announced_before_role_on_connect_and_reconnect(
    tmp_path,
) -> None:
    config = relay_config()
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    store = PacketStore(config.store)
    core = RelayCore(config, store, identity)

    first = MemoryLink("first")
    await core.register_link(first)
    await core.remove_link(first.id)
    second = MemoryLink("second")
    await core.register_link(second)

    for link in (first, second):
        assert [decode_packet(raw).message_type for raw in link.sent] == [
            TYPE_ANNOUNCE,
            TYPE_NODE_CAPABILITY,
        ]
        announcement = validate_announcement(link.sent[0])
        assert announcement is not None
        capability = decode_packet(link.sent[1])
        assert capability.payload == NodeRole.INFRA_RELAY.payload
        assert verify_packet_signature(
            capability, announcement.signing_public_key
        )

    echoed = await core.inbound(first.id, first.sent[0])
    assert echoed.reason == "duplicate"
    assert len(second.sent) == 2
    store.close()


async def test_identity_is_announced_periodically(tmp_path) -> None:
    config = replace(relay_config(), announce_interval_seconds=0.01)
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    store = PacketStore(config.store)
    core = RelayCore(config, store, identity)
    peer = MemoryLink("peer")
    await core.register_link(peer)
    peer.sent.clear()

    await core.start()
    for _ in range(20):
        if len(peer.sent) >= 4:
            break
        await asyncio.sleep(0.01)
    await core.stop()

    assert len(peer.sent) >= 4
    assert [decode_packet(raw).message_type for raw in peer.sent[:2]] == [
        TYPE_ANNOUNCE,
        TYPE_NODE_CAPABILITY,
    ]
    store.close()


async def test_invalid_announcement_is_not_relayed(tmp_path) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    raw = bytearray(
        identity.build_announcement(nickname="Impostor", timestamp_ms=1)
    )
    raw[-1] ^= 1

    result = await core.inbound("source", bytes(raw))

    assert not result.accepted
    assert result.reason == "invalid-announce"
    assert peer.sent == []
    store.close()


async def test_stale_announcement_is_not_relayed_or_pinned(tmp_path) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    now_ms = 10_000_000
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=lambda: now_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    peer.sent.clear()
    stale = identity.build_announcement(
        nickname="Stale",
        timestamp_ms=now_ms - ANNOUNCEMENT_CLOCK_WINDOW_MS - 1,
    )

    result = await core.inbound("source", stale)

    assert not result.accepted
    assert result.reason == "invalid-announce"
    assert peer.sent == []
    store.close()


async def test_known_identity_verifies_signatures_and_rejects_key_rotation(
    tmp_path,
) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    attacker = RelayIdentity.load_or_create(tmp_path / "attacker.json")
    announce = identity.build_announcement(nickname="Known", timestamp_ms=1)
    assert (await core.inbound("source", announce)).accepted
    peer.sent.clear()

    valid = signed_message(identity, payload=b"valid", timestamp_ms=2)
    assert (await core.inbound("source", valid)).accepted
    forged = bytearray(signed_message(identity, payload=b"forged", timestamp_ms=3))
    decoded_forged = decode_packet(bytes(forged))
    forged[decoded_forged.wire_length - 1] ^= 1
    result = await core.inbound("source", bytes(forged))
    assert result.reason == "invalid-signature"

    conflicting_payload = encode_announcement(
        nickname="Conflict",
        noise_public_key=identity.noise_public_key,
        signing_public_key=attacker.signing_public_key,
        is_infrastructure=False,
    )
    unsigned = decode_packet(
        encode_packet(
            message_type=TYPE_ANNOUNCE,
            ttl=7,
            timestamp_ms=4,
            sender_id=identity.peer_id,
            payload=conflicting_payload,
        )
    )
    conflict = encode_packet(
        message_type=TYPE_ANNOUNCE,
        ttl=7,
        timestamp_ms=4,
        sender_id=identity.peer_id,
        payload=conflicting_payload,
        signature=attacker.sign(canonical_packet_bytes(unsigned)),
    )
    assert (await core.inbound("source", conflict)).reason == "identity-conflict"
    store.close()


async def test_pinned_identity_survives_core_restart(tmp_path) -> None:
    trust_path = tmp_path / "trusted-peers.json"
    config = replace(relay_config(), trust_store_path=str(trust_path))
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    attacker = RelayIdentity.load_or_create(tmp_path / "attacker.json")

    first_store = PacketStore(config.store)
    first = RelayCore(
        config,
        first_store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    assert (
        await first.inbound(
            "source",
            identity.build_announcement(nickname="Known", timestamp_ms=1),
        )
    ).accepted
    first_store.close()

    second_store = PacketStore(config.store)
    second = RelayCore(
        config,
        second_store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    valid = await second.inbound(
        "source",
        signed_message(identity, payload=b"after-restart", timestamp_ms=2),
    )
    assert valid.accepted and valid.stored

    conflicting_payload = encode_announcement(
        nickname="Conflict",
        noise_public_key=identity.noise_public_key,
        signing_public_key=attacker.signing_public_key,
        is_infrastructure=False,
    )
    unsigned = decode_packet(
        encode_packet(
            message_type=TYPE_ANNOUNCE,
            ttl=7,
            timestamp_ms=3,
            sender_id=identity.peer_id,
            payload=conflicting_payload,
        )
    )
    conflict = encode_packet(
        message_type=TYPE_ANNOUNCE,
        ttl=7,
        timestamp_ms=3,
        sender_id=identity.peer_id,
        payload=conflicting_payload,
        signature=attacker.sign(canonical_packet_bytes(unsigned)),
    )
    assert (await second.inbound("source", conflict)).reason == "identity-conflict"
    second_store.close()


@pytest.mark.parametrize("policy", ("reject", "relay-live"))
async def test_unknown_signed_packet_is_never_forwarded(
    tmp_path,
    policy: str,
) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    packet = signed_message(identity, payload=b"unknown", timestamp_ms=1)
    config = replace(
        relay_config(),
        identity_verification=IdentityVerificationConfig(
            unknown_signed_policy=policy
        ),
    )
    store = PacketStore(config.store)
    core = RelayCore(config, store)
    peer = MemoryLink("peer")
    await core.register_link(peer)

    result = await core.inbound("source", packet)

    assert not result.accepted
    assert result.reason == "unknown-signing-key"
    assert result.forwarded == 0
    assert not result.stored
    assert peer.sent == []
    assert store.packet_count() == 0
    store.close()


async def test_valid_announce_opens_verified_sos_flow_and_rejects_bad_signature(
    tmp_path,
) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)
    rescuer = RelayIdentity.load_or_create(tmp_path / "rescuer.json")

    announcement = await core.inbound(
        "source",
        rescuer.build_announcement(nickname="Rescatista", timestamp_ms=1),
    )
    assert announcement.accepted and announcement.forwarded == 1
    peer.sent.clear()

    sos = signed_message(
        rescuer,
        payload=b"SOS|rescate requerido||",
        timestamp_ms=2,
    )
    accepted = await core.inbound("source", sos)
    assert accepted.accepted and accepted.forwarded == 1 and accepted.stored
    assert len(peer.sent) == 1

    peer.sent.clear()
    invalid = bytearray(
        signed_message(
            rescuer,
            payload=b"SOS|firma alterada||",
            timestamp_ms=3,
        )
    )
    decoded = decode_packet(bytes(invalid))
    invalid[decoded.wire_length - 1] ^= 1
    rejected = await core.inbound("source", bytes(invalid))
    assert not rejected.accepted
    assert rejected.reason == "invalid-signature"
    assert rejected.forwarded == 0
    assert peer.sent == []
    store.close()


async def test_rate_limit_reserves_capacity_for_emergency() -> None:
    config = replace(
        relay_config(),
        flood=FloodConfig(
            sender_rate_per_second=0.001,
            sender_burst=1,
            emergency_rate_per_second=0.001,
            emergency_burst=1,
            bridge_rate_per_second=1,
            bridge_burst=1,
        ),
    )
    store = PacketStore(config.store)
    core = RelayCore(config, store, monotonic=lambda: 10.0)
    normal = lambda timestamp: encode_packet(
        message_type=0x02,
        ttl=3,
        timestamp_ms=timestamp,
        sender_id=b"sender01",
        payload=b"normal",
    )
    emergency = encode_packet(
        message_type=0x02,
        ttl=3,
        timestamp_ms=3,
        sender_id=b"sender01",
        payload=b"SOS|help||",
    )

    assert (await core.inbound("source", normal(1))).accepted
    assert (await core.inbound("source", normal(2))).reason == "rate-limited"
    assert (await core.inbound("source", emergency)).accepted
    store.close()


@pytest.mark.parametrize(
    "bridge_id",
    ("mqtt:bridge-a", "matrix:bridge-a", "reticulum:bridge-a"),
)
async def test_external_bridge_has_independent_bucket_and_sos_reserve(
    bridge_id: str,
) -> None:
    config = replace(
        relay_config(),
        flood=FloodConfig(
            sender_rate_per_second=1,
            sender_burst=10,
            emergency_rate_per_second=1,
            emergency_burst=2,
            bridge_rate_per_second=0.001,
            bridge_burst=1,
            bridge_emergency_rate_per_second=0.001,
            bridge_emergency_burst=1,
        ),
    )
    store = PacketStore(config.store)
    core = RelayCore(config, store, monotonic=lambda: 10.0)

    def packet(sender: bytes, payload: bytes, timestamp: int) -> bytes:
        return encode_packet(
            message_type=0x02,
            ttl=3,
            timestamp_ms=timestamp,
            sender_id=sender,
            payload=payload,
        )

    assert (
        await core.inbound(
            bridge_id,
            packet(b"sender01", b"normal", 1),
        )
    ).accepted
    assert (
        await core.inbound(
            bridge_id,
            packet(b"sender02", b"normal", 2),
        )
    ).reason == "rate-limited"
    assert (
        await core.inbound(
            bridge_id,
            packet(b"sender03", b"SOS|help||", 3),
        )
    ).accepted
    assert (
        await core.inbound(
            bridge_id,
            packet(b"sender04", b"SOS|help||", 4),
        )
    ).reason == "rate-limited"
    store.close()


async def test_fragment_reassembly_marks_inner_packet_as_seen() -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(config, store)
    inner = encode_packet(
        message_type=0x02,
        ttl=5,
        timestamp_ms=1,
        sender_id=b"sender01",
        payload=b"reassembled",
    )
    split = len(inner) // 2
    chunks = (inner[:split], inner[split:])
    for index, chunk in enumerate(chunks):
        fragment = encode_packet(
            message_type=TYPE_FRAGMENT,
            ttl=4,
            timestamp_ms=10 + index,
            sender_id=b"sender01",
            payload=(
                b"fragment"
                + index.to_bytes(2, "big")
                + len(chunks).to_bytes(2, "big")
                + bytes((0x02,))
                + chunk
            ),
        )
        assert (await core.inbound("source", fragment)).accepted

    assert (await core.inbound("source", inner)).reason == "duplicate"
    store.close()


async def test_fragmented_announce_pins_identity_without_second_forward(
    tmp_path,
) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    announce = identity.build_announcement(nickname="Fragmented", timestamp_ms=1)
    fragments = fragment_frames(
        announce,
        sender_id=identity.peer_id,
        original_type=TYPE_ANNOUNCE,
    )

    for fragment in fragments:
        result = await core.inbound("source", fragment)
    assert result.reason == "relayed-reassembled"
    assert len(peer.sent) == len(fragments)
    assert all(
        decode_packet(frame).message_type == TYPE_FRAGMENT
        for frame in peer.sent
    )

    message = signed_message(identity, payload=b"trusted", timestamp_ms=2)
    accepted = await core.inbound("source", message)
    assert accepted.accepted and accepted.stored
    store.close()


async def test_invalid_fragmented_announce_does_not_pin_identity(tmp_path) -> None:
    base = relay_config()
    config = replace(
        base,
        identity_verification=IdentityVerificationConfig(
            unknown_signed_policy="reject"
        ),
    )
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    announce = bytearray(
        identity.build_announcement(nickname="Invalid", timestamp_ms=1)
    )
    decoded = decode_packet(bytes(announce))
    announce[decoded.wire_length - 1] ^= 1

    for fragment in fragment_frames(
        bytes(announce),
        sender_id=identity.peer_id,
        original_type=TYPE_ANNOUNCE,
    ):
        result = await core.inbound("source", fragment)
    assert result.accepted

    message = signed_message(identity, payload=b"untrusted", timestamp_ms=2)
    assert (await core.inbound("source", message)).reason == "unknown-signing-key"
    store.close()


async def test_fragmented_signed_message_is_stored_without_second_forward(
    tmp_path,
) -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(
        config,
        store,
        announcement_clock_ms=_announcement_clock_ms,
    )
    peer = MemoryLink("peer")
    await core.register_link(peer)
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    await core.inbound(
        "source",
        identity.build_announcement(nickname="Known", timestamp_ms=1),
    )
    peer.sent.clear()
    message = signed_message(identity, payload=b"stored", timestamp_ms=2)
    fragments = fragment_frames(
        message,
        sender_id=identity.peer_id,
        original_type=0x02,
    )

    for fragment in fragments:
        result = await core.inbound("source", fragment)
    assert result.reason == "relayed-reassembled"
    assert result.stored
    assert store.packet_count() == 1
    assert len(peer.sent) == len(fragments)
    assert all(
        decode_packet(frame).message_type == TYPE_FRAGMENT
        for frame in peer.sent
    )
    assert (await core.inbound("source", message)).reason == "duplicate"
    store.close()
