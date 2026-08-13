from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from typing import Any

from dbus_next import BusType, Variant
from dbus_next.aio import MessageBus
from dbus_next.constants import PropertyAccess
from dbus_next.errors import DBusError
from dbus_next.service import ServiceInterface, dbus_property, method

from .config import RelayConfig
from .core import RelayCore
from .link import LinkCapabilities, LinkKind, LinkReliability, RelayLink

LOGGER = logging.getLogger(__name__)

BLUEZ = "org.bluez"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPERTIES = "org.freedesktop.DBus.Properties"
ADAPTER_IFACE = "org.bluez.Adapter1"
DEVICE_IFACE = "org.bluez.Device1"
GATT_MANAGER = "org.bluez.GattManager1"
ADV_MANAGER = "org.bluez.LEAdvertisingManager1"
GATT_SERVICE = "org.bluez.GattService1"
GATT_CHARACTERISTIC = "org.bluez.GattCharacteristic1"
ADVERTISEMENT = "org.bluez.LEAdvertisement1"

SERVICE_UUID = "f47b5e2d-4a9e-4c5a-9b3f-8e1d2c3a4b5c"
SERVICE_UUID_DASHED = "f47b5e2d-4a9e-4c5a-9b3f-8e1d2c3a4b5c"
CHARACTERISTIC_UUID = "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d"
APP_ROOT = "/org/hearthbit/relay"
SERVICE_PATH = f"{APP_ROOT}/service0"
CHARACTERISTIC_PATH = f"{SERVICE_PATH}/char0"
ADVERTISEMENT_PATH = f"{APP_ROOT}/advertisement0"
BLUEZ_FRAME_MTU = 512


class ManagedObjectInterface(ServiceInterface):
    def __init__(self, objects: Callable[[], dict[str, dict[str, dict[str, Variant]]]]):
        super().__init__(OBJECT_MANAGER)
        self._objects = objects

    @method()
    def GetManagedObjects(self) -> "a{oa{sa{sv}}}":
        return self._objects()


class HearthBitService(ServiceInterface):
    def __init__(self) -> None:
        super().__init__(GATT_SERVICE)

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":
        return SERVICE_UUID

    @dbus_property(access=PropertyAccess.READ)
    def Primary(self) -> "b":
        return True

    @dbus_property(access=PropertyAccess.READ)
    def Includes(self) -> "ao":
        return []

    def managed_properties(self) -> dict[str, Variant]:
        return {
            "UUID": Variant("s", self.UUID),
            "Primary": Variant("b", self.Primary),
            "Includes": Variant("ao", self.Includes),
        }


class PeripheralLink(RelayLink):
    def __init__(
        self,
        capabilities: LinkCapabilities,
        characteristic: "HearthBitCharacteristic",
    ) -> None:
        self._capabilities = capabilities
        self._characteristic = characteristic

    @property
    def capabilities(self) -> LinkCapabilities:
        return self._capabilities

    async def send(self, frame: bytes) -> None:
        if len(frame) > self.capabilities.mtu:
            raise ValueError("frame exceeds BlueZ peripheral MTU")
        await self._characteristic.notify(frame)


class HearthBitCharacteristic(ServiceInterface):
    def __init__(self, core: RelayCore) -> None:
        super().__init__(GATT_CHARACTERISTIC)
        self._core = core
        self._value = b""
        self._notifying = False
        self._session = 0
        self._link_id: str | None = None

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":
        return CHARACTERISTIC_UUID

    @dbus_property(access=PropertyAccess.READ)
    def Service(self) -> "o":
        return SERVICE_PATH

    @dbus_property(access=PropertyAccess.READ)
    def Flags(self) -> "as":
        return ["write", "write-without-response", "notify"]

    @dbus_property(access=PropertyAccess.READ)
    def Value(self) -> "ay":
        return self._value

    @dbus_property(access=PropertyAccess.READ)
    def Notifying(self) -> "b":
        return self._notifying

    @method()
    def WriteValue(self, value: "ay", options: "a{sv}") -> "":
        device = _option_value(options, "device", "unknown")
        source_id = f"peripheral-write:{device}"
        asyncio.create_task(self._core.inbound(source_id, bytes(value)))

    @method()
    def StartNotify(self) -> "":
        if self._notifying:
            return
        self._notifying = True
        self._session += 1
        self._link_id = f"peripheral-session:{self._session}"
        self.emit_properties_changed({"Notifying": True})
        link = PeripheralLink(
            LinkCapabilities(
                id=self._link_id,
                kind=LinkKind.BLE,
                mtu=min(self._core.config.max_packet_size, BLUEZ_FRAME_MTU),
                broadcast=True,
                unicast=False,
                reliability=LinkReliability.BEST_EFFORT,
                background=True,
                max_connections=self._core.config.max_central_links,
                cost=10,
            ),
            self,
        )
        asyncio.create_task(self._core.register_link(link))

    @method()
    def StopNotify(self) -> "":
        if not self._notifying:
            return
        link_id = self._link_id
        self._notifying = False
        self._link_id = None
        self.emit_properties_changed({"Notifying": False})
        if link_id is not None:
            asyncio.create_task(self._core.remove_link(link_id))

    async def notify(self, packet: bytes) -> None:
        if not self._notifying:
            raise ConnectionError("no peripheral has notifications enabled")
        self._value = packet
        self.emit_properties_changed({"Value": packet})
        await asyncio.sleep(0)

    def managed_properties(self) -> dict[str, Variant]:
        return {
            "UUID": Variant("s", self.UUID),
            "Service": Variant("o", self.Service),
            "Flags": Variant("as", self.Flags),
            "Value": Variant("ay", self.Value),
            "Notifying": Variant("b", self.Notifying),
        }


