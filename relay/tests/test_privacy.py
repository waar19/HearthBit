from hearthbit_relay.config import MatrixConfig, MqttConfig
from hearthbit_relay.public_bridge import has_emergency_coordinates


def test_emergency_coordinate_detection() -> None:
    assert has_emergency_coordinates(b"SOS|help|4.711|-74.072")
    assert not has_emergency_coordinates(b"SOS|help||")
    assert has_emergency_coordinates(
        b"OK\n[HB-CHECKIN|OK|123|4.711|-74.072|1]"
    )
    assert not has_emergency_coordinates(
        b"OK\n[HB-CHECKIN|OK|123|||1]"
    )


def test_external_bridges_block_sensitive_coordinates_by_default() -> None:
    assert not MqttConfig().allow_sensitive_emergency_coordinates
    assert not MatrixConfig().allow_sensitive_emergency_coordinates
