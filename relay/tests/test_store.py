import sqlite3

from hearthbit_relay.config import StoreConfig
from hearthbit_relay.protocol import (
    TYPE_ANNOUNCE,
    TYPE_EMERGENCY_CAPABILITY,
    TYPE_HBT_CAPABILITY,
    TYPE_MESSAGE,
    TYPE_NODE_CAPABILITY,
)
from hearthbit_relay.store import PacketStore


def test_seen_cache_expires(tmp_path) -> None:
    store = PacketStore(
        StoreConfig(path=str(tmp_path / "relay.db"), seen_ttl_seconds=1)
    )
    fingerprint = b"a" * 16

    assert store.seen_or_add(fingerprint, now_ms=1_000) is False
    assert store.seen_or_add(fingerprint, now_ms=1_500) is True
    assert store.seen_or_add(fingerprint, now_ms=2_001) is False
    store.close()


def test_store_replays_once_per_link_and_evicts_oldest(tmp_path) -> None:
    store = PacketStore(
        StoreConfig(
            path=str(tmp_path / "relay.db"),
            max_packets=2,
            max_bytes=100,
        )
    )
    for index in range(3):
        assert store.enqueue(
            fingerprint=bytes([index]) * 16,
            packet=bytes([index]) * 10,
            message_type=0x02,
            sender_id=b"sender01",
            expires_at_ms=100_000,
            now_ms=1_000 + index,
        )

    assert store.packet_count() == 2
    pending = store.pending_for("peer-a", limit=10, now_ms=2_000)
    assert [item.fingerprint[0] for item in pending] == [1, 2]

    store.mark_delivered(pending[0].fingerprint, "peer-a", now_ms=2_000)
    assert [item.fingerprint[0] for item in store.pending_for(
        "peer-a", limit=10, now_ms=2_000
    )] == [2]
    assert len(store.pending_for("peer-b", limit=10, now_ms=2_000)) == 2
    store.close()


def test_emergency_priority_survives_limits_and_replays_first(tmp_path) -> None:
    store = PacketStore(
        StoreConfig(path=str(tmp_path / "relay.db"), max_packets=2, max_bytes=100)
    )
    store.enqueue(
        fingerprint=b"e" * 16,
        packet=b"emergency",
        message_type=TYPE_MESSAGE,
        sender_id=b"sender01",
        expires_at_ms=100_000,
        priority=100,
        now_ms=1_000,
    )
    for index in range(2):
        store.enqueue(
            fingerprint=bytes([index]) * 16,
            packet=b"normal",
            message_type=TYPE_MESSAGE,
            sender_id=b"sender02",
            expires_at_ms=100_000,
            now_ms=2_000 + index,
        )

    pending = store.pending_for("peer", limit=10, now_ms=3_000)
    assert [item.packet for item in pending] == [b"emergency", b"normal"]
    store.close()


def test_expired_packets_are_removed(tmp_path) -> None:
    store = PacketStore(StoreConfig(path=str(tmp_path / "relay.db")))
    store.enqueue(
        fingerprint=b"x" * 16,
        packet=b"packet",
        message_type=0x02,
        sender_id=b"sender01",
        expires_at_ms=2_000,
        now_ms=1_000,
    )

    store.purge(now_ms=2_000)
    assert store.packet_count() == 0
    store.close()


def test_store_rejects_ephemeral_packets_even_when_called_directly(tmp_path) -> None:
    store = PacketStore(StoreConfig(path=str(tmp_path / "relay.db")))

    for index, message_type in enumerate(
        (
            TYPE_ANNOUNCE,
            TYPE_HBT_CAPABILITY,
            TYPE_NODE_CAPABILITY,
            TYPE_EMERGENCY_CAPABILITY,
        )
    ):
        assert not store.enqueue(
            fingerprint=bytes([index]) * 16,
            packet=b"ephemeral",
            message_type=message_type,
            sender_id=b"sender01",
            expires_at_ms=100_000,
            now_ms=1_000,
        )

    assert store.packet_count() == 0
    store.close()


def test_existing_database_drops_ephemeral_rows_but_keeps_messages(tmp_path) -> None:
    path = tmp_path / "relay.db"
    store = PacketStore(StoreConfig(path=str(path)))
    store.close()

    connection = sqlite3.connect(path)
    rows = [
        (b"a" * 16, b"announce", TYPE_ANNOUNCE),
        (b"h" * 16, b"hbt", TYPE_HBT_CAPABILITY),
        (b"n" * 16, b"node", TYPE_NODE_CAPABILITY),
        (b"m" * 16, b"message", TYPE_MESSAGE),
    ]
    connection.executemany(
        """
        INSERT INTO packets(
            fingerprint, packet, message_type, sender_id,
            created_at_ms, expires_at_ms, size
        ) VALUES(?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (fingerprint, packet, message_type, b"sender01", 1_000, 100_000, len(packet))
            for fingerprint, packet, message_type in rows
        ],
    )
    connection.commit()
    connection.close()

    reopened = PacketStore(StoreConfig(path=str(path)))

    assert reopened.packet_count() == 1
    pending = reopened.pending_for("peer", limit=10, now_ms=2_000)
    assert [item.packet for item in pending] == [b"message"]
    reopened.close()
