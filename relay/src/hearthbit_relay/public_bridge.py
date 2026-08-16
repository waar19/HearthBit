from __future__ import annotations

import asyncio
import logging
import math
import re
from collections import deque
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from .identity import validate_announcement, verify_packet_signature
from .protocol import (
    TYPE_ANNOUNCE,
    TYPE_MESSAGE,
    Packet,
    PacketError,
    decode_packet,
    relay_fingerprint,
)

LOGGER = logging.getLogger(__name__)

SOS_PREFIX = b"SOS|"
CHECKIN_MARKER = b"[HB-CHECKIN|"
_DECIMAL_NUMBER = re.compile(
    r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?"
)
_CHECKIN_STATUSES = frozenset({"OK", "HELP", "INJURED"})


def has_emergency_coordinates(payload: bytes) -> bool:
    """Return true when a public emergency payload carries parseable GPS."""
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError:
        return False
    if text.startswith("SOS|"):
        fields = text.rsplit("|", 2)
        if len(fields) != 3:
            return False
        _, latitude, longitude = fields
        return _coordinates_present(latitude, longitude)
    marker = text.rfind("[HB-CHECKIN|")
    if marker <= 0 or text[marker - 1] != "\n" or not text.endswith("]"):
        return False
    fields = text[marker + len("[HB-CHECKIN|") : -1].split("|")
    if (
        len(fields) != 5
        or fields[0] not in _CHECKIN_STATUSES
        or not fields[1].isdigit()
        or int(fields[1]) <= 0
        or fields[4] != "1"
    ):
        return False
    return _coordinates_present(fields[2], fields[3])


def _coordinates_present(latitude: str, longitude: str) -> bool:
    if (
        _DECIMAL_NUMBER.fullmatch(latitude) is None
        or _DECIMAL_NUMBER.fullmatch(longitude) is None
    ):
        return False
    try:
        lat = float(latitude)
        lon = float(longitude)
    except ValueError:
        return False
    return (
        math.isfinite(lat)
        and math.isfinite(lon)
        and -90 <= lat <= 90
        and -180 <= lon <= 180
    )


class BoundedIngressQueue:
    """Priority ingress queue that reserves capacity by evicting normal work."""

    def __init__(self, capacity: int) -> None:
        self.capacity = capacity
        self._emergency: deque[tuple[bytes, tuple[bytes, ...]]] = deque()
        self._normal: deque[tuple[bytes, tuple[bytes, ...]]] = deque()
        self._ready = asyncio.Event()
        self._handler: (
            Callable[[bytes, tuple[bytes, ...]], Awaitable[object]] | None
        ) = None
        self._task: asyncio.Task[None] | None = None

    def start(
        self,
        handler: Callable[[bytes, tuple[bytes, ...]], Awaitable[object]],
    ) -> None:
        if self._task is not None:
            return
        self._handler = handler
        self._task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        task = self._task
        self._task = None
        if task is not None:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        self._handler = None
        self._emergency.clear()
        self._normal.clear()
        self._ready.clear()

    def enqueue(
        self,
        frame: bytes,
        path: tuple[bytes, ...],
        *,
        emergency: bool,
    ) -> bool:
        size = len(self._emergency) + len(self._normal)
        if size >= self.capacity:
            if not emergency or not self._normal:
                return False
            self._normal.popleft()
        target = self._emergency if emergency else self._normal
        target.append((bytes(frame), tuple(path)))
        self._ready.set()
        return True

    async def _run(self) -> None:
        while True:
            await self._ready.wait()
            while self._emergency or self._normal:
                frame, path = (
                    self._emergency.popleft()
                    if self._emergency
                    else self._normal.popleft()
                )
                handler = self._handler
                if handler is None:
                    return
                try:
                    await handler(frame, path)
                except asyncio.CancelledError:
                    raise
                except Exception:
                    LOGGER.exception("external bridge ingress failed")
            self._ready.clear()


@dataclass(frozen=True, slots=True)
class PublicBridgeFrame:
    frame: bytes
    announcement: bytes
    packet: Packet
    fingerprint: bytes
    kind: str


@dataclass(frozen=True, slots=True)
class _AnnouncementProof:
    raw: bytes
    signing_key: bytes
    expires_at_ms: int


