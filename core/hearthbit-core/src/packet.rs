use std::collections::HashSet;
use std::fmt;
use std::io::Write;

use ed25519_dalek::{Signature, VerifyingKey};
use flate2::write::DeflateEncoder;
use flate2::{Compression, Decompress, FlushDecompress, Status};
use sha2::{Digest, Sha256};

pub const FLAG_HAS_RECIPIENT: u8 = 0x01;
pub const FLAG_HAS_SIGNATURE: u8 = 0x02;
pub const FLAG_IS_COMPRESSED: u8 = 0x04;
pub const FLAG_HAS_ROUTE: u8 = 0x08;
pub const FLAG_RSR: u8 = 0x10;
pub const FLAG_DRILL: u8 = 0x20;
pub const MAX_PAYLOAD_LENGTH: usize = 10 * 1024 * 1024;

const ALLOWED_FLAGS: u8 = FLAG_HAS_RECIPIENT
    | FLAG_HAS_SIGNATURE
    | FLAG_IS_COMPRESSED
    | FLAG_HAS_ROUTE
    | FLAG_RSR
    | FLAG_DRILL;
const SIGNATURE_SIZE: usize = 64;
const PEER_ID_SIZE: usize = 8;
const COMPRESSION_THRESHOLD: usize = 100;
const MAX_EXPANSION_RATIO: usize = 50_000;
const PAD_TARGETS: [usize; 4] = [256, 512, 1024, 2048];
const TYPE_ANNOUNCE: u8 = 0x01;
const TYPE_MESSAGE: u8 = 0x02;
const EMERGENCY_PREANNOUNCE_TLV: u8 = 0xf1;
const DRILL_MARKER: &str = "[HB-DRILL|1|CHECKIN|";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Packet {
    pub version: u8,
    pub packet_type: u8,
    pub ttl: u8,
    pub timestamp: u64,
    pub sender_id: [u8; PEER_ID_SIZE],
    pub recipient_id: Option<[u8; PEER_ID_SIZE]>,
    pub payload: Vec<u8>,
    pub signature: Option<[u8; SIGNATURE_SIZE]>,
    pub route: Vec<[u8; PEER_ID_SIZE]>,
    pub is_rsr: bool,
    pub is_drill: bool,
}

impl Packet {
    /// Decodifica v1/v2. Primero prueba el frame exacto y solo después retira
    /// padding PKCS#7 válido de uno de los tamaños canónicos.
    pub fn decode(input: &[u8]) -> Result<Self, ProtocolError> {
        match Self::decode_unpadded(input) {
            Ok(packet) => Ok(packet),
            Err(original_error) => match remove_valid_padding(input) {
                Some(unpadded) => Self::decode_unpadded(unpadded),
                None => Err(original_error),
            },
        }
    }

