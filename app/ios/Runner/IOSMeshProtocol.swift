import Compression
import CryptoKit
import Foundation
import zlib

enum IOSMeshNodeRole: String, CaseIterable {
  case phoneRelay = "PHONE_RELAY"
  case phoneBeacon = "PHONE_BEACON"
  case infraRelay = "INFRA_RELAY"
  case infraDataAnchor = "INFRA_DATA_ANCHOR"

  private static let defaultsKey = "hearthbit.node_role"
  private static let capabilityVersion: UInt8 = 1
  static let longRangeTrunkFlag: UInt8 = 0x10

  var code: UInt8 {
    switch self {
    case .phoneRelay: return 1
    case .phoneBeacon: return 2
    case .infraRelay: return 3
    case .infraDataAnchor: return 4
    }
  }

  var relaysPackets: Bool {
    self != .phoneBeacon
  }

  var allowsDataPlane: Bool {
    self != .phoneBeacon
  }

  var canChat: Bool {
    self == .phoneRelay
  }

  var storesDirectedPackets: Bool {
    self == .phoneRelay || self == .infraDataAnchor
  }

  var isInfrastructure: Bool {
    self == .infraRelay || self == .infraDataAnchor
  }

  var capabilityPayload: Data {
    capabilityPayload(hasLongRangeTrunk: false)
  }

  func capabilityPayload(hasLongRangeTrunk: Bool) -> Data {
    var flags: UInt8 = 0
    if relaysPackets { flags |= 0x01 }
    if canChat { flags |= 0x02 }
    if storesDirectedPackets { flags |= 0x04 }
    if self == .phoneBeacon { flags |= 0x08 }
    if hasLongRangeTrunk { flags |= Self.longRangeTrunkFlag }
    return Data([Self.capabilityVersion, code, flags])
  }

  func persist() {
    UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
  }

  static func load() -> IOSMeshNodeRole {
    guard
      let value = UserDefaults.standard.string(forKey: defaultsKey),
      let role = IOSMeshNodeRole(rawValue: value)
    else { return .phoneRelay }
    return role
  }

  static func decodeCapability(_ payload: Data) -> IOSNodeCapability? {
    guard payload.count == 3, payload[0] == capabilityVersion else { return nil }
    let role: IOSMeshNodeRole
    switch payload[1] {
    case 1: role = .phoneRelay
    case 2: role = .phoneBeacon
    case 3: role = .infraRelay
    case 4: role = .infraDataAnchor
    default: return nil
    }
    return IOSNodeCapability(role: role, flags: payload[2])
  }
}
struct IOSNodeCapability {
  let role: IOSMeshNodeRole
  let flags: UInt8

  var hasLongRangeTrunk: Bool {
    flags & IOSMeshNodeRole.longRangeTrunkFlag != 0
  }
}
struct IOSMeshPeer {
  let id: String
  let nickname: String
  let noisePublicKey: Data
  let signingPublicKey: Data
  var supportsTransfers: Bool
  var hearthbitVerified: Bool
  var supportsEmergencyAck: Bool
  var isInfrastructure: Bool
  var role: IOSMeshNodeRole
  var hasLongRangeTrunk: Bool
  var lastSeen: Date
}
struct IOSRemoteRadarConsent {
  let expiresAt: UInt64
  let source: String
}

struct IOSPendingBeaconRequest {
  let peerID: String
  let nickname: String
  let control: IOSBeaconControlProtocol.Control
}

struct IOSOutgoingBeaconRequest {
  let peerID: String
  let expiresAt: UInt64
  let flags: UInt8
}

enum IOSBeaconControlProtocol {
  static let version: UInt8 = 1
  static let initialTTL: UInt8 = 2
  static let requestAction: UInt8 = 1
  static let grantAction: UInt8 = 2
  static let revokeAction: UInt8 = 3
  static let stopAction: UInt8 = 4
  static let flashFlag: UInt8 = 0x01
  static let soundFlag: UInt8 = 0x02
  static let vibrateFlag: UInt8 = 0x04
  static let allowedFlags = flashFlag | soundFlag | vibrateFlag
  static let nonceSize = 16
  static let payloadSize = 27
  static let maximumDurationMilliseconds: UInt64 = 5 * 60 * 1000
  static let clockSkewMilliseconds: UInt64 = 2 * 60 * 1000

  struct Control {
    let action: UInt8
    let expiresAt: UInt64
    let nonce: Data
    let flags: UInt8
  }

  static func request(expiresAt: UInt64, flags: UInt8) -> Data? {
    guard let nonce = IOSSecureRandom.data(count: nonceSize) else { return nil }
    return request(expiresAt: expiresAt, flags: flags, nonce: nonce)
  }

  static func request(expiresAt: UInt64, flags: UInt8, nonce: Data) -> Data {
    encode(action: requestAction, expiresAt: expiresAt, nonce: nonce, flags: flags)
  }

  static func grant(expiresAt: UInt64, flags: UInt8, nonce: Data) -> Data {
    encode(action: grantAction, expiresAt: expiresAt, nonce: nonce, flags: flags)
  }

  static func revoke(nonce: Data) -> Data {
    encode(action: revokeAction, expiresAt: 0, nonce: nonce, flags: 0)
  }

  static func stop(nonce: Data) -> Data {
    encode(action: stopAction, expiresAt: 0, nonce: nonce, flags: 0)
  }

  static func decode(_ payload: Data) -> Control? {
    guard payload.count == payloadSize else { return nil }
    var reader = DataReader(payload)
    guard
      reader.byte() == version,
      let action = reader.byte(),
      [requestAction, grantAction, revokeAction, stopAction].contains(action),
      let expiresAt: UInt64 = reader.integer(),
      let nonce = reader.data(count: nonceSize),
      let flags = reader.byte(),
      reader.remaining.isEmpty,
      flags & ~allowedFlags == 0
    else { return nil }
    let terminal = action == revokeAction || action == stopAction
    guard (terminal
      ? expiresAt == 0 && flags == 0
      : expiresAt > 0 && flags != 0)
    else { return nil }
    return Control(action: action, expiresAt: expiresAt, nonce: nonce, flags: flags)
  }

