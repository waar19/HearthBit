import asyncio
import base64
import time
from dataclasses import replace

import pytest

from hearthbit_relay.config import LanConfig, RelayConfig, StoreConfig
from hearthbit_relay.core import RelayCore
from hearthbit_relay.identity import RelayIdentity
from hearthbit_relay.lan import LanTransport
from hearthbit_relay.lan_protocol import (
    HELLO_SIZE,
    ROLE_CLIENT,
    LanProtocolError,
    build_hello,
    opaque_message_id,
    parse_hello,
)
from hearthbit_relay.link import (
    InMemoryRelayLink,
    LinkCapabilities,
    LinkKind,
    LinkReliability,
)
from hearthbit_relay.mdns import DiscoveredGateway, build_announcement, parse_announcement
from hearthbit_relay.protocol import (
    canonical_packet_bytes,
    decode_packet,
    encode_packet,
)
from hearthbit_relay.store import PacketStore


def _lan_config(psk: bytes) -> LanConfig:
    return LanConfig(
        enabled=True,
        listen_host="127.0.0.1",
        port=0,
        psk_base64=base64.b64encode(psk).decode("ascii"),
        discovery=False,
        max_frame_size=2048,
        connect_timeout_seconds=2,
        idle_timeout_seconds=10,
    )


def _core() -> tuple[RelayCore, PacketStore]:
    store_config = replace(
        StoreConfig(),
        path=":memory:",
        max_packets=100,
        max_bytes=100_000,
    )
    config = replace(
        RelayConfig(),
        store=store_config,
        trust_store_path=":memory:",
    )
    store = PacketStore(store_config)
    return RelayCore(config, store), store


def _memory(link_id: str) -> InMemoryRelayLink:
    return InMemoryRelayLink(
        LinkCapabilities(
            id=link_id,
            kind=LinkKind.IN_MEMORY,
            mtu=2048,
            broadcast=True,
            unicast=True,
            reliability=LinkReliability.ACKNOWLEDGED,
            background=True,
            max_connections=1,
            cost=0,
        )
    )


def test_psk_hello_authentication_and_limits() -> None:
    psk = bytes([7]) * 32
    hello = build_hello(
        role=ROLE_CLIENT,
        gateway_id=bytes(range(16)),
        nonce=bytes([9]) * 32,
        max_frame_size=4096,
        psk=psk,
    )

    assert len(hello) == HELLO_SIZE
    assert hello.hex() == (
        "48424c4e0102000102030405060708090a0b0c0d0e0f"
        "0909090909090909090909090909090909090909090909090909090909090909"
        "000010005bf1e102ca63d5c761bb0ec1632012caf0eeaecacd623621f6ac524e5209719e"
    )
    peer = parse_hello(hello, expected_role=ROLE_CLIENT, psk=psk)
    assert peer.gateway_id == bytes(range(16))
    assert peer.max_frame_size == 4096
    with pytest.raises(LanProtocolError, match="authentication"):
        parse_hello(hello, expected_role=ROLE_CLIENT, psk=b"x" * 32)


def test_message_id_is_stable_across_ttl_and_rsr() -> None:
    frame = bytearray(range(32))
    changed = bytearray(frame)
    changed[2] = 1
    changed[11] ^= 0x10

    assert opaque_message_id(frame) == opaque_message_id(changed)
    assert frame[2] == 2


def test_mdns_announcement_exposes_gateway_endpoint() -> None:
    packet = build_announcement(
        instance="Refugio Norte",
        hostname="hearthbit-test.local",
        address="192.168.8.9",
        port=45893,
        gateway_id=b"g" * 16,
    )

    assert parse_announcement(packet, "192.168.8.1") == [
        DiscoveredGateway("192.168.8.9", 45893, b"g" * 16)
    ]


async def test_loopback_gateway_relays_complete_opaque_frame_once_per_core(
    tmp_path,
) -> None:
    psk = b"shared-test-key-material-32-bytes!"
    core_a, store_a = _core()
    core_b, store_b = _core()
    transport_a = LanTransport(
        _lan_config(psk),
        core_a,
        identity_material=b"relay-a",
    )
    transport_b = LanTransport(
        _lan_config(psk),
        core_b,
        identity_material=b"relay-b",
    )
    source = _memory("source")
    sink = _memory("sink")
    await core_a.register_link(source)
    await core_b.register_link(sink)
    await transport_a.start()
    await transport_b.start()
    try:
        await transport_a._connect(
            DiscoveredGateway(
                "127.0.0.1",
                transport_b.status.port,
                transport_b.gateway_id,
            ),
            transport_b.gateway_id,
        )
        for _ in range(50):
            if transport_a.status.connections == transport_b.status.connections == 1:
                break
            await asyncio.sleep(0.01)
        assert transport_a.status.connections == transport_b.status.connections == 1

        identity = RelayIdentity.load_or_create(tmp_path / "sender.json")
        now_ms = time.time_ns() // 1_000_000
        announcement = identity.build_announcement(
            nickname="LAN sender",
            timestamp_ms=now_ms,
        )
        announced = await core_a.inbound(source.id, announcement)
        assert announced.accepted and announced.forwarded == 1
        for _ in range(100):
            if sink.sent:
                break
            await asyncio.sleep(0.01)
        assert len(sink.sent) == 1
        sink.sent.clear()

        unsigned = decode_packet(
            encode_packet(
                message_type=0x02,
                ttl=5,
                timestamp_ms=123,
                sender_id=identity.peer_id,
                payload=b"full opaque BitChat frame",
            )
        )
        raw = encode_packet(
            message_type=0x02,
            ttl=5,
            timestamp_ms=123,
            sender_id=identity.peer_id,
            payload=b"full opaque BitChat frame",
            signature=identity.sign(canonical_packet_bytes(unsigned)),
            pad=True,
        )
        result = await core_a.inbound(source.id, raw)
        assert result.accepted and result.forwarded == 1
        for _ in range(100):
            if sink.sent:
                break
            await asyncio.sleep(0.01)

        assert len(sink.sent) == 1
        assert decode_packet(sink.sent[0]).ttl == 3
        duplicate = await core_a.inbound(source.id, raw)
        assert duplicate.reason == "duplicate"
        await asyncio.sleep(0.05)
        assert len(sink.sent) == 1
    finally:
        await transport_a.stop()
        await transport_b.stop()
        store_a.close()
        store_b.close()
