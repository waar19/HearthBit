from dataclasses import replace

from hearthbit_relay.config import RelayConfig, StoreConfig
from hearthbit_relay.core import RelayCore
from hearthbit_relay.protocol import (
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
