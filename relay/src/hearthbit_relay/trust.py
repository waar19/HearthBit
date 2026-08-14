from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path

TRUST_STORE_VERSION = 1
MAX_TRUSTED_PEERS = 4096
MAX_TRUST_STORE_BYTES = 4 * 1024 * 1024


class TrustStoreError(ValueError):
    """Raised when the persistent peer trust store is unusable."""


class TrustConflictError(TrustStoreError):
    """Raised when an ANNOUNCE conflicts with pinned public keys."""


@dataclass(frozen=True, slots=True)
class TrustedPeer:
    sender_id: bytes
    signing_public_key: bytes
    noise_public_key: bytes | None


class TrustStore:
    """Atomic persistent TOFU store for public peer identity material."""

    def __init__(self, path: str | Path) -> None:
        self.path = str(path)
        self._lock = threading.RLock()
        self._peers = self._load()

    def get(self, sender_id: bytes) -> TrustedPeer | None:
        with self._lock:
            return self._peers.get(bytes(sender_id))

    def pin(
        self,
        sender_id: bytes,
        signing_public_key: bytes,
        noise_public_key: bytes | None,
    ) -> bool:
        peer = _validated_peer(
            sender_id,
            signing_public_key,
            noise_public_key,
        )
        with self._lock:
            existing = self._peers.get(peer.sender_id)
            if existing is not None:
                if (
                    existing.signing_public_key != peer.signing_public_key
                    or (
                        existing.noise_public_key is not None
                        and peer.noise_public_key is not None
                        and existing.noise_public_key != peer.noise_public_key
                    )
                ):
                    raise TrustConflictError("trusted peer identity conflicts")
                return False
            if len(self._peers) >= MAX_TRUSTED_PEERS:
                raise TrustStoreError("trusted peer capacity reached")
            updated = dict(self._peers)
            updated[peer.sender_id] = peer
            self._write(updated)
            self._peers = updated
            return True

    def remove(self, sender_id: bytes) -> bool:
        if len(sender_id) != 8:
            raise TrustStoreError("sender ID must contain 8 bytes")
        with self._lock:
            if sender_id not in self._peers:
                return False
            updated = dict(self._peers)
            updated.pop(sender_id)
            self._write(updated)
            self._peers = updated
            return True

    def sender_ids(self) -> tuple[bytes, ...]:
        with self._lock:
            return tuple(sorted(self._peers))

    def _load(self) -> dict[bytes, TrustedPeer]:
        if self.path == ":memory:":
            return {}
        path = Path(self.path)
        if not path.exists() and not path.is_symlink():
            return {}
        if path.is_symlink():
            raise TrustStoreError("trust store cannot be a symbolic link")
        try:
            if path.stat().st_size > MAX_TRUST_STORE_BYTES:
                raise TrustStoreError("trust store exceeds its size limit")
            document = json.loads(path.read_text(encoding="utf-8"))
        except TrustStoreError:
            raise
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise TrustStoreError("trust store is unreadable or corrupt") from error
        if (
            not isinstance(document, dict)
            or set(document) != {"version", "peers"}
            or document.get("version") != TRUST_STORE_VERSION
            or not isinstance(document.get("peers"), list)
        ):
            raise TrustStoreError("trust store has an invalid format")
        entries = document["peers"]
        if len(entries) > MAX_TRUSTED_PEERS:
            raise TrustStoreError("trust store exceeds peer capacity")
        peers: dict[bytes, TrustedPeer] = {}
        for entry in entries:
            peer = _decode_peer(entry)
            if peer.sender_id in peers:
                raise TrustStoreError("trust store contains duplicate sender IDs")
            peers[peer.sender_id] = peer
        _restrict_file(path)
        return peers

    def _write(self, peers: dict[bytes, TrustedPeer]) -> None:
        if self.path == ":memory:":
            return
        path = Path(self.path)
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        document = {
            "version": TRUST_STORE_VERSION,
            "peers": [
                _encode_peer(peers[sender_id])
                for sender_id in sorted(peers)
            ],
        }
        encoded = (
            json.dumps(document, separators=(",", ":"), sort_keys=True)
            + "\n"
        ).encode("utf-8")
        if len(encoded) > MAX_TRUST_STORE_BYTES:
            raise TrustStoreError("trust store exceeds its size limit")
        descriptor = -1
        temporary = ""
        try:
            descriptor, temporary = tempfile.mkstemp(
                prefix=f".{path.name}.",
                suffix=".tmp",
                dir=path.parent,
            )
            os.chmod(temporary, 0o600)
            with os.fdopen(descriptor, "wb") as stream:
                descriptor = -1
                stream.write(encoded)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
            temporary = ""
            _restrict_file(path)
            _fsync_directory(path.parent)
        except (OSError, TypeError, ValueError) as error:
            raise TrustStoreError("failed to persist trust store") from error
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            if temporary:
                try:
                    os.unlink(temporary)
                except OSError:
                    pass