    /// Codifica el paquete con las reglas canónicas de emisión. La firma se
    /// añade al final y nunca cuenta como payload.
    pub fn encode(&self, padded: bool) -> Result<Vec<u8>, ProtocolError> {
        validate_packet_shape(self)?;

        let mut payload = self.payload.clone();
        let mut original_size = None;
        if !self.is_drill && should_compress(&payload) {
            if let Some(compressed) = compress_raw(&payload)? {
                original_size = Some(payload.len());
                payload = compressed;
            }
        }

        let mut flags = 0_u8;
        if self.recipient_id.is_some() {
            flags |= FLAG_HAS_RECIPIENT;
        }
        if self.signature.is_some() {
            flags |= FLAG_HAS_SIGNATURE;
        }
        if original_size.is_some() {
            flags |= FLAG_IS_COMPRESSED;
        }
        if !self.route.is_empty() {
            flags |= FLAG_HAS_ROUTE;
        }
        if self.is_rsr {
            flags |= FLAG_RSR;
        }
        if self.is_drill {
            flags |= FLAG_DRILL;
        }
        validate_drill_shape(self, flags, false)?;

        let size_prefix = match (self.version, original_size) {
            (_, None) => 0,
            (1, Some(_)) => 2,
            (2, Some(_)) => 4,
            _ => return Err(ProtocolError::UnsupportedVersion(self.version)),
        };
        let transmitted_payload_size = size_prefix
            .checked_add(payload.len())
            .ok_or(ProtocolError::LengthOverflow)?;
        if transmitted_payload_size > MAX_PAYLOAD_LENGTH
            || (self.version == 1 && transmitted_payload_size > u16::MAX as usize)
        {
            return Err(ProtocolError::PayloadTooLarge(transmitted_payload_size));
        }

        let header_size = if self.version == 1 { 14 } else { 16 };
        let route_size = if self.route.is_empty() {
            0
        } else {
            1 + self.route.len() * PEER_ID_SIZE
        };
        let capacity = header_size
            + PEER_ID_SIZE
            + self.recipient_id.map_or(0, |_| PEER_ID_SIZE)
            + route_size
            + transmitted_payload_size
            + self.signature.map_or(0, |_| SIGNATURE_SIZE);
        let mut output = Vec::with_capacity(capacity);

        output.push(self.version);
        output.push(self.packet_type);
        output.push(self.ttl);
        output.extend_from_slice(&self.timestamp.to_be_bytes());
        output.push(flags);
        if self.version == 1 {
            output.extend_from_slice(&(transmitted_payload_size as u16).to_be_bytes());
        } else {
            output.extend_from_slice(&(transmitted_payload_size as u32).to_be_bytes());
        }
        output.extend_from_slice(&self.sender_id);
        if let Some(recipient) = self.recipient_id {
            output.extend_from_slice(&recipient);
        }
        if !self.route.is_empty() {
            output.push(self.route.len() as u8);
            for peer_id in &self.route {
                output.extend_from_slice(peer_id);
            }
        }
        if let Some(size) = original_size {
            if self.version == 1 {
                output.extend_from_slice(&(size as u16).to_be_bytes());
            } else {
                output.extend_from_slice(&(size as u32).to_be_bytes());
            }
        }
        output.extend_from_slice(&payload);
        if let Some(signature) = self.signature {
            output.extend_from_slice(&signature);
        }

        Ok(if padded { add_padding(output) } else { output })
    }

    /// Bytes firmados: TTL cero, RSR retirado, firma separada y padding
    /// canónico. Los demás flags semánticos, incluido DRILL, se conservan.
    pub fn canonical_signing_bytes(&self) -> Result<Vec<u8>, ProtocolError> {
        let mut canonical = self.clone();
        canonical.ttl = 0;
        canonical.is_rsr = false;
        canonical.signature = None;
        canonical.encode(true)
    }

    pub fn canonical_sha256(&self) -> Result<[u8; 32], ProtocolError> {
        let digest = Sha256::digest(self.canonical_signing_bytes()?);
        Ok(digest.into())
    }

    /// Verifica Ed25519 con la comprobación estricta de `ed25519-dalek`.
    pub fn verify_signature(
        &self,
        public_key: &[u8; 32],
    ) -> Result<(), ProtocolError> {
        let signature_bytes = self.signature.ok_or(ProtocolError::MissingSignature)?;
        let verifying_key = VerifyingKey::from_bytes(public_key)
            .map_err(|_| ProtocolError::InvalidPublicKey)?;
        let signature = Signature::from_bytes(&signature_bytes);
        verifying_key
            .verify_strict(&self.canonical_signing_bytes()?, &signature)
            .map_err(|_| ProtocolError::SignatureVerificationFailed)
    }

