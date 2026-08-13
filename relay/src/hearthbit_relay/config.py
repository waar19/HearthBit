from __future__ import annotations

import base64
import binascii
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from .identity import NodeRole
from .protocol import (
    TYPE_COURIER_ENVELOPE,
    TYPE_MESSAGE,
)


@dataclass(frozen=True, slots=True)
class StoreConfig:
    path: str = "/var/lib/hearthbit-relay/relay.db"
    max_bytes: int = 64 * 1024 * 1024
    max_packets: int = 20_000
    packet_ttl_seconds: int = 7 * 24 * 60 * 60
    seen_ttl_seconds: int = 24 * 60 * 60
    replay_batch: int = 256
    require_signature: bool = True
    message_types: frozenset[int] = field(
        default_factory=lambda: frozenset(
            {
                TYPE_MESSAGE,
                TYPE_COURIER_ENVELOPE,
            }
        )
    )


@dataclass(frozen=True, slots=True)
class LanConfig:
    """Opt-in local LAN gateway settings.

    The PSK is base64 so JSON configuration does not accidentally reinterpret
    arbitrary bytes. A 32-byte minimum prevents human passwords from being
    used directly as transport keys.
    """

    enabled: bool = False
    listen_host: str = "0.0.0.0"
    port: int = 45893
    psk_base64: str = ""
    discovery: bool = True
    service_name: str = "HearthBit Relay"
    max_frame_size: int = 2048
    max_connections: int = 8
    connect_timeout_seconds: float = 10.0
    idle_timeout_seconds: float = 90.0
    max_gateway_hops: int = 8


@dataclass(frozen=True, slots=True)
class MqttConfig:
    """Opt-in MQTT bridge settings; credential values never live here."""

    enabled: bool = False
    host: str = ""
    port: int = 8883
    community: str = ""
    topic_prefix: str = "hearthbit"
    tls_ca_file: str = ""
    tls_client_cert_file: str = ""
    tls_client_key_file: str = ""
    username_env: str = "HEARTHBIT_MQTT_USERNAME"
    password_env: str = "HEARTHBIT_MQTT_PASSWORD"
    secrets_file: str = ""
    keepalive_seconds: int = 60
    connect_timeout_seconds: float = 15.0
    message_expiry_seconds: int = 60 * 60
    sos_expiry_seconds: int = 10 * 60
    max_message_age_seconds: int = 60 * 60
    announce_max_age_seconds: int = 10 * 60
    future_skew_seconds: int = 2 * 60
    max_bridge_hops: int = 8

    @property
    def topic(self) -> str:
        return f"{self.topic_prefix}/{self.community}/public"


@dataclass(frozen=True, slots=True)
class MatrixPrivateConfig:
    """Reserved opt-in private routing policy; transport remains disabled."""

    enabled: bool = False
    peer_ids: frozenset[str] = field(default_factory=frozenset)


@dataclass(frozen=True, slots=True)
class MatrixConfig:
    """Opt-in Matrix bridge settings; access-token values never live here."""

    enabled: bool = False
    homeserver_url: str = ""
    rooms: tuple[str, ...] = ()
    sender_allowlist: frozenset[str] = field(default_factory=frozenset)
    bot_user_id: str = ""
    application_service_mode: bool = False
    access_token_env: str = "HEARTHBIT_MATRIX_ACCESS_TOKEN"
    access_token_file: str = ""
    tls_ca_file: str = ""
    sync_timeout_seconds: int = 30
    request_timeout_seconds: float = 15.0
    message_expiry_seconds: int = 60 * 60
    sos_expiry_seconds: int = 10 * 60
    max_message_age_seconds: int = 60 * 60
    announce_max_age_seconds: int = 10 * 60
    future_skew_seconds: int = 2 * 60
    max_bridge_hops: int = 8
    allow_insecure_localhost_for_tests: bool = False
    private_opaque: MatrixPrivateConfig = field(default_factory=MatrixPrivateConfig)


@dataclass(frozen=True, slots=True)
class RelayConfig:
    adapter: str = "hci0"
    local_name: str = "Bitle Relay"
    central_enabled: bool = True
    scan_interval_seconds: float = 20.0
    max_central_links: int = 4
    max_packet_size: int = 2048
    log_level: str = "INFO"
    store: StoreConfig = field(default_factory=StoreConfig)
    identity_path: str = "/var/lib/hearthbit-relay/identity.json"
    nickname: str = "Bitle Relay"
    node_role: NodeRole = NodeRole.INFRA_RELAY
    announce_interval_seconds: float = 5 * 60
    lan: LanConfig = field(default_factory=LanConfig)
    mqtt: MqttConfig = field(default_factory=MqttConfig)
    matrix: MatrixConfig = field(default_factory=MatrixConfig)

    @property
    def adapter_path(self) -> str:
        return f"/org/bluez/{self.adapter}"


