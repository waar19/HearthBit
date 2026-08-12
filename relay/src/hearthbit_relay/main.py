from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal

from .bluez import BlueZTransport
from .config import load_config
from .core import RelayCore
from .store import PacketStore


async def run(config_path: str | None) -> None:
    config = load_config(config_path)
    logging.basicConfig(
        level=getattr(logging, config.log_level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    store = PacketStore(config.store)
    core = RelayCore(config, store)
    transport = BlueZTransport(config, core)
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stopped.set)
        except NotImplementedError:
            pass

    try:
        await transport.start()
        await stopped.wait()
    finally:
        await transport.stop()
        store.close()


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
