use ed25519_dalek::{Signature, VerifyingKey};
use sha2::{Digest, Sha256};

use crate::ProtocolError;

pub const KEY_ROTATION_DOMAIN: &[u8] = b"HearthBitKeyRotationV1";
pub const KEY_ROTATION_PAYLOAD_SIZE: usize = 153;

const VERSION: u8 = 1;
const UNSIGNED_SIZE: usize = 89;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct KeyRotation {
    pub old_peer_id: [u8; 8],
    pub new_noise_public_key: [u8; 32],
    pub new_signing_public_key: [u8; 32],
    pub timestamp: u64,
    pub sequence: u64,
    pub authorization_signature: [u8; 64],
}

impl KeyRotation {
    pub fn decode(payload: &[u8]) -> Result<Self, ProtocolError> {
        if payload.len() != KEY_ROTATION_PAYLOAD_SIZE {
            return Err(ProtocolError::Truncated);
        }
        if payload[0] != VERSION {
            return Err(ProtocolError::UnsupportedVersion(payload[0]));
        }

        let old_peer_id: [u8; 8] = payload[1..9]
            .try_into()
            .map_err(|_| ProtocolError::Truncated)?;
        let new_noise_public_key: [u8; 32] = payload[9..41]
            .try_into()
            .map_err(|_| ProtocolError::Truncated)?;
        let new_signing_public_key: [u8; 32] = payload[41..73]
            .try_into()
            .map_err(|_| ProtocolError::Truncated)?;
        let timestamp = u64::from_be_bytes(
            payload[73..81]
                .try_into()
                .map_err(|_| ProtocolError::Truncated)?,
        );
        let sequence = u64::from_be_bytes(
            payload[81..89]
                .try_into()
                .map_err(|_| ProtocolError::Truncated)?,
        );
        let authorization_signature = payload[89..153]
            .try_into()
            .map_err(|_| ProtocolError::Truncated)?;

        if sequence == 0 || new_noise_public_key.iter().all(|byte| *byte == 0) {
            return Err(ProtocolError::InvalidPublicKey);
        }
        let signing_key = VerifyingKey::from_bytes(&new_signing_public_key)
            .map_err(|_| ProtocolError::InvalidPublicKey)?;
        if signing_key.is_weak() {
            return Err(ProtocolError::InvalidPublicKey);
        }

        Ok(Self {
            old_peer_id,
            new_noise_public_key,
            new_signing_public_key,
            timestamp,
            sequence,
            authorization_signature,
        })
    }

    pub fn new_peer_id(&self) -> [u8; 8] {
        Sha256::digest(self.new_noise_public_key)[..8]
            .try_into()
            .expect("SHA-256 siempre produce al menos ocho bytes")
    }

    pub fn authorization_bytes(&self) -> Vec<u8> {
        let mut output = Vec::with_capacity(KEY_ROTATION_DOMAIN.len() + UNSIGNED_SIZE);
        output.extend_from_slice(KEY_ROTATION_DOMAIN);
        output.push(VERSION);
        output.extend_from_slice(&self.old_peer_id);
        output.extend_from_slice(&self.new_noise_public_key);
        output.extend_from_slice(&self.new_signing_public_key);
        output.extend_from_slice(&self.timestamp.to_be_bytes());
        output.extend_from_slice(&self.sequence.to_be_bytes());
        output
    }

    pub fn verify_authorization(
        &self,
        old_signing_public_key: &[u8; 32],
    ) -> Result<(), ProtocolError> {
        let verifying_key = VerifyingKey::from_bytes(old_signing_public_key)
            .map_err(|_| ProtocolError::InvalidPublicKey)?;
        let signature = Signature::from_bytes(&self.authorization_signature);
        verifying_key
            .verify_strict(&self.authorization_bytes(), &signature)
            .map_err(|_| ProtocolError::SignatureVerificationFailed)
    }
}
