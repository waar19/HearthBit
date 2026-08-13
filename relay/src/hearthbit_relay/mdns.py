from __future__ import annotations

import asyncio
import ipaddress
import logging
import socket
import struct
from dataclasses import dataclass
from typing import Callable

LOGGER = logging.getLogger(__name__)

SERVICE_TYPE = "_hearthbit._tcp.local"
MULTICAST_ADDRESS = "224.0.0.251"
MULTICAST_PORT = 5353
_DNS_HEADER = struct.Struct(">HHHHHH")
_RR_HEADER = struct.Struct(">HHIH")


@dataclass(frozen=True, slots=True)
class DiscoveredGateway:
    host: str
    port: int
    gateway_id: bytes | None


def build_query() -> bytes:
    return _DNS_HEADER.pack(0, 0, 1, 0, 0, 0) + _encode_name(
        SERVICE_TYPE
    ) + struct.pack(">HH", 12, 1)


def build_announcement(
    *,
    instance: str,
    hostname: str,
    address: str,
    port: int,
    gateway_id: bytes,
    ttl: int = 120,
) -> bytes:
    service = _encode_name(SERVICE_TYPE)
    instance_name = _encode_name(f"{instance}.{SERVICE_TYPE}")
    host_name = _encode_name(hostname)
    txt = (
        bytes([4 + len(gateway_id.hex())])
        + b"gid="
        + gateway_id.hex().encode("ascii")
    )
    records = [
        service + _RR_HEADER.pack(12, 1, ttl, len(instance_name)) + instance_name,
        instance_name
        + _RR_HEADER.pack(33, 0x8001, ttl, 6 + len(host_name))
        + struct.pack(">HHH", 0, 0, port)
        + host_name,
        instance_name + _RR_HEADER.pack(16, 0x8001, ttl, len(txt)) + txt,
        host_name
        + _RR_HEADER.pack(1, 0x8001, ttl, 4)
        + ipaddress.IPv4Address(address).packed,
    ]
    return _DNS_HEADER.pack(0, 0x8400, 0, len(records), 0, 0) + b"".join(records)


def parse_announcement(data: bytes, source_host: str) -> list[DiscoveredGateway]:
    if len(data) < _DNS_HEADER.size:
        return []
    try:
        _, flags, question_count, answer_count, authority_count, extra_count = (
            _DNS_HEADER.unpack_from(data)
        )
        if not flags & 0x8000:
            return []
        offset = _DNS_HEADER.size
        for _ in range(question_count):
            _, offset = _decode_name(data, offset)
            offset += 4
        srv: list[tuple[str, int, str]] = []
        gateway_ids: dict[str, bytes] = {}
        addresses: dict[str, str] = {}
        for _ in range(answer_count + authority_count + extra_count):
            name, offset = _decode_name(data, offset)
            if offset + _RR_HEADER.size > len(data):
                return []
            record_type, _, _, length = _RR_HEADER.unpack_from(data, offset)
            offset += _RR_HEADER.size
            end = offset + length
            if end > len(data):
                return []
            if record_type == 33 and length >= 7:
                _, _, port = struct.unpack_from(">HHH", data, offset)
                target, _ = _decode_name(data, offset + 6)
                srv.append((name.lower(), port, target.lower()))
            elif record_type == 16:
                for value in _decode_txt(data[offset:end]):
                    if value.startswith("gid="):
                        try:
                            gateway_id = bytes.fromhex(value[4:])
                        except ValueError:
                            continue
                        if len(gateway_id) == 16:
                            gateway_ids[name.lower()] = gateway_id
            elif record_type == 1 and length == 4:
                addresses[name.lower()] = socket.inet_ntoa(data[offset:end])
            offset = end
    except (IndexError, UnicodeDecodeError, struct.error, ValueError):
        return []

    result = []
    suffix = "." + SERVICE_TYPE
    for instance_name, port, target in srv:
        if not instance_name.endswith(suffix) or not 1 <= port <= 65_535:
            continue
        result.append(
            DiscoveredGateway(
                host=addresses.get(target, source_host),
                port=port,
                gateway_id=gateway_ids.get(instance_name),
            )
        )
    return result