_DEFAULT_STORE = StoreConfig()
_DEFAULT_LAN = LanConfig()
_DEFAULT_MQTT = MqttConfig()
_DEFAULT_MATRIX_PRIVATE = MatrixPrivateConfig()
_DEFAULT_MATRIX = MatrixConfig()
_DEFAULT_RELAY = RelayConfig()


def load_config(path: str | Path | None) -> RelayConfig:
    raw: dict[str, Any] = {}
    if path is not None:
        config_path = Path(path)
        if config_path.exists():
            with config_path.open("r", encoding="utf-8") as stream:
                loaded = json.load(stream)
            if not isinstance(loaded, dict):
                raise ValueError("configuration root must be a JSON object")
            raw = loaded
        else:
            raise FileNotFoundError(config_path)

    store_raw = raw.get("store", {})
    if not isinstance(store_raw, dict):
        raise ValueError("'store' must be a JSON object")
    types = store_raw.get("message_types")
    store = StoreConfig(
        path=str(store_raw.get("path", _DEFAULT_STORE.path)),
        max_bytes=_positive_int(store_raw, "max_bytes", _DEFAULT_STORE.max_bytes),
        max_packets=_positive_int(store_raw, "max_packets", _DEFAULT_STORE.max_packets),
        packet_ttl_seconds=_positive_int(
            store_raw, "packet_ttl_seconds", _DEFAULT_STORE.packet_ttl_seconds
        ),
        seen_ttl_seconds=_positive_int(
            store_raw, "seen_ttl_seconds", _DEFAULT_STORE.seen_ttl_seconds
        ),
        replay_batch=_positive_int(store_raw, "replay_batch", _DEFAULT_STORE.replay_batch),
        require_signature=bool(
            store_raw.get("require_signature", _DEFAULT_STORE.require_signature)
        ),
        message_types=_parse_message_types(types),
    )
    lan_raw = raw.get("lan", {})
    if not isinstance(lan_raw, dict):
        raise ValueError("'lan' must be a JSON object")
    lan = LanConfig(
        enabled=bool(lan_raw.get("enabled", _DEFAULT_LAN.enabled)),
        listen_host=str(lan_raw.get("listen_host", _DEFAULT_LAN.listen_host)),
        port=int(lan_raw.get("port", _DEFAULT_LAN.port)),
        psk_base64=str(lan_raw.get("psk_base64", _DEFAULT_LAN.psk_base64)),
        discovery=bool(lan_raw.get("discovery", _DEFAULT_LAN.discovery)),
        service_name=str(lan_raw.get("service_name", _DEFAULT_LAN.service_name)),
        max_frame_size=_positive_int(
            lan_raw, "max_frame_size", _DEFAULT_LAN.max_frame_size
        ),
        max_connections=_positive_int(
            lan_raw, "max_connections", _DEFAULT_LAN.max_connections
        ),
        connect_timeout_seconds=_positive_number(
            lan_raw,
            "connect_timeout_seconds",
            _DEFAULT_LAN.connect_timeout_seconds,
        ),
        idle_timeout_seconds=_positive_number(
            lan_raw, "idle_timeout_seconds", _DEFAULT_LAN.idle_timeout_seconds
        ),
        max_gateway_hops=_positive_int(
            lan_raw, "max_gateway_hops", _DEFAULT_LAN.max_gateway_hops
        ),
    )
    mqtt_raw = raw.get("mqtt", {})
    if not isinstance(mqtt_raw, dict):
        raise ValueError("'mqtt' must be a JSON object")
    forbidden_credentials = {"username", "password"} & mqtt_raw.keys()
    if forbidden_credentials:
        names = ", ".join(sorted(forbidden_credentials))
        raise ValueError(
            f"MQTT credential values cannot be stored in configuration: {names}"
        )
    mqtt = MqttConfig(
        enabled=bool(mqtt_raw.get("enabled", _DEFAULT_MQTT.enabled)),
        host=str(mqtt_raw.get("host", _DEFAULT_MQTT.host)),
        port=int(mqtt_raw.get("port", _DEFAULT_MQTT.port)),
        community=str(mqtt_raw.get("community", _DEFAULT_MQTT.community)),
        topic_prefix=str(
            mqtt_raw.get("topic_prefix", _DEFAULT_MQTT.topic_prefix)
        ).strip("/"),
        tls_ca_file=str(mqtt_raw.get("tls_ca_file", _DEFAULT_MQTT.tls_ca_file)),
        tls_client_cert_file=str(
            mqtt_raw.get(
                "tls_client_cert_file",
                _DEFAULT_MQTT.tls_client_cert_file,
            )
        ),
        tls_client_key_file=str(
            mqtt_raw.get(
                "tls_client_key_file",
                _DEFAULT_MQTT.tls_client_key_file,
            )
        ),
        username_env=str(
            mqtt_raw.get("username_env", _DEFAULT_MQTT.username_env)
        ),
        password_env=str(
            mqtt_raw.get("password_env", _DEFAULT_MQTT.password_env)
        ),
        secrets_file=str(
            mqtt_raw.get("secrets_file", _DEFAULT_MQTT.secrets_file)
        ),
        keepalive_seconds=_positive_int(
            mqtt_raw,
            "keepalive_seconds",
            _DEFAULT_MQTT.keepalive_seconds,
        ),
        connect_timeout_seconds=_positive_number(
            mqtt_raw,
            "connect_timeout_seconds",
            _DEFAULT_MQTT.connect_timeout_seconds,
        ),
        message_expiry_seconds=_positive_int(
            mqtt_raw,
            "message_expiry_seconds",
            _DEFAULT_MQTT.message_expiry_seconds,
        ),
        sos_expiry_seconds=_positive_int(
            mqtt_raw,
            "sos_expiry_seconds",
            _DEFAULT_MQTT.sos_expiry_seconds,
        ),
        max_message_age_seconds=_positive_int(
            mqtt_raw,
            "max_message_age_seconds",
            _DEFAULT_MQTT.max_message_age_seconds,
        ),
        announce_max_age_seconds=_positive_int(
            mqtt_raw,
            "announce_max_age_seconds",
            _DEFAULT_MQTT.announce_max_age_seconds,
        ),
        future_skew_seconds=_positive_int(
            mqtt_raw,
            "future_skew_seconds",
            _DEFAULT_MQTT.future_skew_seconds,
        ),
        max_bridge_hops=_positive_int(
            mqtt_raw,
            "max_bridge_hops",
            _DEFAULT_MQTT.max_bridge_hops,
        ),
    )
    matrix_raw = raw.get("matrix", {})
    if not isinstance(matrix_raw, dict):
        raise ValueError("'matrix' must be a JSON object")
    forbidden_matrix_credentials = {"access_token", "token"} & matrix_raw.keys()
    if forbidden_matrix_credentials:
        names = ", ".join(sorted(forbidden_matrix_credentials))
        raise ValueError(
            f"Matrix credential values cannot be stored in configuration: {names}"
        )
    private_raw = matrix_raw.get("private_opaque", {})
    if not isinstance(private_raw, dict):
        raise ValueError("'matrix.private_opaque' must be a JSON object")
    private_peer_ids = _parse_string_set(
        private_raw.get("peer_ids", []),
        "matrix.private_opaque.peer_ids",
    )
    matrix_private = MatrixPrivateConfig(
        enabled=bool(private_raw.get("enabled", _DEFAULT_MATRIX_PRIVATE.enabled)),
        peer_ids=private_peer_ids,
    )
    matrix = MatrixConfig(
        enabled=bool(matrix_raw.get("enabled", _DEFAULT_MATRIX.enabled)),
        homeserver_url=str(
            matrix_raw.get("homeserver_url", _DEFAULT_MATRIX.homeserver_url)
        ).rstrip("/"),
        rooms=tuple(
            _parse_string_list(matrix_raw.get("rooms", []), "matrix.rooms")
        ),
        sender_allowlist=_parse_string_set(
            matrix_raw.get("sender_allowlist", []),
            "matrix.sender_allowlist",
        ),
        bot_user_id=str(
            matrix_raw.get("bot_user_id", _DEFAULT_MATRIX.bot_user_id)
        ),
        application_service_mode=bool(
            matrix_raw.get(
                "application_service_mode",
                _DEFAULT_MATRIX.application_service_mode,
            )
        ),
        access_token_env=str(
            matrix_raw.get("access_token_env", _DEFAULT_MATRIX.access_token_env)
        ),
        access_token_file=str(
            matrix_raw.get("access_token_file", _DEFAULT_MATRIX.access_token_file)
        ),
        tls_ca_file=str(
            matrix_raw.get("tls_ca_file", _DEFAULT_MATRIX.tls_ca_file)
        ),
        sync_timeout_seconds=_positive_int(
            matrix_raw,
            "sync_timeout_seconds",
            _DEFAULT_MATRIX.sync_timeout_seconds,
        ),
        request_timeout_seconds=_positive_number(
            matrix_raw,
            "request_timeout_seconds",
            _DEFAULT_MATRIX.request_timeout_seconds,
        ),
        message_expiry_seconds=_positive_int(
            matrix_raw,
            "message_expiry_seconds",
            _DEFAULT_MATRIX.message_expiry_seconds,
        ),
        sos_expiry_seconds=_positive_int(
            matrix_raw,
            "sos_expiry_seconds",
            _DEFAULT_MATRIX.sos_expiry_seconds,
        ),
        max_message_age_seconds=_positive_int(
            matrix_raw,
            "max_message_age_seconds",
            _DEFAULT_MATRIX.max_message_age_seconds,
        ),
        announce_max_age_seconds=_positive_int(
            matrix_raw,
            "announce_max_age_seconds",
            _DEFAULT_MATRIX.announce_max_age_seconds,
        ),
        future_skew_seconds=_positive_int(
            matrix_raw,
            "future_skew_seconds",
            _DEFAULT_MATRIX.future_skew_seconds,
        ),
        max_bridge_hops=_positive_int(
            matrix_raw,
            "max_bridge_hops",
            _DEFAULT_MATRIX.max_bridge_hops,
        ),
        allow_insecure_localhost_for_tests=bool(
            matrix_raw.get(
                "allow_insecure_localhost_for_tests",
                _DEFAULT_MATRIX.allow_insecure_localhost_for_tests,
            )
        ),
        private_opaque=matrix_private,
    )
    config = RelayConfig(
        adapter=str(raw.get("adapter", _DEFAULT_RELAY.adapter)),
        local_name=str(raw.get("local_name", _DEFAULT_RELAY.local_name)),
        central_enabled=bool(raw.get("central_enabled", _DEFAULT_RELAY.central_enabled)),
        scan_interval_seconds=_positive_number(
            raw, "scan_interval_seconds", _DEFAULT_RELAY.scan_interval_seconds
        ),
        max_central_links=_positive_int(
            raw, "max_central_links", _DEFAULT_RELAY.max_central_links
        ),
        max_packet_size=_positive_int(raw, "max_packet_size", _DEFAULT_RELAY.max_packet_size),
        log_level=str(raw.get("log_level", _DEFAULT_RELAY.log_level)).upper(),
        store=store,
        identity_path=str(raw.get("identity_path", _DEFAULT_RELAY.identity_path)),
        nickname=str(raw.get("nickname", _DEFAULT_RELAY.nickname)),
        node_role=NodeRole.parse(
            str(raw.get("node_role", _DEFAULT_RELAY.node_role.value))
        ),
        announce_interval_seconds=_positive_number(
            raw,
            "announce_interval_seconds",
            _DEFAULT_RELAY.announce_interval_seconds,
        ),
        lan=lan,
        mqtt=mqtt,
        matrix=matrix,
    )
    if "/" in config.adapter or not config.adapter:
        raise ValueError("'adapter' must be a BlueZ adapter name such as hci0")
    if not 1 <= config.max_packet_size <= 65_535:
        raise ValueError("'max_packet_size' must be between 1 and 65535")
    if not config.identity_path:
        raise ValueError("'identity_path' cannot be empty")
    if not config.nickname:
        raise ValueError("'nickname' cannot be empty")
    if not 0 <= config.lan.port <= 65_535:
        raise ValueError("'lan.port' must be between 0 and 65535")
    if not 1 <= config.lan.max_frame_size <= 65_535:
        raise ValueError("'lan.max_frame_size' must be between 1 and 65535")
    if config.lan.max_frame_size < config.max_packet_size:
        raise ValueError("'lan.max_frame_size' cannot be smaller than 'max_packet_size'")
    if config.lan.max_gateway_hops > 32:
        raise ValueError("'lan.max_gateway_hops' cannot exceed 32")
    if config.lan.enabled:
        try:
            psk = base64.b64decode(config.lan.psk_base64, validate=True)
        except (binascii.Error, ValueError) as error:
            raise ValueError("'lan.psk_base64' must be valid base64") from error
        if len(psk) < 32:
            raise ValueError("'lan.psk_base64' must decode to at least 32 bytes")
    if not 1 <= config.mqtt.port <= 65_535:
        raise ValueError("'mqtt.port' must be between 1 and 65535")
    if config.mqtt.max_bridge_hops > 32:
        raise ValueError("'mqtt.max_bridge_hops' cannot exceed 32")
    cert_file = bool(config.mqtt.tls_client_cert_file)
    key_file = bool(config.mqtt.tls_client_key_file)
    if cert_file != key_file:
        raise ValueError(
            "'mqtt.tls_client_cert_file' and 'mqtt.tls_client_key_file' "
            "must be configured together"
        )
    if config.mqtt.enabled:
        if not config.mqtt.host:
            raise ValueError("'mqtt.host' is required when MQTT is enabled")
        if not _valid_topic_segment(config.mqtt.community):
            raise ValueError(
                "'mqtt.community' must contain only letters, digits, '.', '_' or '-'"
            )
        if not config.mqtt.topic_prefix or any(
            token in config.mqtt.topic_prefix for token in ("+", "#", "\x00")
        ):
            raise ValueError("'mqtt.topic_prefix' must be an exact MQTT topic prefix")
        if not config.mqtt.username_env and not config.mqtt.secrets_file:
            raise ValueError(
                "MQTT credentials require an environment variable or secrets file"
            )
    if config.matrix.max_bridge_hops > 32:
        raise ValueError("'matrix.max_bridge_hops' cannot exceed 32")
    if config.matrix.private_opaque.enabled:
        raise ValueError(
            "Matrix private opaque routing is unavailable because room delivery "
            "cannot guarantee explicit HearthBit-peer routing"
        )
    if config.matrix.enabled:
        parsed_url = urlparse(config.matrix.homeserver_url)
        local_test_http = (
            config.matrix.allow_insecure_localhost_for_tests
            and parsed_url.scheme == "http"
            and parsed_url.hostname in {"localhost", "127.0.0.1", "::1"}
        )
        if (
            not parsed_url.netloc
            or parsed_url.username is not None
            or parsed_url.password is not None
            or (parsed_url.scheme != "https" and not local_test_http)
            or parsed_url.path not in {"", "/"}
            or parsed_url.query
            or parsed_url.fragment
        ):
            raise ValueError(
                "'matrix.homeserver_url' must be an HTTPS origin; plain HTTP is "
                "allowed only for explicitly enabled localhost tests"
            )
        if not config.matrix.rooms or any(
            not _valid_matrix_id(room_id, "!") for room_id in config.matrix.rooms
        ):
            raise ValueError(
                "'matrix.rooms' must contain explicit Matrix room IDs"
            )
        if len(set(config.matrix.rooms)) != len(config.matrix.rooms):
            raise ValueError("'matrix.rooms' cannot contain duplicates")
        if not config.matrix.sender_allowlist or any(
            not _valid_matrix_id(sender, "@")
            for sender in config.matrix.sender_allowlist
        ):
            raise ValueError(
                "'matrix.sender_allowlist' must contain explicit Matrix user IDs"
            )
        if not _valid_matrix_id(config.matrix.bot_user_id, "@"):
            raise ValueError("'matrix.bot_user_id' must be a Matrix user ID")
        if not config.matrix.access_token_env and not config.matrix.access_token_file:
            raise ValueError(
                "Matrix access token requires an environment variable or token file"
            )
    return config


