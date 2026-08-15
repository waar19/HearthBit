from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import pytest

from hearthbit_relay.config import ReticulumConfig
from hearthbit_relay.identity import RelayIdentity
from hearthbit_relay.protocol import TYPE_MESSAGE, encode_packet
from hearthbit_relay.reticulum import (
    ReticulumBridge,
    _decode_envelope,
    _encode_envelope,
)

NOW_MS = 1_800_000_000_000


@dataclass
class FakeBackend:
    local_hash: bytes = b"L" * 16
    handler: object | None = None
    sent: list[tuple[bytes, bytes]] = field(default_factory=list)
    stopped: bool = False

    async def start(self, handler):
        self.handler = handler
        return self.local_hash

    async def send(self, destination_hash: bytes, payload: bytes) -> bool:
        self.sent.append((destination_hash, payload))
        return True

    async def stop(self) -> None:
        self.stopped = True


@dataclass
class FakeCore:
    registered: list[object] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    inbound_frames: list[tuple[str, bytes, tuple[bytes, ...]]] = field(
        default_factory=list
    )

    async def register_link(self, link) -> int:
        self.registered.append(link)
        return 0

    async def remove_link(self, link_id: str) -> None:
        self.removed.append(link_id)

    async def inbound(
        self,
        source_id: str,
        raw: bytes,
        *,
        gateway_path: tuple[bytes, ...] = (),
    ) -> object:
        self.inbound_frames.append((source_id, raw, gateway_path))
        return object()


def _signed_frame(
    identity: RelayIdentity,
    payload: bytes = b"hello",
    *,
    recipient_id: bytes | None = None,
) -> bytes:
    canonical = encode_packet(
        message_type=TYPE_MESSAGE,
        ttl=0,
        timestamp_ms=NOW_MS,
        sender_id=identity.peer_id,
        recipient_id=recipient_id,
        payload=payload,
        pad=True,
    )
    return encode_packet(
        message_type=TYPE_MESSAGE,
        ttl=7,
        timestamp_ms=NOW_MS,
        sender_id=identity.peer_id,
        recipient_id=recipient_id,
        payload=payload,
        signature=identity.sign(canonical),
    )


def _announcement(identity: RelayIdentity) -> bytes:
    return identity.build_announcement(
        nickname="Reticulum peer",
        timestamp_ms=NOW_MS,
    )


def _identity(path: Path) -> RelayIdentity:
    return RelayIdentity.load_or_create(path)


def _config() -> ReticulumConfig:
    return ReticulumConfig(
        enabled=True,
        storage_path="/tmp/hbt-rns-test",
        destination_hashes=frozenset({b"D" * 16}),
        source_allowlist=frozenset({b"A" * 16}),
    )


def test_envelope_round_trip_and_rejects_duplicate_path() -> None:
    frame = b"signed-frame"
    announcement = b"signed-announcement"
    path = (b"A" * 16, b"B" * 16)
    encoded = _encode_envelope(
        frame,
        announcement,
        "message",
        path,
        max_frame_size=2048,
    )

    assert _decode_envelope(encoded, max_frame_size=2048, max_hops=8) == (
        frame,
        announcement,
        "message",
        path,
    )

    duplicate = _encode_envelope(
        frame,
        announcement,
        "message",
        (b"A" * 16, b"A" * 16),
        max_frame_size=2048,
    )
    assert _decode_envelope(duplicate, max_frame_size=2048, max_hops=8) is None


@pytest.mark.asyncio
async def test_bridge_sends_and_receives_only_verified_public_messages(
    tmp_path: Path,
) -> None:
    core = FakeCore()
    backend = FakeBackend()
    local_identity = _identity(tmp_path / "local.json")
    remote_identity = _identity(tmp_path / "remote.json")
    bridge = ReticulumBridge(
        _config(),
        core,
        backend,
        identity_material=b"identity",
        clock_ms=lambda: NOW_MS,
    )
    await bridge.start()
    local_announcement = _announcement(local_identity)
    frame = _signed_frame(local_identity)

    await bridge.send(local_announcement)
    assert backend.sent == []
    await bridge.send(frame)

    assert len(backend.sent) == 1
    destination, payload = backend.sent[0]
    assert destination == b"D" * 16
    decoded = _decode_envelope(payload, max_frame_size=2048, max_hops=8)
    assert decoded is not None
    assert decoded[0] == frame
    assert decoded[1] == local_announcement
    assert decoded[2] == "message"
    assert decoded[3][-1] == bridge.bridge_id

    remote_path = (b"R" * 16,)
    remote_frame = _signed_frame(remote_identity)
    incoming = _encode_envelope(
        remote_frame,
        _announcement(remote_identity),
        "message",
        remote_path,
        max_frame_size=2048,
    )
    assert backend.handler is not None
    await backend.handler(b"X" * 16, incoming)
    assert core.inbound_frames == []

    await backend.handler(b"A" * 16, incoming)
    assert core.inbound_frames == [(bridge.id, remote_frame, remote_path)]

    await bridge.stop()
    assert backend.stopped
    assert core.removed == [bridge.id]


@pytest.mark.asyncio
async def test_private_and_sensitive_messages_are_blocked_by_default(
    tmp_path: Path,
) -> None:
    core = FakeCore()
    backend = FakeBackend()
    identity = _identity(tmp_path / "sender.json")
    bridge = ReticulumBridge(
        _config(),
        core,
        backend,
        identity_material=b"identity",
        clock_ms=lambda: NOW_MS,
    )
    await bridge.start()

    await bridge.send(_announcement(identity))
    await bridge.send(_signed_frame(identity, recipient_id=b"private1"))
    await bridge.send(_signed_frame(identity, b"SOS|help|4.711|-74.072"))

    assert backend.sent == []
