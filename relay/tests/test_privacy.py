import pytest

from hearthbit_relay.config import MatrixConfig, MqttConfig
from hearthbit_relay.public_bridge import has_emergency_coordinates


@pytest.mark.parametrize(
    "payload",
    [
        b"SOS|help|4.711|-74.072",
        b"SOS|necesito|agua|4.711|-74.072",
        b"SOS|help|casual|1|2",
        b"SOS|text|1|2",
        b"SOS|boundary|-90|180",
        b"OK\n[HB-CHECKIN|OK|123|4.711|-74.072|1]",
    ],
)
def test_emergency_coordinate_detection_accepts_real_gps(payload: bytes) -> None:
    assert has_emergency_coordinates(payload)


@pytest.mark.parametrize(
    "payload",
    [
        b"SOS|",
        b"SOS|help||",
        b"SOS|necesito|agua||",
        b"SOS|help|4.711|",
        b"SOS|help||-74.072",
        b"SOS|help|90.0001|-74.072",
        b"SOS|help|4.711|-180.0001",
        b"SOS|help|NaN|-74.072",
        b"SOS|help|4.711|inf",
        b"SOS|help|4.711|-Infinity",
        b"SOS|help|4.711|-74.072|extra",
        b"OK\n[HB-CHECKIN|OK|123|||1]",
        b"OK\n[HB-CHECKIN|OK|123|4.711|-74.072|1|extra]",
        b"OK\n[HB-CHECKIN|UNKNOWN|123|4.711|-74.072|1]",
        b"OK\n[HB-CHECKIN|OK|not-a-time|4.711|-74.072|1]",
        b"OK\n[HB-CHECKIN|OK|123|4.711|-74.072|2]",
    ],
)
def test_emergency_coordinate_detection_rejects_non_gps_fields(
    payload: bytes,
) -> None:
    assert not has_emergency_coordinates(payload)


def test_external_bridges_block_sensitive_coordinates_by_default() -> None:
    assert not MqttConfig().allow_sensitive_emergency_coordinates
    assert not MatrixConfig().allow_sensitive_emergency_coordinates
