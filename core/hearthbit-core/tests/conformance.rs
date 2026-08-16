use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use ed25519_dalek::{Signer, SigningKey};
use hearthbit_core::{
    FLAG_DRILL, FLAG_HAS_RECIPIENT, FLAG_HAS_ROUTE, FLAG_HAS_SIGNATURE, KeyRotation,
    MAX_PAYLOAD_LENGTH, Packet, ProtocolError,
};
use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    schema_version: u32,
    upstream_commit: String,
    fixtures: Vec<Fixture>,
}

#[derive(Debug, Deserialize)]
struct Fixture {
    id: String,
    operation: String,
    blob: String,
    valid: bool,
    #[serde(default)]
    expect: Value,
}

#[test]
fn validates_every_packet_decode_fixture() {
    let suite = Suite::load();
    let packet_fixtures: Vec<_> = suite
        .manifest
        .fixtures
        .iter()
        .filter(|fixture| fixture.operation == "packet.decode")
        .collect();
    assert!(!packet_fixtures.is_empty());

    for fixture in packet_fixtures {
        let bytes = suite.bytes(fixture);
        let decoded = Packet::decode(&bytes);
        if !fixture.valid {
            assert!(decoded.is_err(), "{} debía rechazarse", fixture.id);
            continue;
        }

        let packet = decoded.unwrap_or_else(|error| {
            panic!("{} debía decodificarse: {error}", fixture.id)
        });
        assert_expected_packet(&fixture.id, &packet, &fixture.expect);
    }
}

#[test]
fn canonical_bytes_and_sha256_match_shared_golden() {
    let suite = Suite::load();
    let fixture = suite.fixture("signature.canonical.v1_announce");
    let announcement = [
        &[0x01, 0x03][..],
        b"bob",
        &[0x02, 0x20][..],
        &[0x11; 32],
        &[0x03, 0x20][..],
        &[0x22; 32],
    ]
    .concat();
    let packet = Packet {
        version: 1,
        packet_type: 1,
        ttl: 7,
        timestamp: 0x0102_0304_0506_0708,
        sender_id: [0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17],
        recipient_id: None,
        payload: announcement,
        signature: Some([0; 64]),
        route: Vec::new(),
        is_rsr: true,
        is_drill: false,
    };

    let canonical = packet.canonical_signing_bytes().unwrap();
    assert_eq!(suite.bytes(fixture), canonical);
    assert_eq!(0, canonical[2]);
    assert_eq!(0, canonical[11] & FLAG_HAS_SIGNATURE);
    assert_eq!(
        "db232b00f54f6c161ab71e8756af799b2165d9f021cd4309aeb9ab203f2028af",
        hex::encode(packet.canonical_sha256().unwrap())
    );
}

#[test]
fn verifies_valid_signature_and_rejects_mutations_strictly() {
    let signing_key = SigningKey::from_bytes(&[7; 32]);
    let mut packet = sample_packet();
    let signature = signing_key.sign(&packet.canonical_signing_bytes().unwrap());
    packet.signature = Some(signature.to_bytes());

    packet
        .verify_signature(&signing_key.verifying_key().to_bytes())
        .unwrap();

    let mut changed_payload = packet.clone();
    changed_payload.payload[0] ^= 1;
    assert_eq!(
        Err(ProtocolError::SignatureVerificationFailed),
        changed_payload.verify_signature(&signing_key.verifying_key().to_bytes())
    );

    let mut changed_signature = packet;
    changed_signature.signature.as_mut().unwrap()[0] ^= 1;
    assert_eq!(
        Err(ProtocolError::SignatureVerificationFailed),
        changed_signature.verify_signature(&signing_key.verifying_key().to_bytes())
    );
}