  static func isValid(
    _ control: Control,
    packetTimestamp: UInt64,
    now: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
  ) -> Bool {
    guard hasValidTimestamp(packetTimestamp, now: now) else { return false }
    switch control.action {
    case requestAction, grantAction:
      return control.expiresAt > now &&
        control.expiresAt <= now + maximumDurationMilliseconds
    case revokeAction, stopAction:
      return control.expiresAt == 0 && control.flags == 0
    default:
      return false
    }
  }

  static func hasValidTimestamp(_ timestamp: UInt64, now: UInt64) -> Bool {
    let earliest = now > clockSkewMilliseconds ? now - clockSkewMilliseconds : 0
    return timestamp >= earliest && timestamp <= now + clockSkewMilliseconds
  }

  static func shouldAutoAccept(
    rescueModeActive: Bool,
    localRadarConsentUntil: UInt64,
    hearthbitVerified: Bool,
    knownRelationship: Bool,
    now: UInt64
  ) -> Bool {
    hearthbitVerified &&
      knownRelationship &&
      (rescueModeActive || localRadarConsentUntil > now)
  }

  static func isValidTTL(_ ttl: UInt8) -> Bool {
    ttl == 1 || ttl == initialTTL
  }

  private static func encode(
    action: UInt8,
    expiresAt: UInt64,
    nonce: Data,
    flags: UInt8
  ) -> Data {
    precondition(nonce.count == nonceSize)
    precondition(flags & ~allowedFlags == 0)
    var output = Data([version, action])
    output.appendInteger(expiresAt)
    output.append(nonce)
    output.append(flags)
    return output
  }

}

enum IOSRangingControlProtocol {
  static let version: UInt8 = 1
  static let nonceSize = 16
  static let fixedSize = 38
  static let maximumOpaqueBytes = 1024
  static let clockSkewMilliseconds: UInt64 = 2 * 60 * 1000
  static let maximumAction: UInt8 = 10
  static let maximumTechnology: UInt8 = 4

  struct Control {
    let action: UInt8
    let technology: UInt8
    let sessionNonce: Data
  }

  static func decode(_ payload: Data) -> Control? {
    guard payload.count >= fixedSize else { return nil }
    var reader = DataReader(payload)
    guard
      reader.byte() == version,
      let action = reader.byte(),
      action > 0 && action <= maximumAction,
      let technology = reader.byte(),
      technology <= maximumTechnology,
      reader.byte() != nil,
      let nonce = reader.data(count: nonceSize),
      reader.skip(16),
      let opaqueLength: UInt16 = reader.integer(),
      Int(opaqueLength) <= maximumOpaqueBytes,
      payload.count == fixedSize + Int(opaqueLength)
    else { return nil }
    return Control(action: action, technology: technology, sessionNonce: nonce)
  }

  static func hasValidTimestamp(_ timestamp: UInt64, now: UInt64) -> Bool {
    let earliest = now > clockSkewMilliseconds ? now - clockSkewMilliseconds : 0
    return timestamp >= earliest && timestamp <= now + clockSkewMilliseconds
  }
}

enum IOSRadarConsentProtocol {
  static let localConsentKey = "hearthbit.radar_consent_until"
  static let version: UInt8 = 1
  static let grantAction: UInt8 = 1
  static let revokeAction: UInt8 = 2
  static let rssiReportAction: UInt8 = 3
  static let nonceSize = 16
  static let payloadSize = 26
  static let rssiReportPayloadSize = 27
  static let manualDurationMilliseconds: UInt64 = 15 * 60 * 1000
  static let sosDurationMilliseconds: UInt64 = 30 * 60 * 1000
  static let maximumGrantMilliseconds: UInt64 = 30 * 60 * 1000
  static let clockSkewMilliseconds: UInt64 = 2 * 60 * 1000

  struct Consent {
    let action: UInt8
    let expiresAt: UInt64
    let nonce: Data
  }

  struct RssiReport {
    let rssi: Int
    let measuredAt: UInt64
    let nonce: Data
  }

  static func grant(expiresAt: UInt64) -> Data? {
    encode(action: grantAction, expiresAt: expiresAt)
  }

  static func revoke() -> Data? {
    encode(action: revokeAction, expiresAt: 0)
  }

  static func rssiReport(rssi: Int, measuredAt: UInt64) -> Data? {
    guard
      (-127...20).contains(rssi),
      let nonce = IOSSecureRandom.data(count: nonceSize)
    else { return nil }
    var output = Data([
      version,
      rssiReportAction,
      UInt8(bitPattern: Int8(rssi)),
    ])
    output.appendInteger(measuredAt)
    output.append(nonce)
    return output
  }

  static func decode(_ payload: Data) -> Consent? {
    guard payload.count == payloadSize else { return nil }
    var reader = DataReader(payload)
    guard
      reader.byte() == version,
      let action = reader.byte(),
      action == grantAction || action == revokeAction,
      let expiresAt: UInt64 = reader.integer(),
      let nonce = reader.data(count: nonceSize),
      (action != revokeAction || expiresAt == 0)
    else { return nil }
    return Consent(action: action, expiresAt: expiresAt, nonce: nonce)
  }

  static func decodeRssiReport(_ payload: Data) -> RssiReport? {
    guard payload.count == rssiReportPayloadSize else { return nil }
    var reader = DataReader(payload)
    guard
      reader.byte() == version,
      reader.byte() == rssiReportAction,
      let encodedRssi = reader.byte(),
      let measuredAt: UInt64 = reader.integer(),
      let nonce = reader.data(count: nonceSize)
    else { return nil }
    let rssi = Int(Int8(bitPattern: encodedRssi))
    guard (-127...20).contains(rssi) else { return nil }
    return RssiReport(rssi: rssi, measuredAt: measuredAt, nonce: nonce)
  }

  static func hasValidTimestamp(_ timestamp: UInt64, now: UInt64) -> Bool {
    timestamp <= saturatingAdd(now, clockSkewMilliseconds) &&
      saturatingAdd(timestamp, clockSkewMilliseconds) >= now
  }

  static func isValidGrant(
    _ consent: Consent,
    packetTimestamp: UInt64,
    now: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
  ) -> Bool {
    consent.action == grantAction &&
      hasValidTimestamp(packetTimestamp, now: now) &&
      consent.expiresAt > now &&
      consent.expiresAt <= saturatingAdd(
        saturatingAdd(now, maximumGrantMilliseconds),
        clockSkewMilliseconds
      )
  }