    fn decode_unpadded(input: &[u8]) -> Result<Self, ProtocolError> {
        let mut reader = Reader::new(input);
        let version = reader.read_u8()?;
        let header_size = match version {
            1 => 22,
            2 => 24,
            other => return Err(ProtocolError::UnsupportedVersion(other)),
        };
        if input.len() < header_size {
            return Err(ProtocolError::Truncated);
        }

        let packet_type = reader.read_u8()?;
        let ttl = reader.read_u8()?;
        let timestamp = reader.read_u64()?;
        let flags = reader.read_u8()?;
        if flags & !ALLOWED_FLAGS != 0 {
            return Err(ProtocolError::UnsupportedFlags(flags));
        }
        if version == 1 && flags & FLAG_HAS_ROUTE != 0 {
            return Err(ProtocolError::RouteNotAllowedInV1);
        }

        let payload_size = if version == 1 {
            reader.read_u16()? as usize
        } else {
            reader.read_u32()? as usize
        };
        if payload_size > MAX_PAYLOAD_LENGTH {
            return Err(ProtocolError::PayloadTooLarge(payload_size));
        }

        let sender_id = reader.read_array()?;
        let recipient_id = if flags & FLAG_HAS_RECIPIENT != 0 {
            Some(reader.read_array()?)
        } else {
            None
        };
        let route = if flags & FLAG_HAS_ROUTE != 0 {
            let count = reader.read_u8()? as usize;
            if count == 0 {
                return Err(ProtocolError::EmptyRoute);
            }
            let route_bytes = count
                .checked_mul(PEER_ID_SIZE)
                .ok_or(ProtocolError::LengthOverflow)?;
            if reader.remaining() < route_bytes {
                return Err(ProtocolError::Truncated);
            }
            let mut route = Vec::with_capacity(count);
            let mut unique = HashSet::with_capacity(count);
            for _ in 0..count {
                let peer_id = reader.read_array()?;
                if !unique.insert(peer_id) {
                    return Err(ProtocolError::DuplicateRouteHop);
                }
                route.push(peer_id);
            }
            route
        } else {
            Vec::new()
        };

        let signature_size = if flags & FLAG_HAS_SIGNATURE != 0 {
            SIGNATURE_SIZE
        } else {
            0
        };
        let required = payload_size
            .checked_add(signature_size)
            .ok_or(ProtocolError::LengthOverflow)?;
        if reader.remaining() < required {
            return Err(ProtocolError::Truncated);
        }

        let payload_data = reader.read_slice(payload_size)?;
        let payload = if flags & FLAG_IS_COMPRESSED != 0 {
            decode_compressed(version, payload_data)?
        } else {
            payload_data.to_vec()
        };
        let signature = if signature_size == 0 {
            None
        } else {
            Some(reader.read_array()?)
        };
        if reader.remaining() != 0 {
            return Err(ProtocolError::TrailingBytes(reader.remaining()));
        }

        let packet = Self {
            version,
            packet_type,
            ttl,
            timestamp,
            sender_id,
            recipient_id,
            payload,
            signature,
            route,
            is_rsr: flags & FLAG_RSR != 0,
            is_drill: flags & FLAG_DRILL != 0,
        };
        validate_packet_shape(&packet)?;
        validate_drill_shape(&packet, flags, true)?;
        Ok(packet)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ProtocolError {
    UnsupportedVersion(u8),
    UnsupportedFlags(u8),
    Truncated,
    TrailingBytes(usize),
    LengthOverflow,
    PayloadTooLarge(usize),
    InvalidCompressedPayload,
    CompressionExpansionLimit,
    RouteNotAllowedInV1,
    EmptyRoute,
    DuplicateRouteHop,
    TooManyRouteHops(usize),
    InvalidDrill,
    MissingSignature,
    InvalidPublicKey,
    SignatureVerificationFailed,
    CompressionFailed,
}

impl fmt::Display for ProtocolError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{self:?}")
    }
}

impl std::error::Error for ProtocolError {}

fn validate_packet_shape(packet: &Packet) -> Result<(), ProtocolError> {
    if !matches!(packet.version, 1 | 2) {
        return Err(ProtocolError::UnsupportedVersion(packet.version));
    }
    if packet.version == 1 && !packet.route.is_empty() {
        return Err(ProtocolError::RouteNotAllowedInV1);
    }
    if packet.route.len() > u8::MAX as usize {
        return Err(ProtocolError::TooManyRouteHops(packet.route.len()));
    }
    if packet.payload.len() > MAX_PAYLOAD_LENGTH
        || (packet.version == 1 && packet.payload.len() > u16::MAX as usize)
    {
        return Err(ProtocolError::PayloadTooLarge(packet.payload.len()));
    }
    let mut unique = HashSet::with_capacity(packet.route.len());
    if packet.route.iter().any(|hop| !unique.insert(*hop)) {
        return Err(ProtocolError::DuplicateRouteHop);
    }
    Ok(())
}

