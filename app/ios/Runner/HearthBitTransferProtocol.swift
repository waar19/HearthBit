import Foundation

/// Codec del HearthBit Transfer Protocol (HBT) v1.
///
/// Formato: `[versión u8][tipo u8][TLV...]` con TLV `[tag u8][len u16][valor]`
/// big-endian y tags en orden ascendente. Debe producir exactamente los mismos
/// bytes que los codecs Dart y Kotlin. Ver `docs/transfer-protocol.md`.
enum HBTransferProtocol {
  static let version: UInt8 = 0x01

  static let typeOffer: UInt8 = 0x01
  static let typeAccept: UInt8 = 0x02
  static let typeReject: UInt8 = 0x03
  static let typeTransportHint: UInt8 = 0x04
  static let typeProgress: UInt8 = 0x05
  static let typeComplete: UInt8 = 0x06
  static let typeCancel: UInt8 = 0x07
  static let typeResumeRequest: UInt8 = 0x08
  static let typeDataChunk: UInt8 = 0x10
  static let typeDataAck: UInt8 = 0x11

  static let tagTransferId: UInt8 = 0x01
  static let tagFileName: UInt8 = 0x02
  static let tagMimeType: UInt8 = 0x03
  static let tagFileSize: UInt8 = 0x04
  static let tagSha256: UInt8 = 0x05
  static let tagChunkSize: UInt8 = 0x06
  static let tagTransports: UInt8 = 0x07
  static let tagEphemeralKey: UInt8 = 0x08
  static let tagExpiresAt: UInt8 = 0x09
  static let tagSenderPeerId: UInt8 = 0x0A
  static let tagSignature: UInt8 = 0x0B
  static let tagTransport: UInt8 = 0x0C
  static let tagEndpoint: UInt8 = 0x0D
  static let tagToken: UInt8 = 0x0E
  static let tagChunkIndex: UInt8 = 0x0F
  static let tagChunkData: UInt8 = 0x10
  static let tagChunkBitmap: UInt8 = 0x11
  static let tagReason: UInt8 = 0x12
  static let tagReceivedCount: UInt8 = 0x14
}

struct HBTransferFrame {
  let type: UInt8
  var tags: [UInt8: Data]

  init(type: UInt8, tags: [UInt8: Data] = [:]) {
    self.type = type
    self.tags = tags
  }

  static func decode(_ input: Data) -> HBTransferFrame? {
    let bytes = [UInt8](input)
    guard bytes.count >= 2, bytes[0] == HBTransferProtocol.version else { return nil }
    var frame = HBTransferFrame(type: bytes[1])
    var offset = 2
    while offset + 3 <= bytes.count {
      let tag = bytes[offset]
      let length = Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
      offset += 3
      guard offset + length <= bytes.count else { return nil }
      frame.tags[tag] = Data(bytes[offset..<(offset + length)])
      offset += length
    }
    return offset == bytes.count ? frame : nil
  }

  func encode() -> Data {
    var output = Data([HBTransferProtocol.version, type])
    for tag in tags.keys.sorted() {
      let value = tags[tag]!
      precondition(value.count <= 0xFFFF, "TLV \(tag) exceeds 65535 bytes")
      output.append(tag)
      output.append(UInt8(value.count >> 8))
      output.append(UInt8(value.count & 0xFF))
      output.append(value)
    }
    return output
  }

  /// Bytes cubiertos por la firma Ed25519 (sin el TLV SIGNATURE).
  func signedBytes() -> Data {
    var unsigned = self
    unsigned.tags.removeValue(forKey: HBTransferProtocol.tagSignature)
    return unsigned.encode()
  }

  func utf8(_ tag: UInt8) -> String? {
    guard let value = tags[tag] else { return nil }
    return String(data: value, encoding: .utf8)
  }

  func u8(_ tag: UInt8) -> UInt8? {
    guard let value = tags[tag], value.count == 1 else { return nil }
    return value[value.startIndex]
  }

  func u32(_ tag: UInt8) -> UInt32? {
    guard let value = tags[tag], value.count == 4 else { return nil }
    return value.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }

  func u64(_ tag: UInt8) -> UInt64? {
    guard let value = tags[tag], value.count == 8 else { return nil }
    return value.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
  }

  mutating func setUtf8(_ tag: UInt8, _ value: String) {
    tags[tag] = Data(value.utf8)
  }

  mutating func setU8(_ tag: UInt8, _ value: UInt8) {
    tags[tag] = Data([value])
  }

  mutating func setU32(_ tag: UInt8, _ value: UInt32) {
    tags[tag] = Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ((3 - $0) * 8)) })
  }

  mutating func setU64(_ tag: UInt8, _ value: UInt64) {
    tags[tag] = Data((0..<8).map { UInt8(truncatingIfNeeded: value >> ((7 - $0) * 8)) })
  }
}
