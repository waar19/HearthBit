import json
import os
import stat

import pytest

import hearthbit_relay.trust as trust_module
from hearthbit_relay.identity import RelayIdentity
from hearthbit_relay.trust import (
    TrustConflictError,
    TrustStore,
    TrustStoreError,
)


def test_trust_store_persists_identity_atomically_with_private_mode(tmp_path) -> None:
    path = tmp_path / "trusted-peers.json"
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    store = TrustStore(path)

    assert store.pin(
        identity.peer_id,
        identity.signing_public_key,
        identity.noise_public_key,
    )
    assert not list(tmp_path.glob(".trusted-peers.json.*.tmp"))
    if os.name != "nt":
        assert stat.S_IMODE(path.stat().st_mode) == 0o600

    reopened = TrustStore(path)
    peer = reopened.get(identity.peer_id)
    assert peer is not None
    assert peer.signing_public_key == identity.signing_public_key
    assert peer.noise_public_key == identity.noise_public_key


def test_trust_store_conflict_survives_restart(tmp_path) -> None:
    path = tmp_path / "trusted-peers.json"
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    attacker = RelayIdentity.load_or_create(tmp_path / "attacker.json")
    TrustStore(path).pin(
        identity.peer_id,
        identity.signing_public_key,
        identity.noise_public_key,
    )

    reopened = TrustStore(path)
    with pytest.raises(TrustConflictError):
        reopened.pin(
            identity.peer_id,
            attacker.signing_public_key,
            identity.noise_public_key,
        )


@pytest.mark.parametrize(
    "content",
    [
        "{not-json",
        '{"version":1,"version":1,"peers":[]}',
        json.dumps({"version": 1, "peers": "not-a-list"}),
        json.dumps(
            {
                "version": 1,
                "peers": [
                    {
                        "sender_id": "00" * 8,
                        "signing_public_key": "11" * 32,
                        "noise_public_key": "22" * 32,
                    }
                ],
            }
        ),
    ],
)
def test_trust_store_fails_closed_on_corruption(tmp_path, content: str) -> None:
    path = tmp_path / "trusted-peers.json"
    path.write_text(content, encoding="utf-8")

    with pytest.raises(TrustStoreError):
        TrustStore(path)

    assert path.read_text(encoding="utf-8") == content


@pytest.mark.skipif(os.name == "nt", reason="POSIX mode bits are required")
def test_trust_store_restricts_existing_file_permissions(tmp_path) -> None:
    path = tmp_path / "trusted-peers.json"
    path.write_text('{"version":1,"peers":[]}', encoding="utf-8")
    path.chmod(0o644)

    TrustStore(path)

    assert stat.S_IMODE(path.stat().st_mode) == 0o600


def test_trust_store_capacity_is_enforced(tmp_path, monkeypatch) -> None:
    assert trust_module.MAX_TRUSTED_PEERS == 4096
    monkeypatch.setattr(trust_module, "MAX_TRUSTED_PEERS", 1)
    first = RelayIdentity.load_or_create(tmp_path / "first.json")
    second = RelayIdentity.load_or_create(tmp_path / "second.json")
    store = TrustStore(tmp_path / "trusted-peers.json")
    store.pin(
        first.peer_id,
        first.signing_public_key,
        first.noise_public_key,
    )

    with pytest.raises(TrustStoreError, match="capacity"):
        store.pin(
            second.peer_id,
            second.signing_public_key,
            second.noise_public_key,
        )


def test_administrative_remove_is_explicit_and_persistent(tmp_path) -> None:
    path = tmp_path / "trusted-peers.json"
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    store = TrustStore(path)
    store.pin(
        identity.peer_id,
        identity.signing_public_key,
        identity.noise_public_key,
    )

    assert store.remove(identity.peer_id)
    assert TrustStore(path).get(identity.peer_id) is None


def test_administrative_signing_key_rotation_is_atomic(tmp_path) -> None:
    path = tmp_path / "trusted-peers.json"
    identity = RelayIdentity.load_or_create(tmp_path / "identity.json")
    replacement = RelayIdentity.load_or_create(tmp_path / "replacement.json")
    store = TrustStore(path)
    store.pin(
        identity.peer_id,
        identity.signing_public_key,
        identity.noise_public_key,
    )

    store.replace(
        identity.peer_id,
        replacement.signing_public_key,
        identity.noise_public_key,
    )

    reopened = TrustStore(path)
    peer = reopened.get(identity.peer_id)
    assert peer is not None
    assert peer.signing_public_key == replacement.signing_public_key
