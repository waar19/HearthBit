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
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from .config import MatrixConfig
from .link import LinkCapabilities, LinkKind, LinkReliability, RelayLink
from .public_bridge import PublicBridgePolicy, expiry_for, valid_expiry

LOGGER = logging.getLogger(__name__)

MATRIX_METADATA_KEY = "org.hearthbit.bridge.v1"
MATRIX_ENVELOPE_VERSION = 1
MAX_MATRIX_DOCUMENT_BYTES = 4 * 1024 * 1024
MAX_EVENT_CONTENT_BYTES = 96 * 1024


@dataclass(frozen=True, slots=True)
class MatrixEvent:
    room_id: str
    sender: str
    event_id: str
    origin_server_ts: int
    content: dict[str, object]


MatrixEventHandler = Callable[[MatrixEvent], Awaitable[None]]


class MatrixApi(Protocol):
    async def start(
        self,
        handler: MatrixEventHandler,
        room_ids: tuple[str, ...],
    ) -> None: ...

    async def send_message(
        self,
        room_id: str,
        transaction_id: str,
        content: dict[str, object],
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
class _MatrixEnvelope:
    body: str
    frame: bytes
    announcement: bytes
    fingerprint: bytes
    path: tuple[bytes, ...]
    published_at_ms: int
    expires_at_ms: int
    kind: str


class MatrixBridge(RelayLink):
    """Matrix room bridge for authenticated public HearthBit frames only."""

    def __init__(
        self,
        config: MatrixConfig,
        core: FrameInjector,
        api: MatrixApi,
        *,
        identity_material: bytes,
        max_frame_size: int = 2048,
        clock_ms: Callable[[], int] | None = None,
    ) -> None:
        self.config = config
        self._core = core
        self._api = api
        self._clock_ms = clock_ms or _now_ms
        self._policy = PublicBridgePolicy(
            max_frame_size=max_frame_size,
            max_message_age_seconds=config.max_message_age_seconds,
            announce_max_age_seconds=config.announce_max_age_seconds,
            future_skew_seconds=config.future_skew_seconds,
            clock_ms=self._clock_ms,
        )
        self._imported: dict[bytes, int] = {}
        self._started = False
        digest = hashlib.blake2s(digest_size=16, person=b"HBitMtrx")
        digest.update(identity_material)
        self.bridge_id = digest.digest()
        self._capabilities = LinkCapabilities(
            id=f"matrix:{self.bridge_id.hex()}",
            kind=LinkKind.MATRIX,
            mtu=max_frame_size,
            broadcast=True,
            unicast=False,
            reliability=LinkReliability.ACKNOWLEDGED,
            background=True,
            max_connections=max(1, len(config.rooms)),
            cost=30,
        )

    @property
    def capabilities(self) -> LinkCapabilities:
        return self._capabilities

    async def start(self) -> None:
        if self._started:
            return
        await self._api.start(self._receive, self.config.rooms)
        try:
            await self._core.register_link(self)
        except Exception:
            await self._api.stop()
            raise
        self._started = True

    async def stop(self) -> None:
        if not self._started:
            return
        await self._core.remove_link(self.id)
        await self._api.stop()
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

        content = _encode_content(
            bridge_id=self.bridge_id,
            path=path,
            fingerprint=inspected.fingerprint,
            frame=inspected.frame,
            announcement=inspected.announcement,
            published_at_ms=now_ms,
            expires_at_ms=expires_at_ms,
            kind=inspected.kind,
            body=_safe_body(inspected.packet.payload, inspected.kind),
        )
        for room_id in self.config.rooms:
            room_digest = hashlib.blake2s(
                room_id.encode("utf-8"),
                digest_size=6,
                person=b"HBitRoom",
            ).hexdigest()
            transaction_id = f"hbit-{inspected.fingerprint.hex()}-{room_digest}"
            await self._api.send_message(room_id, transaction_id, content)

    async def _receive(self, event: MatrixEvent) -> None:
        now_ms = self._clock_ms()
        self._purge(now_ms)
        if (
            event.room_id not in self.config.rooms
            or event.sender not in self.config.sender_allowlist
            or event.sender == self.config.bot_user_id
        ):
            return
        envelope = _decode_content(
            event.content,
            max_hops=self.config.max_bridge_hops,
        )
        if (
            envelope is None
            or envelope.expires_at_ms <= now_ms
            or self.bridge_id in envelope.path
        ):
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
        if (
            inspected.fingerprint != envelope.fingerprint
            or envelope.body != _safe_body(inspected.packet.payload, inspected.kind)
        ):
            return
        if self._imported.get(inspected.fingerprint, 0) > now_ms:
            return
        self._imported[inspected.fingerprint] = envelope.expires_at_ms
        await self._core.inbound(
            self.id,
            inspected.frame,
            gateway_path=envelope.path,
        )

    def _purge(self, now_ms: int) -> None:
        self._policy.purge(now_ms)
        self._imported = {
            fingerprint: expiry
            for fingerprint, expiry in self._imported.items()
            if expiry > now_ms
        }


class HttpMatrixApi:
    """Minimal Matrix Client-Server adapter with no room-join capability."""

    def __init__(self, config: MatrixConfig) -> None:
        self.config = config
        self._handler: MatrixEventHandler | None = None
        self._room_ids: tuple[str, ...] = ()
        self._token: str | None = None
        self._since: str | None = None
        self._sync_task: asyncio.Task[None] | None = None
        self._ssl_context = ssl.create_default_context(
            cafile=config.tls_ca_file or None
        )

    async def start(
        self,
        handler: MatrixEventHandler,
        room_ids: tuple[str, ...],
    ) -> None:
        if self._sync_task is not None:
            return
        self._token = _load_access_token(self.config)
        self._handler = handler
        self._room_ids = tuple(room_ids)
        self._sync_task = asyncio.create_task(self._sync_loop())

    async def send_message(
        self,
        room_id: str,
        transaction_id: str,
        content: dict[str, object],
    ) -> None:
        if self._token is None:
            raise RuntimeError("Matrix API is not started")
        if room_id not in self._room_ids:
            raise ValueError("Matrix room is not configured")
        path = (
            "/_matrix/client/v3/rooms/"
            f"{urllib.parse.quote(room_id, safe='')}/send/m.room.message/"
            f"{urllib.parse.quote(transaction_id, safe='')}"
        )
        query = self._application_service_query()
        await self._request("PUT", path, query=query, document=content)

    async def stop(self) -> None:
        task = self._sync_task
        self._sync_task = None
        if task is not None:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        self._handler = None
        self._room_ids = ()
        self._token = None
        self._since = None

    async def _sync_loop(self) -> None:
        while True:
            try:
                await self._sync_once()
            except asyncio.CancelledError:
                raise
            except Exception:
                LOGGER.warning("Matrix sync failed; retrying")
                await asyncio.sleep(2)

    async def _sync_once(self) -> None:
        filter_document = {
            "account_data": {"not_types": ["*"]},
            "presence": {"not_types": ["*"]},
            "room": {
                "rooms": list(self._room_ids),
                "account_data": {"not_types": ["*"]},
                "ephemeral": {"not_types": ["*"]},
                "state": {"not_types": ["*"]},
                "timeline": {"types": ["m.room.message"], "limit": 50},
            },
        }
        query: dict[str, str | int] = {
            "timeout": self.config.sync_timeout_seconds * 1000,
            "filter": json.dumps(filter_document, separators=(",", ":")),
        }
        if self._since is not None:
            query["since"] = self._since
        query.update(self._application_service_query())
        response = await self._request("GET", "/_matrix/client/v3/sync", query=query)
        next_batch = response.get("next_batch")
        if not isinstance(next_batch, str) or not next_batch:
            raise ValueError("Matrix sync response is missing next_batch")

        rooms = response.get("rooms", {})
        joined = rooms.get("join", {}) if isinstance(rooms, dict) else {}
        handler = self._handler
        if isinstance(joined, dict) and handler is not None:
            for room_id in self._room_ids:
                room = joined.get(room_id)
                if not isinstance(room, dict):
                    continue
                timeline = room.get("timeline", {})
                events = timeline.get("events", []) if isinstance(timeline, dict) else []
                if not isinstance(events, list):
                    continue
                for raw_event in events:
                    event = _parse_matrix_event(room_id, raw_event)
                    if event is not None:
                        try:
                            await handler(event)
                        except Exception:
                            LOGGER.warning("Matrix event handling failed")
        self._since = next_batch

    async def _request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str | int] | None = None,
        document: dict[str, object] | None = None,
    ) -> dict[str, object]:
        if self._token is None:
            raise RuntimeError("Matrix API is not started")
        query_text = urllib.parse.urlencode(query or {})
        url = f"{self.config.homeserver_url}{path}"
        if query_text:
            url = f"{url}?{query_text}"
        payload = (
            json.dumps(document, separators=(",", ":")).encode("utf-8")
            if document is not None
            else None
        )
        return await asyncio.to_thread(
            self._request_sync,
            method,
            url,
            payload,
        )

    def _request_sync(
        self,
        method: str,
        url: str,
        payload: bytes | None,
    ) -> dict[str, object]:
        token = self._token
        if token is None:
            raise RuntimeError("Matrix API is not started")
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        }
        if payload is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            url,
            data=payload,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(
                request,
                timeout=self.config.request_timeout_seconds,
                context=self._ssl_context,
            ) as response:
                raw = response.read(MAX_MATRIX_DOCUMENT_BYTES + 1)
        except urllib.error.HTTPError as error:
            raise ConnectionError(
                f"Matrix request failed with HTTP status {error.code}"
            ) from None
        if len(raw) > MAX_MATRIX_DOCUMENT_BYTES:
            raise ValueError("Matrix response is too large")
        decoded = json.loads(raw)
        if not isinstance(decoded, dict):
            raise ValueError("Matrix response must be a JSON object")
        return decoded

    def _application_service_query(self) -> dict[str, str]:
        if not self.config.application_service_mode:
            return {}
        return {"user_id": self.config.bot_user_id}


