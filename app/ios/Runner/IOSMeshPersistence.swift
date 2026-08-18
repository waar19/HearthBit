import CryptoKit
import Foundation

final class IOSEmergencyFingerprintCache {
  static let defaultMaximumEntries = 2048

  private let key = "hearthbit.emergency_fingerprints"
  private let lifetime: UInt64 = 24 * 60 * 60 * 1_000
  private let defaults: UserDefaults
  private let maximumEntries: Int

  init(
    defaults: UserDefaults = .standard,
    maximumEntries: Int = defaultMaximumEntries
  ) {
    precondition(maximumEntries > 0)
    self.defaults = defaults
    self.maximumEntries = maximumEntries
  }

  func seenOrRemember(_ fingerprint: String, now: UInt64? = nil) -> Bool {
    let timestamp = now ?? UInt64(Date().timeIntervalSince1970 * 1000)
    let normalized = fingerprint.lowercased()
    var entries = validEntries(now: timestamp)
    let duplicate = entries.contains { $0.fingerprint == normalized }
    if !duplicate {
      entries.append((timestamp, normalized))
    }
    defaults.set(
      entries.suffix(maximumEntries).map {
        ["at": $0.at, "fingerprint": $0.fingerprint]
      },
      forKey: key
    )
    return duplicate
  }

  func clear() {
    defaults.removeObject(forKey: key)
  }

  private func validEntries(
    now: UInt64
  ) -> [(at: UInt64, fingerprint: String)] {
    let values = defaults.array(forKey: key) as? [[String: Any]] ?? []
    return values.compactMap {
      guard
        let number = $0["at"] as? NSNumber,
        let fingerprint = $0["fingerprint"] as? String,
        fingerprint.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
      else { return nil }
      let timestamp = number.uint64Value
      guard timestamp <= now, now - timestamp <= lifetime else { return nil }
      return (timestamp, fingerprint)
    }.sorted { $0.at < $1.at }
  }
}

struct IOSRescueModeState: Codable {
  let active: Bool
  let description: String
  let startedAt: Int64
  let lastPingAt: Int64
  let expiresAt: Int64
  let intervalMs: Int64
  let pingCount: Int64?
  let locationPrecision: String?

  var asMap: [String: Any] {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let expected = active && startedAt > 0
      ? max(0, min(now, expiresAt) - startedAt) / intervalMs + 1
      : 0
    return [
      "active": active,
      "description": description,
      "startedAt": startedAt,
      "lastPingAt": lastPingAt,
      "expiresAt": expiresAt,
      "intervalMs": intervalMs,
      "expectedPings": expected,
      "executedPings": pingCount ?? 0,
      "locationPrecision": locationPrecision ?? "approximate",
    ]
  }
}
struct IOSPeerIdentityPin: Codable, Equatable {
  let peerID: String
  let noisePublicKey: Data
  let signingPublicKey: Data
  var lastRotationSequence: UInt64? = nil
  var retired: Bool? = nil
}

enum IOSPeerIdentityPinDecision: Equatable {
  case firstBinding
  case matched
  case conflict(noiseChanged: Bool, signingChanged: Bool)
}

final class IOSPeerIdentityPinStore {
  typealias Read = () throws -> IOSKeychainReadResult
  typealias Upsert = (Data) throws -> Void
  typealias Delete = () throws -> Void

  private struct Envelope: Codable {
    let version: Int
    let pins: [IOSPeerIdentityPin]
  }

  private static let service = "HearthBit.PeerIdentityPins"
  private static let account = "pins.v1"
  private static let version = 1
  static let defaultMaximumPins = 512
  static let legacyDefaultsKey = "hearthbit.peer_identity_pins"

  private let defaults: UserDefaults
  private let read: Read
  private let upsert: Upsert
  private let delete: Delete
  private let maximumPins: Int
  private var pins: [String: IOSPeerIdentityPin] = [:]
  private(set) var failure: Error?

  convenience init(defaults: UserDefaults = .standard) {
    self.init(
      defaults: defaults,
      read: {
        try IOSKeychain.read(
          service: IOSPeerIdentityPinStore.service,
          account: IOSPeerIdentityPinStore.account
        )
      },
      upsert: {
        try IOSKeychain.upsert(
          $0,
          service: IOSPeerIdentityPinStore.service,
          account: IOSPeerIdentityPinStore.account
        )
      },
      delete: {
        try IOSKeychain.delete(
          service: IOSPeerIdentityPinStore.service,
          account: IOSPeerIdentityPinStore.account
        )
      },
      maximumPins: IOSPeerIdentityPinStore.defaultMaximumPins
    )
  }

