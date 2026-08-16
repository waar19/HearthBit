from __future__ import annotations

import base64
import hashlib
import json
import os
import time
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

from .protocol import (
    TYPE_ANNOUNCE,
    TYPE_NODE_CAPABILITY,
    Packet,
    PacketError,
    canonical_packet_bytes,
    decode_packet,
    encode_packet,
)

DEFAULT_TTL = 7
IDENTITY_VERSION = 1
NODE_CAPABILITY_VERSION = 1
ANNOUNCEMENT_CLOCK_WINDOW_MS = 10 * 60 * 1_000


class IdentityError(ValueError):
    """Raised when persistent relay identity data is missing or malformed."""


class NodeRole(str, Enum):
    INFRA_RELAY = "INFRA_RELAY"
    INFRA_DATA_ANCHOR = "INFRA_DATA_ANCHOR"

    @property
    def code(self) -> int:
        return 0x03 if self is NodeRole.INFRA_RELAY else 0x04

    @property
    def capability_flags(self) -> int:
        relay = 0x01
        store = 0x04 if self is NodeRole.INFRA_DATA_ANCHOR else 0
        return relay | store

    @property
    def payload(self) -> bytes:
        return bytes(
            (NODE_CAPABILITY_VERSION, self.code, self.capability_flags)
        )

    @classmethod
    def parse(cls, value: str) -> NodeRole:
        try:
            return cls(value)
        except ValueError as error:
            allowed = ", ".join(role.value for role in cls)
            raise ValueError(f"node_role must be one of: {allowed}") from error


@dataclass(frozen=True, slots=True)
class Announcement:
    nickname: str
    noise_public_key: bytes
    signing_public_key: bytes
    is_infrastructure: bool


class RelayIdentity:
    def __init__(
        self,
        noise_private_key: X25519PrivateKey,
        signing_private_key: Ed25519PrivateKey,
    ) -> None:
        self._noise_private_key = noise_private_key
        self._signing_private_key = signing_private_key
        self.noise_public_key = noise_private_key.public_key().public_bytes(
            serialization.Encoding.Raw,
            serialization.PublicFormat.Raw,
        )
        self.signing_public_key = signing_private_key.public_key().public_bytes(
            serialization.Encoding.Raw,
            serialization.PublicFormat.Raw,
        )
        self.peer_id = peer_id_from_noise_key(self.noise_public_key)

    @classmethod
    def load_or_create(cls, path: str | Path) -> RelayIdentity:
        identity_path = Path(path)
        if identity_path.exists() or identity_path.is_symlink():
            return cls._load(identity_path)

        identity_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        _restrict_permissions(identity_path.parent, 0o700)
        generated = cls(
            X25519PrivateKey.generate(),
            Ed25519PrivateKey.generate(),
        )
        try:
            generated._create_file(identity_path)
        except FileExistsError:
            return cls._load(identity_path)
        return generated

    @classmethod
    def _load(cls, path: Path) -> RelayIdentity:
        if path.is_symlink():
            raise IdentityError("identity file cannot be a symbolic link")
        try:
            raw = _read_private_file(path)
            document = json.loads(raw)
            if document.get("version") != IDENTITY_VERSION:
                raise IdentityError("unsupported identity file version")
            noise_private = _decode_key(document, "noise_private")
            signing_private = _decode_key(document, "signing_private")
            identity = cls(
                X25519PrivateKey.from_private_bytes(noise_private),
                Ed25519PrivateKey.from_private_bytes(signing_private),
            )
        except IdentityError:
            raise
        except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as error:
            raise IdentityError(f"invalid identity file: {path}") from error
        _restrict_permissions(path, 0o600)
        return identity

    def _create_file(self, path: Path) -> None:
        document = {
            "version": IDENTITY_VERSION,
            "noise_private": _encode_key(
                self._noise_private_key.private_bytes(
                    serialization.Encoding.Raw,
                    serialization.PrivateFormat.Raw,
                    serialization.NoEncryption(),
                )
            ),
            "signing_private": _encode_key(
                self._signing_private_key.private_bytes(
                    serialization.Encoding.Raw,
                    serialization.PrivateFormat.Raw,
                    serialization.NoEncryption(),
                )
            ),
        }
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(path, flags, 0o600)
        try:
            stream = os.fdopen(descriptor, "w", encoding="utf-8")
            descriptor = -1
            with stream:
                json.dump(document, stream, separators=(",", ":"))
                stream.write("\n")
        finally:
            if descriptor >= 0:
                os.close(descriptor)
        _restrict_permissions(path, 0o600)

    def sign(self, data: bytes) -> bytes:
        return self._signing_private_key.sign(data)

    def build_announcement(
        self,
        *,
        nickname: str,
        timestamp_ms: int,
        ttl: int = DEFAULT_TTL,
    ) -> bytes:
        payload = encode_announcement(
            nickname=nickname,
            noise_public_key=self.noise_public_key,
            signing_public_key=self.signing_public_key,
            is_infrastructure=True,
        )
        return self._build_signed_packet(
            message_type=TYPE_ANNOUNCE,
            timestamp_ms=timestamp_ms,
            ttl=ttl,
            payload=payload,
        )

    def build_node_capability(
        self,
        *,
        role: NodeRole,
        timestamp_ms: int,
        ttl: int = DEFAULT_TTL,
    ) -> bytes:
        return self._build_signed_packet(
            message_type=TYPE_NODE_CAPABILITY,
            timestamp_ms=timestamp_ms,
            ttl=ttl,
            payload=role.payload,
        )

    def _build_signed_packet(
        self,
        *,
        message_type: int,
        timestamp_ms: int,
        ttl: int,
        payload: bytes,
    ) -> bytes:
        canonical = encode_packet(
            message_type=message_type,
            ttl=0,
            timestamp_ms=timestamp_ms,
            sender_id=self.peer_id,
            payload=payload,
            pad=True,
        )
        return encode_packet(
            message_type=message_type,
            ttl=ttl,
            timestamp_ms=timestamp_ms,
            sender_id=self.peer_id,
            payload=payload,
            signature=self.sign(canonical),
        )


