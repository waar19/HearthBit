from __future__ import annotations

import hashlib
import struct
import zlib
from dataclasses import dataclass, replace

VERSION = 1
SUPPORTED_VERSIONS = (1, 2)
FLAG_RECIPIENT = 0x01
FLAG_SIGNATURE = 0x02
FLAG_COMPRESSED = 0x04
FLAG_ROUTE = 0x08
FLAG_RSR = 0x10

TYPE_ANNOUNCE = 0x01
TYPE_MESSAGE = 0x02
TYPE_COURIER_ENVELOPE = 0x04
TYPE_NOISE_HANDSHAKE = 0x10
TYPE_NOISE_ENCRYPTED = 0x11
TYPE_FRAGMENT = 0x20
TYPE_REQUEST_SYNC = 0x21
TYPE_HBT_CAPABILITY = 0x24
TYPE_NODE_CAPABILITY = 0x25
TYPE_EMERGENCY_CAPABILITY = 0x28
TYPE_EMERGENCY_ACK = 0x29

# Backward-compatible aliases for callers that imported the old, incorrect
# semantic names. These wire values are ephemeral capability announcements.
TYPE_PREKEY_BUNDLE = TYPE_HBT_CAPABILITY
TYPE_GROUP_MESSAGE = TYPE_NODE_CAPABILITY

EPHEMERAL_MESSAGE_TYPES = frozenset(
    {
        TYPE_ANNOUNCE,
        TYPE_HBT_CAPABILITY,
        TYPE_NODE_CAPABILITY,
        TYPE_EMERGENCY_CAPABILITY,
    }
)

