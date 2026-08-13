import base64
from dataclasses import replace

from hearthbit_relay.config import MatrixConfig
from hearthbit_relay.identity import RelayIdentity
from hearthbit_relay.matrix import (
    MATRIX_METADATA_KEY,
    MatrixBridge,
    MatrixEvent,
    _load_access_token,
)
from hearthbit_relay.protocol import (
    TYPE_COURIER_ENVELOPE,
    TYPE_MESSAGE,
    TYPE_NOISE_ENCRYPTED,
    encode_packet,
)

NOW_MS = 1_800_000_000_000
ROOM_ID = "!rescate:example.org"


class FakeMatrixApi:
    def __init__(self) -> None:
        self.handler = None
        self.rooms: tuple[str, ...] = ()
        self.sent: list[tuple[str, str, dict[str, object]]] = []
        self.started = False

    async def start(self, handler, room_ids: tuple[str, ...]) -> None:
        self.handler = handler
        self.rooms = room_ids
        self.started = True

    async def send_message(
        self,
        room_id: str,
        transaction_id: str,
        content: dict[str, object],
    ) -> None:
        self.sent.append((room_id, transaction_id, content))

    async def deliver(
        self,
        content: dict[str, object],
        *,
        room_id: str = ROOM_ID,
        sender: str = "@source-bridge:example.org",
    ) -> None:
        assert self.handler is not None
        await self.handler(
            MatrixEvent(
                room_id,
                sender,
                "$event",
                NOW_MS,
                content,
            )
        )

    async def stop(self) -> None:
        self.started = False


class FakeCore:
    def __init__(self) -> None:
        self.links = {}
        self.injected: list[tuple[str, bytes, tuple[bytes, ...]]] = []

    async def register_link(self, link) -> int:
        self.links[link.id] = link
        return 0

    async def remove_link(self, link_id: str) -> None:
        self.links.pop(link_id, None)

    async def inbound(
        self,
        source_id: str,
        raw: bytes,
        *,
        gateway_path: tuple[bytes, ...] = (),
    ) -> object:
        self.injected.append((source_id, raw, gateway_path))
        return object()


def matrix_config(**changes) -> MatrixConfig:
    return replace(
        MatrixConfig(),
        enabled=True,
        homeserver_url="https://matrix.example.org",
        rooms=(ROOM_ID,),
        sender_allowlist=frozenset({"@source-bridge:example.org"}),
        bot_user_id="@local-bridge:example.org",
        **changes,
    )


def signed_packet(
    identity: RelayIdentity,
    *,
    payload: bytes,
    message_type: int = TYPE_MESSAGE,
    timestamp_ms: int = NOW_MS,
    recipient_id: bytes | None = None,
    signing_identity: RelayIdentity | None = None,
) -> bytes:
    canonical = encode_packet(
        message_type=message_type,
        ttl=0,
        timestamp_ms=timestamp_ms,
        sender_id=identity.peer_id,
        recipient_id=recipient_id,
        payload=payload,
        pad=True,
    )
    signer = identity if signing_identity is None else signing_identity
    return encode_packet(
        message_type=message_type,
        ttl=6,
        timestamp_ms=timestamp_ms,
        sender_id=identity.peer_id,
        recipient_id=recipient_id,
        payload=payload,
        signature=signer.sign(canonical),
    )


def announcement(identity: RelayIdentity) -> bytes:
    return identity.build_announcement(
        nickname="Equipo Alfa",
        timestamp_ms=NOW_MS,
    )


def bridge(
    core: FakeCore,
    api: FakeMatrixApi,
    *,
    material: bytes,
    clock,
    config: MatrixConfig | None = None,
) -> MatrixBridge:
    return MatrixBridge(
        config or matrix_config(),
        core,
        api,
        identity_material=material,
        clock_ms=clock,
    )


async def test_export_preserves_signed_frame_and_announce_in_explicit_room(
    tmp_path,
) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    core = FakeCore()
    api = FakeMatrixApi()
    matrix = bridge(core, api, material=b"matrix-a", clock=lambda: NOW_MS)

    await matrix.send(announcement(identity))
    frame = signed_packet(identity, payload=b"mensaje publico")
    await matrix.send(frame)

    [(room_id, transaction_id, content)] = api.sent
    metadata = content[MATRIX_METADATA_KEY]
    assert room_id == ROOM_ID
    assert transaction_id.startswith("hbit-")
    assert content["body"] == "mensaje publico"
    assert base64.b64decode(metadata["frame_b64"]) == frame
    assert base64.b64decode(metadata["announce_b64"]) == announcement(identity)
    assert metadata["kind"] == "message"


