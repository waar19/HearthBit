import json

import pytest
from dbus_fast import Variant

from hearthbit_relay.bluez import (
    SERVICE_UUID_DASHED,
    HearthBitAdvertisement,
    is_hearthbit_device,
)
from hearthbit_relay.config import RelayConfig, load_config
from hearthbit_relay.identity import NodeRole


def test_default_central_limit_is_greater_than_two() -> None:
    assert RelayConfig().max_central_links > 2


def test_identity_role_and_presence_interval_are_configurable(tmp_path) -> None:
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps(
            {
                "identity_path": str(tmp_path / "identity.json"),
                "nickname": "Refugio Norte",
                "node_role": "INFRA_DATA_ANCHOR",
                "announce_interval_seconds": 45,
                "max_central_links": 6,
            }
        ),
        encoding="utf-8",
    )

    config = load_config(path)

    assert config.identity_path == str(tmp_path / "identity.json")
    assert config.nickname == "Refugio Norte"
    assert config.node_role is NodeRole.INFRA_DATA_ANCHOR
    assert config.announce_interval_seconds == 45
    assert config.max_central_links == 6


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("node_role", "PHONE_RELAY"),
        ("max_central_links", 0),
    ],
)
def test_invalid_identity_and_bluez_configuration_is_rejected(
    tmp_path, field: str, value: object
) -> None:
    path = tmp_path / "config.json"
    path.write_text(json.dumps({field: value}), encoding="utf-8")

    with pytest.raises(ValueError):
        load_config(path)


def test_discovery_accepts_service_uuid_without_exact_bluetooth_name() -> None:
    device = {
        "Name": Variant("s", "Teléfono de Ana"),
        "UUIDs": Variant("as", [SERVICE_UUID_DASHED.upper()]),
    }

    assert is_hearthbit_device(device)
    assert not is_hearthbit_device(
        {
            "Name": Variant("s", "Bitle Relay"),
            "UUIDs": Variant("as", ["0000180f-0000-1000-8000-00805f9b34fb"]),
        }
    )


def test_advertisement_exposes_service_uuid_with_custom_name() -> None:
    advertisement = HearthBitAdvertisement("Custom name")

    assert advertisement.ServiceUUIDs == [SERVICE_UUID_DASHED]
    assert advertisement.LocalName == "Custom name"


def test_mqtt_is_disabled_and_tls_port_is_secure_by_default() -> None:
    config = RelayConfig().mqtt

    assert not config.enabled
    assert config.port == 8883
    assert config.topic == "hearthbit//public"


def test_matrix_is_disabled_and_private_routing_is_unavailable_by_default() -> None:
    config = RelayConfig().matrix

    assert not config.enabled
    assert not config.private_opaque.enabled
    assert config.rooms == ()


def test_enabled_matrix_requires_explicit_rooms_allowlist_and_https(tmp_path) -> None:
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps(
            {
                "matrix": {
                    "enabled": True,
                    "homeserver_url": "https://matrix.example.org",
                    "rooms": ["!rescate:example.org"],
                    "sender_allowlist": ["@remote-bridge:example.org"],
                    "bot_user_id": "@hearthbit:example.org",
                    "application_service_mode": True,
                    "access_token_file": "/run/secrets/matrix-token",
                }
            }
        ),
        encoding="utf-8",
    )

    config = load_config(path).matrix

    assert config.rooms == ("!rescate:example.org",)
    assert config.sender_allowlist == frozenset({"@remote-bridge:example.org"})
    assert config.application_service_mode
    assert not config.private_opaque.enabled