class HearthBitAdvertisement(ServiceInterface):
    def __init__(self, local_name: str) -> None:
        super().__init__(ADVERTISEMENT)
        self._local_name = local_name

    @dbus_property(access=PropertyAccess.READ)
    def Type(self) -> "s":
        return "peripheral"

    @dbus_property(access=PropertyAccess.READ)
    def ServiceUUIDs(self) -> "as":
        return [SERVICE_UUID]

    @dbus_property(access=PropertyAccess.READ)
    def LocalName(self) -> "s":
        return self._local_name

    @dbus_property(access=PropertyAccess.READ)
    def Discoverable(self) -> "b":
        return True

    @method()
    def Release(self) -> "":
        LOGGER.info("BlueZ released the HearthBit advertisement")


class CentralLink(RelayLink):
    def __init__(self, capabilities: LinkCapabilities, characteristic: Any) -> None:
        self._capabilities = capabilities
        self._characteristic = characteristic

    @property
    def capabilities(self) -> LinkCapabilities:
        return self._capabilities

    async def send(self, frame: bytes) -> None:
        if len(frame) > self.capabilities.mtu:
            raise ValueError("frame exceeds BlueZ central MTU")
        await self._characteristic.call_write_value(
            frame, {"type": Variant("s", "command")}
        )