def _encode_content(
    *,
    bridge_id: bytes,
    path: tuple[bytes, ...],
    fingerprint: bytes,
    frame: bytes,
    announcement: bytes,
    published_at_ms: int,
    expires_at_ms: int,
    kind: str,
    body: str,
) -> dict[str, object]:
    return {
        "msgtype": "m.text",
        "body": body,
        MATRIX_METADATA_KEY: {
            "v": MATRIX_ENVELOPE_VERSION,
            "bridge_id": bridge_id.hex(),
            "path": [hop.hex() for hop in path],
            "fingerprint": fingerprint.hex(),
            "frame_b64": base64.b64encode(frame).decode("ascii"),
            "announce_b64": base64.b64encode(announcement).decode("ascii"),
            "published_at_ms": published_at_ms,
            "expires_at_ms": expires_at_ms,
            "kind": kind,
        },
    }


def _decode_content(
    content: dict[str, object],
    *,
    max_hops: int,
) -> _MatrixEnvelope | None:
    try:
        encoded = json.dumps(content, separators=(",", ":")).encode("utf-8")
        if len(encoded) > MAX_EVENT_CONTENT_BYTES:
            return None
        metadata = content.get(MATRIX_METADATA_KEY)
        if (
            content.get("msgtype") != "m.text"
            or not isinstance(content.get("body"), str)
            or not isinstance(metadata, dict)
            or metadata.get("v") != MATRIX_ENVELOPE_VERSION
            or metadata.get("kind") not in {"message", "sos"}
        ):
            return None
        allowed = {
            "v",
            "bridge_id",
            "path",
            "fingerprint",
            "frame_b64",
            "announce_b64",
            "published_at_ms",
            "expires_at_ms",
            "kind",
        }
        if set(metadata) != allowed:
            return None
        bridge_id = _decode_hex(metadata["bridge_id"], 16)
        fingerprint = _decode_hex(metadata["fingerprint"], 16)
        path_values = metadata["path"]
        if not isinstance(path_values, list) or not 1 <= len(path_values) <= max_hops:
            return None
        path = tuple(_decode_hex(value, 16) for value in path_values)
        if bridge_id != path[-1] or len(set(path)) != len(path):
            return None
        frame = _decode_base64(metadata["frame_b64"])
        announcement = _decode_base64(metadata["announce_b64"])
        published_at_ms = _strict_int(metadata["published_at_ms"])
        expires_at_ms = _strict_int(metadata["expires_at_ms"])
        if published_at_ms < 0 or expires_at_ms <= published_at_ms:
            return None
        return _MatrixEnvelope(
            str(content["body"]),
            frame,
            announcement,
            fingerprint,
            path,
            published_at_ms,
            expires_at_ms,
            str(metadata["kind"]),
        )
    except (
        binascii.Error,
        KeyError,
        TypeError,
        UnicodeDecodeError,
        ValueError,
    ):
        return None


