from __future__ import annotations

import asyncio
import base64
import contextlib
import hashlib
import logging
from dataclasses import dataclass

from .config import LanConfig
from .core import RelayCore
from .lan_protocol import (
    RECORD_FRAME,
    LanProtocolError,
    LanRecordStream,
    MessageDeduplicator,
    authenticate_stream,
    opaque_message_id,
)
from .link import LinkCapabilities, LinkKind, LinkReliability, RelayLink
from .mdns import DiscoveredGateway, MdnsService, local_ipv4, start_mdns

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class LanStatus:
    gateway_id: bytes
    port: int
    connections: int


class LanConnection(RelayLink):
    def __init__(
        self,
        owner: LanTransport,
        *,
        peer_gateway_id: bytes,
        stream: LanRecordStream,
        writer: asyncio.StreamWriter,
        outbound: bool,
    ) -> None:
        self.owner = owner
        self.peer_gateway_id = peer_gateway_id
        self.stream = stream
        self.writer = writer
        self.outbound = outbound
        self._send_lock = asyncio.Lock()
        self._closed = False

    @property
    def capabilities(self) -> LinkCapabilities:
        return LinkCapabilities(
            id=f"lan:{self.peer_gateway_id.hex()}",
            kind=LinkKind.LAN,
            mtu=self.stream.max_frame_size,
            broadcast=True,
            unicast=True,
            reliability=LinkReliability.ACKNOWLEDGED,
            background=True,
            max_connections=self.owner.config.max_connections,
            cost=2,
        )

    async def send(self, frame: bytes) -> None:
        await self.send_with_path(frame)

    async def send_with_path(
        self,
        frame: bytes,
        gateway_path: tuple[bytes, ...] = (),
    ) -> None:
        path = gateway_path + (self.owner.gateway_id,)
        if self.owner.gateway_id in gateway_path:
            raise LanProtocolError("local gateway already appears in LAN path")
        if self.peer_gateway_id in path:
            raise LanProtocolError("peer gateway already appears in LAN path")
        if len(path) > self.owner.config.max_gateway_hops:
            raise LanProtocolError("LAN gateway path exceeded configured limit")
        async with self._send_lock:
            await self.stream.send_frame(
                bytes(frame),
                message_id=opaque_message_id(frame),
                gateway_path=path,
            )

    async def run(self) -> None:
        ping = asyncio.create_task(self._ping_loop())
        try:
            while True:
                record_type, message_id, path, frame = await self.stream.read(
                    timeout=self.owner.config.idle_timeout_seconds,
                    max_gateway_hops=self.owner.config.max_gateway_hops,
                )
                if record_type != RECORD_FRAME:
                    continue
                if path[-1] != self.peer_gateway_id:
                    raise LanProtocolError("LAN path does not identify authenticated peer")
                if self.owner.gateway_id in path:
                    LOGGER.debug("dropping LAN loop from %s", self.id)
                    continue
                if message_id != opaque_message_id(frame):
                    raise LanProtocolError("LAN message ID does not match frame")
                if self.owner.deduplicator.seen_or_add(message_id):
                    continue
                await self.owner.core.inbound(
                    self.id,
                    frame,
                    gateway_path=path,
                )
        finally:
            ping.cancel()
            await asyncio.gather(ping, return_exceptions=True)
            await self.close()

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self.writer.close()
        with contextlib.suppress(Exception):
            await self.writer.wait_closed()

    async def _ping_loop(self) -> None:
        interval = max(5.0, self.owner.config.idle_timeout_seconds / 3)
        while True:
            await asyncio.sleep(interval)
            async with self._send_lock:
                await self.stream.send_ping()


