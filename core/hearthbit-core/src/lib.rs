//! Núcleo portable para decodificar y autenticar frames HearthBit.
//!
//! Esta fase expone una biblioteca Rust pura. No incluye FFI ni sustituye
//! todavía los codecs nativos de Android, iOS o Dart.

mod key_rotation;
mod packet;

pub use key_rotation::{KEY_ROTATION_DOMAIN, KEY_ROTATION_PAYLOAD_SIZE, KeyRotation};
pub use packet::{
    FLAG_DRILL, FLAG_HAS_RECIPIENT, FLAG_HAS_ROUTE, FLAG_HAS_SIGNATURE, FLAG_IS_COMPRESSED,
    FLAG_RSR, MAX_PAYLOAD_LENGTH, Packet, ProtocolError,
};