def _parse_matrix_event(room_id: str, value: object) -> MatrixEvent | None:
    if not isinstance(value, dict) or value.get("type") != "m.room.message":
        return None
    sender = value.get("sender")
    event_id = value.get("event_id")
    timestamp = value.get("origin_server_ts")
    content = value.get("content")
    if (
        not isinstance(sender, str)
        or not isinstance(event_id, str)
        or isinstance(timestamp, bool)
        or not isinstance(timestamp, int)
        or not isinstance(content, dict)
    ):
        return None
    return MatrixEvent(room_id, sender, event_id, timestamp, content)


def _load_access_token(config: MatrixConfig) -> str:
    token = os.environ.get(config.access_token_env) if config.access_token_env else None
    if token is None and config.access_token_file:
        token_path = Path(config.access_token_file)
        if token_path.is_symlink():
            raise ValueError("Matrix access-token file cannot be a symbolic link")
        file_mode = stat.S_IMODE(token_path.stat().st_mode)
        if os.name != "nt" and file_mode & 0o077:
            raise PermissionError(
                "Matrix access-token file must not be group/world accessible"
            )
        if token_path.stat().st_size > 16 * 1024:
            raise ValueError("Matrix access-token file is too large")
        token = token_path.read_text(encoding="utf-8").strip()
    if token is None or not token or any(character.isspace() for character in token):
        raise ValueError("Matrix access token is missing or invalid")
    return token


def _safe_body(payload: bytes, kind: str) -> str:
    try:
        return payload.decode("utf-8")
    except UnicodeDecodeError:
        return "HearthBit SOS" if kind == "sos" else "HearthBit public message"


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


def _now_ms() -> int:
    return time.time_ns() // 1_000_000
