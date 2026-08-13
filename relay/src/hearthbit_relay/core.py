from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from typing import Protocol

from .config import RelayConfig
from .identity import RelayIdentity, validate_announcement
from .protocol import (
    EPHEMERAL_MESSAGE_TYPES,
    TYPE_ANNOUNCE,
    TYPE_NOISE_HANDSHAKE,
    TYPE_REQUEST_SYNC,
    Packet,
    PacketError,
    courier_expiry_ms,
    decode_packet,
    relay_fingerprint,
)
from .store import PacketStore

LOGGER = logging.getLogger(__name__)


class RelayLink(Protocol):
    id: str

    async def send(self, packet: bytes) -> None: ...


@dataclass(frozen=True, slots=True)
class RelayResult:
    accepted: bool
    reason: str
    forwarded: int = 0
    stored: bool = False


class RelayCore:
    def __init__(
        self,
        config: RelayConfig,
        store: PacketStore,
        identity: RelayIdentity | None = None,
    ) -> None:
        self.config = config
        self.store = store
        self.identity = identity
        self._links: dict[str, RelayLink] = {}
        self._lock = asyncio.Lock()
        self._presence_task: asyncio.Task[None] | None = None

    async def start(self) -> None:
        if self.identity is None or self._presence_task is not None:
            return
        self._presence_task = asyncio.create_task(self._presence_loop())

    async def stop(self) -> None:
        if self._presence_task is None:
            return
        self._presence_task.cancel()
        await asyncio.gather(self._presence_task, return_exceptions=True)
        self._presence_task = None

    async def register_link(self, link: RelayLink) -> int:
        async with self._lock:
            self._links[link.id] = link
        LOGGER.info("link ready: %s", link.id)
        await self._send_presence(link)
        return await self._replay(link)

    async def remove_link(self, link_id: str) -> None:
        async with self._lock:
            self._links.pop(link_id, None)
        LOGGER.info("link removed: %s", link_id)

    async def inbound(self, source_id: str, raw: bytes) -> RelayResult:
        try:
            packet = decode_packet(raw, max_size=self.config.max_packet_size)
        except PacketError as error:
            LOGGER.warning("invalid packet from %s: %s", source_id, error)
            return RelayResult(False, "invalid")

        if packet.message_type == TYPE_ANNOUNCE and validate_announcement(packet) is None:
            LOGGER.warning("invalid ANNOUNCE identity from %s", source_id)
            return RelayResult(False, "invalid-announce")

        fingerprint = relay_fingerprint(packet)
        now_ms = _now_ms()
        async with self._lock:
            if self.store.seen_or_add(fingerprint, now_ms=now_ms):
                return RelayResult(False, "duplicate")
            links = [
                link for link_id, link in self._links.items() if link_id != source_id
            ]

        policy_reason = _relay_policy(packet)
        if policy_reason is not None:
            return RelayResult(False, policy_reason)

        forwarded_packet = packet.forwarded_bytes()
        stored = self._store_if_eligible(
            packet, fingerprint, forwarded_packet, now_ms=now_ms
        )
        sent = 0
        for link in links:
            try:
                await link.send(forwarded_packet)
                sent += 1
                if stored:
                    self.store.mark_delivered(fingerprint, link.id, now_ms=now_ms)
            except Exception:
                LOGGER.exception("failed forwarding packet to %s", link.id)

        LOGGER.debug(
            "packet type=0x%02x ttl=%d forwarded=%d stored=%s",
            packet.message_type,
            packet.ttl,
            sent,
            stored,
        )
        return RelayResult(True, "relayed", sent, stored)

    async def _presence_loop(self) -> None:
        while True:
            await self._broadcast_presence()
            await asyncio.sleep(self.config.announce_interval_seconds)

    async def _broadcast_presence(self) -> None:
        async with self._lock:
            links = list(self._links.values())
        for link in links:
            await self._send_presence(link)

    async def _send_presence(self, link: RelayLink) -> None:
        if self.identity is None:
            return
        now_ms = _now_ms()
        announcement = self.identity.build_announcement(
            nickname=self.config.nickname,
            timestamp_ms=now_ms,
        )
        capability = self.identity.build_node_capability(
            role=self.config.node_role,
            timestamp_ms=now_ms,
        )
        for local_packet in (announcement, capability):
            decoded = decode_packet(
                local_packet,
                max_size=self.config.max_packet_size,
            )
            self.store.seen_or_add(
                relay_fingerprint(decoded),
                now_ms=now_ms,
            )
        try:
            await link.send(announcement)
            await link.send(capability)
        except Exception:
            LOGGER.exception("failed sending relay identity to %s", link.id)

    async def _replay(self, link: RelayLink) -> int:
        pending = self.store.pending_for(
            link.id, limit=self.config.store.replay_batch
        )
        sent = 0
        for item in pending:
            try:
                await link.send(item.packet)
            except Exception:
                LOGGER.exception("store-and-forward failed on %s", link.id)
                break
            self.store.mark_delivered(item.fingerprint, link.id)
            sent += 1
        if sent:
            LOGGER.info("replayed %d stored packet(s) to %s", sent, link.id)
        return sent

    def _store_if_eligible(
        self,
        packet: Packet,
        fingerprint: bytes,
        forwarded_packet: bytes,
        *,
        now_ms: int,
    ) -> bool:
        policy = self.config.store
        if packet.message_type in EPHEMERAL_MESSAGE_TYPES:
            return False
        if packet.message_type not in policy.message_types:
            return False
        if policy.require_signature and not packet.has_signature:
            return False

        expires_at = now_ms + policy.packet_ttl_seconds * 1000
        courier_expiry = courier_expiry_ms(packet)
        if courier_expiry is not None:
            expires_at = min(expires_at, courier_expiry)
        return self.store.enqueue(
            fingerprint=fingerprint,
            packet=forwarded_packet,
            message_type=packet.message_type,
            sender_id=packet.sender_id,
            expires_at_ms=expires_at,
            now_ms=now_ms,
        )


def _relay_policy(packet: Packet) -> str | None:
    if packet.ttl <= 1:
        return "ttl-expired"
    if packet.message_type == TYPE_REQUEST_SYNC:
        return "link-local"
    if packet.message_type == TYPE_NOISE_HANDSHAKE and not packet.is_directed:
        return "undirected-handshake"
    return None


def _now_ms() -> int:
    return time.time_ns() // 1_000_000