async def test_export_rejects_private_opaque_unknown_and_bad_signatures(
    tmp_path,
) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    attacker = RelayIdentity.load_or_create(tmp_path / "attacker.json")
    core = FakeCore()
    api = FakeMatrixApi()
    matrix = bridge(core, api, material=b"matrix-a", clock=lambda: NOW_MS)
    await matrix.send(announcement(identity))

    excluded = [
        signed_packet(
            identity,
            payload=b"privado",
            recipient_id=b"target01",
        ),
        signed_packet(
            identity,
            payload=b"courier",
            message_type=TYPE_COURIER_ENVELOPE,
        ),
        signed_packet(
            identity,
            payload=b"noise",
            message_type=TYPE_NOISE_ENCRYPTED,
        ),
        signed_packet(
            identity,
            payload=b"firma falsa",
            signing_identity=attacker,
        ),
    ]
    for frame in excluded:
        await matrix.send(frame)

    assert api.sent == []


async def test_import_checks_allowlist_signature_fingerprint_replay_and_loop(
    tmp_path,
) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    source_core = FakeCore()
    source_api = FakeMatrixApi()
    source = bridge(
        source_core,
        source_api,
        material=b"matrix-source",
        clock=lambda: NOW_MS,
    )
    await source.send(announcement(identity))
    frame = signed_packet(identity, payload=b"SOS|Necesito ayuda||")
    await source.send(frame)
    content = source_api.sent[0][2]

    target_core = FakeCore()
    target_api = FakeMatrixApi()
    target = bridge(
        target_core,
        target_api,
        material=b"matrix-target",
        clock=lambda: NOW_MS,
    )
    await target_api.start(target._receive, (ROOM_ID,))

    await target_api.deliver(content, sender="@not-allowed:example.org")
    await target_api.deliver(content, room_id="!other:example.org")
    assert target_core.injected == []

    await target_api.deliver(content)
    await target_api.deliver(content)
    assert target_core.injected == [
        (target.id, frame, (source.bridge_id,))
    ]

    looped = {
        **content,
        MATRIX_METADATA_KEY: {
            **content[MATRIX_METADATA_KEY],
            "path": [
                target.bridge_id.hex(),
                source.bridge_id.hex(),
            ],
        },
    }
    await target_api.deliver(looped)
    assert len(target_core.injected) == 1


async def test_import_rejects_tampering_and_expired_events(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    attacker = RelayIdentity.load_or_create(tmp_path / "attacker.json")
    source_core = FakeCore()
    source_api = FakeMatrixApi()
    source = bridge(
        source_core,
        source_api,
        material=b"matrix-source",
        clock=lambda: NOW_MS,
    )
    await source.send(announcement(identity))
    await source.send(signed_packet(identity, payload=b"valido"))
    content = source_api.sent[0][2]

    invalid = signed_packet(
        identity,
        payload=b"firma falsa",
        signing_identity=attacker,
    )
    tampered = {
        **content,
        MATRIX_METADATA_KEY: {
            **content[MATRIX_METADATA_KEY],
            "frame_b64": base64.b64encode(invalid).decode("ascii"),
        },
    }
    target_core = FakeCore()
    target_api = FakeMatrixApi()
    target = bridge(
        target_core,
        target_api,
        material=b"matrix-target",
        clock=lambda: NOW_MS,
    )
    await target_api.start(target._receive, (ROOM_ID,))
    misleading = {**content, "body": "mensaje no firmado"}
    await target_api.deliver(misleading)
    await target_api.deliver(tampered)
    assert target_core.injected == []

    late_core = FakeCore()
    late_api = FakeMatrixApi()
    late = bridge(
        late_core,
        late_api,
        material=b"matrix-late",
        clock=lambda: NOW_MS + 3_601_000,
    )
    await late_api.start(late._receive, (ROOM_ID,))
    await late_api.deliver(content)
    assert late_core.injected == []


def test_access_token_comes_from_environment_or_private_file(
    tmp_path,
    monkeypatch,
) -> None:
    token_file = tmp_path / "matrix-token"
    token_file.write_text("file-token\n", encoding="utf-8")
    config = matrix_config(
        access_token_env="TEST_MATRIX_TOKEN",
        access_token_file=str(token_file),
    )

    monkeypatch.delenv("TEST_MATRIX_TOKEN", raising=False)
    assert _load_access_token(config) == "file-token"

    monkeypatch.setenv("TEST_MATRIX_TOKEN", "environment-token")
    assert _load_access_token(config) == "environment-token"