HEADER_V1 = struct.Struct(">BBBQBH8s")
HEADER_V2 = struct.Struct(">BBBQBI8s")
# Preserve the public v1 header name for existing integrations.
HEADER = HEADER_V1
NORMALIZED_SIZES = (256, 512, 1024, 2048)
MAX_PACKET_SIZE = NORMALIZED_SIZES[-1]
MAX_PAYLOAD_LENGTH = 10_485_760
MAX_FRAGMENT_COUNT = 256
MAX_FRAGMENT_SET_BYTES = 1_048_576
MAX_GCS_FILTER_BYTES = 1024


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
    route: tuple[bytes, ...] = ()

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
    if len(data) < HEADER_V1.size:
        raise PacketError("truncated packet header")

    version = data[0]
    if version not in SUPPORTED_VERSIONS:
        raise PacketError(f"unsupported packet version {version}")
    header = HEADER_V1 if version == 1 else HEADER_V2
    if len(data) < header.size:
        raise PacketError("truncated packet header")

    version, message_type, ttl, timestamp_ms, flags, payload_len, sender_id = (
        header.unpack_from(data)
    )

    offset = header.size
    recipient_id = None
    if flags & FLAG_RECIPIENT:
        if offset + 8 > len(data):
            raise PacketError("truncated recipient ID")
        recipient_id = data[offset : offset + 8]
        offset += 8

    route: tuple[bytes, ...] = ()
    if version == 2 and flags & FLAG_ROUTE:
        if offset >= len(data):
            raise PacketError("truncated route header")
        route_count = data[offset]
        offset += 1
        route_end = offset + route_count * 8
        if route_end > len(data):
            raise PacketError("truncated route")
        route = tuple(
            data[hop_offset : hop_offset + 8]
            for hop_offset in range(offset, route_end, 8)
        )
        offset = route_end

    payload_end = offset + payload_len
    signature_len = 64 if flags & FLAG_SIGNATURE else 0
    wire_length = payload_end + signature_len
    if wire_length > len(data):
        raise PacketError("declared payload or signature exceeds packet size")

    payload = data[offset:payload_end]
    if flags & FLAG_COMPRESSED:
        size_bytes = 4 if version == 2 else 2
        if len(payload) <= size_bytes:
            raise PacketError("compressed payload is missing its size or stream")
        original_size = int.from_bytes(payload[:size_bytes], "big")
        if not 0 < original_size <= MAX_PAYLOAD_LENGTH:
            raise PacketError("invalid expanded payload size")
        payload = _decompress_exact(payload[size_bytes:], original_size)
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
        route=route,
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
    version: int = VERSION,
    recipient_id: bytes | None = None,
    route: tuple[bytes, ...] | list[bytes] = (),
    signature: bytes | None = None,
    extra_flags: int = 0,
    pad: bool = False,
) -> bytes:
    if version not in SUPPORTED_VERSIONS:
        raise PacketError(f"unsupported packet version {version}")
    if len(sender_id) != 8:
        raise PacketError("sender ID must contain 8 bytes")
    if recipient_id is not None and len(recipient_id) != 8:
        raise PacketError("recipient ID must contain 8 bytes")
    if signature is not None and len(signature) != 64:
        raise PacketError("signature must contain 64 bytes")
    if version == 1 and len(payload) > 0xFFFF:
        raise PacketError("payload exceeds the v1 uint16 length")
    if len(payload) > 0xFFFFFFFF:
        raise PacketError("payload exceeds the v2 uint32 length")
    if not 0 <= ttl <= 0xFF:
        raise PacketError("TTL must fit in one byte")
    if version == 1 and route:
        raise PacketError("source routes require packet version 2")
    if len(route) > 0xFF:
        raise PacketError("route cannot contain more than 255 hops")
    if any(len(hop) != 8 for hop in route):
        raise PacketError("every route hop must contain 8 bytes")

    flags = extra_flags & ~(FLAG_RECIPIENT | FLAG_SIGNATURE | FLAG_ROUTE)
    flags |= FLAG_RECIPIENT if recipient_id is not None else 0
    flags |= FLAG_SIGNATURE if signature is not None else 0
    flags |= FLAG_ROUTE if route else 0
    header = HEADER_V1 if version == 1 else HEADER_V2
    frame = bytearray(
        header.pack(
            version,
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
    if route:
        frame.append(len(route))
        for hop in route:
            frame.extend(hop)
    frame.extend(payload)
    if signature is not None:
        frame.extend(signature)
    if pad:
        _apply_padding(frame)
    return bytes(frame)


def relay_fingerprint(packet: Packet) -> bytes:
    canonical = canonical_relay_bytes(packet)
    digest = hashlib.blake2s(digest_size=16, person=b"HBitRly")
    digest.update(canonical)
    return digest.digest()


def canonical_relay_bytes(packet: Packet) -> bytes:
    """Canonical opaque bytes for hop-independent relay deduplication."""
    canonical = bytearray(packet.raw[: packet.wire_length])
    canonical[2] = 0
    canonical[11] &= ~FLAG_RSR
    return bytes(canonical)


def canonical_packet_bytes(packet: Packet) -> bytes:
    """Return the padded TTL-zero bytes covered by an Ed25519 signature."""
    return encode_packet(
        version=packet.version,
        message_type=packet.message_type,
        ttl=0,
        timestamp_ms=packet.timestamp_ms,
        sender_id=packet.sender_id,
        recipient_id=packet.recipient_id,
        route=packet.route,
        payload=packet.payload,
        extra_flags=packet.flags & ~(FLAG_SIGNATURE | FLAG_RSR | FLAG_COMPRESSED),
        pad=True,
    )


@dataclass(frozen=True, slots=True)
class FragmentPayload:
    fragment_id: bytes
    index: int
    total: int
    original_type: int
    data: bytes


def decode_fragment_payload(payload: bytes) -> FragmentPayload:
    if len(payload) < 13:
        raise PacketError("truncated fragment header")
    index = int.from_bytes(payload[8:10], "big")
    total = int.from_bytes(payload[10:12], "big")
    if total == 0 or index >= total:
        raise PacketError("invalid fragment index or total")
    return FragmentPayload(payload[:8], index, total, payload[12], payload[13:])


class FragmentReassembler:
    """Bounded relay-side reassembly using the production packet decoder."""

    def __init__(self) -> None:
        self._sets: dict[tuple[bytes, bytes], dict[str, object]] = {}
        self._bytes = 0

    def accept(self, packet: Packet) -> Packet | None:
        if packet.message_type != TYPE_FRAGMENT:
            return None
        fragment = decode_fragment_payload(packet.payload)
        if (
            fragment.total > MAX_FRAGMENT_COUNT
            or fragment.original_type == TYPE_FRAGMENT
            or not fragment.data
        ):
            return None
        key = (packet.sender_id, fragment.fragment_id)
        current = self._sets.get(key)
        metadata = (
            fragment.original_type,
            fragment.total,
            packet.sender_id,
            packet.recipient_id,
        )
        if current is None:
            if len(self._sets) >= 64:
                return None
            current = {"metadata": metadata, "parts": {}, "bytes": 0}
            self._sets[key] = current
        elif current["metadata"] != metadata:
            self._remove(key)
            return None
        parts = current["parts"]
        assert isinstance(parts, dict)
        existing = parts.get(fragment.index)
        if existing is not None:
            if existing != fragment.data:
                self._remove(key)
            return None
        set_bytes = int(current["bytes"])
        if (
            set_bytes + len(fragment.data) > MAX_FRAGMENT_SET_BYTES
            or self._bytes + len(fragment.data) > 4 * MAX_FRAGMENT_SET_BYTES
        ):
            self._remove(key)
            return None
        parts[fragment.index] = fragment.data
        current["bytes"] = set_bytes + len(fragment.data)
        self._bytes += len(fragment.data)
        if len(parts) != fragment.total:
            return None
        encoded = b"".join(parts[index] for index in range(fragment.total))
        self._remove(key)
        try:
            decoded = decode_packet(encoded, max_size=MAX_FRAGMENT_SET_BYTES)
        except PacketError:
            return None
        if (
            decoded.message_type != fragment.original_type
            or decoded.sender_id != packet.sender_id
            or decoded.recipient_id != packet.recipient_id
        ):
            return None
        return replace(decoded, ttl=0)

    def _remove(self, key: tuple[bytes, bytes]) -> None:
        removed = self._sets.pop(key, None)
        if removed is not None:
            self._bytes = max(0, self._bytes - int(removed["bytes"]))


@dataclass(frozen=True, slots=True)
class SyncRequest:
    p: int
    m: int
    filter: bytes


def decode_sync_request(payload: bytes) -> SyncRequest:
    fields = _decode_wide_tlvs(payload)
    p_bytes = fields.get(0x01)
    m_bytes = fields.get(0x02)
    filter_bytes = fields.get(0x03)
    if p_bytes is None or len(p_bytes) != 1 or not 1 <= p_bytes[0] <= 32:
        raise PacketError("invalid GCS P")
    if m_bytes is None or len(m_bytes) != 4:
        raise PacketError("invalid GCS M")
    m = int.from_bytes(m_bytes, "big")
    if m == 0:
        raise PacketError("invalid GCS range")
    if filter_bytes is None or len(filter_bytes) > MAX_GCS_FILTER_BYTES:
        raise PacketError("invalid GCS filter")
    return SyncRequest(p_bytes[0], m, filter_bytes)


def decode_gcs(request: SyncRequest, *, maximum: int = 1024) -> tuple[int, ...]:
    bit = 0
    accumulator = 0
    values: list[int] = []

    def read_bit() -> int | None:
        nonlocal bit
        if bit >= len(request.filter) * 8:
            return None
        value = (request.filter[bit // 8] >> (7 - bit % 8)) & 1
        bit += 1
        return value

    while len(values) < maximum:
        quotient = 0
        current = read_bit()
        if current is None:
            break
        while current == 1:
            quotient += 1
            current = read_bit()
            if current is None:
                return tuple(values)
        remainder = 0
        for _ in range(request.p):
            current = read_bit()
            if current is None:
                return tuple(values)
            remainder = (remainder << 1) | current
        accumulator += (quotient << request.p) + remainder + 1
        if accumulator >= request.m:
            break
        values.append(accumulator)
    return tuple(values)


@dataclass(frozen=True, slots=True)
class CourierEnvelope:
    recipient_tag: bytes
    expiry_ms: int
    ciphertext: bytes
    copies: int = 1
    prekey_id: int | None = None


def decode_courier_envelope(payload: bytes) -> CourierEnvelope:
    fields = _decode_wide_tlvs(payload)
    tag = fields.get(0x01)
    expiry = fields.get(0x02)
    ciphertext = fields.get(0x03)
    copies = fields.get(0x04, b"\x01")
    prekey = fields.get(0x05)
    if tag is None or len(tag) != 16:
        raise PacketError("invalid Courier recipient tag")
    if expiry is None or len(expiry) != 8:
        raise PacketError("invalid Courier expiry")
    if not ciphertext:
        raise PacketError("invalid Courier ciphertext")
    if len(copies) != 1 or not 1 <= copies[0] <= 8:
        raise PacketError("invalid Courier copy count")
    if prekey is not None and len(prekey) != 4:
        raise PacketError("invalid Courier prekey ID")
    return CourierEnvelope(
        tag,
        int.from_bytes(expiry, "big"),
        ciphertext,
        copies[0],
        int.from_bytes(prekey, "big") if prekey is not None else None,
    )


@dataclass(frozen=True, slots=True)
class ExtensionEnvelope:
    namespace: str
    subtype: int
    version: int
    flags: int
    payload: bytes


def decode_extension_envelope(data: bytes) -> ExtensionEnvelope:
    if len(data) < 12:
        raise PacketError("truncated extension envelope")
    namespace_bytes = data[:4]
    if any(byte < 0x20 or byte > 0x7E for byte in namespace_bytes):
        raise PacketError("invalid extension namespace")
    flags = data[7]
    if flags & 0xFC:
        raise PacketError("reserved extension flags are set")
    length = int.from_bytes(data[8:12], "big")
    if length > MAX_PAYLOAD_LENGTH or len(data) != 12 + length:
        raise PacketError("invalid extension payload length")
    return ExtensionEnvelope(
        namespace_bytes.decode("ascii"),
        int.from_bytes(data[4:6], "big"),
        data[6],
        flags,
        data[12:],
    )


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


def _decompress_exact(data: bytes, expected_size: int) -> bytes:
    looks_like_zlib = (
        len(data) >= 2
        and data[0] & 0x0F == 8
        and (data[0] << 8 | data[1]) % 31 == 0
    )
    modes = (zlib.MAX_WBITS, -zlib.MAX_WBITS) if looks_like_zlib else (-zlib.MAX_WBITS,)
    for mode in modes:
        try:
            inflater = zlib.decompressobj(mode)
            output = inflater.decompress(data, expected_size + 1)
            output += inflater.flush()
            if (
                len(output) == expected_size
                and inflater.eof
                and not inflater.unused_data
                and not inflater.unconsumed_tail
            ):
                return output
        except zlib.error:
            pass
    raise PacketError("invalid or non-canonical compressed payload")


def _decode_wide_tlvs(payload: bytes) -> dict[int, bytes]:
    fields: dict[int, bytes] = {}
    offset = 0
    while offset < len(payload):
        if offset + 3 > len(payload):
            raise PacketError("truncated TLV header")
        field_type = payload[offset]
        field_len = int.from_bytes(payload[offset + 1 : offset + 3], "big")
        offset += 3
        end = offset + field_len
        if end > len(payload):
            raise PacketError("truncated TLV value")
        fields[field_type] = payload[offset:end]
        offset = end
    return fields


def _apply_padding(frame: bytearray) -> None:
    for target in NORMALIZED_SIZES:
        difference = target - len(frame)
        if 0 < difference <= 0xFF:
            frame.extend(bytes([difference]) * difference)
            return