  init(
    defaults: UserDefaults,
    read: @escaping Read,
    upsert: @escaping Upsert,
    delete: @escaping Delete,
    maximumPins: Int = defaultMaximumPins
  ) {
    precondition(maximumPins > 0)
    self.defaults = defaults
    self.read = read
    self.upsert = upsert
    self.delete = delete
    self.maximumPins = maximumPins
    do {
      try restore()
    } catch {
      failure = error
      pins.removeAll()
    }
  }

  func pin(for peerID: String) -> IOSPeerIdentityPin? {
    pins[peerID.lowercased()].flatMap { $0.retired == true ? nil : $0 }
  }

  func validateAndPin(
    peerID: String,
    noisePublicKey: Data,
    signingPublicKey: Data,
    protectedPeerIDs: Set<String> = []
  ) throws -> IOSPeerIdentityPinDecision {
    try ensureAvailable()
    let normalized = peerID.lowercased()
    guard
      normalized.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
      noisePublicKey.count == 32,
      signingPublicKey.count == 32
    else {
      throw IOSSecureStorageError.corruptValue(
        service: Self.service,
        account: "invalid-pin"
      )
    }
    if let existing = pins[normalized] {
      if existing.retired == true {
        return .conflict(noiseChanged: true, signingChanged: true)
      }
      let noiseChanged = existing.noisePublicKey != noisePublicKey
      let signingChanged = existing.signingPublicKey != signingPublicKey
      if noiseChanged || signingChanged {
        return .conflict(
          noiseChanged: noiseChanged,
          signingChanged: signingChanged
        )
      }
      return .matched
    }
    guard IOSMeshProtocol.peerID(noisePublicKey).hex == normalized else {
      throw IOSSecureStorageError.corruptValue(
        service: Self.service,
        account: "peer-id-binding"
      )
    }
    let previousPins = pins
    guard pins.count <= maximumPins else {
      throw IOSSecureStorageError.logicalTransactionFailed(
        "Peer identity pin capacity exceeded"
      )
    }
    if pins.count == maximumPins {
      let protected = Set(protectedPeerIDs.map { $0.lowercased() })
      guard let eviction = pins.values
        .filter { $0.retired != true && !protected.contains($0.peerID) }
        .map(\.peerID)
        .sorted()
        .first
      else {
        throw IOSSecureStorageError.logicalTransactionFailed(
          "Peer identity pin capacity reached with no evictable pin"
        )
      }
      pins.removeValue(forKey: eviction)
    }

    let pin = IOSPeerIdentityPin(
      peerID: normalized,
      noisePublicKey: noisePublicKey,
      signingPublicKey: signingPublicKey,
      lastRotationSequence: 0,
      retired: false
    )
    pins[normalized] = pin
    do {
      try persist()
    } catch {
      pins = previousPins
      failure = error
      throw error
    }
    return .firstBinding
  }

