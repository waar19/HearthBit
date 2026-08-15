from __future__ import annotations

import asyncio
import hashlib
import logging
import struct
import time
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any, Protocol

try:
    import LXMF
    import RNS
except ModuleNotFoundError:
    LXMF = None
    RNS = None

from .config import ReticulumConfig
from .link import LinkCapabilities, LinkKind, LinkReliability, RelayLink
from .public_bridge import PublicBridgePolicy, has_emergency_coordinates

LOGGER = logging.getLogger(__name__)

ENVELOPE_MAGIC = b"HBRNS2"
_HEADER = struct.Struct(">6s16sBHHB")
_KIND_TO_CODE = {"message": 1, "sos": 2}
_CODE_TO_KIND = {value: key for key, value in _KIND_TO_CODE.items()}


def _now_ms() -> int:
    return time.time_ns() // 1_000_000


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


InboundHandler = Callable[[bytes, bytes], Awaitable[None]]


class ReticulumBackend(Protocol):
    async def start(self, handler: InboundHandler) -> bytes: ...

    async def send(self, destination_hash: bytes, payload: bytes) -> bool: ...

    async def stop(self) -> None: ...


class LxmfBackend:
    """Thin optional adapter around the official RNS/LXMF Python packages."""

    def __init__(self, config: ReticulumConfig) -> None:
        self._config = config
        self._router: Any | None = None
        self._source: Any | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._handler: InboundHandler | None = None

    async def start(self, handler: InboundHandler) -> bytes:
        if RNS is None or LXMF is None:
            raise RuntimeError(
                "Reticulum bridge requires the optional 'reticulum' extra"
            )
        self._loop = asyncio.get_running_loop()
        self._handler = handler
        storage = Path(self._config.storage_path)
        storage.mkdir(parents=True, exist_ok=True)
        if self._config.rns_config_path:
            RNS.Reticulum(configdir=self._config.rns_config_path)
        else:
            RNS.Reticulum()
        identity_path = storage / "identity"
        identity = (
            RNS.Identity.from_file(str(identity_path))
            if identity_path.exists()
            else RNS.Identity()
        )
        if not identity_path.exists():
            identity.to_file(str(identity_path))
        self._router = LXMF.LXMRouter(storagepath=str(storage / "lxmf"))
        self._source = self._router.register_delivery_identity(
            identity,
            display_name="HearthBit Relay",
        )
        if self._source is None:
            raise RuntimeError("LXMF could not register the delivery identity")
        self._router.register_delivery_callback(self._delivery_callback)
        self._router.announce(self._source.hash)
        return bytes(self._source.hash)

    async def send(self, destination_hash: bytes, payload: bytes) -> bool:
        if RNS is None or LXMF is None or self._router is None or self._source is None:
            return False

        def _send() -> bool:
            identity = RNS.Identity.recall(destination_hash)
            if identity is None:
                RNS.Transport.request_path(destination_hash)
                return False
            destination = RNS.Destination(
                identity,
                RNS.Destination.OUT,
                RNS.Destination.SINGLE,
                "lxmf",
                "delivery",
            )
            message = LXMF.LXMessage(
                destination,
                self._source,
                payload,
                title="HearthBit frame",
                desired_method=LXMF.LXMessage.DIRECT,
            )
            message.try_propagation_on_fail = True
            self._router.handle_outbound(message)
            return True

        return await asyncio.to_thread(_send)

    async def stop(self) -> None:
        router = self._router
        self._router = None
        self._source = None
        self._handler = None
        if router is not None:
            await asyncio.to_thread(router.exit_handler)

    def _delivery_callback(self, message: Any) -> None:
        if (
            self._loop is None
            or self._handler is None
            or not bool(getattr(message, "signature_validated", False))
        ):
            return
        source_hash = bytes(getattr(message, "source_hash", b""))
        raw_content = getattr(message, "content", b"")
        content = (
            raw_content.encode("utf-8")
            if isinstance(raw_content, str)
            else bytes(raw_content)
        )
        if not source_hash or not content:
            return
        self._loop.call_soon_threadsafe(
            asyncio.create_task,
            self._handler(source_hash, content),
        )


