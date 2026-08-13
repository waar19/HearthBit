from __future__ import annotations

import asyncio
import hashlib
import hmac
import os
import struct
from collections import OrderedDict
from dataclasses import dataclass

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

MAGIC = b"HBLN"
VERSION = 1
ROLE_SERVER = 1
ROLE_CLIENT = 2
RECORD_FRAME = 1
RECORD_PING = 2
GATEWAY_ID_SIZE = 16
MAX_GATEWAY_HOPS = 32

_HELLO_UNSIGNED = struct.Struct(">4sBB16s32sI")
HELLO_SIZE = _HELLO_UNSIGNED.size + 32
_RECORD_PREFIX = struct.Struct(">BQ")
_FRAME_PREFIX = struct.Struct(">B16sB")


class LanProtocolError(ValueError):
    """The authenticated LAN stream violated its framing contract."""


@dataclass(frozen=True, slots=True)
class LanPeer:
    gateway_id: bytes
    max_frame_size: int


def build_hello(
    *,
    role: int,
    gateway_id: bytes,
    nonce: bytes,
    max_frame_size: int,
    psk: bytes,
) -> bytes:
    if role not in (ROLE_SERVER, ROLE_CLIENT):
        raise LanProtocolError("invalid LAN role")
    if len(gateway_id) != GATEWAY_ID_SIZE:
        raise LanProtocolError("gateway ID must contain 16 bytes")
    if len(nonce) != 32:
        raise LanProtocolError("LAN nonce must contain 32 bytes")
    if not 1 <= max_frame_size <= 65_535:
        raise LanProtocolError("invalid LAN maximum frame size")
    unsigned = _HELLO_UNSIGNED.pack(
        MAGIC,
        VERSION,
        role,
        gateway_id,
        nonce,
        max_frame_size,
    )
    return unsigned + hmac.digest(psk, b"hello:" + unsigned, "sha256")


def parse_hello(data: bytes, *, expected_role: int, psk: bytes) -> LanPeer:
    if len(data) != HELLO_SIZE:
        raise LanProtocolError("invalid LAN hello size")
    unsigned, received_tag = data[:-32], data[-32:]
    expected_tag = hmac.digest(psk, b"hello:" + unsigned, "sha256")
    if not hmac.compare_digest(received_tag, expected_tag):
        raise LanProtocolError("LAN authentication failed")
    magic, version, role, gateway_id, _, max_frame_size = _HELLO_UNSIGNED.unpack(
        unsigned
    )
    if magic != MAGIC or version != VERSION:
        raise LanProtocolError("unsupported LAN protocol")
    if role != expected_role:
        raise LanProtocolError("unexpected LAN peer role")
    if not 1 <= max_frame_size <= 65_535:
        raise LanProtocolError("invalid peer maximum frame size")
    return LanPeer(gateway_id, max_frame_size)


async def authenticate_stream(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    *,
    server: bool,
    gateway_id: bytes,
    psk: bytes,
    max_frame_size: int,
    timeout: float,
) -> tuple[LanPeer, LanRecordStream]:
    """Mutually authenticate and derive directional AES-256-GCM keys."""

    local_role = ROLE_SERVER if server else ROLE_CLIENT
    peer_role = ROLE_CLIENT if server else ROLE_SERVER
    local_nonce = os.urandom(32)
    local_hello = build_hello(
        role=local_role,
        gateway_id=gateway_id,
        nonce=local_nonce,
        max_frame_size=max_frame_size,
        psk=psk,
    )

    if server:
        writer.write(local_hello)
        await writer.drain()
        peer_hello = await _read_exactly(reader, HELLO_SIZE, timeout)
        server_hello, client_hello = local_hello, peer_hello
    else:
        peer_hello = await _read_exactly(reader, HELLO_SIZE, timeout)
        writer.write(local_hello)
        await writer.drain()
        server_hello, client_hello = peer_hello, local_hello

    peer = parse_hello(peer_hello, expected_role=peer_role, psk=psk)
    if peer.gateway_id == gateway_id:
        raise LanProtocolError("refusing a LAN connection to this gateway")

    transcript = server_hello + client_hello
    server_nonce = server_hello[22:54]
    client_nonce = client_hello[22:54]
    material = HKDF(
        algorithm=SHA256(),
        length=64,
        salt=server_nonce + client_nonce,
        info=b"hearthbit-lan-v1:" + transcript,
    ).derive(psk)
    server_key, client_key = material[:32], material[32:]

    local_finish = hmac.digest(
        psk,
        b"finish:" + transcript + bytes([local_role]),
        "sha256",
    )
    if server:
        writer.write(local_finish)
        await writer.drain()
        peer_finish = await _read_exactly(reader, 32, timeout)
    else:
        peer_finish = await _read_exactly(reader, 32, timeout)
        writer.write(local_finish)
        await writer.drain()
    expected_finish = hmac.digest(
        psk,
        b"finish:" + transcript + bytes([peer_role]),
        "sha256",
    )
    if not hmac.compare_digest(peer_finish, expected_finish):
        raise LanProtocolError("LAN transcript authentication failed")

    send_key = server_key if server else client_key
    receive_key = client_key if server else server_key
    return peer, LanRecordStream(
        reader,
        writer,
        send_key=send_key,
        receive_key=receive_key,
        max_frame_size=min(max_frame_size, peer.max_frame_size),
    )