  func rotate(
    oldPeerID: String,
    noisePublicKey: Data,
    signingPublicKey: Data,
    sequence: UInt64
  ) throws -> IOSPeerIdentityPin? {
    try ensureAvailable()
    let oldID = oldPeerID.lowercased()
    guard
      sequence > 0,
      let oldPin = pins[oldID],
      oldPin.retired != true,
      sequence > (oldPin.lastRotationSequence ?? 0),
      noisePublicKey.count == 32,
      signingPublicKey.count == 32,
      noisePublicKey.contains(where: { $0 != 0 }),
      signingPublicKey.contains(where: { $0 != 0 }),
      (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: noisePublicKey)) != nil,
      (try? Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey)) != nil
    else { return nil }
    let newID = IOSMeshProtocol.peerID(noisePublicKey).hex
    let collides = pins.values.contains {
      $0.peerID != oldID &&
        $0.retired != true &&
        ($0.noisePublicKey == noisePublicKey ||
         $0.signingPublicKey == signingPublicKey)
    }
    guard newID != oldID, pins[newID] == nil, !collides else { return nil }
    let replacement = IOSPeerIdentityPin(
      peerID: newID,
      noisePublicKey: noisePublicKey,
      signingPublicKey: signingPublicKey,
      lastRotationSequence: sequence
    )
    var retiredPin = oldPin
    retiredPin.retired = true
    pins[oldID] = retiredPin
    pins[newID] = replacement
    do {
      try persist()
      return replacement
    } catch {
      pins.removeValue(forKey: newID)
      pins[oldID] = oldPin
      failure = error
      throw error
    }
  }

  func clear() throws {
    do {
      try delete()
      defaults.removeObject(forKey: Self.legacyDefaultsKey)
      pins.removeAll()
      failure = nil
    } catch {
      failure = error
      throw error
    }
  }

  private func restore() throws {
    switch try read() {
    case .missing:
      guard let legacy = defaults.data(forKey: Self.legacyDefaultsKey) else { return }
      let restored = try decodePins(legacy)
      pins = restored
      try persist()
      defaults.removeObject(forKey: Self.legacyDefaultsKey)
    case let .value(data):
      if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
         envelope.version == Self.version {
        pins = try validatedDictionary(envelope.pins)
        return
      }
      // Migra el formato inicial no versionado si existió en una build previa.
      let legacyPins = try JSONDecoder().decode([IOSPeerIdentityPin].self, from: data)
      pins = try validatedDictionary(legacyPins)
      try persist()
    }
  }

  private func decodePins(_ data: Data) throws -> [String: IOSPeerIdentityPin] {
    if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
       envelope.version == Self.version {
      return try validatedDictionary(envelope.pins)
    }
    return try validatedDictionary(
      JSONDecoder().decode([IOSPeerIdentityPin].self, from: data)
    )
  }

  private func validatedDictionary(
    _ values: [IOSPeerIdentityPin]
  ) throws -> [String: IOSPeerIdentityPin] {
    guard values.count <= maximumPins else {
      throw IOSSecureStorageError.corruptValue(
        service: Self.service,
        account: Self.account
      )
    }
    var output: [String: IOSPeerIdentityPin] = [:]
    for pin in values {
      let normalized = pin.peerID.lowercased()
      guard
        output[normalized] == nil,
        normalized.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
        pin.noisePublicKey.count == 32,
        pin.signingPublicKey.count == 32,
        IOSMeshProtocol.peerID(pin.noisePublicKey).hex == normalized
      else {
        throw IOSSecureStorageError.corruptValue(
          service: Self.service,
          account: Self.account
        )
      }
      output[normalized] = IOSPeerIdentityPin(
        peerID: normalized,
        noisePublicKey: pin.noisePublicKey,
        signingPublicKey: pin.signingPublicKey,
        lastRotationSequence: pin.lastRotationSequence ?? 0,
        retired: pin.retired ?? false
      )
    }
    return output
  }

  private func persist() throws {
    let envelope = Envelope(
      version: Self.version,
      pins: pins.values.sorted { $0.peerID < $1.peerID }
    )
    try upsert(JSONEncoder().encode(envelope))
  }

  private func ensureAvailable() throws {
    if let failure { throw failure }
  }
}

enum IOSRescueModeStore {
  private static let service = "HearthBit.RescueMode"
  private static let account = "state.v1"
  static let defaultInterval: Int64 = 5 * 60_000
  private static let minimumInterval: Int64 = 30_000
  private static let maximumInterval: Int64 = 15 * 60_000
  private static let maximumLifetime: Int64 = 24 * 60 * 60_000

