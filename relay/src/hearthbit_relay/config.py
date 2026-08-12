from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .protocol import (
    TYPE_COURIER_ENVELOPE,
    TYPE_GROUP_MESSAGE,
    TYPE_MESSAGE,
    TYPE_PREKEY_BUNDLE,
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
                TYPE_PREKEY_BUNDLE,
                TYPE_GROUP_MESSAGE,
            }
        )
    )


@dataclass(frozen=True, slots=True)
class RelayConfig:
    adapter: str = "hci0"
    local_name: str = "Bitle Relay"
    central_enabled: bool = True
    scan_interval_seconds: float = 20.0
    max_central_links: int = 2
    max_packet_size: int = 2048
    log_level: str = "INFO"
    store: StoreConfig = field(default_factory=StoreConfig)

    @property
    def adapter_path(self) -> str:
        return f"/org/bluez/{self.adapter}"


_DEFAULT_STORE = StoreConfig()
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
    )
    if "/" in config.adapter or not config.adapter:
        raise ValueError("'adapter' must be a BlueZ adapter name such as hci0")
    if not 1 <= config.max_packet_size <= 65_535:
        raise ValueError("'max_packet_size' must be between 1 and 65535")
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