class LanRecordStream:
    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        *,
        send_key: bytes,
        receive_key: bytes,
        max_frame_size: int,
    ) -> None:
        self._reader = reader
        self._writer = writer
        self._send_aead = AESGCM(send_key)
        self._receive_aead = AESGCM(receive_key)
        self._send_sequence = 0
        self._receive_sequence = 0
        self.max_frame_size = max_frame_size

    async def send_frame(
        self,
        frame: bytes,
        *,
        message_id: bytes,
        gateway_path: tuple[bytes, ...],
    ) -> None:
        if not 1 <= len(frame) <= self.max_frame_size:
            raise LanProtocolError("LAN frame exceeds negotiated limit")
        if len(message_id) != 16:
            raise LanProtocolError("LAN message ID must contain 16 bytes")
        if not gateway_path or len(gateway_path) > MAX_GATEWAY_HOPS:
            raise LanProtocolError("invalid LAN gateway path")
        if any(len(gateway) != GATEWAY_ID_SIZE for gateway in gateway_path):
            raise LanProtocolError("invalid gateway ID in path")
        plaintext = bytearray(
            _FRAME_PREFIX.pack(RECORD_FRAME, message_id, len(gateway_path))
        )
        plaintext.extend(b"".join(gateway_path))
        plaintext.extend(struct.pack(">I", len(frame)))
        plaintext.extend(frame)
        await self._send_record(bytes(plaintext))

    async def send_ping(self) -> None:
        await self._send_record(bytes([RECORD_PING]))

    async def read(
        self,
        *,
        timeout: float,
        max_gateway_hops: int,
    ) -> tuple[int, bytes, tuple[bytes, ...], bytes]:
        length_bytes = await _read_exactly(self._reader, 4, timeout)
        length = int.from_bytes(length_bytes, "big")
        maximum = (
            _RECORD_PREFIX.size
            + 16
            + _FRAME_PREFIX.size
            + MAX_GATEWAY_HOPS * GATEWAY_ID_SIZE
            + 4
            + self.max_frame_size
        )
        if length < _RECORD_PREFIX.size + 17 or length > maximum:
            raise LanProtocolError("invalid encrypted LAN record length")
        body = await _read_exactly(self._reader, length, timeout)
        version, sequence = _RECORD_PREFIX.unpack_from(body)
        if version != VERSION or sequence != self._receive_sequence:
            raise LanProtocolError("invalid LAN record sequence")
        aad = body[: _RECORD_PREFIX.size]
        try:
            plaintext = self._receive_aead.decrypt(
                _nonce(sequence),
                body[_RECORD_PREFIX.size :],
                aad,
            )
        except Exception as error:
            raise LanProtocolError("LAN record authentication failed") from error
        self._receive_sequence += 1
        if not plaintext:
            raise LanProtocolError("empty LAN record")
        if plaintext[0] == RECORD_PING:
            if len(plaintext) != 1:
                raise LanProtocolError("invalid LAN ping")
            return RECORD_PING, b"", (), b""
        if len(plaintext) < _FRAME_PREFIX.size + 4:
            raise LanProtocolError("truncated LAN frame envelope")
        record_type, message_id, path_count = _FRAME_PREFIX.unpack_from(plaintext)
        if record_type != RECORD_FRAME:
            raise LanProtocolError("unknown LAN record type")
        if not 1 <= path_count <= min(max_gateway_hops, MAX_GATEWAY_HOPS):
            raise LanProtocolError("invalid LAN gateway path length")
        offset = _FRAME_PREFIX.size
        path_end = offset + path_count * GATEWAY_ID_SIZE
        if path_end + 4 > len(plaintext):
            raise LanProtocolError("truncated LAN gateway path")
        gateway_path = tuple(
            plaintext[index : index + GATEWAY_ID_SIZE]
            for index in range(offset, path_end, GATEWAY_ID_SIZE)
        )
        frame_size = int.from_bytes(plaintext[path_end : path_end + 4], "big")
        frame = plaintext[path_end + 4 :]
        if frame_size != len(frame) or not 1 <= frame_size <= self.max_frame_size:
            raise LanProtocolError("invalid LAN frame size")
        return RECORD_FRAME, message_id, gateway_path, frame

    async def _send_record(self, plaintext: bytes) -> None:
        sequence = self._send_sequence
        if sequence >= (1 << 64):
            raise LanProtocolError("LAN record sequence exhausted")
        prefix = _RECORD_PREFIX.pack(VERSION, sequence)
        encrypted = self._send_aead.encrypt(_nonce(sequence), plaintext, prefix)
        body = prefix + encrypted
        self._writer.write(struct.pack(">I", len(body)) + body)
        await self._writer.drain()
        self._send_sequence += 1


class MessageDeduplicator:
    def __init__(self, capacity: int = 4096) -> None:
        self._capacity = capacity
        self._items: OrderedDict[bytes, None] = OrderedDict()

    def seen_or_add(self, message_id: bytes) -> bool:
        if message_id in self._items:
            self._items.move_to_end(message_id)
            return True
        self._items[message_id] = None
        while len(self._items) > self._capacity:
            self._items.popitem(last=False)
        return False


def opaque_message_id(frame: bytes) -> bytes:
    """Stable ID across BitChat TTL/RSR changes without mutating the frame."""

    canonical = bytearray(frame)
    if len(canonical) >= 12:
        canonical[2] = 0
        canonical[11] &= ~0x10
    return hashlib.sha256(canonical).digest()[:16]


async def _read_exactly(
    reader: asyncio.StreamReader,
    size: int,
    timeout: float,
) -> bytes:
    try:
        return await asyncio.wait_for(reader.readexactly(size), timeout)
    except asyncio.TimeoutError as error:
        raise LanProtocolError("LAN I/O timeout") from error
    except asyncio.IncompleteReadError as error:
        raise LanProtocolError("LAN connection closed") from error


def _nonce(sequence: int) -> bytes:
    return b"\x00\x00\x00\x00" + sequence.to_bytes(8, "big")