def _validated_peer(
    sender_id: bytes,
    signing_public_key: bytes,
    noise_public_key: bytes | None,
) -> TrustedPeer:
    sender = bytes(sender_id)
    signing = bytes(signing_public_key)
    noise = bytes(noise_public_key) if noise_public_key is not None else None
    if len(sender) != 8:
        raise TrustStoreError("sender ID must contain 8 bytes")
    if len(signing) != 32:
        raise TrustStoreError("signing public key must contain 32 bytes")
    if noise is not None:
        if len(noise) != 32:
            raise TrustStoreError("Noise public key must contain 32 bytes")
        if hashlib.sha256(noise).digest()[:8] != sender:
            raise TrustStoreError("Noise public key does not derive the sender ID")
    return TrustedPeer(sender, signing, noise)


def _decode_peer(value: object) -> TrustedPeer:
    if not isinstance(value, dict):
        raise TrustStoreError("trust store peer entry must be an object")
    required = {"sender_id", "signing_public_key", "noise_public_key"}
    if set(value) != required or any(
        not isinstance(value[field], str) for field in required
    ):
        raise TrustStoreError("trust store peer entry has an invalid format")
    try:
        sender = bytes.fromhex(value["sender_id"])
        signing = bytes.fromhex(value["signing_public_key"])
        noise_text = value["noise_public_key"]
        noise = bytes.fromhex(noise_text) if noise_text else None
    except ValueError as error:
        raise TrustStoreError("trust store contains invalid hexadecimal") from error
    return _validated_peer(sender, signing, noise)


def _encode_peer(peer: TrustedPeer) -> dict[str, str]:
    return {
        "sender_id": peer.sender_id.hex(),
        "signing_public_key": peer.signing_public_key.hex(),
        "noise_public_key": (
            peer.noise_public_key.hex()
            if peer.noise_public_key is not None
            else ""
        ),
    }


def _restrict_file(path: Path) -> None:
    try:
        os.chmod(path, 0o600, follow_symlinks=False)
    except (NotImplementedError, OSError) as error:
        if os.name != "nt":
            raise TrustStoreError("trust store permissions cannot be secured") from error
    if os.name != "nt":
        mode = stat.S_IMODE(path.stat().st_mode)
        if mode != 0o600:
            raise TrustStoreError("trust store permissions must be 0600")


def _fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    try:
        descriptor = os.open(path, flags)
    except OSError:
        return
    try:
        os.fsync(descriptor)
    except OSError:
        pass
    finally:
        os.close(descriptor)


def _parse_sender(value: str) -> bytes:
    try:
        sender = bytes.fromhex(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "sender must be 16 hexadecimal characters"
        ) from error
    if len(sender) != 8:
        raise argparse.ArgumentTypeError(
            "sender must be 16 hexadecimal characters"
        )
    return sender


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Administrative HearthBit peer trust-store operations"
    )
    parser.add_argument("--store", required=True, help="trust-store JSON path")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("list", help="list pinned sender IDs")
    remove = subparsers.add_parser("remove", help="remove one pinned sender")
    remove.add_argument("--sender", required=True, type=_parse_sender)
    remove.add_argument(
        "--confirm",
        action="store_true",
        help="confirm the destructive trust removal",
    )
    args = parser.parse_args()
    try:
        store = TrustStore(args.store)
        if args.command == "list":
            for sender_id in store.sender_ids():
                print(sender_id.hex())
            return
        if not args.confirm:
            parser.error("remove requires --confirm")
        removed = store.remove(args.sender)
        print("removed" if removed else "not-found")
    except TrustStoreError as error:
        print(f"trust-store error: {error}", file=sys.stderr)
        raise SystemExit(2) from None


if __name__ == "__main__":
    main()
