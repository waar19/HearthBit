import CryptoKit
import Foundation
import Security

enum IOSSecureRandom {
  static func data(count: Int) -> Data? {
    guard count > 0 else { return nil }
    var output = Data(count: count)
    let status = output.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, count, address)
    }
    return status == errSecSuccess ? output : nil
  }
}
enum IOSSecureStorageError: LocalizedError, Equatable {
  case operationFailed(operation: String, service: String, account: String, status: OSStatus)
  case corruptValue(service: String, account: String)
  case logicalTransactionFailed(String)

  var errorDescription: String? {
    switch self {
    case let .operationFailed(operation, service, account, status):
      return "Keychain \(operation) failed for \(service)/\(account) (OSStatus \(status))"
    case let .corruptValue(service, account):
      return "Keychain contains corrupt data for \(service)/\(account)"
    case let .logicalTransactionFailed(message):
      return message
    }
  }
}

enum IOSKeychainReadResult: Equatable {
  case missing
  case value(Data)
}

enum IOSKeychain {
  static func read(service: String, account: String) throws -> IOSKeychainReadResult {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else {
        throw IOSSecureStorageError.corruptValue(service: service, account: account)
      }
      return .value(data)
    case errSecItemNotFound:
      return .missing
    default:
      throw IOSSecureStorageError.operationFailed(
        operation: "read",
        service: service,
        account: account,
        status: status
      )
    }
  }

  static func upsert(
    _ data: Data,
    service: String,
    account: String,
    accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  ) throws {
    let base: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let updateStatus = SecItemUpdate(
      base as CFDictionary,
      [kSecValueData: data, kSecAttrAccessible: accessible] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw IOSSecureStorageError.operationFailed(
        operation: "update",
        service: service,
        account: account,
        status: updateStatus
      )
    }

    var item = base
    item[kSecValueData] = data
    item[kSecAttrAccessible] = accessible
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    if addStatus == errSecSuccess { return }
    if addStatus == errSecDuplicateItem {
      let retryStatus = SecItemUpdate(
        base as CFDictionary,
        [kSecValueData: data, kSecAttrAccessible: accessible] as CFDictionary
      )
      guard retryStatus == errSecSuccess else {
        throw IOSSecureStorageError.operationFailed(
          operation: "update-after-duplicate",
          service: service,
          account: account,
          status: retryStatus
        )
      }
      return
    }
    throw IOSSecureStorageError.operationFailed(
      operation: "add",
      service: service,
      account: account,
      status: addStatus
    )
  }

  static func delete(service: String, account: String) throws {
    let status = SecItemDelete([
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ] as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw IOSSecureStorageError.operationFailed(
        operation: "delete",
        service: service,
        account: account,
        status: status
      )
    }
  }
}
final class IOSMeshIdentity {
  private static let service = "HearthBit"
  let noisePrivateKey: Curve25519.KeyAgreement.PrivateKey
  let signingPrivateKey: Curve25519.Signing.PrivateKey
  let peerID: Data
  let peerIDHex: String

  // «SOS-XXXX» como nombre por defecto: neutro y comprensible en cualquier
  // idioma, clave ahora que la app está localizada en varios idiomas.
  var nickname: String {
    get {
      UserDefaults.standard.string(forKey: "hearthbit.nickname")
        ?? "SOS-\(peerIDHex.suffix(4))"
    }
    set { UserDefaults.standard.set(newValue, forKey: "hearthbit.nickname") }
  }

