# hearthbit-core

Biblioteca Rust pura del frame de malla HearthBit. La Fase 7 no contiene FFI ni
está conectada al runtime móvil.

API pública:

- `Packet::decode` para frames v1/v2, compresión DEFLATE cruda y lectura zlib.
- `Packet::encode` para emisión sin padding o con padding canónico.
- `Packet::canonical_signing_bytes` y `Packet::canonical_sha256`.
- `Packet::verify_signature` con Ed25519 estricto.
- `KeyRotation::decode`, `authorization_bytes`, `new_peer_id` y
  `verify_authorization`.

Los tests cargan dinámicamente todos los fixtures `packet.decode`, el golden
`packet.canonical` y `extension.key_rotation.v1`. En esta fase se omiten
explícitamente `packet.fingerprint`, fragmentación, GCS, Courier, extensiones
genéricas, envelopes y HBT; esos codecs siguen cubiertos por sus
implementaciones actuales.

Validación:

```text
cargo fmt --check --manifest-path core/hearthbit-core/Cargo.toml
cargo clippy --locked --manifest-path core/hearthbit-core/Cargo.toml --all-targets -- -D warnings
cargo test --locked --manifest-path core/hearthbit-core/Cargo.toml
```
