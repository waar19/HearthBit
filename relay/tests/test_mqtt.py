import base64
import json
from dataclasses import replace

import pytest

from hearthbit_relay.config import MqttConfig
from hearthbit_relay.identity import RelayIdentity
from hearthbit_relay.mqtt import BrokerMessage, MqttBridge
from hearthbit_relay.protocol import (
    TYPE_COURIER_ENVELOPE,
    TYPE_HBT_CAPABILITY,
    TYPE_MESSAGE,
    TYPE_NODE_CAPABILITY,
    TYPE_NOISE_ENCRYPTED,
    encode_packet,
)

NOW_MS = 1_800_000_000_000


class FakeBroker:
    def __init__(self) -> None:
        self.handler = None
        self.published: list[dict[str, object]] = []
        self.started = False

    async def start(self, handler) -> None:
        self.handler = handler
        self.started = True

    async def publish(
        self,
        topic: str,
        payload: bytes,
        *,
        qos: int,
        retain: bool,
        expiry_seconds: int,
    ) -> None:
        self.published.append(
            {
                "topic": topic,
                "payload": payload,
                "qos": qos,
                "retain": retain,
                "expiry_seconds": expiry_seconds,
            }
        )

    async def deliver(self, payload: bytes, *, retained: bool = False) -> None:
        assert self.handler is not None
        await self.handler(
            BrokerMessage("hearthbit/rescate/public", payload, retained)
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


def mqtt_config(**changes) -> MqttConfig:
    return replace(
        MqttConfig(),
        enabled=True,
        host="mqtt.example.org",
        community="rescate",
        **changes,
    )


def signed_packet(
    identity: RelayIdentity,
    *,
    payload: bytes,
    message_type: int = TYPE_MESSAGE,
    timestamp_ms: int = NOW_MS,
    recipient_id: bytes | None = None,
    sender_id: bytes | None = None,
    signing_identity: RelayIdentity | None = None,
) -> bytes:
    sender = identity.peer_id if sender_id is None else sender_id
    canonical = encode_packet(
        message_type=message_type,
        ttl=0,
        timestamp_ms=timestamp_ms,
        sender_id=sender,
        recipient_id=recipient_id,
        payload=payload,
        pad=True,
    )
    signer = identity if signing_identity is None else signing_identity
    return encode_packet(
        message_type=message_type,
        ttl=6,
        timestamp_ms=timestamp_ms,
        sender_id=sender,
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
    broker: FakeBroker,
    *,
    material: bytes,
    clock,
    config: MqttConfig | None = None,
) -> MqttBridge:
    return MqttBridge(
        config or mqtt_config(),
        core,
        broker,
        identity_material=material,
        clock_ms=clock,
    )


async def test_export_only_allows_authenticated_undirected_messages(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    core = FakeCore()
    broker = FakeBroker()
    mqtt = bridge(core, broker, material=b"bridge-a", clock=lambda: NOW_MS)

    await mqtt.send(announcement(identity))
    assert broker.published == []

    public = signed_packet(identity, payload=b"mensaje publico")
    await mqtt.send(public)
    assert len(broker.published) == 1
    exported = json.loads(broker.published[0]["payload"])
    assert base64.b64decode(exported["frame_b64"]) == public
    assert exported["kind"] == "message"

    excluded = [
        signed_packet(
            identity,
            payload=b"dirigido",
            recipient_id=b"target01",
        ),
        encode_packet(
            message_type=TYPE_MESSAGE,
            ttl=6,
            timestamp_ms=NOW_MS,
            sender_id=identity.peer_id,
            payload=b"sin firma",
        ),
    ]
    for message_type in (
        TYPE_NOISE_ENCRYPTED,
        TYPE_COURIER_ENVELOPE,
        0x23,
        TYPE_HBT_CAPABILITY,
        TYPE_NODE_CAPABILITY,
    ):
        excluded.append(
            signed_packet(
                identity,
                payload=b"no exportar",
                message_type=message_type,
            )
        )
    for frame in excluded:
        await mqtt.send(frame)

    assert len(broker.published) == 1


async def test_export_rejects_invalid_signature_and_gateway_loop(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    attacker = RelayIdentity.load_or_create(tmp_path / "attacker.json")
    core = FakeCore()
    broker = FakeBroker()
    mqtt = bridge(core, broker, material=b"bridge-a", clock=lambda: NOW_MS)
    await mqtt.send(announcement(identity))

    wrong_signature = signed_packet(
        identity,
        payload=b"alterado",
        signing_identity=attacker,
    )
    await mqtt.send(wrong_signature)
    valid = signed_packet(identity, payload=b"valido")
    await mqtt.send_with_path(valid, (mqtt.bridge_id,))

    assert broker.published == []


async def test_sos_uses_qos_one_expiry_and_never_retains(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    core = FakeCore()
    broker = FakeBroker()
    mqtt = bridge(core, broker, material=b"bridge-a", clock=lambda: NOW_MS)
    await mqtt.send(announcement(identity))

    await mqtt.send(signed_packet(identity, payload=b"SOS|Necesito ayuda||"))

    [published] = broker.published
    envelope = json.loads(published["payload"])
    assert envelope["kind"] == "sos"
    assert published["qos"] == 1
    assert published["retain"] is False
    assert published["expiry_seconds"] == mqtt.config.sos_expiry_seconds


async def test_import_validates_signature_replay_retained_and_loop(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    source_core = FakeCore()
    source_broker = FakeBroker()
    source = bridge(
        source_core,
        source_broker,
        material=b"bridge-source",
        clock=lambda: NOW_MS,
    )
    await source.send(announcement(identity))
    frame = signed_packet(identity, payload=b"mensaje")
    await source.send(frame)
    payload = source_broker.published[0]["payload"]

    target_core = FakeCore()
    target_broker = FakeBroker()
    target = bridge(
        target_core,
        target_broker,
        material=b"bridge-target",
        clock=lambda: NOW_MS,
    )
    await target_broker.start(target._receive)

    await target_broker.deliver(payload, retained=True)
    assert target_core.injected == []

    await target_broker.deliver(payload)
    await target_broker.deliver(payload)
    assert target_core.injected == [
        (target.id, frame, (source.bridge_id,))
    ]

    looped = json.loads(payload)
    looped["path"].insert(0, target.bridge_id.hex())
    await target_broker.deliver(
        json.dumps(looped, separators=(",", ":")).encode()
    )
    assert len(target_core.injected) == 1


async def test_import_rejects_invalid_signature_and_expired_envelope(tmp_path) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    attacker = RelayIdentity.load_or_create(tmp_path / "attacker.json")
    source_core = FakeCore()
    source_broker = FakeBroker()
    source = bridge(
        source_core,
        source_broker,
        material=b"bridge-source",
        clock=lambda: NOW_MS,
    )
    await source.send(announcement(identity))
    await source.send(signed_packet(identity, payload=b"valido"))
    document = json.loads(source_broker.published[0]["payload"])

    invalid = signed_packet(
        identity,
        payload=b"firma falsa",
        signing_identity=attacker,
    )
    document["frame_b64"] = base64.b64encode(invalid).decode()
    target_core = FakeCore()
    target_broker = FakeBroker()
    target = bridge(
        target_core,
        target_broker,
        material=b"bridge-target",
        clock=lambda: NOW_MS,
    )
    await target_broker.start(target._receive)
    await target_broker.deliver(json.dumps(document).encode())
    assert target_core.injected == []

    await source.send(signed_packet(identity, payload=b"SOS|tarde||"))
    expired_payload = source_broker.published[-1]["payload"]
    late_core = FakeCore()
    late_broker = FakeBroker()
    late = bridge(
        late_core,
        late_broker,
        material=b"bridge-late",
        clock=lambda: NOW_MS + 601_000,
    )
    await late_broker.start(late._receive)
    await late_broker.deliver(expired_payload)
    assert late_core.injected == []


async def test_message_without_recent_valid_announcement_is_not_exported(
    tmp_path,
) -> None:
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    core = FakeCore()
    broker = FakeBroker()
    mqtt = bridge(core, broker, material=b"bridge-a", clock=lambda: NOW_MS)

    await mqtt.send(signed_packet(identity, payload=b"sin announce"))
    stale = identity.build_announcement(
        nickname="Viejo",
        timestamp_ms=NOW_MS - 601_000,
    )
    await mqtt.send(stale)
    await mqtt.send(signed_packet(identity, payload=b"announce viejo"))

    assert broker.published == []


@pytest.mark.parametrize("field", ["username", "password"])
def test_plaintext_credentials_are_not_mqtt_config_fields(field: str) -> None:
    assert not hasattr(MqttConfig(), field)