def peer_id_from_noise_key(public_key: bytes) -> bytes:
    if len(public_key) != 32:
        raise IdentityError("Noise X25519 public key must contain 32 bytes")
    return hashlib.sha256(public_key).digest()[:8]


def encode_announcement(
    *,
    nickname: str,
    noise_public_key: bytes,
    signing_public_key: bytes,
    is_infrastructure: bool,
) -> bytes:
    if len(noise_public_key) != 32 or len(signing_public_key) != 32:
        raise IdentityError("announcement public keys must contain 32 bytes")
    nickname_bytes = nickname.encode("utf-8")[:31]
    fields = [
        (0x01, nickname_bytes),
        (0x02, noise_public_key),
        (0x03, signing_public_key),
        (0x05, b"\x00"),
    ]
    if is_infrastructure:
        fields.append((0xB1, b"\x01"))
    return b"".join(bytes((field_type, len(value))) + value for field_type, value in fields)


def decode_announcement(payload: bytes) -> Announcement | None:
    offset = 0
    nickname: str | None = None
    noise_public_key: bytes | None = None
    signing_public_key: bytes | None = None
    is_infrastructure = False
    try:
        while offset < len(payload):
            if offset + 2 > len(payload):
                return None
            field_type = payload[offset]
            field_length = payload[offset + 1]
            offset += 2
            end = offset + field_length
            if end > len(payload):
                return None
            value = payload[offset:end]
            offset = end
            if field_type == 0x01:
                nickname = value.decode("utf-8")
            elif field_type == 0x02:
                noise_public_key = value
            elif field_type == 0x03:
                signing_public_key = value
            elif field_type == 0xB1:
                is_infrastructure = bool(value and value[0] & 0x01)
    except UnicodeDecodeError:
        return None

    if (
        nickname is None
        or noise_public_key is None
        or len(noise_public_key) != 32
        or signing_public_key is None
        or len(signing_public_key) != 32
    ):
        return None
    return Announcement(
        nickname,
        noise_public_key,
        signing_public_key,
        is_infrastructure,
    )


def verify_packet_signature(packet: Packet, public_key: bytes) -> bool:
    if packet.signature is None or len(public_key) != 32:
        return False
    try:
        Ed25519PublicKey.from_public_bytes(public_key).verify(
            packet.signature,
            canonical_packet_bytes(packet),
        )
    except (InvalidSignature, ValueError):
        return False
    return True


def validate_announcement(
    packet: Packet | bytes,
    now_ms: int | None = None,
) -> Announcement | None:
    try:
        decoded = decode_packet(packet) if isinstance(packet, bytes) else packet
    except PacketError:
        return None
    if decoded.message_type != TYPE_ANNOUNCE:
        return None
    current_ms = time.time_ns() // 1_000_000 if now_ms is None else now_ms
    if not (
        current_ms - ANNOUNCEMENT_CLOCK_WINDOW_MS
        <= decoded.timestamp_ms
        <= current_ms + ANNOUNCEMENT_CLOCK_WINDOW_MS
    ):
        return None
    announcement = decode_announcement(decoded.payload)
    if announcement is None:
        return None
    if peer_id_from_noise_key(announcement.noise_public_key) != decoded.sender_id:
        return None
    if not verify_packet_signature(decoded, announcement.signing_public_key):
        return None
    return announcement


def _encode_key(value: bytes) -> str:
    return base64.b64encode(value).decode("ascii")


def _decode_key(document: dict[str, object], name: str) -> bytes:
    value = document[name]
    if not isinstance(value, str):
        raise IdentityError(f"{name} must be base64 text")
    try:
        decoded = base64.b64decode(value, validate=True)
    except ValueError as error:
        raise IdentityError(f"{name} is not valid base64") from error
    if len(decoded) != 32:
        raise IdentityError(f"{name} must contain 32 bytes")
    return decoded


def _read_private_file(path: Path) -> str:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        with os.fdopen(descriptor, "r", encoding="utf-8") as stream:
            value = stream.read()
        descriptor = -1
        return value
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def _restrict_permissions(path: Path, mode: int) -> None:
    try:
        os.chmod(path, mode, follow_symlinks=False)
    except (NotImplementedError, OSError):
        if os.name != "nt":
            raise
