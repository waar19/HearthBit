from __future__ import annotations

import logging
from collections.abc import Callable
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

        identity = validate_announcement(announcement_packet)
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
        announcement = validate_announcement(packet)
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
