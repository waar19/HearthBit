import hashlib
from dataclasses import replace

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

from hearthbit_relay.config import RelayConfig, StoreConfig
from hearthbit_relay.core import RelayCore
from hearthbit_relay.identity import RelayIdentity
from hearthbit_relay.link import InMemoryRelayLink
from hearthbit_relay.protocol import (
    TYPE_MESSAGE,
    canonical_packet_bytes,
    decode_packet,
    encode_packet,
)
from hearthbit_relay.store import PacketStore
from hearthbit_relay.trust import TrustStore


def _identity(seed: int) -> RelayIdentity:
    seed_bytes = str(seed).encode("ascii")
    return RelayIdentity(
        X25519PrivateKey.from_private_bytes(
            hashlib.sha256(b"noise:" + seed_bytes).digest()
        ),
        Ed25519PrivateKey.from_private_bytes(
            hashlib.sha256(b"signing:" + seed_bytes).digest()
        ),
    )


def _signed_message(
    identity: RelayIdentity,
    *,
    timestamp_ms: int,
    payload: bytes,
) -> bytes:
    fields = {
        "message_type": TYPE_MESSAGE,
        "ttl": 7,
        "timestamp_ms": timestamp_ms,
        "sender_id": identity.peer_id,
        "payload": payload,
    }
    unsigned = decode_packet(encode_packet(**fields))
    return encode_packet(
        **fields,
        signature=identity.sign(canonical_packet_bytes(unsigned)),
    )


def _relay_config() -> RelayConfig:
    return replace(
        RelayConfig(),
        store=replace(StoreConfig(), path=":memory:"),
        trust_store_path=":memory:",
    )


async def test_unknown_signed_identity_spam_is_rejected_without_state_growth() -> None:
    config = _relay_config()
    store = PacketStore(config.store)
    trust_store = TrustStore(":memory:")
    core = RelayCore(
        config,
        store,
        trust_store=trust_store,
        monotonic=lambda: 100.0,
    )
    sink = InMemoryRelayLink()
    await core.register_link(sink)
    identity_count = config.flood.sender_burst * 4
    identities = [_identity(seed) for seed in range(1, identity_count + 1)]

    try:
        results = [
            await core.inbound(
                "ble:source",
                _signed_message(
                    identity,
                    timestamp_ms=index,
                    payload=b"SOS|unknown sender||",
                ),
            )
            for index, identity in enumerate(identities, start=1)
        ]

        assert len({identity.peer_id for identity in identities}) == identity_count
        assert config.identity_verification.unknown_signed_policy == "reject"
        assert {result.reason for result in results} == {"unknown-signing-key"}
        assert all(
            not result.accepted
            and result.forwarded == 0
            and not result.stored
            for result in results
        )
        assert trust_store.sender_ids() == ()
        assert core._buckets == {}
        assert store.packet_count() == 0
        assert sink.sent == []
    finally:
        store.close()


async def test_verified_sos_burst_is_bounded_by_current_emergency_policy() -> None:
    config = _relay_config()
    store = PacketStore(config.store)
    trust_store = TrustStore(":memory:")
    core = RelayCore(
        config,
        store,
        trust_store=trust_store,
        monotonic=lambda: 100.0,
        announcement_clock_ms=lambda: 1,
    )
    sink = InMemoryRelayLink()
    await core.register_link(sink)
    sender = _identity(10_000)

    try:
        announcement = await core.inbound(
            "ble:source",
            sender.build_announcement(nickname="Load sender", timestamp_ms=1),
        )
        assert announcement.accepted
        sink.sent.clear()

        burst = config.flood.emergency_burst
        results = [
            await core.inbound(
                "ble:source",
                _signed_message(
                    sender,
                    timestamp_ms=index + 1,
                    payload=f"SOS|burst {index}||".encode(),
                ),
            )
            for index in range(burst * 2)
        ]

        accepted = results[:burst]
        rejected = results[burst:]
        assert len(accepted) == len(rejected) == burst
        assert all(
            result.accepted
            and result.reason == "relayed"
            and result.forwarded == 1
            and result.stored
            for result in accepted
        )
        assert all(
            not result.accepted
            and result.reason == "rate-limited"
            and result.forwarded == 0
            and not result.stored
            for result in rejected
        )
        assert len(sink.sent) == burst
        assert store.packet_count() == burst
    finally:
        store.close()