  static func load(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws
    -> IOSRescueModeState
  {
    let stored = try IOSKeychain.read(service: service, account: account)
    guard case let .value(data) = stored else {
      return IOSRescueModeState(
        active: false,
        description: "",
        startedAt: 0,
        lastPingAt: 0,
        expiresAt: 0,
        intervalMs: defaultInterval,
        pingCount: 0,
        locationPrecision: "approximate"
      )
    }
    guard var state = try? JSONDecoder().decode(IOSRescueModeState.self, from: data) else {
      throw IOSSecureStorageError.corruptValue(service: service, account: account)
    }
    if state.active && state.expiresAt <= now {
      try clear()
      state = IOSRescueModeState(
        active: false,
        description: "",
        startedAt: 0,
        lastPingAt: state.lastPingAt,
        expiresAt: 0,
        intervalMs: state.intervalMs,
        pingCount: state.pingCount,
        locationPrecision: state.locationPrecision
      )
    }
    return state
  }

  static func configure(
    description: String,
    startedAt: Int64,
    lastPingAt: Int64,
    expiresAt: Int64,
    intervalMs: Int64,
    locationPrecision: String,
    now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
  ) throws -> IOSRescueModeState {
    let safeStart = startedAt > 0 && startedAt <= now ? startedAt : now
    let requestedExpiry = expiresAt > now ? expiresAt : safeStart + maximumLifetime
    let state = IOSRescueModeState(
      active: true,
      description: String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
      startedAt: safeStart,
      lastPingAt: max(lastPingAt, 0),
      expiresAt: min(requestedExpiry, safeStart + maximumLifetime),
      intervalMs: min(max(intervalMs, minimumInterval), maximumInterval),
      pingCount: lastPingAt > 0 ? 1 : 0,
      locationPrecision: ["exact", "approximate", "none"].contains(locationPrecision)
        ? locationPrecision : "approximate"
    )
    let data = try JSONEncoder().encode(state)
    try write(data)
    return state
  }

  static func recordPing(_ timestamp: Int64) throws {
    let current = try load()
    guard current.active else { return }
    let updated = IOSRescueModeState(
      active: true,
      description: current.description,
      startedAt: current.startedAt,
      lastPingAt: timestamp,
      expiresAt: current.expiresAt,
      intervalMs: current.intervalMs,
      pingCount: (current.pingCount ?? 0) + 1,
      locationPrecision: current.locationPrecision
    )
    try write(JSONEncoder().encode(updated))
  }

  static func clear() throws {
    try IOSKeychain.delete(service: service, account: account)
  }

  private static func write(_ data: Data) throws {
    try IOSKeychain.upsert(data, service: service, account: account)
  }
}

final class IOSStoreForward {
  static let entriesKey = "hearthbit.store_forward"
  static let migrationVersionKey = "hearthbit.store_forward.migration_version"
  static let currentMigrationVersion = 1
  private static let keychainService = "HearthBit.StoreForward"
  private static let keychainAccount = "encryption"
  private let lifetime: TimeInterval = 12 * 60 * 60
  private let emergencyLifetime: TimeInterval = 24 * 60 * 60
  private let maximum = 100
  private let defaults: UserDefaults
  private var encryptionKey: SymmetricKey?
  private(set) var failure: Error?

  init(defaults: UserDefaults = .standard, testingKey: SymmetricKey? = nil) {
    self.defaults = defaults
    do {
      encryptionKey = try testingKey ?? Self.loadOrCreateKey()
      try migrateLegacyPlaintextOnce()
    } catch {
      encryptionKey = nil
      failure = error
    }
  }

  func put(_ packet: IOSMeshPacket) throws {
    try ensureAvailable()
    guard IOSNoiseReplayPolicy.isStoreForwardSafe(packet) else { return }
    let now = Date().timeIntervalSince1970
    var entries = try validEntries(now: now)
    let encoded = IOSMeshProtocol.encode(packet, padded: false)
    if !entries.contains(where: { $0.encoded == encoded }) {
      entries.append((
        now + (IOSMeshProtocol.isEmergency(packet) ? emergencyLifetime : lifetime),
        encoded
      ))
    }
    entries.sort {
      let firstPriority = IOSMeshProtocol.decode($0.encoded)
        .map(IOSMeshProtocol.isEmergency) ?? false
      let secondPriority = IOSMeshProtocol.decode($1.encoded)
        .map(IOSMeshProtocol.isEmergency) ?? false
      if firstPriority != secondPriority { return !firstPriority }
      return $0.expiry < $1.expiry
    }
    try save(Array(entries.suffix(maximum)))
  }

  func packets(for recipient: Data) throws -> [IOSMeshPacket] {
    try ensureAvailable()
    let entries = try validEntries(now: Date().timeIntervalSince1970)
    try save(entries)
    return entries.compactMap {
      guard
        let packet = IOSMeshProtocol.decode($0.encoded),
        packet.recipientID == recipient
      else { return nil }
      return packet
    }
  }

  func emergencyPackets() throws -> [IOSMeshPacket] {
    try ensureAvailable()
    let entries = try validEntries(now: Date().timeIntervalSince1970)
    try save(entries)
    return entries.compactMap {
      IOSMeshProtocol.decode($0.encoded)
    }.filter(IOSMeshProtocol.isEmergency)
  }

  func emergency(hash: String) throws -> IOSMeshPacket? {
    let normalized = hash.lowercased()
    return try emergencyPackets().first {
      IOSMeshProtocol.emergencyCanonicalHash($0).hex == normalized
    }
  }

  func clear() throws {
    defaults.removeObject(forKey: Self.entriesKey)
    defaults.removeObject(forKey: Self.migrationVersionKey)
    do {
      try Self.deleteKey()
      encryptionKey = try Self.createAndPersistKey()
      failure = nil
      defaults.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
    } catch {
      encryptionKey = nil
      failure = error
      throw error
    }
  }