  init() throws {
    let noiseStored = try IOSKeychain.read(service: Self.service, account: "noise")
    let signingStored = try IOSKeychain.read(service: Self.service, account: "signing")
    switch (noiseStored, signingStored) {
    case (.missing, .missing):
      let noise = Curve25519.KeyAgreement.PrivateKey()
      let signing = Curve25519.Signing.PrivateKey()
      try IOSKeychain.upsert(
        noise.rawRepresentation,
        service: Self.service,
        account: "noise"
      )
      do {
        try IOSKeychain.upsert(
          signing.rawRepresentation,
          service: Self.service,
          account: "signing"
        )
      } catch {
        do {
          try IOSKeychain.delete(service: Self.service, account: "noise")
        } catch let rollbackError {
          throw IOSSecureStorageError.logicalTransactionFailed(
            "Identity creation failed and rollback also failed: \(error.localizedDescription); " +
              rollbackError.localizedDescription
          )
        }
        throw error
      }
      noisePrivateKey = noise
      signingPrivateKey = signing
    case let (.value(noiseData), .value(signingData)):
      guard
        noiseData.count == 32,
        signingData.count == 32,
        let noise = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: noiseData),
        let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: signingData)
      else {
        throw IOSSecureStorageError.corruptValue(
          service: Self.service,
          account: "identity"
        )
      }
      noisePrivateKey = noise
      signingPrivateKey = signing
    case (.missing, .value(_)), (.value(_), .missing):
      throw IOSSecureStorageError.corruptValue(
        service: Self.service,
        account: "identity-partial"
      )
    }
    peerID = IOSMeshProtocol.peerID(noisePrivateKey.publicKey.rawRepresentation)
    peerIDHex = peerID.hex
  }

  func sign(_ packet: IOSMeshPacket) -> IOSMeshPacket {
    var signed = packet
    signed.signature = try? signingPrivateKey.signature(for: packet.canonical())
    return signed
  }

  static func verify(_ packet: IOSMeshPacket, key: Data) -> Bool {
    guard
      let signature = packet.signature,
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key)
    else { return false }
    return publicKey.isValidSignature(signature, for: packet.canonical())
  }

  /// Firma Ed25519 de bytes arbitrarios (ofertas de transferencia, boletines).
  func signBytes(_ data: Data) throws -> Data {
    try signingPrivateKey.signature(for: data)
  }

  static func verifyBytes(_ data: Data, signature: Data, key: Data) -> Bool {
    guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key)
    else { return false }
    return publicKey.isValidSignature(signature, for: data)
  }

  static func clear() throws {
    for account in ["noise", "signing"] {
      try IOSKeychain.delete(service: service, account: account)
    }
    UserDefaults.standard.removeObject(forKey: "hearthbit.nickname")
    UserDefaults.standard.removeObject(forKey: IOSRadarConsentProtocol.localConsentKey)
  }

}

final class IOSNoiseSession {
  static let maximumSessionAge: TimeInterval = 60 * 60
  private let claimedPeerID: Data
  let initiator: Bool
  private let localStatic: Curve25519.KeyAgreement.PrivateKey
  private var handshake: IOSNoiseHandshake
  private var sendCipher: IOSNoiseCipher?
  private var receiveCipher: IOSNoiseCipher?
  private let now: () -> Date
  private let createdAt: Date

  private(set) var established = false
  var handshaking: Bool { !established }
  var requiresRekey: Bool {
    established &&
      (now().timeIntervalSince(createdAt) >= Self.maximumSessionAge ||
       sendCipher?.requiresRekey == true ||
       receiveCipher?.requiresRekey == true)
  }

  init(
    claimedPeerID: Data,
    initiator: Bool,
    localStatic: Curve25519.KeyAgreement.PrivateKey,
    now: @escaping () -> Date = { Date() }
  ) {
    self.claimedPeerID = claimedPeerID
    self.initiator = initiator
    self.localStatic = localStatic
    self.now = now
    createdAt = now()
    handshake = IOSNoiseHandshake(initiator: initiator, localStatic: localStatic)
  }

  func start() throws -> Data {
    guard initiator else { throw IOSMeshError.noise }
    return try handshake.write()
  }

  func process(_ message: Data) throws -> Data? {
    try handshake.read(message)
    var response: Data?
    if handshake.needsWrite { response = try handshake.write() }
    if handshake.complete {
      guard
        let remoteStatic = handshake.remoteStatic,
        IOSMeshProtocol.peerID(remoteStatic.rawRepresentation) == claimedPeerID
      else { throw IOSMeshError.identityMismatch }
      let ciphers = handshake.split()
      sendCipher = initiator ? ciphers.0 : ciphers.1
      receiveCipher = initiator ? ciphers.1 : ciphers.0
      established = true
    }
    return response
  }

  func encrypt(_ plaintext: Data) throws -> Data {
    guard established, let sendCipher else { throw IOSMeshError.noise }
    return try sendCipher.encrypt(plaintext, extractedNonce: true)
  }

  func decrypt(_ ciphertext: Data) throws -> Data {
    guard established, let receiveCipher else { throw IOSMeshError.noise }
    return try receiveCipher.decrypt(ciphertext, extractedNonce: true)
  }
}

final class IOSNoiseHandshake {
  private let initiator: Bool
  private let localStatic: Curve25519.KeyAgreement.PrivateKey
  private let symmetric = IOSNoiseSymmetric()
  private var localEphemeral: Curve25519.KeyAgreement.PrivateKey?
  private var remoteEphemeral: Curve25519.KeyAgreement.PublicKey?
  private(set) var remoteStatic: Curve25519.KeyAgreement.PublicKey?
  private var pattern = 0

