import pytest

from hearthbit_relay.bluez import CentralLink, PeripheralLink
from hearthbit_relay.link import (
    InMemoryRelayLink,
    LinkCapabilities,
    LinkKind,
    LinkReliability,
    RelayLink,
)


def test_bluez_adapters_implement_relay_link_abc() -> None:
    assert issubclass(CentralLink, RelayLink)
    assert issubclass(PeripheralLink, RelayLink)


async def test_memory_link_contract_preserves_opaque_frame() -> None:
    capabilities = LinkCapabilities(
        id="memory:test",
        kind=LinkKind.IN_MEMORY,
        mtu=4,
        broadcast=True,
        unicast=True,
        reliability=LinkReliability.ACKNOWLEDGED,
        background=True,
        max_connections=2,
        cost=0,
    )
    link = InMemoryRelayLink(capabilities)
    frame = bytearray(b"\x01\x02\x03\x04")

    await link.send(frame)
    frame[0] = 9

    assert isinstance(link, RelayLink)
    assert link.capabilities == capabilities
    assert link.sent == [b"\x01\x02\x03\x04"]


async def test_memory_link_rejects_frame_larger_than_mtu() -> None:
    link = InMemoryRelayLink(
        LinkCapabilities(
            id="memory:small",
            kind=LinkKind.IN_MEMORY,
            mtu=2,
            broadcast=False,
            unicast=True,
            reliability=LinkReliability.BEST_EFFORT,
            background=False,
            max_connections=1,
            cost=5,
        )
    )

    with pytest.raises(ValueError, match="MTU"):
        await link.send(b"\x01\x02\x03")

    assert link.sent == []