#[test]
fn rejects_truncation_invalid_padding_and_limits() {
    let encoded = sample_packet().encode(false).unwrap();
    assert!(Packet::decode(&encoded[..encoded.len() - 1]).is_err());

    let mut invalid_padding = sample_packet().canonical_signing_bytes().unwrap();
    let last_data_index = invalid_padding.len() - 2;
    invalid_padding[last_data_index] = 0;
    assert!(Packet::decode(&invalid_padding).is_err());

    let mut oversized = vec![0_u8; 24];
    oversized[0] = 2;
    oversized[12..16].copy_from_slice(&((MAX_PAYLOAD_LENGTH + 1) as u32).to_be_bytes());
    assert_eq!(
        Err(ProtocolError::PayloadTooLarge(MAX_PAYLOAD_LENGTH + 1)),
        Packet::decode(&oversized)
    );

    let mut duplicate_route = sample_packet();
    duplicate_route.version = 2;
    duplicate_route.route = vec![[9; 8], [9; 8]];
    assert_eq!(
        Err(ProtocolError::DuplicateRouteHop),
        duplicate_route.encode(false)
    );

    let mut oversized_v1 = sample_packet();
    oversized_v1.payload = vec![0; u16::MAX as usize + 1];
    assert_eq!(
        Err(ProtocolError::PayloadTooLarge(u16::MAX as usize + 1)),
        oversized_v1.encode(false)
    );
}

#[test]
fn preserves_drill_semantics_in_canonical_bytes() {
    let suite = Suite::load();
    let packet = Packet::decode(&suite.bytes(suite.fixture("packet.v1.drill_message"))).unwrap();
    assert!(packet.is_drill);

    let canonical = packet.canonical_signing_bytes().unwrap();
    assert_eq!(0, canonical[2]);
    assert_eq!(FLAG_DRILL, canonical[11] & FLAG_DRILL);
    assert_eq!(0, canonical[11] & FLAG_HAS_SIGNATURE);
}

#[test]
fn decodes_shared_key_rotation_fixture() {
    let suite = Suite::load();
    let fixture = suite.fixture("extension.key_rotation.v1");
    let rotation = KeyRotation::decode(&suite.bytes(fixture)).unwrap();

    assert_eq!([1, 2, 3, 4, 5, 6, 7, 8], rotation.old_peer_id);
    assert_eq!(1_700_000_000_000, rotation.timestamp);
    assert_eq!(1, rotation.sequence);
    assert_eq!(64, rotation.authorization_signature.len());

    let bytes = suite.bytes(fixture);
    assert!(KeyRotation::decode(&bytes[..bytes.len() - 1]).is_err());
    let mut zero_noise_key = bytes;
    zero_noise_key[9..41].fill(0);
    assert_eq!(
        Err(ProtocolError::InvalidPublicKey),
        KeyRotation::decode(&zero_noise_key)
    );
}

#[test]
fn explicitly_accounts_for_non_packet_fixtures() {
    let suite = Suite::load();
    let implemented: BTreeSet<_> = [
        "packet.decode",
        "packet.canonical",
        "key-rotation.decode",
    ]
    .into_iter()
    .collect();
    // Fase 7 se limita al frame de malla y rotación de clave. Estos codecs se
    // mantienen en sus implementaciones actuales hasta las fases FFI.
    let intentionally_omitted: BTreeSet<_> = [
        "packet.fingerprint",
        "fragment.decode",
        "fragment.packet",
        "gcs.decode",
        "courier.decode",
        "extension.decode",
        "extension-envelope.decode",
        "hbt.decode",
        "hbt.signed",
    ]
    .into_iter()
    .collect();

    for fixture in &suite.manifest.fixtures {
        assert!(
            implemented.contains(fixture.operation.as_str())
                || intentionally_omitted.contains(fixture.operation.as_str()),
            "operación sin clasificar: {} ({})",
            fixture.operation,
            fixture.id
        );
    }
}

#[test]
fn manifest_pins_the_expected_upstream_revision() {
    let suite = Suite::load();
    assert_eq!(1, suite.manifest.schema_version);
    assert_eq!(
        "5156f7de89ec9f6a3429630d90f709b68f6fd7fd",
        suite.manifest.upstream_commit
    );
}

fn sample_packet() -> Packet {
    Packet {
        version: 1,
        packet_type: 2,
        ttl: 7,
        timestamp: 1,
        sender_id: [1, 2, 3, 4, 5, 6, 7, 8],
        recipient_id: None,
        payload: b"mensaje firmado".to_vec(),
        signature: None,
        route: Vec::new(),
        is_rsr: true,
        is_drill: false,
    }
}

