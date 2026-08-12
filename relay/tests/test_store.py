from hearthbit_relay.config import StoreConfig
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
