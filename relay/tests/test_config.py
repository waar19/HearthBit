import json

import pytest
from dbus_next import Variant

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