fn validate_drill_shape(
    packet: &Packet,
    flags: u8,
    require_signature: bool,
) -> Result<(), ProtocolError> {
    let has_marker_without_flag = packet.packet_type == TYPE_MESSAGE
        && String::from_utf8_lossy(&packet.payload).contains("[HB-DRILL|");
    if !packet.is_drill {
        return if has_marker_without_flag {
            Err(ProtocolError::InvalidDrill)
        } else {
            Ok(())
        };
    }

    let marked_payload = match packet.packet_type {
        TYPE_ANNOUNCE => has_emergency_preannounce(&packet.payload),
        TYPE_MESSAGE => is_valid_drill_message(&packet.payload),
        _ => false,
    };
    if packet.version != 1
        || (require_signature && packet.signature.is_none())
        || packet.recipient_id.is_some()
        || !packet.route.is_empty()
        || flags & FLAG_IS_COMPRESSED != 0
        || !marked_payload
    {
        return Err(ProtocolError::InvalidDrill);
    }
    Ok(())
}

fn has_emergency_preannounce(payload: &[u8]) -> bool {
    let mut offset = 0;
    while offset + 2 <= payload.len() {
        let tag = payload[offset];
        let length = payload[offset + 1] as usize;
        offset += 2;
        if offset + length > payload.len() {
            return false;
        }
        if tag == EMERGENCY_PREANNOUNCE_TLV {
            return length == 1 && payload[offset] == 1;
        }
        offset += length;
    }
    false
}

fn is_valid_drill_message(payload: &[u8]) -> bool {
    let Ok(content) = std::str::from_utf8(payload) else {
        return false;
    };
    if content.starts_with("SOS|")
        || content.contains("[HB-CHECKIN|")
        || !content.ends_with(']')
    {
        return false;
    }
    let Some(marker) = content.rfind(DRILL_MARKER) else {
        return false;
    };
    if marker == 0 {
        return false;
    }
    let fields: Vec<_> = content[marker + DRILL_MARKER.len()..content.len() - 1]
        .split('|')
        .collect();
    fields.len() == 2
        && matches!(fields[0], "OK" | "HELP" | "INJURED")
        && !fields[1].is_empty()
        && fields[1].bytes().all(|byte| byte.is_ascii_digit())
        && fields[1].parse::<u64>().is_ok_and(|value| value > 0)
}

fn should_compress(input: &[u8]) -> bool {
    if input.len() < COMPRESSION_THRESHOLD {
        return false;
    }
    let sample_size = input.len().min(256);
    let unique = input.iter().copied().collect::<HashSet<_>>().len();
    unique as f64 / (sample_size as f64) < 0.9
}

fn compress_raw(input: &[u8]) -> Result<Option<Vec<u8>>, ProtocolError> {
    let mut encoder = DeflateEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(input)
        .map_err(|_| ProtocolError::CompressionFailed)?;
    let compressed = encoder
        .finish()
        .map_err(|_| ProtocolError::CompressionFailed)?;
    Ok((!compressed.is_empty() && compressed.len() < input.len()).then_some(compressed))
}