class MdnsService(asyncio.DatagramProtocol):
    def __init__(
        self,
        *,
        instance: str,
        hostname: str,
        address: str,
        port: int,
        gateway_id: bytes,
        on_gateway: Callable[[DiscoveredGateway], None],
    ) -> None:
        self._instance = _sanitize_label(instance)
        self._hostname = _sanitize_label(hostname) + ".local"
        self._address = address
        self._port = port
        self._gateway_id = gateway_id
        self._on_gateway = on_gateway
        self._transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self._transport = transport  # type: ignore[assignment]
        self.announce()

    def datagram_received(self, data: bytes, addr: tuple[str, int]) -> None:
        if len(data) >= 4 and not int.from_bytes(data[2:4], "big") & 0x8000:
            if _encode_name(SERVICE_TYPE).lower() in data.lower():
                self.announce(destination=addr)
            return
        for gateway in parse_announcement(data, addr[0]):
            self._on_gateway(gateway)

    def error_received(self, exc: Exception) -> None:
        LOGGER.debug("mDNS datagram error: %s", exc)

    def query(self) -> None:
        self._send(build_query(), (MULTICAST_ADDRESS, MULTICAST_PORT))

    def announce(self, destination: tuple[str, int] | None = None) -> None:
        packet = build_announcement(
            instance=self._instance,
            hostname=self._hostname,
            address=self._address,
            port=self._port,
            gateway_id=self._gateway_id,
        )
        self._send(packet, destination or (MULTICAST_ADDRESS, MULTICAST_PORT))

    def close(self) -> None:
        if self._transport is not None:
            self._transport.close()
            self._transport = None

    def _send(self, data: bytes, destination: tuple[str, int]) -> None:
        if self._transport is not None:
            self._transport.sendto(data, destination)


async def start_mdns(service: MdnsService) -> asyncio.DatagramTransport:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("", MULTICAST_PORT))
        membership = socket.inet_aton(MULTICAST_ADDRESS) + socket.inet_aton("0.0.0.0")
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
        sock.setblocking(False)
        loop = asyncio.get_running_loop()
        transport, _ = await loop.create_datagram_endpoint(lambda: service, sock=sock)
        return transport
    except Exception:
        sock.close()
        raise


def local_ipv4() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 9))
        address = sock.getsockname()[0]
    except OSError:
        address = "127.0.0.1"
    finally:
        sock.close()
    return address


def _encode_name(name: str) -> bytes:
    output = bytearray()
    for label in name.rstrip(".").split("."):
        encoded = label.encode("utf-8")
        if not encoded or len(encoded) > 63:
            raise ValueError("invalid DNS label")
        output.append(len(encoded))
        output.extend(encoded)
    output.append(0)
    return bytes(output)


def _decode_name(
    data: bytes,
    offset: int,
    *,
    depth: int = 0,
) -> tuple[str, int]:
    if depth > 16:
        raise ValueError("DNS compression loop")
    labels: list[str] = []
    next_offset = offset
    jumped = False
    while True:
        if offset >= len(data):
            raise ValueError("truncated DNS name")
        length = data[offset]
        if length & 0xC0 == 0xC0:
            if offset + 1 >= len(data):
                raise ValueError("truncated DNS pointer")
            pointer = ((length & 0x3F) << 8) | data[offset + 1]
            suffix, _ = _decode_name(data, pointer, depth=depth + 1)
            labels.append(suffix)
            if not jumped:
                next_offset = offset + 2
            break
        if length == 0:
            if not jumped:
                next_offset = offset + 1
            break
        if length & 0xC0:
            raise ValueError("invalid DNS label")
        offset += 1
        end = offset + length
        if end > len(data):
            raise ValueError("truncated DNS label")
        labels.append(data[offset:end].decode("utf-8"))
        offset = end
    return ".".join(labels), next_offset


def _decode_txt(data: bytes) -> list[str]:
    values: list[str] = []
    offset = 0
    while offset < len(data):
        length = data[offset]
        offset += 1
        end = offset + length
        if end > len(data):
            raise ValueError("truncated TXT record")
        values.append(data[offset:end].decode("utf-8"))
        offset = end
    return values


def _sanitize_label(value: str) -> str:
    cleaned = "".join(
        character if character.isalnum() or character in "-_" else "-"
        for character in value.strip()
    ).strip("-")
    return (cleaned or "HearthBit")[:63]
