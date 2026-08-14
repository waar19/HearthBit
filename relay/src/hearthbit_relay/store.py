from __future__ import annotations

import asyncio
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from .config import StoreConfig
from .protocol import EPHEMERAL_MESSAGE_TYPES


@dataclass(frozen=True, slots=True)
class StoredPacket:
    fingerprint: bytes
    packet: bytes
    expires_at_ms: int


class PacketStore:
    def __init__(self, config: StoreConfig) -> None:
        self.config = config
        if config.path != ":memory:":
            Path(config.path).parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._db = sqlite3.connect(
            config.path,
            isolation_level=None,
            check_same_thread=False,
        )
        self._db.execute("PRAGMA foreign_keys = ON")
        self._db.execute("PRAGMA journal_mode = WAL")
        self._db.execute("PRAGMA synchronous = NORMAL")
        self._db.executescript(
            """
            CREATE TABLE IF NOT EXISTS seen (
                fingerprint BLOB PRIMARY KEY,
                expires_at_ms INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS seen_expiry ON seen(expires_at_ms);

            CREATE TABLE IF NOT EXISTS packets (
                fingerprint BLOB PRIMARY KEY,
                packet BLOB NOT NULL,
                message_type INTEGER NOT NULL,
                sender_id BLOB NOT NULL,
                created_at_ms INTEGER NOT NULL,
                expires_at_ms INTEGER NOT NULL,
                priority INTEGER NOT NULL DEFAULT 0,
                size INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS packet_expiry ON packets(expires_at_ms);
            CREATE INDEX IF NOT EXISTS packet_created ON packets(created_at_ms);

            CREATE TABLE IF NOT EXISTS deliveries (
                fingerprint BLOB NOT NULL REFERENCES packets(fingerprint)
                    ON DELETE CASCADE,
                link_id TEXT NOT NULL,
                delivered_at_ms INTEGER NOT NULL,
                PRIMARY KEY (fingerprint, link_id)
            );
            """
        )
        packet_columns = {
            str(row[1]) for row in self._db.execute("PRAGMA table_info(packets)")
        }
        if "priority" not in packet_columns:
            self._db.execute(
                "ALTER TABLE packets ADD COLUMN priority INTEGER NOT NULL DEFAULT 0"
            )
        self._remove_ephemeral_packets()
        self._operations = 0

    def seen_or_add(
        self, fingerprint: bytes, *, now_ms: int | None = None
    ) -> bool:
        return self.seen_or_add_compatible(fingerprint, (), now_ms=now_ms)

    def seen_or_add_compatible(
        self,
        fingerprint: bytes,
        aliases: tuple[bytes, ...],
        *,
        now_ms: int | None = None,
    ) -> bool:
        now = _now_ms() if now_ms is None else now_ms
        candidates = (fingerprint, *aliases)
        with self._lock:
            placeholders = ",".join("?" for _ in candidates)
            row = self._db.execute(
                f"""
                SELECT 1
                FROM (
                    SELECT fingerprint, expires_at_ms FROM seen
                    UNION ALL
                    SELECT fingerprint, expires_at_ms FROM packets
                )
                WHERE fingerprint IN ({placeholders}) AND expires_at_ms > ?
                LIMIT 1
                """,
                (*candidates, now),
            ).fetchone()
            if row is not None:
                return True
            expiry = now + self.config.seen_ttl_seconds * 1000
            self._db.executemany(
                """
                INSERT INTO seen(fingerprint, expires_at_ms) VALUES(?, ?)
                ON CONFLICT(fingerprint) DO UPDATE
                SET expires_at_ms = excluded.expires_at_ms
                """,
                [(candidate, expiry) for candidate in candidates],
            )
            self._periodic_purge(now)
            return False

    def enqueue(
        self,
        *,
        fingerprint: bytes,
        packet: bytes,
        message_type: int,
        sender_id: bytes,
        expires_at_ms: int,
        priority: int = 0,
        now_ms: int | None = None,
    ) -> bool:
        now = _now_ms() if now_ms is None else now_ms
        if message_type in EPHEMERAL_MESSAGE_TYPES or expires_at_ms <= now:
            return False
        with self._lock:
            cursor = self._db.execute(
                """
                INSERT OR IGNORE INTO packets(
                    fingerprint, packet, message_type, sender_id,
                    created_at_ms, expires_at_ms, priority, size
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    fingerprint,
                    packet,
                    message_type,
                    sender_id,
                    now,
                    expires_at_ms,
                    max(0, min(priority, 100)),
                    len(packet),
                ),
            )
            self.purge(now_ms=now)
            self._enforce_limits()
            return cursor.rowcount == 1

    def pending_for(
        self, link_id: str, *, limit: int, now_ms: int | None = None
    ) -> list[StoredPacket]:
        now = _now_ms() if now_ms is None else now_ms
        with self._lock:
            rows = self._db.execute(
                """
                SELECT p.fingerprint, p.packet, p.expires_at_ms
                FROM packets AS p
                LEFT JOIN deliveries AS d
                  ON d.fingerprint = p.fingerprint AND d.link_id = ?
                WHERE p.expires_at_ms > ? AND d.fingerprint IS NULL
                ORDER BY p.priority DESC, p.created_at_ms ASC
                LIMIT ?
                """,
                (link_id, now, limit),
            ).fetchall()
        return [
            StoredPacket(bytes(fingerprint), bytes(packet), int(expiry))
            for fingerprint, packet, expiry in rows
        ]

    def mark_delivered(
        self, fingerprint: bytes, link_id: str, *, now_ms: int | None = None
    ) -> None:
        now = _now_ms() if now_ms is None else now_ms
        with self._lock:
            self._db.execute(
                """
                INSERT OR REPLACE INTO deliveries(
                    fingerprint, link_id, delivered_at_ms
                ) VALUES(?, ?, ?)
                """,
                (fingerprint, link_id, now),
            )

    def purge(self, *, now_ms: int | None = None) -> None:
        now = _now_ms() if now_ms is None else now_ms
        with self._lock:
            self._db.execute("DELETE FROM packets WHERE expires_at_ms <= ?", (now,))
            self._db.execute("DELETE FROM seen WHERE expires_at_ms <= ?", (now,))

    def packet_count(self) -> int:
        with self._lock:
            row = self._db.execute("SELECT COUNT(*) FROM packets").fetchone()
        return int(row[0])

    def packet_bytes(self) -> int:
        with self._lock:
            row = self._db.execute(
                "SELECT COALESCE(SUM(size), 0) FROM packets"
            ).fetchone()
        return int(row[0])

    def close(self) -> None:
        with self._lock:
            self._db.close()

    async def aseen_or_add_compatible(
        self,
        fingerprint: bytes,
        aliases: tuple[bytes, ...],
        *,
        now_ms: int | None = None,
    ) -> bool:
        return await asyncio.to_thread(
            self.seen_or_add_compatible,
            fingerprint,
            aliases,
            now_ms=now_ms,
        )

    async def aenqueue(self, **values: object) -> bool:
        return await asyncio.to_thread(self.enqueue, **values)

    async def apending_for(
        self,
        link_id: str,
        *,
        limit: int,
        now_ms: int | None = None,
    ) -> list[StoredPacket]:
        return await asyncio.to_thread(
            self.pending_for,
            link_id,
            limit=limit,
            now_ms=now_ms,
        )

    async def amark_delivered(
        self,
        fingerprint: bytes,
        link_id: str,
        *,
        now_ms: int | None = None,
    ) -> None:
        await asyncio.to_thread(
            self.mark_delivered,
            fingerprint,
            link_id,
            now_ms=now_ms,
        )

    def _periodic_purge(self, now_ms: int) -> None:
        self._operations += 1
        if self._operations % 256 == 0:
            self.purge(now_ms=now_ms)

    def _remove_ephemeral_packets(self) -> None:
        placeholders = ",".join("?" for _ in EPHEMERAL_MESSAGE_TYPES)
        self._db.execute(
            f"DELETE FROM packets WHERE message_type IN ({placeholders})",
            tuple(EPHEMERAL_MESSAGE_TYPES),
        )

    def _enforce_limits(self) -> None:
        while (
            self.packet_count() > self.config.max_packets
            or self.packet_bytes() > self.config.max_bytes
        ):
            self._db.execute(
                """
                DELETE FROM packets
                WHERE fingerprint = (
                    SELECT fingerprint FROM packets
                    ORDER BY priority ASC, created_at_ms ASC LIMIT 1
                )
                """
            )


def _now_ms() -> int:
    return time.time_ns() // 1_000_000