  static func isValidReport(
    _ report: RssiReport,
    packetTimestamp: UInt64,
    now: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
  ) -> Bool {
    hasValidTimestamp(packetTimestamp, now: now) &&
      hasValidTimestamp(report.measuredAt, now: now)
  }

  static func sosConsentExpiresAt(packetTimestamp: UInt64, now: UInt64) -> UInt64 {
    min(
      saturatingAdd(packetTimestamp, sosDurationMilliseconds),
      saturatingAdd(now, sosDurationMilliseconds)
    )
  }

  private static func saturatingAdd(_ value: UInt64, _ increment: UInt64) -> UInt64 {
    let (result, overflow) = value.addingReportingOverflow(increment)
    return overflow ? UInt64.max : result
  }

  private static func encode(action: UInt8, expiresAt: UInt64) -> Data? {
    guard let nonce = IOSSecureRandom.data(count: nonceSize) else { return nil }
    var output = Data([version, action])
    output.appendInteger(expiresAt)
    output.append(nonce)
    return output
  }
}
struct IOSMeshPacket {
  var version: UInt8 = 1
  var type: UInt8
  var ttl: UInt8
  var timestamp: UInt64
  var senderID: Data
  var recipientID: Data?
  var payload: Data
  var signature: Data?
  var route: [Data] = []
  var isRSR = false
  var isDrill = false

  func canonical() -> Data {
    var copy = self
    copy.ttl = 0
    copy.signature = nil
    copy.isRSR = false
    return IOSMeshProtocol.encode(copy, padded: true)
  }
}
enum IOSMeshProtocol {
  static let announce: UInt8 = 0x01
  static let message: UInt8 = 0x02
  static let courierEnvelope: UInt8 = 0x04
  static let noiseHandshake: UInt8 = 0x10
  static let noiseEncrypted: UInt8 = 0x11
  static let fragment: UInt8 = 0x20
  static let requestSync: UInt8 = 0x21
  static let radarControl: UInt8 = 0x23
  static let legacyHbtCapability: UInt8 = 0x24
  static let nodeCapability: UInt8 = 0x25
  static let beaconControl: UInt8 = 0x26
  static let rangingControl: UInt8 = 0x27
  static let emergencyCapability: UInt8 = 0x28
  static let legacyEmergencyAck: UInt8 = 0x29
  static let hbtCapability: UInt8 = 0x2A
  static let emergencyAck: UInt8 = 0x2B
  static let keyRotation: UInt8 = 0x2C
  static let emergencyVersion: UInt8 = 0x01
  static let hbtVersion: UInt8 = 0x01
  static let noisePrivate: UInt8 = 0x01
  /// Trama HBT (HearthBit Transfer) encapsulada dentro de la sesión Noise.
  static let noiseTransferFrame: UInt8 = 0x30
  static let defaultTTL: UInt8 = 7
  static let drillFlag: UInt8 = 0x20

  struct PublicMessage {
    let id: String
    let sender: String
    let content: String
    let timestamp: UInt64
    let channel: String?
  }

  struct Announcement {
    let nickname: String
    let noisePublicKey: Data
    let signingPublicKey: Data
    let supportsTransfers: Bool
    let isInfrastructure: Bool
    let emergencyPreannounce: Bool
  }

  struct PrivateMessage {
    let id: String
    let content: String
  }

  struct SyncRequest {
    let p: Int
    let m: UInt64
    let filter: Data
    let typeFlags: UInt64
    let since: UInt64?
  }

  struct CourierEnvelope {
    let recipientTag: Data
    let expiry: UInt64
    let ciphertext: Data
    let copies: UInt8
  }

  static func emergencyCanonicalHash(_ packet: IOSMeshPacket) -> Data {
    var normalized = packet
    normalized.ttl = 0
    normalized.isRSR = false
    return Data(SHA256.hash(data: encode(normalized, padded: false)))
  }

  static func isEmergency(_ packet: IOSMeshPacket) -> Bool {
    guard packet.type == message, !packet.isDrill,
          let content = String(data: packet.payload, encoding: .utf8)
    else { return false }
    return content.hasPrefix("SOS|") || content.contains("[HB-CHECKIN|")
  }

  static func isDrill(_ packet: IOSMeshPacket) -> Bool {
    guard packet.type == message, packet.isDrill,
          let content = String(data: packet.payload, encoding: .utf8)
    else { return false }
    return isDrillPayload(content)
  }

  static func isDrillPayload(_ content: String) -> Bool {
    let marker = "[HB-DRILL|1|CHECKIN|"
    guard
      !content.hasPrefix("SOS|"),
      !content.contains("[HB-CHECKIN|"),
      content.hasSuffix("]"),
      let range = content.range(of: marker, options: .backwards),
      range.lowerBound > content.startIndex
    else { return false }
    let end = content.index(before: content.endIndex)
    let fields = content[range.upperBound..<end].split(
      separator: "|",
      omittingEmptySubsequences: false
    )
    guard
      fields.count == 2,
      ["OK", "HELP", "INJURED"].contains(String(fields[0])),
      !fields[1].isEmpty,
      fields[1].allSatisfy(\.isNumber),
      let timestamp = UInt64(String(fields[1])),
      timestamp > 0
    else { return false }
    return true
  }

  static func emergencyCapabilityPayload() -> Data {
    Data([emergencyVersion, 0x01])
  }

  static func supportsEmergencyAcknowledgements(_ payload: Data) -> Bool {
    payload.count == 2 &&
      payload[0] == emergencyVersion &&
      payload[1] & 0x01 != 0
  }

  static func emergencyAcknowledgementPayload(hash: Data) -> Data {
    guard hash.count == 32 else { return Data() }
    return Data([emergencyVersion]) + hash
  }

  static func decodeEmergencyAcknowledgement(_ payload: Data) -> Data? {
    guard payload.count == 33, payload[0] == emergencyVersion else { return nil }
    return payload.subdata(in: 1..<33)
  }

  struct FragmentPayload {
    let fragmentID: Data
    let index: Int
    let total: Int
    let originalType: UInt8
    let data: Data
  }