  var complete: Bool { pattern >= 3 }
  var needsWrite: Bool {
    initiator ? pattern == 0 || pattern == 2 : pattern == 1
  }

  init(initiator: Bool, localStatic: Curve25519.KeyAgreement.PrivateKey) {
    self.initiator = initiator
    self.localStatic = localStatic
  }

  func write() throws -> Data {
    var output = Data()
    switch pattern {
    case 0 where initiator:
      localEphemeral = Curve25519.KeyAgreement.PrivateKey()
      let publicKey = localEphemeral!.publicKey.rawRepresentation
      output.append(publicKey)
      symmetric.mixHash(publicKey)
    case 1 where !initiator:
      localEphemeral = Curve25519.KeyAgreement.PrivateKey()
      let publicKey = localEphemeral!.publicKey.rawRepresentation
      output.append(publicKey)
      symmetric.mixHash(publicKey)
      try mixDH(localEphemeral, remoteEphemeral)
      output.append(try symmetric.encryptAndHash(localStatic.publicKey.rawRepresentation))
      try mixDH(localStatic, remoteEphemeral)
    case 2 where initiator:
      output.append(try symmetric.encryptAndHash(localStatic.publicKey.rawRepresentation))
      try mixDH(localStatic, remoteEphemeral)
    default:
      throw IOSMeshError.noise
    }
    output.append(try symmetric.encryptAndHash(Data()))
    pattern += 1
    return output
  }

  func read(_ input: Data) throws {
    var reader = DataReader(input)
    switch pattern {
    case 0 where !initiator:
      guard let ephemeral = reader.data(count: 32) else { throw IOSMeshError.noise }
      remoteEphemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
      symmetric.mixHash(ephemeral)
    case 1 where initiator:
      guard let ephemeral = reader.data(count: 32) else { throw IOSMeshError.noise }
      remoteEphemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
      symmetric.mixHash(ephemeral)
      try mixDH(localEphemeral, remoteEphemeral)
      guard let encryptedStatic = reader.data(count: 48) else { throw IOSMeshError.noise }
      remoteStatic = try Curve25519.KeyAgreement.PublicKey(
        rawRepresentation: symmetric.decryptAndHash(encryptedStatic)
      )
      try mixDH(localEphemeral, remoteStatic)
    case 2 where !initiator:
      guard let encryptedStatic = reader.data(count: 48) else { throw IOSMeshError.noise }
      remoteStatic = try Curve25519.KeyAgreement.PublicKey(
        rawRepresentation: symmetric.decryptAndHash(encryptedStatic)
      )
      try mixDH(localEphemeral, remoteStatic)
    default:
      throw IOSMeshError.noise
    }
    _ = try symmetric.decryptAndHash(reader.remaining)
    pattern += 1
  }

  func split() -> (IOSNoiseCipher, IOSNoiseCipher) {
    symmetric.split()
  }

  private func mixDH(
    _ privateKey: Curve25519.KeyAgreement.PrivateKey?,
    _ publicKey: Curve25519.KeyAgreement.PublicKey?
  ) throws {
    guard let privateKey, let publicKey else { throw IOSMeshError.noise }
    let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    symmetric.mixKey(secret.withUnsafeBytes { Data($0) })
  }
}

final class IOSNoiseSymmetric {
  private var cipher = IOSNoiseCipher()
  private var chainingKey: Data
  private var hash: Data

  init() {
    let name = Data("Noise_XX_25519_ChaChaPoly_SHA256".utf8)
    hash = name.count <= 32 ? name + Data(repeating: 0, count: 32 - name.count) :
      Data(SHA256.hash(data: name))
    chainingKey = hash
    mixHash(Data())
  }

  func mixHash(_ data: Data) {
    hash = Data(SHA256.hash(data: hash + data))
  }

  func mixKey(_ input: Data) {
    let values = hkdf(input: input, count: 2)
    chainingKey = values[0]
    cipher = IOSNoiseCipher(key: SymmetricKey(data: values[1]))
  }

  func encryptAndHash(_ plaintext: Data) throws -> Data {
    guard cipher.hasKey else {
      mixHash(plaintext)
      return plaintext
    }
    let encrypted = try cipher.encrypt(plaintext, associatedData: hash)
    mixHash(encrypted)
    return encrypted
  }

  func decryptAndHash(_ ciphertext: Data) throws -> Data {
    guard cipher.hasKey else {
      mixHash(ciphertext)
      return ciphertext
    }
    let plaintext = try cipher.decrypt(ciphertext, associatedData: hash)
    mixHash(ciphertext)
    return plaintext
  }