class ReticulumBridge(RelayLink):
    """Allowlisted authenticated-public-message bridge over Reticulum/LXMF."""

    def __init__(
        self,
        config: ReticulumConfig,
        core: FrameInjector,
        backend: ReticulumBackend,
        *,
        identity_material: bytes,
        clock_ms: Callable[[], int] | None = None,
    ) -> None:
        self.config = config
        self._core = core
        self._backend = backend
        self._started = False
        self._policy = PublicBridgePolicy(
            max_frame_size=config.max_frame_size,
            max_message_age_seconds=60 * 60,
            announce_max_age_seconds=10 * 60,
            future_skew_seconds=2 * 60,
            clock_ms=clock_ms or _now_ms,
        )
        digest = hashlib.blake2s(digest_size=16, person=b"HBitRNS")
        digest.update(identity_material)
        self.bridge_id = digest.digest()
        self._capabilities = LinkCapabilities(
            id=f"reticulum:{self.bridge_id.hex()}",
            kind=LinkKind.RETICULUM,
            mtu=config.max_frame_size,
            broadcast=True,
            unicast=False,
            reliability=LinkReliability.ACKNOWLEDGED,
            background=True,
            max_connections=max(1, len(config.destination_hashes)),
            cost=25,
        )

    @property
    def capabilities(self) -> LinkCapabilities:
        return self._capabilities

    async def start(self) -> None:
        if self._started:
            return
        local_hash = await self._backend.start(self._receive)
        if len(local_hash) != 16:
            await self._backend.stop()
            raise RuntimeError("LXMF destination hash must contain 16 bytes")
        try:
            await self._core.register_link(self)
        except Exception:
            await self._backend.stop()
            raise
        self._started = True
        LOGGER.info("Reticulum bridge ready on %s", local_hash.hex())

    async def stop(self) -> None:
        if not self._started:
            return
        await self._core.remove_link(self.id)
        await self._backend.stop()
        self._started = False

    async def send(self, frame: bytes) -> None:
        await self.send_with_path(frame)

    async def send_with_path(
        self,
        frame: bytes,
        gateway_path: tuple[bytes, ...] = (),
    ) -> None:
        if not 0 < len(frame) <= self.config.max_frame_size:
            return
        inspected = self._policy.inspect_outbound(frame)
        if inspected is None:
            return
        if (
            not self.config.allow_sensitive_emergency_coordinates
            and has_emergency_coordinates(inspected.packet.payload)
        ):
            LOGGER.warning(
                "Reticulum privacy policy blocked emergency coordinates; "
                "enable allow_sensitive_emergency_coordinates explicitly"
            )
            return
        path = tuple(gateway_path)
        if (
            self.bridge_id in path
            or len(path) >= self.config.max_gateway_hops
            or any(len(hop) != 16 for hop in path)
        ):
            return
        payload = _encode_envelope(
            frame=inspected.frame,
            announcement=inspected.announcement,
            kind=inspected.kind,
            path=path + (self.bridge_id,),
            max_frame_size=self.config.max_frame_size,
        )
        accepted = 0
        for destination_hash in self.config.destination_hashes:
            if await self._backend.send(destination_hash, payload):
                accepted += 1
        if accepted != len(self.config.destination_hashes):
            raise ConnectionError(
                "one or more LXMF destinations have no known Reticulum path"
            )

    async def _receive(self, source_hash: bytes, payload: bytes) -> None:
        if source_hash not in self.config.source_allowlist:
            return
        decoded = _decode_envelope(
            payload,
            max_frame_size=self.config.max_frame_size,
            max_hops=self.config.max_gateway_hops,
        )
        if decoded is None:
            return
        frame, announcement, kind, path = decoded
        if self.bridge_id in path:
            return
        inspected = self._policy.inspect_inbound(
            frame=frame,
            announcement=announcement,
            kind=kind,
        )
        if inspected is None:
            return
        if (
            not self.config.allow_sensitive_emergency_coordinates
            and has_emergency_coordinates(inspected.packet.payload)
        ):
            return
        await self._core.inbound(
            self.id,
            inspected.frame,
            gateway_path=path,
        )


def _encode_envelope(
    frame: bytes,
    announcement: bytes,
    kind: str,
    path: tuple[bytes, ...],
    *,
    max_frame_size: int,
) -> bytes:
    if (
        not 0 < len(frame) <= max_frame_size
        or not 0 < len(announcement) <= max_frame_size
    ):
        raise ValueError("invalid Reticulum frame size")
    if len(path) > 255 or any(len(hop) != 16 for hop in path):
        raise ValueError("invalid Reticulum gateway path")
    kind_code = _KIND_TO_CODE.get(kind)
    if kind_code is None:
        raise ValueError("invalid Reticulum public message kind")
    bridge_id = path[-1] if path else bytes(16)
    return (
        _HEADER.pack(
            ENVELOPE_MAGIC,
            bridge_id,
            len(path),
            len(frame),
            len(announcement),
            kind_code,
        )
        + b"".join(path)
        + announcement
        + frame
    )


def _decode_envelope(
    payload: bytes,
    *,
    max_frame_size: int,
    max_hops: int,
) -> tuple[bytes, bytes, str, tuple[bytes, ...]] | None:
    if len(payload) < _HEADER.size + 1:
        return None
    magic, bridge_id, count, frame_len, announcement_len, kind_code = (
        _HEADER.unpack_from(payload)
    )
    kind = _CODE_TO_KIND.get(kind_code)
    if (
        magic != ENVELOPE_MAGIC
        or count == 0
        or count > max_hops
        or kind is None
        or not 0 < frame_len <= max_frame_size
        or not 0 < announcement_len <= max_frame_size
    ):
        return None
    path_end = _HEADER.size + count * 16
    announcement_end = path_end + announcement_len
    frame_end = announcement_end + frame_len
    if frame_end != len(payload):
        return None
    path = tuple(
        payload[offset : offset + 16]
        for offset in range(_HEADER.size, path_end, 16)
    )
    if path[-1] != bridge_id or len(set(path)) != len(path):
        return None
    announcement = payload[path_end:announcement_end]
    frame = payload[announcement_end:frame_end]
    return frame, announcement, kind, path