  struct ExtensionEnvelope {
    let namespace: String
    let subtype: UInt16
    let version: UInt8
    let flags: UInt8
    let payload: Data
  }

  struct KeyRotation {
    static let version: UInt8 = 1
    static let payloadSize = 153
    static let clockWindowMilliseconds: UInt64 = 10 * 60 * 1_000
    static let domain = Data("HearthBitKeyRotationV1".utf8)

    let oldPeerID: Data
    let newNoisePublicKey: Data
    let newSigningPublicKey: Data
    let timestamp: UInt64
    let sequence: UInt64
    let authorizationSignature: Data

    var newPeerID: Data { IOSMeshProtocol.peerID(newNoisePublicKey) }

    var authorizationBytes: Data {
      Self.domain + IOSMeshProtocol.keyRotationUnsigned(
        oldPeerID: oldPeerID,
        newNoisePublicKey: newNoisePublicKey,
        newSigningPublicKey: newSigningPublicKey,
        timestamp: timestamp,
        sequence: sequence
      )
    }

    func timestampIsCurrent(now: UInt64) -> Bool {
      let delta = timestamp >= now ? timestamp - now : now - timestamp
      return delta <= Self.clockWindowMilliseconds
    }
  }

  static func decodeKeyRotation(_ payload: Data) -> KeyRotation? {
    guard payload.count == KeyRotation.payloadSize else { return nil }
    var reader = DataReader(payload)
    guard
      reader.byte() == KeyRotation.version,
      let oldPeerID = reader.data(count: 8),
      let noise = reader.data(count: 32),
      noise.contains(where: { $0 != 0 }),
      let signing = reader.data(count: 32),
      signing.contains(where: { $0 != 0 }),
      let timestamp: UInt64 = reader.integer(),
      let sequence: UInt64 = reader.integer(),
      sequence > 0,
      let signature = reader.data(count: 64),
      reader.remaining.isEmpty,
      (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: noise)) != nil,
      (try? Curve25519.Signing.PublicKey(rawRepresentation: signing)) != nil
    else { return nil }
    return KeyRotation(
      oldPeerID: oldPeerID,
      newNoisePublicKey: noise,
      newSigningPublicKey: signing,
      timestamp: timestamp,
      sequence: sequence,
      authorizationSignature: signature
    )
  }

  static func keyRotationPayload(
    oldPeerID: Data,
    newNoisePublicKey: Data,
    newSigningPublicKey: Data,
    timestamp: UInt64,
    sequence: UInt64,
    authorizationSignature: Data
  ) -> Data {
    precondition(authorizationSignature.count == 64)
    return keyRotationUnsigned(
      oldPeerID: oldPeerID,
      newNoisePublicKey: newNoisePublicKey,
      newSigningPublicKey: newSigningPublicKey,
      timestamp: timestamp,
      sequence: sequence
    ) + authorizationSignature
  }

  private static func keyRotationUnsigned(
    oldPeerID: Data,
    newNoisePublicKey: Data,
    newSigningPublicKey: Data,
    timestamp: UInt64,
    sequence: UInt64
  ) -> Data {
    precondition(oldPeerID.count == 8)
    precondition(newNoisePublicKey.count == 32)
    precondition(newSigningPublicKey.count == 32)
    precondition(sequence > 0)
    var output = Data([KeyRotation.version])
    output.append(oldPeerID)
    output.append(newNoisePublicKey)
    output.append(newSigningPublicKey)
    output.appendInteger(timestamp)
    output.appendInteger(sequence)
    return output
  }

  static func decodeExtensionEnvelope(_ input: Data) -> ExtensionEnvelope? {
    guard input.count >= 12 else { return nil }
    var reader = DataReader(input)
    guard
      let namespaceData = reader.data(count: 4),
      namespaceData.allSatisfy({ (0x20...0x7e).contains($0) }),
      let namespace = String(data: namespaceData, encoding: .ascii),
      let subtype: UInt16 = reader.integer(),
      let version = reader.byte(),
      let flags = reader.byte(),
      flags & 0xfc == 0,
      let length: UInt32 = reader.integer(),
      Int(length) <= maximumPayloadLength,
      let payload = reader.data(count: Int(length)),
      reader.remaining.isEmpty
    else { return nil }
    return ExtensionEnvelope(
      namespace: namespace,
      subtype: subtype,
      version: version,
      flags: flags,
      payload: payload
    )
  }

  static func encodeFragmentPayload(_ fragment: FragmentPayload) -> Data? {
    guard
      fragment.fragmentID.count == fragmentIDSize,
      (0...Int(UInt16.max)).contains(fragment.index),
      (1...Int(UInt16.max)).contains(fragment.total),
      fragment.index < fragment.total
    else { return nil }
    var output = fragment.fragmentID
    output.appendInteger(UInt16(fragment.index))
    output.appendInteger(UInt16(fragment.total))
    output.append(fragment.originalType)
    output.append(fragment.data)
    return output
  }

  static func decodeFragmentPayload(_ payload: Data) -> FragmentPayload? {
    guard payload.count >= fragmentHeaderSize else { return nil }
    var reader = DataReader(payload)
    guard
      let fragmentID = reader.data(count: fragmentIDSize),
      let index: UInt16 = reader.integer(),
      let total: UInt16 = reader.integer(),
      total > 0,
      index < total,
      let originalType = reader.byte()
    else { return nil }
    return FragmentPayload(
      fragmentID: fragmentID,
      index: Int(index),
      total: Int(total),
      originalType: originalType,
      data: reader.remaining
    )
  }

  static func encode(_ packet: IOSMeshPacket, padded: Bool = true) -> Data {
    precondition(packet.version == 1 || packet.version == 2)
    precondition(packet.version >= 2 || packet.route.isEmpty)
    precondition(packet.route.count <= 255 && packet.route.allSatisfy { $0.count == 8 })
    var payload = packet.payload
    var originalPayloadSize: Int?
    if !packet.isDrill, shouldCompress(payload), let compressed = compress(payload) {
      originalPayloadSize = payload.count
      payload = compressed
    }
    var flags: UInt8 = 0
    if packet.recipientID != nil { flags |= 0x01 }
    if packet.signature != nil { flags |= 0x02 }
    if originalPayloadSize != nil { flags |= 0x04 }
    if packet.version >= 2 && !packet.route.isEmpty { flags |= 0x08 }
    if packet.isRSR { flags |= 0x10 }
    if packet.isDrill { flags |= drillFlag }
    precondition(validDrillShape(packet, flags: flags))
    var output = Data([
      packet.version,
      packet.type,
      packet.ttl,
    ])
    output.appendInteger(packet.timestamp)
    output.append(flags)
    let originalSizeField = originalPayloadSize == nil ? 0 : (packet.version >= 2 ? 4 : 2)
    let payloadDataSize = payload.count + originalSizeField
    if packet.version >= 2 {
      output.appendInteger(UInt32(payloadDataSize))
    } else {
      output.appendInteger(UInt16(payloadDataSize))
    }
    output.append(packet.senderID)
    if let recipient = packet.recipientID { output.append(recipient) }
    if packet.version >= 2 && !packet.route.isEmpty {
      output.append(UInt8(packet.route.count))
      packet.route.forEach { output.append($0) }
    }
    if let originalPayloadSize {
      if packet.version >= 2 {
        output.appendInteger(UInt32(originalPayloadSize))
      } else {
        output.appendInteger(UInt16(originalPayloadSize))
      }
    }
    output.append(payload)
    if let signature = packet.signature { output.append(signature) }
    return padded ? pad(output) : output
  }

  static func encodeForBLE(_ packet: IOSMeshPacket) -> Data {
    encode(
      packet,
      padded: packet.type == noiseHandshake || packet.type == noiseEncrypted
    )
  }

  static func removeBLETransportPadding(_ packet: IOSMeshPacket, encoded: Data) -> Data {
    guard packet.type == noiseHandshake || packet.type == noiseEncrypted else {
      return encoded
    }
    let rawSize = encode(packet, padded: false).count
    guard encoded.count > rawSize else { return encoded }
    let unpadded = unpad(encoded)
    return unpadded.count == rawSize ? unpadded : encoded
  }

  static func decode(_ encoded: Data) -> IOSMeshPacket? {
    decodeRaw(encoded) ?? decodeRaw(unpad(encoded))
  }

  private static func decodeRaw(_ encoded: Data) -> IOSMeshPacket? {
    guard encoded.count >= 22 else { return nil }
    var reader = DataReader(encoded)
    guard
      let version = reader.byte(),
      version == 1 || version == 2,
      let type = reader.byte(),
      let ttl = reader.byte(),
      let timestamp: UInt64 = reader.integer(),
      let flags = reader.byte()
    else { return nil }
    let payloadLength: Int
    if version >= 2 {
      guard let length: UInt32 = reader.integer() else { return nil }
      payloadLength = Int(length)
    } else {
      guard let length: UInt16 = reader.integer() else { return nil }
      payloadLength = Int(length)
    }
    guard let sender = reader.data(count: 8) else { return nil }
    let recipient = flags & 0x01 != 0 ? reader.data(count: 8) : nil
    var route: [Data] = []
    if version >= 2, flags & 0x08 != 0 {
      guard let count = reader.byte() else { return nil }
      for _ in 0..<count {
        guard let hop = reader.data(count: 8) else { return nil }
        route.append(hop)
      }
    }
    guard let payloadData = reader.data(count: payloadLength) else { return nil }
    let payload: Data
    if flags & 0x04 != 0 {
      var compressedReader = DataReader(payloadData)
      let originalSize: Int
      if version >= 2 {
        guard let size: UInt32 = compressedReader.integer() else { return nil }
        originalSize = Int(size)
      } else {
        guard let size: UInt16 = compressedReader.integer() else { return nil }
        originalSize = Int(size)
      }
      guard
        originalSize > 0,
        originalSize <= maximumPayloadLength,
        !compressedReader.remaining.isEmpty,
        let expanded = decompress(
          compressedReader.remaining,
          originalSize: originalSize
        ),
        expanded.count == originalSize
      else { return nil }
      payload = expanded
    } else {
      payload = payloadData
    }
    let signature = flags & 0x02 != 0 ? reader.data(count: 64) : nil
    if flags & 0x02 != 0, signature == nil { return nil }
    guard reader.remaining.isEmpty else { return nil }
    let packet = IOSMeshPacket(
      version: version,
      type: type,
      ttl: ttl,
      timestamp: timestamp,
      senderID: sender,
      recipientID: recipient,
      payload: payload,
      signature: signature,
      route: route,
      isRSR: flags & 0x10 != 0,
      isDrill: flags & drillFlag != 0
    )
    guard validDrillShape(packet, flags: flags, requireSignature: true) else {
      return nil
    }
    return packet
  }

  private static func validDrillShape(
    _ packet: IOSMeshPacket,
    flags: UInt8,
    requireSignature: Bool = false
  ) -> Bool {
    let content = String(data: packet.payload, encoding: .utf8) ?? ""
    if !packet.isDrill {
      return packet.type != message || !content.contains("[HB-DRILL|")
    }
    let markedPayload: Bool
    switch packet.type {
    case announce:
      markedPayload = decodeAnnouncement(packet.payload)?.emergencyPreannounce == true
    case message:
      markedPayload = isDrillPayload(content)
    default:
      markedPayload = false
    }
    return packet.version == 1 &&
      (!requireSignature || packet.signature != nil) &&
      packet.recipientID == nil &&
      packet.route.isEmpty &&
      flags & 0x04 == 0 &&
      markedPayload
  }

  static func publicMessage(
    nickname: String,
    peerID: String,
    content: String,
    channel: String?
  ) -> (id: String, data: Data) {
    let id = UUID().uuidString.uppercased()
    var flags: UInt8 = 0x10
    if channel != nil { flags |= 0x40 }
    var output = Data([flags])
    output.appendInteger(UInt64(Date().timeIntervalSince1970 * 1000))
    output.appendByteString(Data(id.utf8))
    output.appendByteString(Data(nickname.utf8))
    let contentData = Data(content.utf8).prefix(65_535)
    output.appendInteger(UInt16(contentData.count))
    output.append(contentData)
    output.appendByteString(Data(peerID.utf8))
    if let channel { output.appendByteString(Data(channel.utf8)) }
    return (id, output)
  }

  static func decodePublicMessage(_ payload: Data) -> PublicMessage? {
    var reader = DataReader(payload)
    guard
      let flags = reader.byte(),
      flags & 0x80 == 0,
      let timestamp: UInt64 = reader.integer(),
      let id = reader.byteString(),
      let sender = reader.byteString(),
      let length: UInt16 = reader.integer(),
      let content = reader.data(count: Int(length))
    else { return nil }
    if flags & 0x04 != 0 { _ = reader.byteString() }
    if flags & 0x08 != 0 { _ = reader.byteString() }
    if flags & 0x10 != 0 { _ = reader.byteString() }
    if flags & 0x20 != 0, let count = reader.byte() {
      for _ in 0..<count { _ = reader.byteString() }
    }
    let channel = flags & 0x40 != 0 ? reader.byteString() : nil
    return PublicMessage(
      id: id,
      sender: sender,
      content: String(data: content, encoding: .utf8) ?? "",
      timestamp: timestamp,
      channel: channel
    )
  }

  static func announcement(
    nickname: String,
    noisePublicKey: Data,
    signingPublicKey: Data,
    emergencyPreannounce: Bool = false
  ) -> Data {
    var output = Data()
    output.appendTLV(type: 0x01, value: Data(nickname.utf8).prefix(31))
    output.appendTLV(type: 0x02, value: noisePublicKey)
    output.appendTLV(type: 0x03, value: signingPublicKey)
    output.appendTLV(type: 0x05, value: Data([0x00]))
    if emergencyPreannounce {
      output.appendTLV(type: 0xF1, value: Data([0x01]))
    }
    return output
  }

  static func decodeAnnouncement(_ payload: Data) -> Announcement? {
    var reader = DataReader(payload)
    var nickname: String?
    var noise: Data?
    var signing: Data?
    var supportsTransfers = false
    var isInfrastructure = false
    var emergencyPreannounce = false
    while let type = reader.byte(), let length = reader.byte(),
          let value = reader.data(count: Int(length)) {
      switch type {
      case 0x01: nickname = String(data: value, encoding: .utf8)
      case 0x02: noise = value
      case 0x03: signing = value
      case 0xF0: supportsTransfers = value == Data([0x01])
      case 0xB1: isInfrastructure = value.first.map { $0 & 0x01 != 0 } ?? false
      case 0xF1: emergencyPreannounce = value == Data([0x01])
      default: break
      }
    }
    guard let nickname, let noise, noise.count == 32,
          let signing, signing.count == 32 else { return nil }
    return Announcement(
      nickname: nickname,
      noisePublicKey: noise,
      signingPublicKey: signing,
      supportsTransfers: supportsTransfers,
      isInfrastructure: isInfrastructure,
      emergencyPreannounce: emergencyPreannounce
    )
  }

  static func privateMessage(id: String, content: String) -> Data {
    var output = Data()
    output.appendTLV(type: 0x00, value: Data(id.utf8).prefix(255))
    output.appendTLV(type: 0x01, value: Data(content.utf8).prefix(255))
    return output
  }

  static func decodePrivateMessage(_ payload: Data.SubSequence) -> PrivateMessage? {
    var reader = DataReader(Data(payload))
    var id: String?
    var content: String?
    while let type = reader.byte(), let length = reader.byte(),
          let value = reader.data(count: Int(length)) {
      switch type {
      case 0x00: id = String(data: value, encoding: .utf8)
      case 0x01: content = String(data: value, encoding: .utf8)
      default: return nil
      }
    }
    guard let id, let content else { return nil }
    return PrivateMessage(id: id, content: content)
  }

  static func packetID(_ packet: IOSMeshPacket) -> Data {
    var input = Data([packet.type])
    input.append(packet.senderID)
    input.appendInteger(packet.timestamp)
    input.append(packet.payload)
    return Data(SHA256.hash(data: input).prefix(16))
  }

  static func encodeSyncRequest(_ packets: [IOSMeshPacket]) -> Data {
    let ids = packets.prefix(syncMaximumElements).map(packetID)
    let m: UInt64 = ids.isEmpty ? 1 : UInt64(ids.count) << syncGCSP
    let buckets = Array(Set(ids.map { gcsBucket(packetID: $0, m: m) })).sorted()
    var output = Data()
    output.appendWideTLV(type: 0x01, value: Data([UInt8(syncGCSP)]))
    var mBytes = Data()
    mBytes.appendInteger(UInt32(m))
    output.appendWideTLV(type: 0x02, value: mBytes)
    output.appendWideTLV(type: 0x03, value: encodeGCS(buckets, p: syncGCSP))
    output.appendWideTLV(type: 0x04, value: Data([UInt8(syncFlagAnnounce | syncFlagMessage)]))
    return output
  }

  static func decodeSyncRequest(_ payload: Data) -> SyncRequest? {
    var reader = DataReader(payload)
    var p: Int?
    var m: UInt64?
    var filter: Data?
    var typeFlags: UInt64?
    var since: UInt64?
    while let type = reader.byte(), let length: UInt16 = reader.integer(),
          let value = reader.data(count: Int(length)) {
      switch type {
      case 0x01 where value.count == 1:
        p = Int(value[0])
      case 0x02 where value.count == 4:
        var valueReader = DataReader(value)
        if let range: UInt32 = valueReader.integer() { m = UInt64(range) }
      case 0x03:
        guard value.count <= syncMaximumAcceptedBytes else { return nil }
        filter = value
      case 0x04:
        var flags: UInt64 = 0
        for (index, byte) in value.prefix(8).enumerated() {
          flags |= UInt64(byte) << (index * 8)
        }
        typeFlags = flags
      case 0x05 where value.count == 8:
        var valueReader = DataReader(value)
        since = valueReader.integer()
      default:
        break
      }
    }
    guard let p, (1...32).contains(p), let m, m > 0, let filter else { return nil }
    return SyncRequest(
      p: p,
      m: m,
      filter: filter,
      typeFlags: typeFlags ?? (syncFlagAnnounce | syncFlagMessage),
      since: since
    )
  }

  static func decodeGCS(_ request: SyncRequest) -> [UInt64] {
    let bytes = [UInt8](request.filter)
    var bitOffset = 0
    func readBit() -> UInt64? {
      guard bitOffset < bytes.count * 8 else { return nil }
      defer { bitOffset += 1 }
      return UInt64((bytes[bitOffset / 8] >> (7 - bitOffset % 8)) & 1)
    }
    var output: [UInt64] = []
    var accumulator: UInt64 = 0
    while output.count < syncMaximumDecodedElements {
      var quotient: UInt64 = 0
      guard var bit = readBit() else { break }
      while bit == 1 {
        quotient += 1
        guard let next = readBit() else { return output }
        bit = next
      }
      var remainder: UInt64 = 0
      for _ in 0..<request.p {
        guard let next = readBit() else { return output }
        remainder = (remainder << 1) | next
      }
      accumulator += (quotient << request.p) + remainder + 1
      if accumulator >= request.m { break }
      output.append(accumulator)
    }
    return output
  }

  static func gcsBucket(packetID: Data, m: UInt64) -> UInt64 {
    guard m > 1 else { return 0 }
    let digest = SHA256.hash(data: packetID)
    var hash: UInt64 = 0
    for byte in digest.prefix(8) { hash = (hash << 8) | UInt64(byte) }
    let value = (hash & (UInt64.max >> 1)) % m
    return value == 0 ? 1 : value
  }

  static func courierEnvelope(
    recipientNoiseKey: Data,
    ciphertext: Data,
    now: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
    expiry: UInt64? = nil,
    copies: UInt8 = 4
  ) -> Data? {
    let envelopeExpiry = expiry ?? now + courierLifetimeMilliseconds
    guard
      recipientNoiseKey.count == 32,
      !ciphertext.isEmpty,
      ciphertext.count <= Int(UInt16.max),
      envelopeExpiry > now,
      envelopeExpiry <= now + courierMaximumLifetimeMilliseconds
    else { return nil }
    var output = Data()
    output.appendWideTLV(
      type: 0x01,
      value: courierTag(noiseKey: recipientNoiseKey, epochDay: now / dayMilliseconds)
    )
    var expiryBytes = Data()
    expiryBytes.appendInteger(envelopeExpiry)
    output.appendWideTLV(type: 0x02, value: expiryBytes)
    output.appendWideTLV(type: 0x03, value: ciphertext)
    if copies > 1 {
      output.appendWideTLV(type: 0x04, value: Data([min(copies, 8)]))
    }
    return output
  }

  static func decodeCourierEnvelope(_ payload: Data) -> CourierEnvelope? {
    var reader = DataReader(payload)
    var tag: Data?
    var expiry: UInt64?
    var ciphertext: Data?
    var copies: UInt8 = 1
    while let type = reader.byte(), let length: UInt16 = reader.integer(),
          let value = reader.data(count: Int(length)) {
      switch type {
      case 0x01 where value.count == 16:
        tag = value
      case 0x02 where value.count == 8:
        var valueReader = DataReader(value)
        expiry = valueReader.integer()
      case 0x03 where !value.isEmpty:
        ciphertext = value
      case 0x04 where value.count == 1:
        copies = min(max(value[0], 1), 8)
      default:
        break
      }
    }
    guard let tag, let expiry, let ciphertext else { return nil }
    return CourierEnvelope(
      recipientTag: tag,
      expiry: expiry,
      ciphertext: ciphertext,
      copies: copies
    )
  }

  static func courierEnvelopeIsFor(
    _ envelope: CourierEnvelope,
    noisePublicKey: Data,
    now: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
  ) -> Bool {
    guard
      noisePublicKey.count == 32,
      envelope.expiry > now,
      envelope.expiry <= now + courierMaximumLifetimeMilliseconds
    else { return false }
    let day = now / dayMilliseconds
    let days = day == 0 ? [0, 1] : [day - 1, day, day + 1]
    return days.contains {
      courierTag(noiseKey: noisePublicKey, epochDay: $0) == envelope.recipientTag
    }
  }

  static func peerID(_ noisePublicKey: Data) -> Data {
    Data(SHA256.hash(data: noisePublicKey).prefix(8))
  }

  /// Huella operativa de relay sobre la representación wire recibida.
  ///
  /// Conserva compresión y bytes opacos, excluye únicamente padding válido y
  /// normaliza TTL/RSR en sitio. No debe sustituirse por decode + encode.
  static func relayFingerprint(_ encoded: Data) -> String? {
    guard encoded.count >= 22 else { return nil }
    let version = encoded[0]
    guard version == 1 || version == 2 else { return nil }
    let flags = encoded[11]
    let headerSize = version == 1 ? 22 : 24
    guard encoded.count >= headerSize else { return nil }

    let payloadSize: Int
    if version == 1 {
      payloadSize = Int(encoded[12]) << 8 | Int(encoded[13])
    } else {
      payloadSize =
        Int(encoded[12]) << 24 |
        Int(encoded[13]) << 16 |
        Int(encoded[14]) << 8 |
        Int(encoded[15])
    }

    var wireSize = headerSize
    if flags & 0x01 != 0 {
      guard wireSize <= Int.max - 8 else { return nil }
      wireSize += 8
    }
    if version == 2, flags & 0x08 != 0 {
      guard wireSize < encoded.count else { return nil }
      let routeBytes = Int(encoded[wireSize]) * 8
      guard wireSize <= Int.max - 1 - routeBytes else { return nil }
      wireSize += 1 + routeBytes
    }
    guard wireSize <= Int.max - payloadSize else { return nil }
    wireSize += payloadSize
    if flags & 0x02 != 0 {
      guard wireSize <= Int.max - 64 else { return nil }
      wireSize += 64
    }
    guard wireSize <= encoded.count else { return nil }

    let paddingCount = encoded.count - wireSize
    if paddingCount > 0 {
      guard
        paddingCount <= 255,
        encoded.suffix(paddingCount).allSatisfy({ $0 == UInt8(paddingCount) })
      else { return nil }
    }

    var canonical = Data(encoded.prefix(wireSize))
    canonical[2] = 0
    canonical[11] &= ~UInt8(0x10)
    return Data(SHA256.hash(data: canonical).prefix(12)).hex
  }

  /// ID semántico local: re-encodea un paquete ya decodificado. No usar para
  /// deduplicación de relay ni para comparar representaciones wire.
  static func fingerprint(_ packet: IOSMeshPacket) -> String {
    var normalized = packet
    normalized.ttl = 0
    normalized.isRSR = false
    return Data(SHA256.hash(data: encode(normalized, padded: false)).prefix(12)).hex
  }

  private static func encodeGCS(_ sorted: [UInt64], p: Int) -> Data {
    var output = Data()
    var current: UInt8 = 0
    var bitCount = 0
    func writeBit(_ bit: UInt8) {
      current = (current << 1) | (bit & 1)
      bitCount += 1
      if bitCount == 8 {
        output.append(current)
        current = 0
        bitCount = 0
      }
    }
    var previous: UInt64 = 0
    for value in sorted {
      let encoded = value - previous - 1
      previous = value
      for _ in 0..<(encoded >> p) { writeBit(1) }
      writeBit(0)
      for shift in stride(from: p - 1, through: 0, by: -1) {
        writeBit(UInt8((encoded >> shift) & 1))
      }
    }
    if bitCount > 0 { output.append(current << (8 - bitCount)) }
    return output
  }

  private static func courierTag(noiseKey: Data, epochDay: UInt64) -> Data {
    var message = Data(courierTagContext.utf8)
    message.appendInteger(UInt32(truncatingIfNeeded: epochDay))
    let authentication = HMAC<SHA256>.authenticationCode(
      for: message,
      using: SymmetricKey(data: noiseKey)
    )
    return Data(authentication.prefix(16))
  }

  private static func pad(_ data: Data) -> Data {
    guard
      let target = [256, 512, 1024, 2048].first(where: { data.count + 16 <= $0 }),
      target - data.count <= 255
    else { return data }
    let count = target - data.count
    return data + Data(repeating: UInt8(count), count: count)
  }

  private static func unpad(_ data: Data) -> Data {
    guard let last = data.last else { return data }
    let count = Int(last)
    guard count > 0, count <= data.count,
          data.suffix(count).allSatisfy({ $0 == last }) else { return data }
    return data.dropLast(count)
  }

  private static func shouldCompress(_ data: Data) -> Bool {
    guard data.count >= compressionThreshold else { return false }
    let uniqueRatio = Double(Set(data).count) / Double(min(data.count, 256))
    return uniqueRatio < 0.9
  }

  private static func compress(_ data: Data) -> Data? {
    let capacity = data.count + (data.count / 255) + 16
    var output = Data(count: capacity)
    let compressedSize = output.withUnsafeMutableBytes { destination in
      data.withUnsafeBytes { source in
        guard
          let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
          let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
        else { return 0 }
        return compression_encode_buffer(
          destinationBase,
          capacity,
          sourceBase,
          data.count,
          nil,
          COMPRESSION_ZLIB
        )
      }
    }
    guard compressedSize > 0, compressedSize < data.count else { return nil }
    output.count = compressedSize
    return output
  }

  private static func decompress(_ data: Data, originalSize: Int) -> Data? {
    if looksLikeZlib(data),
       data.count >= 6,
       let expanded = decompressRawExact(data.dropFirst(2).dropLast(4), originalSize: originalSize),
       adler32(expanded) == data.suffix(4).reduce(UInt32(0), { ($0 << 8) | UInt32($1) }) {
      return expanded
    }
    return decompressRawExact(data, originalSize: originalSize)
  }

  private static func decompressRawExact(
    _ data: Data.SubSequence,
    originalSize: Int
  ) -> Data? {
    guard !data.isEmpty else { return nil }
    var stream = z_stream()
    guard inflateInit2_(
      &stream,
      -MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    ) == Z_OK else { return nil }
    defer { inflateEnd(&stream) }

    var output = Data(count: originalSize)
    let valid = output.withUnsafeMutableBytes { destination in
      data.withUnsafeBytes { source in
        guard
          let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
          let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
        else { return false }
        stream.next_in = UnsafeMutablePointer(mutating: sourceBase)
        stream.avail_in = uInt(data.count)
        stream.next_out = destinationBase
        stream.avail_out = uInt(originalSize)
        return inflate(&stream, Z_FINISH) == Z_STREAM_END &&
          stream.avail_in == 0 &&
          stream.avail_out == 0
      }
    }
    return valid ? output : nil
  }

  private static func looksLikeZlib(_ data: Data) -> Bool {
    guard data.count >= 2 else { return false }
    let cmf = Int(data[data.startIndex])
    let flg = Int(data[data.index(after: data.startIndex)])
    return cmf & 0x0F == 8 &&
      cmf >> 4 <= 7 &&
      ((cmf << 8) | flg).isMultiple(of: 31) &&
      flg & 0x20 == 0
  }

  private static func adler32(_ data: Data) -> UInt32 {
    let modulus: UInt32 = 65_521
    var first: UInt32 = 1
    var second: UInt32 = 0
    for byte in data {
      first = (first + UInt32(byte)) % modulus
      second = (second + first) % modulus
    }
    return (second << 16) | first
  }

  private static let compressionThreshold = 100
  private static let maximumPayloadLength = 10_485_760
  static let fragmentHeaderSize = 13
  static let fragmentIDSize = 8
  static let syncFlagAnnounce: UInt64 = 1 << 0
  static let syncFlagMessage: UInt64 = 1 << 1
  private static let syncGCSP = 7
  private static let syncMaximumElements = 355
  private static let syncMaximumDecodedElements = 1024
  private static let syncMaximumAcceptedBytes = 1024
  private static let dayMilliseconds: UInt64 = 86_400_000
  private static let courierLifetimeMilliseconds: UInt64 = 12 * 60 * 60 * 1000
  private static let courierMaximumLifetimeMilliseconds: UInt64 = 25 * 60 * 60 * 1000
  private static let courierTagContext = "bitchat-courier-tag-v1"
}

extension IOSBLEFramePriority {
  static func forPacket(_ packet: IOSMeshPacket) -> IOSBLEFramePriority {
    if IOSMeshProtocol.isEmergency(packet) ||
       packet.type == IOSMeshProtocol.emergencyAck ||
       packet.type == IOSMeshProtocol.legacyEmergencyAck ||
       packet.type == IOSMeshProtocol.beaconControl {
      return .emergency
    }
    return .normal
  }
}