  func split() -> (IOSNoiseCipher, IOSNoiseCipher) {
    let values = hkdf(input: Data(), count: 2)
    return (
      IOSNoiseCipher(key: SymmetricKey(data: values[0])),
      IOSNoiseCipher(key: SymmetricKey(data: values[1]))
    )
  }

  private func hkdf(input: Data, count: Int) -> [Data] {
    let pseudo = Data(HMAC<SHA256>.authenticationCode(
      for: input,
      using: SymmetricKey(data: chainingKey)
    ))
    var previous = Data()
    return (1...count).map { index in
      previous = Data(HMAC<SHA256>.authenticationCode(
        for: previous + Data([UInt8(index)]),
        using: SymmetricKey(data: pseudo)
      ))
      return previous
    }
  }
}

struct IOSNoiseReplayWindow {
  static let size = 1024
  private static let wordBits = 64
  private var watermark: UInt32?
  private var bitmap = [UInt64](repeating: 0, count: size / wordBits)

  func canAccept(_ nonce: UInt32) -> Bool {
    guard let watermark else { return true }
    if nonce > watermark { return true }
    let distance = Int(watermark - nonce)
    guard distance < Self.size else { return false }
    return !isSet(distance)
  }

  mutating func markAccepted(_ nonce: UInt32) {
    precondition(canAccept(nonce))
    guard let currentWatermark = watermark else {
      watermark = nonce
      set(0)
      return
    }
    if nonce > currentWatermark {
      shift(by: Int(nonce - currentWatermark))
      watermark = nonce
      set(0)
    } else {
      set(Int(currentWatermark - nonce))
    }
  }

  private func isSet(_ distance: Int) -> Bool {
    let word = distance / Self.wordBits
    let bit = distance % Self.wordBits
    return bitmap[word] & (UInt64(1) << UInt64(bit)) != 0
  }

  private mutating func set(_ distance: Int) {
    let word = distance / Self.wordBits
    let bit = distance % Self.wordBits
    bitmap[word] |= UInt64(1) << UInt64(bit)
  }

  private mutating func shift(by distance: Int) {
    guard distance < Self.size else {
      bitmap = [UInt64](repeating: 0, count: bitmap.count)
      return
    }
    let previous = bitmap
    bitmap = [UInt64](repeating: 0, count: bitmap.count)
    for oldDistance in 0..<(Self.size - distance) {
      let word = oldDistance / Self.wordBits
      let bit = oldDistance % Self.wordBits
      if previous[word] & (UInt64(1) << UInt64(bit)) != 0 {
        set(oldDistance + distance)
      }
    }
  }
}

final class IOSNoiseCipher {
  static let defaultMessageLimit: UInt64 = 1 << 20
  private let key: SymmetricKey?
  private var nonce: UInt64 = 0
  private var replayWindow = IOSNoiseReplayWindow()
  private let messageLimit: UInt64
  private var messageCount: UInt64 = 0

  var hasKey: Bool { key != nil }
  var requiresRekey: Bool {
    messageCount >= messageLimit || nonce > UInt64(UInt32.max)
  }

  init(
    key: SymmetricKey? = nil,
    messageLimit: UInt64 = IOSNoiseCipher.defaultMessageLimit,
    initialNonce: UInt64 = 0
  ) {
    precondition(messageLimit > 0)
    self.key = key
    self.messageLimit = messageLimit
    nonce = initialNonce
  }

  func encrypt(
    _ plaintext: Data,
    associatedData: Data = Data(),
    extractedNonce: Bool = false
  ) throws -> Data {
    guard let key else { throw IOSMeshError.noise }
    guard messageCount < messageLimit else { throw IOSMeshError.noiseRekeyRequired }
    let current = nonce
    if extractedNonce, current > UInt64(UInt32.max) {
      throw IOSMeshError.noiseRekeyRequired
    }
    let box = try ChaChaPoly.seal(
      plaintext,
      using: key,
      nonce: try ChaChaPoly.Nonce(data: nonceData(current)),
      authenticating: associatedData
    )
    nonce = try incremented(nonce)
    messageCount += 1
    var output = Data()
    if extractedNonce { output.appendInteger(UInt32(current)) }
    output.append(box.ciphertext)
    output.append(box.tag)
    return output
  }

