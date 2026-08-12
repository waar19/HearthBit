from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass

VERSION = 1
FLAG_RECIPIENT = 0x01
FLAG_SIGNATURE = 0x02
FLAG_COMPRESSED = 0x04
FLAG_RSR = 0x10

TYPE_ANNOUNCE = 0x01
TYPE_MESSAGE = 0x02
TYPE_COURIER_ENVELOPE = 0x04
TYPE_NOISE_HANDSHAKE = 0x10
TYPE_NOISE_ENCRYPTED = 0x11
TYPE_FRAGMENT = 0x20
TYPE_REQUEST_SYNC = 0x21
TYPE_PREKEY_BUNDLE = 0x24
TYPE_GROUP_MESSAGE = 0x25

HEADER = struct.Struct(">BBBQB H 8s")
NORMALIZED_SIZES = (256, 512, 1024, 2048)
MAX_PACKET_SIZE = NORMALIZED_SIZES[-1]


class PacketError(ValueError):
    """Raised when a frame is not a valid HearthBit/BitChat packet."""


@dataclass(frozen=True, slots=True)
class Packet:
    version: int
    message_type: int
    ttl: int
    timestamp_ms: int
    flags: int
    sender_id: bytes
    recipient_id: bytes | None
    payload: bytes
    signature: bytes | None
    raw: bytes
    wire_length: int

    @property
    def has_signature(self) -> bool:
        return self.signature is not None

    @property
    def is_directed(self) -> bool:
        return self.recipient_id is not None

    def forwarded_bytes(self) -> bytes:
        if self.ttl <= 1:
            raise PacketError("a packet with TTL <= 1 cannot be forwarded")
        data = bytearray(self.raw)
        data[2] = self.ttl - 1
        return bytes(data)


def decode_packet(data: bytes, *, max_size: int = MAX_PACKET_SIZE) -> Packet:
    if not data or len(data) > max_size:
        raise PacketError(f"packet size must be between 1 and {max_size} bytes")
    if len(data) < HEADER.size:
        raise PacketError("truncated packet header")

    version, message_type, ttl, timestamp_ms, flags, payload_len, sender_id = (
        HEADER.unpack_from(data)
    )
    if version != VERSION:
        raise PacketError(f"unsupported packet version {version}")

    offset = HEADER.size
    recipient_id = None
    if flags & FLAG_RECIPIENT:
        if offset + 8 > len(data):
            raise PacketError("truncated recipient ID")
        recipient_id = data[offset : offset + 8]
        offset += 8

    payload_end = offset + payload_len
    signature_len = 64 if flags & FLAG_SIGNATURE else 0
    wire_length = payload_end + signature_len
    if wire_length > len(data):
        raise PacketError("declared payload or signature exceeds packet size")

    payload = data[offset:payload_end]
    signature = data[payload_end:wire_length] if signature_len else None
    _validate_padding(data[wire_length:])

    return Packet(
        version=version,
        message_type=message_type,
        ttl=ttl,
        timestamp_ms=timestamp_ms,
        flags=flags,
        sender_id=sender_id,
        recipient_id=recipient_id,
        payload=payload,
        signature=signature,
        raw=data,
        wire_length=wire_length,
    )


def encode_packet(
    *,
    message_type: int,
    ttl: int,
    timestamp_ms: int,
    sender_id: bytes,
    payload: bytes,
    recipient_id: bytes | None = None,
    signature: bytes | None = None,
    extra_flags: int = 0,
    pad: bool = False,
) -> bytes:
    if len(sender_id) != 8:
        raise PacketError("sender ID must contain 8 bytes")
    if recipient_id is not None and len(recipient_id) != 8:
        raise PacketError("recipient ID must contain 8 bytes")
    if signature is not None and len(signature) != 64:
        raise PacketError("signature must contain 64 bytes")
    if len(payload) > 0xFFFF:
        raise PacketError("payload exceeds the v1 uint16 length")
    if not 0 <= ttl <= 0xFF:
        raise PacketError("TTL must fit in one byte")

    flags = extra_flags & ~(FLAG_RECIPIENT | FLAG_SIGNATURE)
    flags |= FLAG_RECIPIENT if recipient_id is not None else 0
    flags |= FLAG_SIGNATURE if signature is not None else 0
    frame = bytearray(
        HEADER.pack(
            VERSION,
            message_type,
            ttl,
            timestamp_ms,
            flags,
            len(payload),
            sender_id,
        )
    )
    if recipient_id is not None:
        frame.extend(recipient_id)
    frame.extend(payload)
    if signature is not None:
        frame.extend(signature)
    if pad:
        _apply_padding(frame)
    return bytes(frame)


def relay_fingerprint(packet: Packet) -> bytes:
    canonical = packet.raw[: packet.wire_length]
    digest = hashlib.blake2s(digest_size=16, person=b"HBitRly")
    digest.update(canonical[:2])
    digest.update(canonical[3:])
    return digest.digest()


def courier_expiry_ms(packet: Packet) -> int | None:
    if packet.message_type != TYPE_COURIER_ENVELOPE:
        return None
    offset = 0
    while offset + 3 <= len(packet.payload):
        field_type = packet.payload[offset]
        field_len = int.from_bytes(packet.payload[offset + 1 : offset + 3], "big")
        offset += 3
        end = offset + field_len
        if end > len(packet.payload):
            return None
        if field_type == 0x02 and field_len == 8:
            return int.from_bytes(packet.payload[offset:end], "big")
        offset = end
    return None


def _validate_padding(padding: bytes) -> None:
    if not padding:
        return
    count = padding[-1]
    if count == 0 or count != len(padding) or padding != bytes([count]) * count:
        raise PacketError("invalid PKCS#7 packet padding")


def _apply_padding(frame: bytearray) -> None:
    for target in NORMALIZED_SIZES:
        difference = target - len(frame)
        if 0 < difference <= 0xFF:
            frame.extend(bytes([difference]) * difference)
            return
