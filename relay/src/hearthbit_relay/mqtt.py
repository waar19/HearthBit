from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import json
import logging
import os
import ssl
import stat
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

try:
    import paho.mqtt.client as paho
    from paho.mqtt.enums import CallbackAPIVersion
    from paho.mqtt.packettypes import PacketTypes
    from paho.mqtt.properties import Properties
except ModuleNotFoundError:
    paho = None
    CallbackAPIVersion = None
    PacketTypes = None
    Properties = None

from .config import MqttConfig
from .link import (
    LinkCapabilities,
    LinkKind,
    LinkReliability,
    RelayLink,
)
from .public_bridge import (
    BoundedIngressQueue,
    PublicBridgePolicy,
    expiry_for,
    has_emergency_coordinates,
    valid_expiry,
)

LOGGER = logging.getLogger(__name__)

ENVELOPE_VERSION = 1
MAX_ENVELOPE_BYTES = 64 * 1024


@dataclass(frozen=True, slots=True)
class BrokerMessage:
    topic: str
    payload: bytes
    retained: bool = False


MessageHandler = Callable[[BrokerMessage], Awaitable[None]]


class MqttBroker(Protocol):
    async def start(self, handler: MessageHandler) -> None: ...

    async def publish(
        self,
        topic: str,
        payload: bytes,
        *,
        qos: int,
        retain: bool,
        expiry_seconds: int,
    ) -> None: ...

    async def stop(self) -> None: ...


class FrameInjector(Protocol):
    async def register_link(self, link: RelayLink) -> int: ...

    async def remove_link(self, link_id: str) -> None: ...

    async def inbound(
        self,
        source_id: str,
        raw: bytes,
        *,
        gateway_path: tuple[bytes, ...] = (),
    ) -> object: ...


@dataclass(frozen=True, slots=True)
class _Envelope:
    frame: bytes
    announcement: bytes
    fingerprint: bytes
    path: tuple[bytes, ...]
    published_at_ms: int
    expires_at_ms: int
    kind: str