  func decrypt(
    _ input: Data,
    associatedData: Data = Data(),
    extractedNonce: Bool = false
  ) throws -> Data {
    guard let key else { throw IOSMeshError.noise }
    guard messageCount < messageLimit else { throw IOSMeshError.noiseRekeyRequired }
    var reader = DataReader(input)
    let current: UInt64
    if extractedNonce {
      guard let transmitted: UInt32 = reader.integer(),
            replayWindow.canAccept(transmitted) else {
        throw IOSMeshError.noise
      }
      current = UInt64(transmitted)
    } else {
      current = nonce
    }
    let encrypted = reader.remaining
    guard encrypted.count >= 16 else { throw IOSMeshError.noise }
    let box = try ChaChaPoly.SealedBox(
      nonce: try ChaChaPoly.Nonce(data: nonceData(current)),
      ciphertext: encrypted.dropLast(16),
      tag: encrypted.suffix(16)
    )
    let plaintext = try ChaChaPoly.open(box, using: key, authenticating: associatedData)
    if extractedNonce {
      replayWindow.markAccepted(UInt32(current))
    } else {
      nonce = try incremented(nonce)
    }
    messageCount += 1
    return plaintext
  }

  private func nonceData(_ value: UInt64) -> Data {
    var data = Data(repeating: 0, count: 4)
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    return data
  }

  private func incremented(_ value: UInt64) throws -> UInt64 {
    guard value < UInt64.max else { throw IOSMeshError.noiseRekeyRequired }
    return value + 1
  }
}

struct DataReader {
  private let data: Data
  private(set) var offset = 0

  init(_ data: Data) { self.data = data }

  var remaining: Data { data.dropFirst(offset) }

  mutating func byte() -> UInt8? {
    guard offset < data.count else { return nil }
    defer { offset += 1 }
    return data[data.startIndex + offset]
  }

  mutating func data(count: Int) -> Data? {
    guard count >= 0, offset + count <= data.count else { return nil }
    defer { offset += count }
    return data.subdata(in: offset..<(offset + count))
  }

  mutating func integer<T: FixedWidthInteger>() -> T? {
    guard let bytes = data(count: MemoryLayout<T>.size) else { return nil }
    return bytes.reduce(T.zero) { ($0 << 8) | T($1) }
  }

  mutating func byteString() -> String? {
    guard let length = byte(), let bytes = data(count: Int(length)) else { return nil }
    return String(data: bytes, encoding: .utf8)
  }

  mutating func skip(_ count: Int) -> Bool {
    guard count >= 0, offset + count <= data.count else { return false }
    offset += count
    return true
  }
}

extension Data {
  init(hex: String) throws {
    guard hex.count % 2 == 0 else { throw IOSMeshError.invalidPeerID }
    var output = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else {
        throw IOSMeshError.invalidPeerID
      }
      output.append(byte)
      index = next
    }
    self = output
  }

  var hex: String { map { String(format: "%02x", $0) }.joined() }

  mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
    for shift in stride(from: (MemoryLayout<T>.size - 1) * 8, through: 0, by: -8) {
      append(UInt8(truncatingIfNeeded: value >> shift))
    }
  }

  mutating func appendByteString(_ value: Data) {
    let limited = value.prefix(255)
    append(UInt8(limited.count))
    append(limited)
  }

  mutating func appendTLV(type: UInt8, value: Data) {
    let limited = value.prefix(255)
    append(type)
    append(UInt8(limited.count))
    append(limited)
  }

  mutating func appendWideTLV(type: UInt8, value: Data) {
    precondition(value.count <= Int(UInt16.max))
    append(type)
    appendInteger(UInt16(value.count))
    append(value)
  }
}
enum IOSMeshError: LocalizedError {
  case notRunning
  case peerUnavailable
  case invalidPeerID
  case identityMismatch
  case identityUnavailable
  case noise
  case noiseRekeyRequired
  case storageUnavailable
  case secureRandomUnavailable
  case invalidPayload
  case radarConsentRequired
  case roleCannotChat

  var errorDescription: String? {
    switch self {
    case .notRunning: return HearthBitL10n.string("not_running")
    case .peerUnavailable: return HearthBitL10n.string("peer_unavailable")
    case .invalidPeerID: return HearthBitL10n.string("invalid_peer_id")
    case .identityMismatch: return HearthBitL10n.string("identity_mismatch")
    case .identityUnavailable: return HearthBitL10n.string("identity_unavailable")
    case .noise: return HearthBitL10n.string("noise_failed")
    case .noiseRekeyRequired: return HearthBitL10n.string("noise_rekey_required")
    case .storageUnavailable: return HearthBitL10n.string("storage_unavailable")
    case .secureRandomUnavailable: return HearthBitL10n.string("secure_random_unavailable")
    case .invalidPayload: return HearthBitL10n.string("invalid_payload")
    case .radarConsentRequired: return HearthBitL10n.string("radar_consent_required")
    case .roleCannotChat: return HearthBitL10n.string("role_cannot_chat")
    }
  }
}