fn decode_compressed(version: u8, payload: &[u8]) -> Result<Vec<u8>, ProtocolError> {
    let size_prefix = if version == 1 { 2 } else { 4 };
    if payload.len() <= size_prefix {
        return Err(ProtocolError::InvalidCompressedPayload);
    }
    let expected_size = if version == 1 {
        u16::from_be_bytes([payload[0], payload[1]]) as usize
    } else {
        u32::from_be_bytes([
            payload[0], payload[1], payload[2], payload[3],
        ]) as usize
    };
    if expected_size == 0 || expected_size > MAX_PAYLOAD_LENGTH {
        return Err(ProtocolError::PayloadTooLarge(expected_size));
    }
    let compressed = &payload[size_prefix..];
    if compressed.is_empty() {
        return Err(ProtocolError::InvalidCompressedPayload);
    }
    if expected_size
        > compressed
            .len()
            .checked_mul(MAX_EXPANSION_RATIO)
            .ok_or(ProtocolError::CompressionExpansionLimit)?
    {
        return Err(ProtocolError::CompressionExpansionLimit);
    }

    if looks_like_zlib(compressed) {
        inflate_exact(compressed, expected_size, true)
            .or_else(|_| inflate_exact(compressed, expected_size, false))
    } else {
        inflate_exact(compressed, expected_size, false)
    }
}

fn looks_like_zlib(input: &[u8]) -> bool {
    if input.len() < 2 {
        return false;
    }
    let cmf = input[0];
    let flg = input[1];
    cmf & 0x0f == 8
        && cmf >> 4 <= 7
        && (u16::from(cmf) * 256 + u16::from(flg)) % 31 == 0
}

fn inflate_exact(
    input: &[u8],
    expected_size: usize,
    zlib_header: bool,
) -> Result<Vec<u8>, ProtocolError> {
    let mut decompressor = Decompress::new(zlib_header);
    let mut output = vec![0_u8; expected_size + 1];
    let status = decompressor
        .decompress(input, &mut output, FlushDecompress::Finish)
        .map_err(|_| ProtocolError::InvalidCompressedPayload)?;
    if status != Status::StreamEnd
        || decompressor.total_in() != input.len() as u64
        || decompressor.total_out() != expected_size as u64
    {
        return Err(ProtocolError::InvalidCompressedPayload);
    }
    output.truncate(expected_size);
    Ok(output)
}

fn add_padding(mut input: Vec<u8>) -> Vec<u8> {
    let Some(target) = PAD_TARGETS
        .iter()
        .copied()
        .find(|target| input.len() + 16 <= *target)
    else {
        return input;
    };
    let padding = target - input.len();
    if !(1..=u8::MAX as usize).contains(&padding) {
        return input;
    }
    input.resize(target, padding as u8);
    input
}

fn remove_valid_padding(input: &[u8]) -> Option<&[u8]> {
    if !PAD_TARGETS.contains(&input.len()) {
        return None;
    }
    let padding = *input.last()? as usize;
    if padding == 0 || padding > u8::MAX as usize || padding > input.len() {
        return None;
    }
    let start = input.len() - padding;
    input[start..]
        .iter()
        .all(|byte| *byte as usize == padding)
        .then_some(&input[..start])
}

struct Reader<'a> {
    input: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { input, offset: 0 }
    }

    fn remaining(&self) -> usize {
        self.input.len() - self.offset
    }

    fn read_u8(&mut self) -> Result<u8, ProtocolError> {
        Ok(self.read_slice(1)?[0])
    }

    fn read_u16(&mut self) -> Result<u16, ProtocolError> {
        Ok(u16::from_be_bytes(self.read_array()?))
    }

    fn read_u32(&mut self) -> Result<u32, ProtocolError> {
        Ok(u32::from_be_bytes(self.read_array()?))
    }

    fn read_u64(&mut self) -> Result<u64, ProtocolError> {
        Ok(u64::from_be_bytes(self.read_array()?))
    }

    fn read_array<const N: usize>(&mut self) -> Result<[u8; N], ProtocolError> {
        self.read_slice(N)?
            .try_into()
            .map_err(|_| ProtocolError::Truncated)
    }

    fn read_slice(&mut self, length: usize) -> Result<&'a [u8], ProtocolError> {
        let end = self
            .offset
            .checked_add(length)
            .ok_or(ProtocolError::LengthOverflow)?;
        if end > self.input.len() {
            return Err(ProtocolError::Truncated);
        }
        let slice = &self.input[self.offset..end];
        self.offset = end;
        Ok(slice)
    }
}