class LanTransport:
    """Authenticated TCP LAN gateway and mDNS client/server transport."""

    def __init__(
        self,
        config: LanConfig,
        core: RelayCore,
        *,
        identity_material: bytes,
    ) -> None:
        self.config = config
        self.core = core
        self.gateway_id = hashlib.sha256(
            b"hearthbit-lan-gateway:" + identity_material
        ).digest()[:16]
        self.psk = base64.b64decode(config.psk_base64, validate=True)
        self.deduplicator = MessageDeduplicator()
        self._server: asyncio.Server | None = None
        self._mdns: MdnsService | None = None
        self._mdns_transport: asyncio.DatagramTransport | None = None
        self._query_task: asyncio.Task[None] | None = None
        self._connections: dict[bytes, LanConnection] = {}
        self._connection_tasks: set[asyncio.Task[None]] = set()
        self._connecting: set[bytes | tuple[str, int]] = set()
        self._stopping = False

    @property
    def status(self) -> LanStatus:
        port = 0
        if self._server is not None and self._server.sockets:
            port = int(self._server.sockets[0].getsockname()[1])
        return LanStatus(self.gateway_id, port, len(self._connections))

    async def start(self) -> None:
        if not self.config.enabled or self._server is not None:
            return
        self._stopping = False
        self._server = await asyncio.start_server(
            self._accept,
            self.config.listen_host,
            self.config.port,
            limit=self.config.max_frame_size + 1024,
        )
        port = self.status.port
        LOGGER.info(
            "LAN gateway listening on %s:%d id=%s",
            self.config.listen_host,
            port,
            self.gateway_id.hex(),
        )
        if self.config.discovery:
            address = local_ipv4()
            self._mdns = MdnsService(
                instance=self.config.service_name,
                hostname=f"hearthbit-{self.gateway_id.hex()[:8]}",
                address=address,
                port=port,
                gateway_id=self.gateway_id,
                on_gateway=self._discovered,
            )
            self._mdns_transport = await start_mdns(self._mdns)
            self._query_task = asyncio.create_task(self._query_loop())

    async def stop(self) -> None:
        self._stopping = True
        if self._query_task is not None:
            self._query_task.cancel()
            await asyncio.gather(self._query_task, return_exceptions=True)
            self._query_task = None
        if self._mdns_transport is not None:
            self._mdns_transport.close()
            self._mdns_transport = None
            self._mdns = None
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
        connections = list(self._connections.values())
        await asyncio.gather(*(connection.close() for connection in connections))
        tasks = list(self._connection_tasks)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for connection in connections:
            await self.core.remove_link(connection.id)
        self._connections.clear()
        self._connection_tasks.clear()
        self._connecting.clear()

    async def _accept(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        if len(self._connections) >= self.config.max_connections:
            writer.close()
            return
        try:
            await self._authenticate(reader, writer, outbound=False)
        except (LanProtocolError, OSError):
            LOGGER.debug("rejected unauthenticated LAN client", exc_info=True)

    def _discovered(self, gateway: DiscoveredGateway) -> None:
        if self._stopping or gateway.gateway_id == self.gateway_id:
            return
        key: bytes | tuple[str, int] = gateway.gateway_id or (
            gateway.host,
            gateway.port,
        )
        if gateway.gateway_id in self._connections or key in self._connecting:
            return
        if len(self._connections) + len(self._connecting) >= self.config.max_connections:
            return
        self._connecting.add(key)
        task = asyncio.create_task(self._connect(gateway, key))
        self._track_task(task)

    async def _connect(
        self,
        gateway: DiscoveredGateway,
        key: bytes | tuple[str, int],
    ) -> None:
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(
                    gateway.host,
                    gateway.port,
                    limit=self.config.max_frame_size + 1024,
                ),
                self.config.connect_timeout_seconds,
            )
            await self._authenticate(reader, writer, outbound=True)
        except (OSError, asyncio.TimeoutError, LanProtocolError):
            LOGGER.debug(
                "could not connect to discovered LAN gateway %s:%d",
                gateway.host,
                gateway.port,
                exc_info=True,
            )
        finally:
            self._connecting.discard(key)

    async def _authenticate(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        *,
        outbound: bool,
    ) -> None:
        try:
            peer, stream = await authenticate_stream(
                reader,
                writer,
                server=not outbound,
                gateway_id=self.gateway_id,
                psk=self.psk,
                max_frame_size=self.config.max_frame_size,
                timeout=self.config.connect_timeout_seconds,
            )
            existing = self._connections.get(peer.gateway_id)
            if existing is not None:
                # The lexicographically smaller ID owns the outbound socket.
                prefer_outbound = self.gateway_id < peer.gateway_id
                if existing.outbound == prefer_outbound or outbound != prefer_outbound:
                    writer.close()
                    await writer.wait_closed()
                    return
                await existing.close()
            connection = LanConnection(
                self,
                peer_gateway_id=peer.gateway_id,
                stream=stream,
                writer=writer,
                outbound=outbound,
            )
            self._connections[peer.gateway_id] = connection
            await self.core.register_link(connection)
            LOGGER.info(
                "authenticated LAN gateway %s (%s)",
                peer.gateway_id.hex(),
                "client" if outbound else "server",
            )
            task = asyncio.create_task(self._run_connection(connection))
            self._track_task(task)
        except Exception:
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()
            raise

    async def _run_connection(self, connection: LanConnection) -> None:
        try:
            await connection.run()
        except (LanProtocolError, OSError, asyncio.CancelledError):
            if not self._stopping:
                LOGGER.debug("LAN gateway disconnected: %s", connection.id)
        finally:
            if self._connections.get(connection.peer_gateway_id) is connection:
                self._connections.pop(connection.peer_gateway_id, None)
                await self.core.remove_link(connection.id)

    async def _query_loop(self) -> None:
        while True:
            if self._mdns is not None:
                self._mdns.query()
            await asyncio.sleep(15)

    def _track_task(self, task: asyncio.Task[None]) -> None:
        self._connection_tasks.add(task)
        task.add_done_callback(self._connection_tasks.discard)
