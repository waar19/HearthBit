import asyncio
from dataclasses import replace

from hearthbit_relay.config import RelayConfig, StoreConfig
from hearthbit_relay.core import RelayCore
from hearthbit_relay.identity import (
    NodeRole,
    RelayIdentity,
    validate_announcement,
    verify_packet_signature,
)
from hearthbit_relay.protocol import (
    TYPE_ANNOUNCE,
    TYPE_HBT_CAPABILITY,
    TYPE_NODE_CAPABILITY,
    TYPE_NOISE_HANDSHAKE,
    TYPE_REQUEST_SYNC,
    decode_packet,
    encode_packet,
)
from hearthbit_relay.store import PacketStore


class MemoryLink:
    def __init__(self, link_id: str) -> None:
        self.id = link_id
        self.sent: list[bytes] = []

    async def send(self, packet: bytes) -> None:
        self.sent.append(packet)


def relay_config() -> RelayConfig:
    store = replace(
        StoreConfig(),
        path=":memory:",
        max_packets=10,
        max_bytes=10_000,
        replay_batch=10,
    )
    return replace(RelayConfig(), store=store)


async def test_relay_deduplicates_decrements_ttl_and_replays_store() -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(config, store)
    source = MemoryLink("source")
    live_peer = MemoryLink("live")
    await core.register_link(source)
    await core.register_link(live_peer)
    raw = encode_packet(
        message_type=0x02,
        ttl=7,
        timestamp_ms=123,
        sender_id=b"sender01",
        payload=b"mensaje",
        signature=b"s" * 64,
        pad=True,
    )

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


async def test_v2_route_is_relayed_without_changes_other_than_ttl() -> None:
    config = relay_config()
    store = PacketStore(config.store)
    core = RelayCore(config, store)
    peer = MemoryLink("peer")
    await core.register_link(peer)
    raw = encode_packet(
        version=2,
        message_type=0x02,
        ttl=4,
        timestamp_ms=1,
        sender_id=b"sender01",
        recipient_id=b"target01",
        route=[b"route001", b"route002"],
        payload=b"publico",
        signature=b"s" * 64,
        extra_flags=0x90,
        pad=True,
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
    core = RelayCore(config, store)
    peer = MemoryLink("peer")
    await core.register_link(peer)

    remote_identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    packets = [
        remote_identity.build_announcement(
            nickname="Relay remoto",
            timestamp_ms=TYPE_ANNOUNCE,
        ),
        encode_packet(
            message_type=TYPE_HBT_CAPABILITY,
            ttl=3,
            timestamp_ms=TYPE_HBT_CAPABILITY,
            sender_id=b"sender01",
            payload=b"efimero",
            signature=b"s" * 64,
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
    await asyncio.sleep(0.025)
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
    core = RelayCore(config, store)
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
