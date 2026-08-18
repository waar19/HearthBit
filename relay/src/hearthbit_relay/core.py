from __future__ import annotations

import asyncio
import json
import logging
import threading
import time
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass

from .config import RelayConfig
from .identity import (
    RelayIdentity,
    validate_announcement,
    verify_packet_signature,
)
from .link import LinkKind, RelayLink
from .protocol import (
    EMERGENCY_ACK_RETENTION_SECONDS,
    EPHEMERAL_MESSAGE_TYPES,
    TYPE_ANNOUNCE,
    TYPE_EMERGENCY_ACK,
    TYPE_FRAGMENT,
    TYPE_MESSAGE,
    TYPE_NOISE_HANDSHAKE,
    TYPE_REQUEST_SYNC,
    FragmentReassembler,
    Packet,
    PacketError,
    courier_expiry_ms,
    decode_packet,
    is_storable_emergency_ack,
    legacy_relay_fingerprint,
    relay_fingerprint,
)
from .store import PacketStore
from .trust import (
    TrustCapacityError,
    TrustConflictError,
    TrustStore,
    TrustStoreError,
)

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class RelayResult:
    accepted: bool
    reason: str
    forwarded: int = 0
    stored: bool = False


class RelayOperationalCounters:
    """Process-lifetime aggregate counters with no peer or payload data."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._reasons: Counter[str] = Counter()
        self._accepted = 0
        self._forwarded = 0
        self._stored = 0

    def record(self, result: RelayResult) -> None:
        with self._lock:
            self._reasons[result.reason] += 1
            if result.accepted:
                self._accepted += 1
            self._forwarded += result.forwarded
            if result.stored:
                self._stored += 1

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            reasons = dict(sorted(self._reasons.items()))
            return {
                "lifetime": "process",
                "accepted": self._accepted,
                "rejected": sum(reasons.values()) - self._accepted,
                "forwarded": self._forwarded,
                "stored": self._stored,
                "trustConflicts": reasons.get("identity-conflict", 0),
                "trustCapacityRejected": reasons.get("trust-capacity", 0),
                "resultsByReason": reasons,
            }


@dataclass(slots=True)
class _TokenBucket:
    tokens: float
    updated_at: float

    def consume(
        self,
        *,
        now: float,
        rate_per_second: float,
        capacity: int,
    ) -> bool:
        elapsed = max(0.0, now - self.updated_at)
        self.tokens = min(float(capacity), self.tokens + elapsed * rate_per_second)
        self.updated_at = now
        if self.tokens < 1.0:
            return False
        self.tokens -= 1.0
        return True


class RelayCore:
    def __init__(
        self,
        config: RelayConfig,
        store: PacketStore,
        identity: RelayIdentity | None = None,
        *,
        trust_store: TrustStore | None = None,
        monotonic: Callable[[], float] | None = None,
        announcement_clock_ms: Callable[[], int] | None = None,
    ) -> None:
        self.config = config
        self.store = store
        self.identity = identity
        self._links: dict[str, RelayLink] = {}
        self._lock = asyncio.Lock()
        self._identity_lock = asyncio.Lock()
        self._presence_task: asyncio.Task[None] | None = None
        self._trust_store = trust_store or TrustStore(config.trust_store_path)
        self._reassembler = FragmentReassembler()
        self._buckets: dict[tuple[str, bytes], _TokenBucket] = {}
        self._monotonic = monotonic or time.monotonic
        self._announcement_clock_ms = announcement_clock_ms or _now_ms
        self._operational_counters = RelayOperationalCounters()

    async def start(self) -> None:
        if self.identity is None or self._presence_task is not None:
            return
        self._presence_task = asyncio.create_task(self._presence_loop())

    async def stop(self) -> None:
        if self._presence_task is not None:
            self._presence_task.cancel()
            await asyncio.gather(self._presence_task, return_exceptions=True)
            self._presence_task = None
        LOGGER.info(
            "operational counters: %s",
            json.dumps(self.diagnostic_snapshot(), sort_keys=True),
        )

    def diagnostic_snapshot(self) -> dict[str, object]:
        """Return deterministic local diagnostics; no network endpoint is opened."""
        return self._operational_counters.snapshot()

    async def register_link(self, link: RelayLink) -> int:
        async with self._lock:
            self._links[link.id] = link
        capabilities = link.capabilities
        LOGGER.info(
            "link ready: %s kind=%s mtu=%d reliability=%s cost=%d",
            link.id,
            capabilities.kind,
            capabilities.mtu,
            capabilities.reliability,
            capabilities.cost,
        )
        await self._send_presence(link)
        return await self._replay(link)

    async def remove_link(self, link_id: str) -> None:
        async with self._lock:
            self._links.pop(link_id, None)
        LOGGER.info("link removed: %s", link_id)

    async def inbound(
        self,
        source_id: str,
        raw: bytes,
        *,
        gateway_path: tuple[bytes, ...] = (),
    ) -> RelayResult:
        try:
            packet = decode_packet(raw, max_size=self.config.max_packet_size)
        except PacketError as error:
            LOGGER.warning("invalid packet from %s: %s", source_id, error)
            result = RelayResult(False, "invalid")
            self._operational_counters.record(result)
            return result

        result = await self._process_packet(
            source_id,
            packet,
            gateway_path=gateway_path,
            allow_forward=True,
            apply_rate_limit=True,
            allow_reassembly=True,
        )
        self._operational_counters.record(result)
        return result

    async def _process_packet(
        self,
        source_id: str,
        packet: Packet,
        *,
        gateway_path: tuple[bytes, ...],
        allow_forward: bool,
        apply_rate_limit: bool,
        allow_reassembly: bool,
    ) -> RelayResult:
        if packet.is_drill and source_id.startswith(
            ("mqtt:", "matrix:", "reticulum:")
        ):
            return RelayResult(False, "drill-bridge-forbidden")
        identity_reason, can_store = await self._authenticate(packet, source_id)
        if identity_reason is not None:
            return RelayResult(False, identity_reason)

        priority = _packet_priority(packet)
        if apply_rate_limit and not self._consume_rate_limit(
            packet.sender_id,
            source_id=source_id,
            emergency=priority > 0,
        ):
            return RelayResult(False, "rate-limited")

        fingerprint = relay_fingerprint(packet)
        legacy_fingerprint = legacy_relay_fingerprint(packet)
        now_ms = _now_ms()
        if await self.store.aseen_or_add_compatible(
            fingerprint,
            (legacy_fingerprint,),
            now_ms=now_ms,
        ):
            return RelayResult(False, "duplicate")

        reassembled: Packet | None = None
        if packet.message_type == TYPE_FRAGMENT:
            if not allow_reassembly:
                return RelayResult(False, "nested-fragment")
            try:
                reassembled = self._reassembler.accept(packet)
            except PacketError:
                return RelayResult(False, "invalid-fragment")

        policy_reason = _relay_policy(packet)
        if policy_reason is not None:
            return RelayResult(False, policy_reason)

        forwarded_packet = packet.forwarded_bytes()
        stored = (
            await self._store_if_eligible(
                packet,
                fingerprint,
                forwarded_packet,
                now_ms=now_ms,
            )
            if can_store
            else False
        )

        links: list[RelayLink] = []
        if allow_forward:
            async with self._lock:
                links = [
                    link
                    for link_id, link in self._links.items()
                    if link_id != source_id
                    and (
                        not packet.is_drill
                        or link.capabilities.kind
                        not in {LinkKind.MQTT, LinkKind.MATRIX, LinkKind.RETICULUM}
                    )
                ]

        sent = 0
        for link in links:
            try:
                await link.send_with_path(forwarded_packet, gateway_path)
                sent += 1
                if stored:
                    await self.store.amark_delivered(
                        fingerprint,
                        link.id,
                        now_ms=now_ms,
                    )
            except Exception:
                LOGGER.exception("failed forwarding packet to %s", link.id)

        reassembled_result: RelayResult | None = None
        if reassembled is not None:
            reassembled_result = await self._process_packet(
                source_id,
                reassembled,
                gateway_path=(),
                allow_forward=False,
                apply_rate_limit=False,
                allow_reassembly=False,
            )
            stored = stored or reassembled_result.stored
            if not reassembled_result.accepted:
                LOGGER.warning(
                    "reassembled packet rejected from %s: %s",
                    source_id,
                    reassembled_result.reason,
                )

        LOGGER.debug(
            "packet type=0x%02x ttl=%d forwarded=%d stored=%s",
            packet.message_type,
            packet.ttl,
            sent,
            stored,
        )
        reason = "processed-local" if not allow_forward else "relayed"
        if reassembled_result is not None and reassembled_result.accepted:
            reason = "relayed-reassembled"
        return RelayResult(True, reason, sent, stored)

    async def _authenticate(
        self,
        packet: Packet,
        source_id: str,
    ) -> tuple[str | None, bool]:
        can_store = True
        async with self._identity_lock:
            if packet.message_type == TYPE_ANNOUNCE:
                announcement = validate_announcement(
                    packet,
                    now_ms=self._announcement_clock_ms(),
                )
                if announcement is None:
                    LOGGER.warning("invalid ANNOUNCE identity from %s", source_id)
                    return "invalid-announce", False
                try:
                    await asyncio.to_thread(
                        self._trust_store.pin,
                        packet.sender_id,
                        announcement.signing_public_key,
                        announcement.noise_public_key,
                    )
                except TrustConflictError:
                    LOGGER.warning(
                        "rejected identity change for pinned sender %s",
                        packet.sender_id.hex(),
                    )
                    return "identity-conflict", False
                except TrustCapacityError:
                    LOGGER.warning("trusted peer capacity reached")
                    return "trust-capacity", False
                except TrustStoreError:
                    LOGGER.error("failed to persist trusted peer identity")
                    return "trust-store-error", False
            elif packet.has_signature:
                trusted = self._trust_store.get(packet.sender_id)
                if trusted is None:
                    LOGGER.warning(
                        "missing signing key for signed packet from %s",
                        packet.sender_id.hex(),
                    )
                    return "unknown-signing-key", False
                if not verify_packet_signature(
                    packet,
                    trusted.signing_public_key,
                ):
                    LOGGER.warning(
                        "invalid signature from pinned sender %s",
                        packet.sender_id.hex(),
                    )
                    return "invalid-signature", False
        return None, can_store

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
            await self.store.aseen_or_add_compatible(
                relay_fingerprint(decoded),
                (legacy_relay_fingerprint(decoded),),
                now_ms=now_ms,
            )
        try:
            await link.send(announcement)
            await link.send(capability)
        except Exception:
            LOGGER.exception("failed sending relay identity to %s", link.id)

    async def _replay(self, link: RelayLink) -> int:
        pending = await self.store.apending_for(
            link.id,
            limit=self.config.store.replay_batch,
        )
        sent = 0
        for item in pending:
            try:
                await link.send(item.packet)
            except Exception:
                LOGGER.exception("store-and-forward failed on %s", link.id)
                break
            await self.store.amark_delivered(item.fingerprint, link.id)
            sent += 1
        if sent:
            LOGGER.info("replayed %d stored packet(s) to %s", sent, link.id)
        return sent

    async def _store_if_eligible(
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
        if (
            packet.message_type == TYPE_EMERGENCY_ACK
            and not is_storable_emergency_ack(packet)
        ):
            return False

        expires_at = now_ms + policy.packet_ttl_seconds * 1000
        if packet.message_type == TYPE_EMERGENCY_ACK:
            ack_window_ms = EMERGENCY_ACK_RETENTION_SECONDS * 1000
            expires_at = min(
                expires_at,
                now_ms + ack_window_ms,
                packet.timestamp_ms + ack_window_ms,
            )
        courier_expiry = courier_expiry_ms(packet)
        if courier_expiry is not None:
            expires_at = min(expires_at, courier_expiry)
        return await self.store.aenqueue(
            fingerprint=fingerprint,
            packet=forwarded_packet,
            message_type=packet.message_type,
            sender_id=packet.sender_id,
            expires_at_ms=expires_at,
            priority=_packet_priority(packet),
            now_ms=now_ms,
        )

    def _consume_rate_limit(
        self,
        sender_id: bytes,
        *,
        source_id: str,
        emergency: bool,
    ) -> bool:
        policy = self.config.flood
        now = float(self._monotonic())
        sender_kind = "emergency" if emergency else "sender"
        sender_rate = (
            policy.emergency_rate_per_second
            if emergency
            else policy.sender_rate_per_second
        )
        sender_capacity = (
            policy.emergency_burst if emergency else policy.sender_burst
        )
        if not self._consume_bucket(
            (sender_kind, bytes(sender_id)),
            now=now,
            rate=sender_rate,
            capacity=sender_capacity,
        ):
            return False
        if source_id.startswith(("mqtt:", "matrix:", "reticulum:")):
            return self._consume_bucket(
                (
                    "bridge-emergency" if emergency else "bridge",
                    source_id.encode("utf-8"),
                ),
                now=now,
                rate=(
                    policy.bridge_emergency_rate_per_second
                    if emergency
                    else policy.bridge_rate_per_second
                ),
                capacity=(
                    policy.bridge_emergency_burst
                    if emergency
                    else policy.bridge_burst
                ),
            )
        return True

    def _consume_bucket(
        self,
        key: tuple[str, bytes],
        *,
        now: float,
        rate: float,
        capacity: int,
    ) -> bool:
        bucket = self._buckets.get(key)
        if bucket is None:
            if len(self._buckets) >= 4096:
                oldest_key = min(
                    self._buckets,
                    key=lambda candidate: self._buckets[candidate].updated_at,
                )
                self._buckets.pop(oldest_key, None)
            bucket = _TokenBucket(float(capacity), now)
            self._buckets[key] = bucket
        return bucket.consume(
            now=now,
            rate_per_second=rate,
            capacity=capacity,
        )


def _relay_policy(packet: Packet) -> str | None:
    if packet.ttl <= 1:
        return "ttl-expired"
    if packet.message_type == TYPE_REQUEST_SYNC:
        return "link-local"
    if packet.message_type == TYPE_NOISE_HANDSHAKE and not packet.is_directed:
        return "undirected-handshake"
    return None


def _packet_priority(packet: Packet) -> int:
    if packet.message_type != TYPE_MESSAGE or packet.is_drill:
        return 0
    if packet.payload.startswith(b"SOS|") or b"[HB-CHECKIN|" in packet.payload:
        return 100
    return 0


def _now_ms() -> int:
    return time.time_ns() // 1_000_000