fn assert_expected_packet(id: &str, packet: &Packet, expected: &Value) {
    assert_json_u64(id, "version", packet.version as u64, expected);
    assert_json_u64(id, "type", packet.packet_type as u64, expected);
    assert_json_u64(id, "ttl", packet.ttl as u64, expected);
    assert_json_u64(id, "timestamp", packet.timestamp, expected);
    assert_json_hex(id, "sender", &packet.sender_id, expected);
    if let Some(recipient) = packet.recipient_id {
        assert_json_hex(id, "recipient", &recipient, expected);
    }
    if let Some(payload) = expected.get("payload").and_then(Value::as_str) {
        assert_eq!(payload, hex::encode(&packet.payload), "{id}: payload");
    }
    if let Some(pattern) = expected.get("payloadPattern").and_then(Value::as_str) {
        let pattern = hex::decode(pattern).unwrap();
        assert!(
            packet
                .payload
                .iter()
                .enumerate()
                .all(|(index, byte)| *byte == pattern[index % pattern.len()]),
            "{id}: patrón de payload"
        );
    }
    if let Some(payload_bytes) = expected.get("payloadBytes").and_then(Value::as_u64) {
        assert_eq!(payload_bytes as usize, packet.payload.len(), "{id}: bytes");
    }
    if let Some(signature_bytes) = expected.get("signatureBytes").and_then(Value::as_u64) {
        assert_eq!(
            signature_bytes as usize,
            packet.signature.map_or(0, |signature| signature.len()),
            "{id}: firma"
        );
    }
    if let Some(drill) = expected.get("drill").and_then(Value::as_bool) {
        assert_eq!(drill, packet.is_drill, "{id}: drill");
    }
    if let Some(flags) = expected.get("flags").and_then(Value::as_u64) {
        let actual_flags = u64::from(packet.is_drill) * u64::from(FLAG_DRILL)
            + u64::from(packet.signature.is_some()) * u64::from(FLAG_HAS_SIGNATURE)
            + u64::from(packet.recipient_id.is_some()) * u64::from(FLAG_HAS_RECIPIENT)
            + u64::from(!packet.route.is_empty()) * u64::from(FLAG_HAS_ROUTE);
        assert_eq!(flags, actual_flags, "{id}: flags semánticos");
    }
    if let Some(route) = expected.get("route").and_then(Value::as_array) {
        let actual: Vec<_> = packet.route.iter().map(|hop| hex::encode(hop)).collect();
        let expected: Vec<_> = route
            .iter()
            .map(|value| value.as_str().unwrap().to_owned())
            .collect();
        assert_eq!(expected, actual, "{id}: ruta");
    }
}

fn assert_json_u64(id: &str, field: &str, actual: u64, expected: &Value) {
    if let Some(value) = expected.get(field).and_then(Value::as_u64) {
        assert_eq!(value, actual, "{id}: {field}");
    }
}

fn assert_json_hex(id: &str, field: &str, actual: &[u8], expected: &Value) {
    if let Some(value) = expected.get(field).and_then(Value::as_str) {
        assert_eq!(value, hex::encode(actual), "{id}: {field}");
    }
}

struct Suite {
    root: PathBuf,
    manifest: Manifest,
}

impl Suite {
    fn load() -> Self {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join("tests")
            .join("conformance");
        let manifest = serde_json::from_slice(
            &fs::read(root.join("fixtures.v1.json")).expect("leer fixtures.v1.json"),
        )
        .expect("decodificar fixtures.v1.json");
        Self { root, manifest }
    }

    fn fixture(&self, id: &str) -> &Fixture {
        self.manifest
            .fixtures
            .iter()
            .find(|fixture| fixture.id == id)
            .unwrap_or_else(|| panic!("fixture desconocido: {id}"))
    }

    fn bytes(&self, fixture: &Fixture) -> Vec<u8> {
        let source = fs::read_to_string(self.root.join(&fixture.blob))
            .unwrap_or_else(|error| panic!("leer {}: {error}", fixture.id));
        hex::decode(
            source
                .chars()
                .filter(|character| !character.is_whitespace())
                .collect::<String>(),
        )
        .unwrap_or_else(|error| panic!("hex de {}: {error}", fixture.id))
    }
}