class MqttBridge(RelayLink):
    """Policy-enforcing MQTT boundary for authenticated public messages."""

    def __init__(
        self,
        config: MqttConfig,
        core: FrameInjector,
        broker: MqttBroker,
        *,
        identity_material: bytes,
        max_frame_size: int = 2048,
        clock_ms: Callable[[], int] | None = None,
    ) -> None:
        self.config = config
        self._core = core
        self._broker = broker
        self._clock_ms = clock_ms or _now_ms
        self._policy = PublicBridgePolicy(
            max_frame_size=max_frame_size,
            max_message_age_seconds=config.max_message_age_seconds,
            announce_max_age_seconds=config.announce_max_age_seconds,
            future_skew_seconds=config.future_skew_seconds,
            clock_ms=self._clock_ms,
        )
        self._imported: dict[bytes, int] = {}
        self._ingress = BoundedIngressQueue(config.inbound_queue_size)
        self._started = False
        digest = hashlib.blake2s(digest_size=16, person=b"HBitMQTT")
        digest.update(identity_material)
        self.bridge_id = digest.digest()
        self._capabilities = LinkCapabilities(
            id=f"mqtt:{self.bridge_id.hex()}",
            kind=LinkKind.MQTT,
            mtu=max_frame_size,
            broadcast=True,
            unicast=False,
            reliability=LinkReliability.ACKNOWLEDGED,
            background=True,
            max_connections=1,
            cost=20,
        )

    @property
    def capabilities(self) -> LinkCapabilities:
        return self._capabilities

    async def start(self) -> None:
        if self._started:
            return
        self._ingress.start(self._inject)
        await self._broker.start(self._receive)
        try:
            await self._core.register_link(self)
        except Exception:
            await self._broker.stop()
            await self._ingress.stop()
            raise
        self._started = True
        LOGGER.info("MQTT bridge ready with ID %s", self.bridge_id.hex())

    async def stop(self) -> None:
        if not self._started:
            return
        await self._core.remove_link(self.id)
        await self._broker.stop()
        await self._ingress.stop()
        self._started = False

    async def send(self, frame: bytes) -> None:
        await self.send_with_path(frame)

    async def send_with_path(
        self,
        frame: bytes,
        gateway_path: tuple[bytes, ...] = (),
    ) -> None:
        now_ms = self._clock_ms()
        self._purge(now_ms)
        inspected = self._policy.inspect_outbound(frame)
        if inspected is None:
            return
        if (
            not self.config.allow_sensitive_emergency_coordinates
            and has_emergency_coordinates(inspected.packet.payload)
        ):
            LOGGER.warning(
                "MQTT privacy policy blocked emergency coordinates; "
                "enable allow_sensitive_emergency_coordinates explicitly"
            )
            return

        path = tuple(gateway_path)
        if (
            self.bridge_id in path
            or len(path) >= self.config.max_bridge_hops
            or any(len(hop) != 16 for hop in path)
        ):
            return
        path += (self.bridge_id,)
        expires_at_ms = expiry_for(
            inspected,
            published_at_ms=now_ms,
            message_expiry_seconds=self.config.message_expiry_seconds,
            sos_expiry_seconds=self.config.sos_expiry_seconds,
            max_message_age_seconds=self.config.max_message_age_seconds,
        )
        if expires_at_ms <= now_ms:
            return

        payload = _encode_envelope(
            community=self.config.community,
            bridge_id=self.bridge_id,
            path=path,
            fingerprint=inspected.fingerprint,
            frame=inspected.frame,
            announcement=inspected.announcement,
            published_at_ms=now_ms,
            expires_at_ms=expires_at_ms,
            kind=inspected.kind,
        )
        await self._broker.publish(
            self.config.topic,
            payload,
            qos=1,
            retain=False,
            expiry_seconds=max(1, (expires_at_ms - now_ms + 999) // 1000),
        )

    async def _receive(self, message: BrokerMessage) -> None:
        now_ms = self._clock_ms()
        self._purge(now_ms)
        if message.topic != self.config.topic or message.retained:
            return
        envelope = _decode_envelope(
            message.payload,
            community=self.config.community,
            max_hops=self.config.max_bridge_hops,
        )
        if envelope is None or envelope.expires_at_ms <= now_ms:
            return
        if envelope.path[-1] not in self.config.bridge_allowlist:
            return
        if self.bridge_id in envelope.path:
            return

        inspected = self._policy.inspect_inbound(
            frame=envelope.frame,
            announcement=envelope.announcement,
            kind=envelope.kind,
        )
        if inspected is None or not valid_expiry(
            inspected,
            published_at_ms=envelope.published_at_ms,
            expires_at_ms=envelope.expires_at_ms,
            now_ms=now_ms,
            message_expiry_seconds=self.config.message_expiry_seconds,
            sos_expiry_seconds=self.config.sos_expiry_seconds,
            max_message_age_seconds=self.config.max_message_age_seconds,
            future_skew_seconds=self.config.future_skew_seconds,
        ):
            return
        fingerprint = inspected.fingerprint
        if fingerprint != envelope.fingerprint:
            return
        if self._imported.get(fingerprint, 0) > now_ms:
            return

        self._imported[fingerprint] = envelope.expires_at_ms
        if not self._ingress.enqueue(
            envelope.frame,
            envelope.path,
            emergency=inspected.kind == "sos",
        ):
            self._imported.pop(fingerprint, None)
            LOGGER.warning("MQTT ingress queue is full; frame dropped")

    async def _inject(self, frame: bytes, path: tuple[bytes, ...]) -> object:
        return await self._core.inbound(
            self.id,
            frame,
            gateway_path=path,
        )

    def _purge(self, now_ms: int) -> None:
        self._policy.purge(now_ms)
        self._imported = {
            fingerprint: expiry
            for fingerprint, expiry in self._imported.items()
            if expiry > now_ms
        }


class PahoMqttBroker:
    """Paho MQTT v5 adapter. The policy layer can use a fake in tests."""

    def __init__(self, config: MqttConfig) -> None:
        self.config = config
        self._client: Any | None = None
        self._handler: MessageHandler | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._connected: asyncio.Future[None] | None = None

    async def start(self, handler: MessageHandler) -> None:
        if paho is None:
            raise RuntimeError(
                "MQTT support requires the optional 'hearthbit-relay[mqtt]' extra"
            )
        if self._client is not None:
            return
        username, password = _load_credentials(self.config)
        self._handler = handler
        self._loop = asyncio.get_running_loop()
        self._connected = self._loop.create_future()
        client = paho.Client(
            CallbackAPIVersion.VERSION2,
            client_id=f"hearthbit-{os.getpid()}-{id(self):x}",
            protocol=paho.MQTTv5,
        )
        client.on_connect = self._on_connect
        client.on_disconnect = self._on_disconnect
        client.on_message = self._on_message
        client.reconnect_delay_set(min_delay=1, max_delay=60)
        client.tls_set(
            ca_certs=self.config.tls_ca_file or None,
            certfile=self.config.tls_client_cert_file or None,
            keyfile=self.config.tls_client_key_file or None,
            tls_version=ssl.PROTOCOL_TLS_CLIENT,
        )
        client.tls_insecure_set(False)
        if username is not None:
            client.username_pw_set(username, password)
        self._client = client
        result = client.connect_async(
            self.config.host,
            self.config.port,
            keepalive=self.config.keepalive_seconds,
        )
        if result != paho.MQTT_ERR_SUCCESS:
            self._client = None
            raise ConnectionError(f"MQTT connection setup failed with code {result}")
        client.loop_start()
        try:
            await asyncio.wait_for(
                self._connected,
                timeout=self.config.connect_timeout_seconds,
            )
        except Exception:
            await self.stop()
            raise

    async def publish(
        self,
        topic: str,
        payload: bytes,
        *,
        qos: int,
        retain: bool,
        expiry_seconds: int,
    ) -> None:
        if self._client is None or paho is None:
            raise RuntimeError("MQTT broker is not started")
        properties = Properties(PacketTypes.PUBLISH)
        properties.MessageExpiryInterval = expiry_seconds
        info = self._client.publish(
            topic,
            payload,
            qos=qos,
            retain=retain,
            properties=properties,
        )
        if info.rc != paho.MQTT_ERR_SUCCESS:
            raise ConnectionError(f"MQTT publish failed with code {info.rc}")
        await asyncio.to_thread(
            info.wait_for_publish,
            self.config.connect_timeout_seconds,
        )
        if not info.is_published():
            raise TimeoutError("MQTT QoS acknowledgment timed out")

    async def stop(self) -> None:
        client = self._client
        self._client = None
        if client is None:
            return
        client.disconnect()
        await asyncio.to_thread(client.loop_stop)

    def _on_connect(
        self,
        client: Any,
        userdata: object,
        flags: object,
        reason_code: Any,
        properties: object,
    ) -> None:
        del userdata, flags, properties
        loop = self._loop
        connected = self._connected
        if loop is None or connected is None:
            return
        if reason_code.is_failure:
            error = ConnectionError(f"MQTT connection rejected: {reason_code}")
            loop.call_soon_threadsafe(_set_future_exception, connected, error)
            return
        result, _ = client.subscribe(self.config.topic, qos=1)
        if paho is not None and result != paho.MQTT_ERR_SUCCESS:
            error = ConnectionError(f"MQTT subscription failed with code {result}")
            loop.call_soon_threadsafe(_set_future_exception, connected, error)
            return
        loop.call_soon_threadsafe(_set_future_result, connected)

    def _on_disconnect(
        self,
        client: Any,
        userdata: object,
        disconnect_flags: object,
        reason_code: Any,
        properties: object,
    ) -> None:
        del client, userdata, disconnect_flags, properties
        if self._client is not None:
            LOGGER.warning(
                "MQTT disconnected (%s); Paho will reconnect with backoff",
                reason_code,
            )

    def _on_message(self, client: Any, userdata: object, message: Any) -> None:
        del client, userdata
        loop = self._loop
        handler = self._handler
        if loop is None or handler is None:
            return
        broker_message = BrokerMessage(
            topic=str(message.topic),
            payload=bytes(message.payload),
            retained=bool(message.retain),
        )
        future = asyncio.run_coroutine_threadsafe(handler(broker_message), loop)
        future.add_done_callback(_log_handler_result)


def _encode_envelope(
    *,
    community: str,
    bridge_id: bytes,
    path: tuple[bytes, ...],
    fingerprint: bytes,
    frame: bytes,
    announcement: bytes,
    published_at_ms: int,
    expires_at_ms: int,
    kind: str,
) -> bytes:
    document = {
        "v": ENVELOPE_VERSION,
        "community": community,
        "bridge_id": bridge_id.hex(),
        "path": [hop.hex() for hop in path],
        "fingerprint": fingerprint.hex(),
        "frame_b64": base64.b64encode(frame).decode("ascii"),
        "announce_b64": base64.b64encode(announcement).decode("ascii"),
        "published_at_ms": published_at_ms,
        "expires_at_ms": expires_at_ms,
        "kind": kind,
    }
    return json.dumps(document, separators=(",", ":"), sort_keys=True).encode("utf-8")


def _decode_envelope(
    payload: bytes,
    *,
    community: str,
    max_hops: int,
) -> _Envelope | None:
    if not payload or len(payload) > MAX_ENVELOPE_BYTES:
        return None
    try:
        document = json.loads(payload)
        if (
            not isinstance(document, dict)
            or document.get("v") != ENVELOPE_VERSION
            or document.get("community") != community
            or document.get("kind") not in {"message", "sos"}
        ):
            return None
        allowed = {
            "v",
            "community",
            "bridge_id",
            "path",
            "fingerprint",
            "frame_b64",
            "announce_b64",
            "published_at_ms",
            "expires_at_ms",
            "kind",
        }
        if set(document) != allowed:
            return None
        bridge_id = _decode_hex(document["bridge_id"], 16)
        fingerprint = _decode_hex(document["fingerprint"], 16)
        path_values = document["path"]
        if not isinstance(path_values, list) or not 1 <= len(path_values) <= max_hops:
            return None
        path = tuple(_decode_hex(value, 16) for value in path_values)
        if bridge_id != path[-1] or len(set(path)) != len(path):
            return None
        frame = _decode_base64(document["frame_b64"])
        announcement = _decode_base64(document["announce_b64"])
        published_at_ms = _strict_int(document["published_at_ms"])
        expires_at_ms = _strict_int(document["expires_at_ms"])
        if published_at_ms < 0 or expires_at_ms <= published_at_ms:
            return None
        return _Envelope(
            frame,
            announcement,
            fingerprint,
            path,
            published_at_ms,
            expires_at_ms,
            str(document["kind"]),
        )
    except (
        binascii.Error,
        json.JSONDecodeError,
        KeyError,
        TypeError,
        UnicodeDecodeError,
        ValueError,
    ):
        return None


def _load_credentials(config: MqttConfig) -> tuple[str | None, str | None]:
    username = os.environ.get(config.username_env) if config.username_env else None
    password = os.environ.get(config.password_env) if config.password_env else None
    if config.secrets_file:
        secret_path = Path(config.secrets_file)
        if secret_path.is_symlink():
            raise ValueError("MQTT secrets file cannot be a symbolic link")
        file_mode = stat.S_IMODE(secret_path.stat().st_mode)
        if os.name != "nt" and file_mode & 0o077:
            raise PermissionError("MQTT secrets file must not be group/world accessible")
        document = json.loads(secret_path.read_text(encoding="utf-8"))
        if not isinstance(document, dict) or set(document) - {"username", "password"}:
            raise ValueError("MQTT secrets file has unsupported fields")
        file_username = document.get("username")
        file_password = document.get("password")
        if file_username is not None and not isinstance(file_username, str):
            raise ValueError("MQTT secrets username must be text")
        if file_password is not None and not isinstance(file_password, str):
            raise ValueError("MQTT secrets password must be text")
        username = username if username is not None else file_username
        password = password if password is not None else file_password
    if password is not None and username is None:
        raise ValueError("MQTT password requires a username")
    return username, password


def _decode_hex(value: object, size: int) -> bytes:
    if not isinstance(value, str):
        raise TypeError("hex field must be text")
    decoded = bytes.fromhex(value)
    if len(decoded) != size:
        raise ValueError("hex field has invalid length")
    return decoded


def _decode_base64(value: object) -> bytes:
    if not isinstance(value, str):
        raise TypeError("base64 field must be text")
    return base64.b64decode(value, validate=True)


def _strict_int(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError("integer field must be an integer")
    return value


def _set_future_result(future: asyncio.Future[None]) -> None:
    if not future.done():
        future.set_result(None)


def _set_future_exception(
    future: asyncio.Future[None],
    error: Exception,
) -> None:
    if not future.done():
        future.set_exception(error)


def _log_handler_result(future: object) -> None:
    try:
        result = future.result()  # type: ignore[attr-defined]
        del result
    except Exception:
        LOGGER.exception("MQTT message handler failed")


def _now_ms() -> int:
    return time.time_ns() // 1_000_000