@pytest.mark.parametrize(
    "matrix",
    [
        {
            "enabled": True,
            "homeserver_url": "http://matrix.example.org",
            "rooms": ["!rescate:example.org"],
            "sender_allowlist": ["@remote:example.org"],
            "bot_user_id": "@local:example.org",
        },
        {
            "enabled": True,
            "homeserver_url": "https://matrix.example.org",
            "rooms": [],
            "sender_allowlist": ["@remote:example.org"],
            "bot_user_id": "@local:example.org",
        },
        {
            "enabled": True,
            "homeserver_url": "https://matrix.example.org",
            "rooms": ["!rescate:example.org"],
            "sender_allowlist": [],
            "bot_user_id": "@local:example.org",
        },
        {
            "enabled": True,
            "homeserver_url": "https://matrix.example.org",
            "rooms": ["!rescate:example.org"],
            "sender_allowlist": ["@remote:example.org"],
            "bot_user_id": "@local:example.org",
            "access_token": "no-debe-estar-aqui",
        },
        {
            "private_opaque": {
                "enabled": True,
                "peer_ids": ["0011223344556677"],
            }
        },
    ],
)
def test_unsafe_matrix_configuration_is_rejected(tmp_path, matrix) -> None:
    path = tmp_path / "config.json"
    path.write_text(json.dumps({"matrix": matrix}), encoding="utf-8")

    with pytest.raises(ValueError):
        load_config(path)


def test_enabled_mqtt_uses_community_scoped_exact_topic(tmp_path) -> None:
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps(
            {
                "mqtt": {
                    "enabled": True,
                    "host": "mqtt.example.org",
                    "community": "refugio-norte",
                    "topic_prefix": "organizacion/hearthbit",
                    "tls_client_cert_file": "/ssl/client.crt",
                    "tls_client_key_file": "/ssl/client.key",
                    "bridge_allowlist": [
                        "00112233445566778899aabbccddeeff"
                    ],
                    "inbound_queue_size": 64,
                }
            }
        ),
        encoding="utf-8",
    )

    config = load_config(path).mqtt

    assert config.topic == "organizacion/hearthbit/refugio-norte/public"
    assert "+" not in config.topic and "#" not in config.topic
    assert config.bridge_allowlist == frozenset(
        {bytes.fromhex("00112233445566778899aabbccddeeff")}
    )
    assert config.inbound_queue_size == 64


@pytest.mark.parametrize(
    "mqtt",
    [
        {
            "enabled": True,
            "host": "",
            "community": "rescate",
        },
        {
            "enabled": True,
            "host": "mqtt.example.org",
            "community": "../otra",
        },
        {
            "enabled": True,
            "host": "mqtt.example.org",
            "community": "rescate",
            "topic_prefix": "hearthbit/#",
        },
        {
            "enabled": True,
            "host": "mqtt.example.org",
            "community": "rescate",
            "tls_client_cert_file": "/ssl/client.crt",
        },
        {
            "enabled": True,
            "host": "mqtt.example.org",
            "community": "rescate",
            "password": "no-debe-estar-aqui",
        },
        {
            "enabled": True,
            "host": "mqtt.example.org",
            "community": "rescate",
            "bridge_allowlist": ["not-hex"],
        },
    ],
)
def test_unsafe_mqtt_configuration_is_rejected(tmp_path, mqtt) -> None:
    path = tmp_path / "config.json"
    path.write_text(json.dumps({"mqtt": mqtt}), encoding="utf-8")

    with pytest.raises(ValueError):
        load_config(path)


def test_identity_and_flood_policies_are_bounded(tmp_path) -> None:
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps(
            {
                "identity_verification": {
                    "unknown_signed_policy": "reject",
                },
                "flood": {
                    "sender_rate_per_second": 4,
                    "sender_burst": 8,
                    "emergency_rate_per_second": 1,
                    "emergency_burst": 3,
                    "bridge_rate_per_second": 10,
                    "bridge_burst": 20,
                },
            }
        ),
        encoding="utf-8",
    )

    config = load_config(path)
    assert config.identity_verification.unknown_signed_policy == "reject"
    assert config.flood.sender_burst == 8

    path.write_text(
        json.dumps(
            {
                "identity_verification": {
                    "unknown_signed_policy": "allow-unverified",
                }
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError):
        load_config(path)