class PublicBridgePolicy:
    """Shared authenticated-public-message boundary for external bridges."""

    def __init__(
        self,
        *,
        max_frame_size: int,
        max_message_age_seconds: int,
        announce_max_age_seconds: int,
        future_skew_seconds: int,
        clock_ms: Callable[[], int],
    ) -> None:
        self.max_frame_size = max_frame_size
        self.max_message_age_seconds = max_message_age_seconds
        self.announce_max_age_seconds = announce_max_age_seconds
        self.future_skew_seconds = future_skew_seconds
        self._clock_ms = clock_ms
        self._announcements: dict[bytes, _AnnouncementProof] = {}

    def inspect_outbound(self, frame: bytes) -> PublicBridgeFrame | None:
        """Cache ANNOUNCE frames and return only verified public MESSAGE frames."""
        now_ms = self._clock_ms()
        self.purge(now_ms)
        try:
            packet = decode_packet(frame, max_size=self.max_frame_size)
        except PacketError:
            return None
        if packet.message_type == TYPE_ANNOUNCE:
            self._remember_announcement(packet, frame, now_ms)
            return None

        kind = public_message_kind(packet)
        if kind is None or not self.valid_message_timestamp(packet, now_ms):
            return None
        proof = self._announcements.get(packet.sender_id)
        if (
            proof is None
            or proof.expires_at_ms <= now_ms
            or not verify_packet_signature(packet, proof.signing_key)
        ):
            return None
        return PublicBridgeFrame(
            bytes(frame),
            proof.raw,
            packet,
            relay_fingerprint(packet),
            kind,
        )

    def inspect_inbound(
        self,
        *,
        frame: bytes,
        announcement: bytes,
        kind: str,
    ) -> PublicBridgeFrame | None:
        """Revalidate the complete identity proof for an imported frame."""
        now_ms = self._clock_ms()
        self.purge(now_ms)
        try:
            announcement_packet = decode_packet(
                announcement,
                max_size=self.max_frame_size,
            )
            packet = decode_packet(frame, max_size=self.max_frame_size)
        except PacketError:
            return None

        identity = validate_announcement(announcement_packet, now_ms=now_ms)
        actual_kind = public_message_kind(packet)
        if (
            identity is None
            or announcement_packet.sender_id != packet.sender_id
            or not self.valid_announcement_timestamp(announcement_packet, now_ms)
            or actual_kind is None
            or actual_kind != kind
            or not self.valid_message_timestamp(packet, now_ms)
            or not verify_packet_signature(packet, identity.signing_public_key)
        ):
            return None
        return PublicBridgeFrame(
            bytes(frame),
            bytes(announcement),
            packet,
            relay_fingerprint(packet),
            actual_kind,
        )

    def valid_announcement_timestamp(self, packet: Packet, now_ms: int) -> bool:
        skew_ms = self.future_skew_seconds * 1000
        age_ms = self.announce_max_age_seconds * 1000
        return now_ms - age_ms <= packet.timestamp_ms <= now_ms + skew_ms

    def valid_message_timestamp(self, packet: Packet, now_ms: int) -> bool:
        skew_ms = self.future_skew_seconds * 1000
        age_ms = self.max_message_age_seconds * 1000
        return now_ms - age_ms <= packet.timestamp_ms <= now_ms + skew_ms

    def purge(self, now_ms: int | None = None) -> None:
        current_ms = self._clock_ms() if now_ms is None else now_ms
        self._announcements = {
            sender: proof
            for sender, proof in self._announcements.items()
            if proof.expires_at_ms > current_ms
        }

    def _remember_announcement(
        self,
        packet: Packet,
        raw: bytes,
        now_ms: int,
    ) -> None:
        announcement = validate_announcement(packet, now_ms=now_ms)
        if (
            announcement is None
            or not self.valid_announcement_timestamp(packet, now_ms)
        ):
            return
        existing = self._announcements.get(packet.sender_id)
        if (
            existing is not None
            and existing.signing_key != announcement.signing_public_key
        ):
            LOGGER.warning(
                "external bridge rejected signing-key change for sender %s",
                packet.sender_id.hex(),
            )
            return
        self._announcements[packet.sender_id] = _AnnouncementProof(
            bytes(raw),
            announcement.signing_public_key,
            packet.timestamp_ms + self.announce_max_age_seconds * 1000,
        )


def public_message_kind(packet: Packet) -> str | None:
    if (
        packet.message_type != TYPE_MESSAGE
        or packet.recipient_id is not None
        or not packet.has_signature
    ):
        return None
    return "sos" if packet.payload.startswith(SOS_PREFIX) else "message"


def expiry_for(
    frame: PublicBridgeFrame,
    *,
    published_at_ms: int,
    message_expiry_seconds: int,
    sos_expiry_seconds: int,
    max_message_age_seconds: int,
) -> int:
    lifetime_seconds = (
        sos_expiry_seconds if frame.kind == "sos" else message_expiry_seconds
    )
    return min(
        published_at_ms + lifetime_seconds * 1000,
        frame.packet.timestamp_ms + max_message_age_seconds * 1000,
    )


def valid_expiry(
    frame: PublicBridgeFrame,
    *,
    published_at_ms: int,
    expires_at_ms: int,
    now_ms: int,
    message_expiry_seconds: int,
    sos_expiry_seconds: int,
    max_message_age_seconds: int,
    future_skew_seconds: int,
) -> bool:
    if published_at_ms > now_ms + future_skew_seconds * 1000:
        return False
    if expires_at_ms <= now_ms:
        return False
    return expires_at_ms <= expiry_for(
        frame,
        published_at_ms=published_at_ms,
        message_expiry_seconds=message_expiry_seconds,
        sos_expiry_seconds=sos_expiry_seconds,
        max_message_age_seconds=max_message_age_seconds,
    )
