from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import StrEnum


class LinkKind(StrEnum):
    BLE = "ble"
    LAN = "lan"
    MQTT = "mqtt"
    MATRIX = "matrix"
    LORA = "lora"
    IN_MEMORY = "in-memory"


class LinkReliability(StrEnum):
    BEST_EFFORT = "best-effort"
    ACKNOWLEDGED = "acknowledged"


@dataclass(frozen=True, slots=True)
class LinkCapabilities:
    id: str
    kind: LinkKind
    mtu: int
    broadcast: bool
    unicast: bool
    reliability: LinkReliability
    background: bool
    max_connections: int
    cost: int

    def __post_init__(self) -> None:
        if not self.id:
            raise ValueError("link id cannot be empty")
        if self.mtu <= 0:
            raise ValueError("link MTU must be positive")
        if not self.broadcast and not self.unicast:
            raise ValueError("a link must support broadcast or unicast")
        if self.max_connections <= 0:
            raise ValueError("max_connections must be positive")
        if self.cost < 0:
            raise ValueError("link cost cannot be negative")


class RelayLink(ABC):
    """Opaque BitChat frame link; transport adapters own physical I/O only."""

    @property
    @abstractmethod
    def capabilities(self) -> LinkCapabilities:
        raise NotImplementedError

    @property
    def id(self) -> str:
        return self.capabilities.id

    @abstractmethod
    async def send(self, frame: bytes) -> None:
        """Send one frame without decoding or mutating it."""
        raise NotImplementedError

    async def send_with_path(
        self,
        frame: bytes,
        gateway_path: tuple[bytes, ...] = (),
    ) -> None:
        """Send a frame with optional out-of-band gateway loop metadata.

        Radio and in-memory adapters intentionally ignore the path. LAN
        adapters override this method and keep it outside the BitChat frame.
        """
        await self.send(frame)


class InMemoryRelayLink(RelayLink):
    def __init__(self, capabilities: LinkCapabilities | None = None) -> None:
        self._capabilities = capabilities or LinkCapabilities(
            id="memory",
            kind=LinkKind.IN_MEMORY,
            mtu=2048,
            broadcast=True,
            unicast=True,
            reliability=LinkReliability.ACKNOWLEDGED,
            background=True,
            max_connections=1,
            cost=0,
        )
        self.sent: list[bytes] = []

    @property
    def capabilities(self) -> LinkCapabilities:
        return self._capabilities

    async def send(self, frame: bytes) -> None:
        if len(frame) > self.capabilities.mtu:
            raise ValueError(
                f"frame exceeds {self.capabilities.id} MTU "
                f"({len(frame)} > {self.capabilities.mtu})"
            )
        self.sent.append(bytes(frame))
