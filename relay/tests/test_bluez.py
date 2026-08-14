import asyncio

from dbus_fast import Variant

from hearthbit_relay.bluez import HearthBitCharacteristic
from hearthbit_relay.config import RelayConfig


class FakeCore:
    def __init__(self) -> None:
        self.config = RelayConfig()
        self.registered: list[str] = []
        self.removed: list[str] = []
        self.received: list[tuple[str, bytes]] = []

    async def register_link(self, link) -> int:
        self.registered.append(link.id)
        return 0

    async def remove_link(self, link_id: str) -> None:
        self.removed.append(link_id)

    async def inbound(self, source_id: str, raw: bytes) -> object:
        self.received.append((source_id, raw))
        return object()


async def test_peripheral_write_uses_notification_session_as_source() -> None:
    core = FakeCore()
    characteristic = HearthBitCharacteristic(core)

    characteristic.StartNotify()
    await asyncio.sleep(0)
    [session_id] = core.registered
    characteristic.WriteValue(
        b"frame",
        {"device": Variant("o", "/org/bluez/hci0/dev_01")},
    )
    await asyncio.sleep(0)
    characteristic.StopNotify()
    await asyncio.sleep(0)

    assert core.received == [(session_id, b"frame")]
    assert core.removed == [session_id]