  func validEntries(now: TimeInterval) throws -> [(expiry: TimeInterval, encoded: Data)] {
    try ensureAvailable()
    let stored = defaults.array(forKey: Self.entriesKey) as? [[String: Any]] ?? []
    var output: [(expiry: TimeInterval, encoded: Data)] = []
    for value in stored {
      guard
        let expiry = value["expiry"] as? TimeInterval,
        let storedValue = value["encoded"] as? String,
        expiry > now,
        let persisted = Data(base64Encoded: storedValue)
      else { continue }
      guard let data = try decrypt(persisted) else {
        throw IOSSecureStorageError.corruptValue(
          service: Self.keychainService,
          account: "encrypted-packets"
        )
      }
      guard
        let packet = IOSMeshProtocol.decode(data),
        IOSNoiseReplayPolicy.isStoreForwardSafe(packet)
      else { continue }
      output.append((expiry, data))
    }
    return output.sorted { $0.expiry < $1.expiry }
  }

  private func save(_ entries: [(expiry: TimeInterval, encoded: Data)]) throws {
    guard let encryptionKey else { throw failure ?? IOSMeshError.storageUnavailable }
    let persistedEntries: [[String: Any]] = try entries.map { entry in
      guard let sealed = try AES.GCM.seal(
        entry.encoded,
        using: encryptionKey
      ).combined else {
        throw IOSSecureStorageError.logicalTransactionFailed(
          "AES-GCM did not produce a combined store-forward value"
        )
      }
      return [
        "expiry": entry.expiry,
        "encoded": sealed.base64EncodedString(),
      ]
    }
    defaults.set(persistedEntries, forKey: Self.entriesKey)
  }

  private func decrypt(_ value: Data) throws -> Data? {
    guard let encryptionKey else { throw failure ?? IOSMeshError.storageUnavailable }
    guard let sealed = try? AES.GCM.SealedBox(combined: value) else { return nil }
    return try AES.GCM.open(sealed, using: encryptionKey)
  }

  private func migrateLegacyPlaintextOnce() throws {
    guard defaults.integer(forKey: Self.migrationVersionKey) < Self.currentMigrationVersion else {
      return
    }
    let stored = defaults.array(forKey: Self.entriesKey) as? [[String: Any]] ?? []
    var migrated: [(expiry: TimeInterval, encoded: Data)] = []
    for value in stored {
      guard
        let expiry = value["expiry"] as? TimeInterval,
        let encoded = value["encoded"] as? String,
        let persisted = Data(base64Encoded: encoded)
      else { continue }
      let plaintext: Data
      if let legacyPacket = IOSMeshProtocol.decode(persisted),
         IOSNoiseReplayPolicy.isStoreForwardSafe(legacyPacket) {
        plaintext = persisted
      } else if let decrypted = try decrypt(persisted),
                let encryptedPacket = IOSMeshProtocol.decode(decrypted),
                IOSNoiseReplayPolicy.isStoreForwardSafe(encryptedPacket) {
        plaintext = decrypted
      } else {
        throw IOSSecureStorageError.corruptValue(
          service: Self.keychainService,
          account: "legacy-packets"
        )
      }
      migrated.append((expiry, plaintext))
    }
    try save(migrated)
    defaults.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
    guard defaults.integer(forKey: Self.migrationVersionKey) == Self.currentMigrationVersion else {
      throw IOSSecureStorageError.logicalTransactionFailed(
        "Store-forward migration version could not be persisted"
      )
    }
  }

  private func ensureAvailable() throws {
    if let failure { throw failure }
    guard encryptionKey != nil else { throw IOSMeshError.storageUnavailable }
  }

  private static func loadOrCreateKey() throws -> SymmetricKey {
    switch try IOSKeychain.read(service: keychainService, account: keychainAccount) {
    case .missing:
      return try createAndPersistKey()
    case let .value(data):
      guard data.count == 32 else {
        throw IOSSecureStorageError.corruptValue(
          service: keychainService,
          account: keychainAccount
        )
      }
      return SymmetricKey(data: data)
    }
  }

  private static func createAndPersistKey() throws -> SymmetricKey {
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    try IOSKeychain.upsert(data, service: keychainService, account: keychainAccount)
    return key
  }

  private static func deleteKey() throws {
    try IOSKeychain.delete(service: keychainService, account: keychainAccount)
  }
}
