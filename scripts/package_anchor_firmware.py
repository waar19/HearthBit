#!/usr/bin/env python3
"""Validate and package a signed Anchor firmware release for HearthBit."""

from __future__ import annotations

import argparse
import hashlib
import shutil
import struct
from pathlib import Path


MANIFEST_LENGTH = 110
MANIFEST_MAGIC = b"BOTA"


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        default=root / "firmware" / "anchor-node" / "build" / "bitle.bin",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=root / "firmware" / "anchor-node" / "build" / "bitle.bin.bota",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=root / "app" / "assets" / "firmware",
    )
    args = parser.parse_args()

    image = args.image.read_bytes()
    manifest = args.manifest.read_bytes()
    if len(manifest) != MANIFEST_LENGTH or manifest[:4] != MANIFEST_MAGIC:
        raise SystemExit("invalid Anchor OTA manifest")

    version, declared_size = struct.unpack(">II", manifest[4:12])
    digest = manifest[12:44]
    chunk_size = struct.unpack(">H", manifest[44:46])[0]
    if version == 0:
        raise SystemExit("manifest version must be positive")
    if declared_size != len(image):
        raise SystemExit("manifest size does not match bitle.bin")
    if hashlib.sha256(image).digest() != digest:
        raise SystemExit("manifest digest does not match bitle.bin")
    if not 64 <= chunk_size <= 480:
        raise SystemExit("manifest chunk size is outside 64..480")

    args.output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.image, args.output / "bitle.bin")
    shutil.copyfile(args.manifest, args.output / "bitle.bin.bota")
    print(
        f"Packaged Anchor firmware v{version}: {len(image)} bytes, "
        f"chunk {chunk_size}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