def _positive_int(values: dict[str, Any], key: str, default: int) -> int:
    value = int(values.get(key, default))
    if value <= 0:
        raise ValueError(f"'{key}' must be positive")
    return value


def _positive_number(values: dict[str, Any], key: str, default: float) -> float:
    value = float(values.get(key, default))
    if value <= 0:
        raise ValueError(f"'{key}' must be positive")
    return value


def _parse_message_types(value: Any) -> frozenset[int]:
    if value is None:
        return _DEFAULT_STORE.message_types
    if not isinstance(value, list):
        raise ValueError("'message_types' must be a JSON array")
    parsed: set[int] = set()
    for item in value:
        parsed_item = int(item, 0) if isinstance(item, str) else int(item)
        if not 0 <= parsed_item <= 0xFF:
            raise ValueError("message type must fit in one byte")
        parsed.add(parsed_item)
    return frozenset(parsed)


def _parse_string_list(value: Any, name: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ValueError(f"'{name}' must be an array of strings")
    return [item for item in value]


def _parse_string_set(value: Any, name: str) -> frozenset[str]:
    return frozenset(_parse_string_list(value, name))


def _valid_matrix_id(value: str, sigil: str) -> bool:
    return (
        value.startswith(sigil)
        and ":" in value[1:]
        and not any(character.isspace() for character in value)
        and len(value) <= 255
    )


def _valid_topic_segment(value: str) -> bool:
    return bool(value) and len(value) <= 64 and all(
        character.isalnum() or character in "._-" for character in value
    )
