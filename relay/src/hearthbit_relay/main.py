from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal

from .bluez import BlueZTransport
from .config import load_config
from .core import RelayCore
from .identity import RelayIdentity
from .lan import LanTransport
from .matrix import HttpMatrixApi, MatrixBridge
from .mqtt import MqttBridge, PahoMqttBroker
from .store import PacketStore
from .trust import TrustStore


async def run(config_path: str | None) -> None:
    config = load_config(config_path)
    logging.basicConfig(
        level=getattr(logging, config.log_level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    identity = await asyncio.to_thread(
        RelayIdentity.load_or_create,
        config.identity_path,
    )
    trust_store = await asyncio.to_thread(TrustStore, config.trust_store_path)
    store = await asyncio.to_thread(PacketStore, config.store)
    core = RelayCore(config, store, identity, trust_store=trust_store)
    transport = BlueZTransport(config, core)
    lan_transport = (
        LanTransport(
            config.lan,
            core,
            identity_material=identity.noise_public_key,
        )
        if config.lan.enabled
        else None
    )
    mqtt_transport = (
        MqttBridge(
            config.mqtt,
            core,
            PahoMqttBroker(config.mqtt),
            identity_material=identity.noise_public_key,
            max_frame_size=config.max_packet_size,
        )
        if config.mqtt.enabled
        else None
    )
    matrix_transport = (
        MatrixBridge(
            config.matrix,
            core,
            HttpMatrixApi(config.matrix),
            identity_material=identity.noise_public_key,
            max_frame_size=config.max_packet_size,
        )
        if config.matrix.enabled
        else None
    )
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stopped.set)
        except NotImplementedError:
            pass

    try:
        await transport.start()
        if lan_transport is not None:
            await lan_transport.start()
        if mqtt_transport is not None:
            await mqtt_transport.start()
        if matrix_transport is not None:
            await matrix_transport.start()
        await core.start()
        await stopped.wait()
    finally:
        if matrix_transport is not None:
            await matrix_transport.stop()
        if mqtt_transport is not None:
            await mqtt_transport.stop()
        await core.stop()
        if lan_transport is not None:
            await lan_transport.stop()
        await transport.stop()
        await asyncio.to_thread(store.close)


def main() -> None:
    parser = argparse.ArgumentParser(description="HearthBit Linux BlueZ relay")
    parser.add_argument(
        "--config",
        default=os.environ.get("HEARTHBIT_CONFIG"),
        help="JSON configuration path",
    )
    args = parser.parse_args()
    try:
        asyncio.run(run(args.config))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