class BlueZTransport:
    def __init__(self, config: RelayConfig, core: RelayCore) -> None:
        self.config = config
        self.core = core
        self.bus: MessageBus | None = None
        self._service = HearthBitService()
        self._characteristic = HearthBitCharacteristic(core)
        self._advertisement = HearthBitAdvertisement(config.local_name)
        self._object_manager = ManagedObjectInterface(self._managed_objects)
        self._central_links: dict[str, CentralLink] = {}
        self._scan_task: asyncio.Task[None] | None = None
        self._gatt_manager: Any = None
        self._adv_manager: Any = None

    async def start(self) -> None:
        self.bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
        adapter = await self._proxy(self.config.adapter_path)
        properties = adapter.get_interface(PROPERTIES)
        await properties.call_set(ADAPTER_IFACE, "Powered", Variant("b", True))

        self.bus.export(APP_ROOT, self._object_manager)
        self.bus.export(SERVICE_PATH, self._service)
        self.bus.export(CHARACTERISTIC_PATH, self._characteristic)
        self.bus.export(ADVERTISEMENT_PATH, self._advertisement)

        self._gatt_manager = adapter.get_interface(GATT_MANAGER)
        self._adv_manager = adapter.get_interface(ADV_MANAGER)
        await self._gatt_manager.call_register_application(APP_ROOT, {})
        await self._adv_manager.call_register_advertisement(ADVERTISEMENT_PATH, {})
        LOGGER.info(
            "BlueZ relay active on %s as %s", self.config.adapter, self.config.local_name
        )
        if self.config.central_enabled:
            self._scan_task = asyncio.create_task(self._scan_loop())

    async def stop(self) -> None:
        if self._scan_task is not None:
            self._scan_task.cancel()
            await asyncio.gather(self._scan_task, return_exceptions=True)
        if self._adv_manager is not None:
            try:
                await self._adv_manager.call_unregister_advertisement(ADVERTISEMENT_PATH)
            except DBusError:
                pass
        if self._gatt_manager is not None:
            try:
                await self._gatt_manager.call_unregister_application(APP_ROOT)
            except DBusError:
                pass
        if self.bus is not None:
            self.bus.disconnect()

    async def wait(self) -> None:
        if self.bus is None:
            raise RuntimeError("transport has not started")
        await self.bus.wait_for_disconnect()

    def _managed_objects(self) -> dict[str, dict[str, dict[str, Variant]]]:
        return {
            SERVICE_PATH: {GATT_SERVICE: self._service.managed_properties()},
            CHARACTERISTIC_PATH: {
                GATT_CHARACTERISTIC: self._characteristic.managed_properties()
            },
        }

    async def _scan_loop(self) -> None:
        adapter = await self._proxy(self.config.adapter_path)
        adapter_iface = adapter.get_interface(ADAPTER_IFACE)
        try:
            await adapter_iface.call_set_discovery_filter(
                {
                    "Transport": Variant("s", "le"),
                    "UUIDs": Variant("as", [SERVICE_UUID_DASHED]),
                }
            )
            await adapter_iface.call_start_discovery()
        except DBusError as error:
            if not error.type.endswith(".InProgress"):
                raise

        while True:
            try:
                await self._refresh_central_links()
            except asyncio.CancelledError:
                raise
            except Exception:
                LOGGER.exception("BlueZ discovery refresh failed")
            await asyncio.sleep(self.config.scan_interval_seconds)

    async def _refresh_central_links(self) -> None:
        managed = await self._bluez_managed_objects()
        for path in list(self._central_links):
            device = managed.get(path, {}).get(DEVICE_IFACE)
            if device is None or not _variant_value(device.get("Connected"), False):
                await self.core.remove_link(path)
                self._central_links.pop(path, None)

        if len(self._central_links) >= self.config.max_central_links:
            return
        for path, interfaces in managed.items():
            device = interfaces.get(DEVICE_IFACE)
            if device is None or path in self._central_links:
                continue
            if not is_hearthbit_device(device):
                continue
            if len(self._central_links) >= self.config.max_central_links:
                break
            try:
                await self._connect_central(path)
            except Exception:
                LOGGER.exception("failed to connect relay peer %s", path)

    async def _connect_central(self, device_path: str) -> None:
        device_object = await self._proxy(device_path)
        device = device_object.get_interface(DEVICE_IFACE)
        try:
            await device.call_connect()
        except DBusError as error:
            if not error.type.endswith(".AlreadyConnected"):
                raise

        for _ in range(100):
            if await device.get_services_resolved():
                break
            await asyncio.sleep(0.1)
        else:
            raise TimeoutError(f"GATT services did not resolve for {device_path}")

        managed = await self._bluez_managed_objects()
        characteristic_path = next(
            (
                path
                for path, interfaces in managed.items()
                if path.startswith(f"{device_path}/")
                and GATT_CHARACTERISTIC in interfaces
                and _normalize_uuid(
                    str(
                        _variant_value(
                            interfaces[GATT_CHARACTERISTIC].get("UUID"), ""
                        )
                    )
                )
                == _normalize_uuid(CHARACTERISTIC_UUID)
            ),
            None,
        )
        if characteristic_path is None:
            raise LookupError("HearthBit characteristic not found")

        characteristic_object = await self._proxy(characteristic_path)
        characteristic = characteristic_object.get_interface(GATT_CHARACTERISTIC)
        properties = characteristic_object.get_interface(PROPERTIES)

        def changed(
            interface_name: str,
            values: dict[str, Variant],
            invalidated: list[str],
        ) -> None:
            del invalidated
            if interface_name == GATT_CHARACTERISTIC and "Value" in values:
                asyncio.create_task(
                    self.core.inbound(device_path, bytes(values["Value"].value))
                )

        properties.on_properties_changed(changed)
        await characteristic.call_start_notify()
        link = CentralLink(
            LinkCapabilities(
                id=device_path,
                kind=LinkKind.BLE,
                mtu=min(self.config.max_packet_size, BLUEZ_FRAME_MTU),
                broadcast=False,
                unicast=True,
                reliability=LinkReliability.BEST_EFFORT,
                background=True,
                max_connections=self.config.max_central_links,
                cost=10,
            ),
            characteristic,
        )
        self._central_links[device_path] = link
        await self.core.register_link(link)

    async def _bluez_managed_objects(
        self,
    ) -> dict[str, dict[str, dict[str, Variant]]]:
        root = await self._proxy("/")
        manager = root.get_interface(OBJECT_MANAGER)
        return await manager.call_get_managed_objects()

    async def _proxy(self, path: str) -> Any:
        if self.bus is None:
            raise RuntimeError("system bus is not connected")
        introspection = await self.bus.introspect(BLUEZ, path)
        return self.bus.get_proxy_object(BLUEZ, path, introspection)


def _option_value(options: dict[str, Variant], key: str, default: Any) -> Any:
    value = options.get(key)
    return value.value if isinstance(value, Variant) else default


def _variant_value(value: Variant | None, default: Any) -> Any:
    return value.value if isinstance(value, Variant) else default


def is_hearthbit_device(device: dict[str, Variant]) -> bool:
    uuids = _variant_value(device.get("UUIDs"), [])
    return any(
        _normalize_uuid(str(value)) == _normalize_uuid(SERVICE_UUID)
        for value in uuids
    )


def _normalize_uuid(value: str) -> str:
    return value.lower().replace("-", "")
