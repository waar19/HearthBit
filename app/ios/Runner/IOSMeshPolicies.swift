import CoreBluetooth
import CryptoKit
import Foundation

enum IOSPowerProfile: String {
  case performance
  case balanced
  case powerSaver
  case critical
  case survival

  var savesPower: Bool {
    self != .performance && self != .balanced
  }

  var scanBurst: TimeInterval {
    switch self {
    case .powerSaver: return 10
    case .critical: return 5
    case .performance, .balanced, .survival: return 0
    }
  }

  var scanPause: TimeInterval {
    switch self {
    case .powerSaver: return 50
    case .critical: return 115
    case .performance, .balanced, .survival: return 0
    }
  }

  var maximumOutgoingConnections: Int {
    switch self {
    case .critical: return 3
    case .survival: return 0
    case .performance, .balanced, .powerSaver:
      return IOSBLENeighborSelectionPolicy.maximumNeighbors
    }
  }

  static func resolve(
    batteryLevel: Int,
    charging: Bool,
    foreground: Bool,
    lowPowerMode: Bool,
    survivalMode: Bool,
    highPerformanceRequested: Bool
  ) -> IOSPowerProfile {
    let battery = min(max(batteryLevel, 0), 100)
    if survivalMode { return .survival }
    if battery <= 10 { return .critical }
    if lowPowerMode || !foreground { return .powerSaver }
    if charging && highPerformanceRequested { return .performance }
    if charging { return .balanced }
    if battery <= 40 { return .powerSaver }
    return .balanced
  }
}

struct IOSBLENeighborCandidate: Equatable {
  let identifier: UUID
  let rssi: Int
  let knownPeer: Bool
  let preferred: Bool
  let protected: Bool
}

enum IOSBLENeighborSelectionDecision: Equatable {
  case accept
  case reject
  case replace(UUID)
}

enum IOSBLENeighborSelectionPolicy {
  static let maximumNeighbors = 8
  static let maximumSubscribedCentrals = 8
  static let replacementRSSIMargin = 12

  static func decision(
    candidate: IOSBLENeighborCandidate,
    current: [IOSBLENeighborCandidate],
    maximum: Int = maximumNeighbors
  ) -> IOSBLENeighborSelectionDecision {
    guard maximum > 0 else { return .reject }
    guard !current.contains(where: { $0.identifier == candidate.identifier }) else {
      return .reject
    }
    guard current.count >= maximum else { return .accept }
    guard
      let worst = current
        .filter { !$0.protected && !$0.preferred }
        .min(by: isWorse)
    else { return .reject }
    guard isClearlyBetter(candidate, than: worst) else { return .reject }
    return .replace(worst.identifier)
  }

  private static func isWorse(
    _ lhs: IOSBLENeighborCandidate,
    _ rhs: IOSBLENeighborCandidate
  ) -> Bool {
    let lhsPriority = priority(lhs)
    let rhsPriority = priority(rhs)
    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
    if lhs.rssi != rhs.rssi { return lhs.rssi < rhs.rssi }
    return lhs.identifier.uuidString < rhs.identifier.uuidString
  }

  private static func isClearlyBetter(
    _ candidate: IOSBLENeighborCandidate,
    than current: IOSBLENeighborCandidate
  ) -> Bool {
    let candidatePriority = priority(candidate)
    let currentPriority = priority(current)
    if candidatePriority != currentPriority {
      return candidatePriority > currentPriority
    }
    let threshold = current.rssi.addingReportingOverflow(replacementRSSIMargin)
    return !threshold.overflow && candidate.rssi >= threshold.partialValue
  }

  private static func priority(_ candidate: IOSBLENeighborCandidate) -> Int {
    if candidate.preferred { return 2 }
    return candidate.knownPeer ? 1 : 0
  }
}

enum IOSBLEScanSelection: Equatable {
  case meshFiltered
  case genericUnfiltered
}

enum IOSGenericBLEScanPolicy {
  static let windowDuration: TimeInterval = 10
  static let pauseDuration: TimeInterval = 50

  static func selection(
    genericEnabled: Bool,
    genericWindowActive: Bool,
    foreground: Bool,
    radarActive: Bool,
    recoveryActive: Bool
  ) -> IOSBLEScanSelection {
    if genericEnabled &&
       genericWindowActive &&
       foreground &&
       !radarActive &&
       !recoveryActive {
      return .genericUnfiltered
    }
    return .meshFiltered
  }
}

enum IOSAnnouncementClockPolicy {
  static let standardWindowMilliseconds: UInt64 = 10 * 60 * 1_000
  static let emergencyPastWindowMilliseconds: UInt64 = 24 * 60 * 60 * 1_000

  static func accepts(
    timestamp: UInt64,
    emergencyPreannounce: Bool,
    now: UInt64
  ) -> Bool {
    if timestamp > now {
      return timestamp - now <= standardWindowMilliseconds
    }
    let pastWindow = emergencyPreannounce
      ? emergencyPastWindowMilliseconds
      : standardWindowMilliseconds
    return now - timestamp <= pastWindow
  }
}

enum IOSLanBridgeLifecyclePolicy {
  static func shouldClearOnStop(notify: Bool) -> Bool { notify }
}

enum IOSPeerReachabilityPolicy {
  static let window: TimeInterval = 4 * 60

  static func isOnline(
    lastActivity: Date?,
    now: Date,
    window: TimeInterval = IOSPeerReachabilityPolicy.window
  ) -> Bool {
    guard let lastActivity else { return false }
    return now.timeIntervalSince(lastActivity) <= window
  }

  static func requiresTransportRekey(previousLastSeen: Date?, now: Date) -> Bool {
    previousLastSeen != nil &&
      !isOnline(lastActivity: previousLastSeen, now: now)
  }
}

enum IOSBLEFramePriority {
  case normal
  case emergency
}

struct IOSBLEPriorityQueue<Element> {
  private enum Lane {
    case normal
    case emergency
  }

  static var maximumEmergencyBurst: Int { 8 }
  static var maximumRetries: Int { 3 }

  private struct Entry {
    let value: Element
    var failures = 0
  }

  private let normalCapacity: Int
  private let emergencyReserve: Int
  private var normal: [Entry] = []
  private var emergency: [Entry] = []
  private var activeLane: Lane?
  private var emergencyBurst = 0

  init(normalCapacity: Int, emergencyReserve: Int) {
    precondition(normalCapacity > 0)
    precondition(emergencyReserve > 0)
    self.normalCapacity = normalCapacity
    self.emergencyReserve = emergencyReserve
  }

  var count: Int { normal.count + emergency.count }
  var isEmpty: Bool { normal.isEmpty && emergency.isEmpty }
  var currentPriority: IOSBLEFramePriority? {
    guard let activeLane else { return nil }
    return activeLane == .emergency ? .emergency : .normal
  }

  mutating func enqueue(_ values: [Element], priority: IOSBLEFramePriority) -> Bool {
    guard !values.isEmpty else { return true }
    switch priority {
    case .normal:
      guard count + values.count <= normalCapacity else { return false }
      normal.append(contentsOf: values.map { Entry(value: $0) })
    case .emergency:
      guard count + values.count <= normalCapacity + emergencyReserve else { return false }
      emergency.append(contentsOf: values.map { Entry(value: $0) })
    }
    return true
  }

  mutating func next() -> Element? {
    if let activeLane {
      return activeLane == .emergency ? emergency.first?.value : normal.first?.value
    }
    if !emergency.isEmpty &&
       (emergencyBurst < Self.maximumEmergencyBurst || normal.isEmpty) {
      activeLane = .emergency
      return emergency.first?.value
    }
    if !normal.isEmpty {
      activeLane = .normal
      return normal.first?.value
    }
    if !emergency.isEmpty {
      activeLane = .emergency
      return emergency.first?.value
    }
    return nil
  }

  mutating func completeCurrent() {
    guard let activeLane else { return }
    switch activeLane {
    case .emergency:
      if !emergency.isEmpty { emergency.removeFirst() }
      emergencyBurst += 1
    case .normal:
      if !normal.isEmpty { normal.removeFirst() }
      emergencyBurst = 0
    }
    self.activeLane = nil
  }

  mutating func failCurrent() -> (attempt: Int, discarded: Bool)? {
    guard let activeLane else { return nil }
    switch activeLane {
    case .emergency:
      guard !emergency.isEmpty else { return nil }
      emergency[0].failures += 1
      let attempt = emergency[0].failures
      if attempt > Self.maximumRetries {
        completeCurrent()
        return (attempt, true)
      }
      return (attempt, false)
    case .normal:
      guard !normal.isEmpty else { return nil }
      normal[0].failures += 1
      let attempt = normal[0].failures
      if attempt > Self.maximumRetries {
        completeCurrent()
        return (attempt, true)
      }
      return (attempt, false)
    }
  }
}
final class IOSUnknownIngressRateLimiter {
  static let defaultMaximumPackets = 30
  static let defaultWindow: TimeInterval = 10
  static let maximumTrackedSources = 256

  private struct Window {
    var startedAt: TimeInterval
    var packets: Int
  }

  private let maximumPackets: Int
  private let window: TimeInterval
  private var windows: [String: Window] = [:]
  private let lock = NSLock()

  init(
    maximumPackets: Int = defaultMaximumPackets,
    window: TimeInterval = defaultWindow
  ) {
    self.maximumPackets = maximumPackets
    self.window = window
  }

  func allow(
    source: String,
    now: TimeInterval = Date().timeIntervalSince1970
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    if var current = windows[source],
       now >= current.startedAt,
       now - current.startedAt < window {
      guard current.packets < maximumPackets else { return false }
      current.packets += 1
      windows[source] = current
      return true
    }
    if windows.count >= Self.maximumTrackedSources,
       let oldest = windows.min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
      windows.removeValue(forKey: oldest)
    }
    windows[source] = Window(startedAt: now, packets: 1)
    return true
  }
}

enum IOSMeshIngressPolicy {
  private static let publicSignatureTypes: Set<UInt8> = [
    IOSMeshProtocol.message,
    IOSMeshProtocol.courierEnvelope,
    IOSMeshProtocol.requestSync,
    IOSMeshProtocol.radarControl,
    IOSMeshProtocol.legacyHbtCapability,
    IOSMeshProtocol.hbtCapability,
    IOSMeshProtocol.nodeCapability,
    IOSMeshProtocol.beaconControl,
    IOSMeshProtocol.rangingControl,
    IOSMeshProtocol.emergencyCapability,
    IOSMeshProtocol.legacyEmergencyAck,
    IOSMeshProtocol.emergencyAck,
    IOSMeshProtocol.keyRotation,
  ]

  static func requiresPublicSignature(_ packetType: UInt8) -> Bool {
    publicSignatureTypes.contains(packetType)
  }

  static func accepts(
    _ packet: IOSMeshPacket,
    signingPublicKey: Data?
  ) -> Bool {
    guard requiresPublicSignature(packet.type) else { return true }
    guard let signingPublicKey else { return false }
    return IOSMeshIdentity.verify(packet, key: signingPublicKey)
  }
}

enum IOSMeshRelayPolicy {
  static func shouldRelay(
    role: IOSMeshNodeRole,
    packetType: UInt8,
    ttl: UInt8,
    addressedToLocalNode: Bool,
    hasDirectedRecipient: Bool
  ) -> Bool {
    guard role.relaysPackets, ttl > 1 else { return false }
    switch packetType {
    case IOSMeshProtocol.beaconControl:
      return ttl == IOSBeaconControlProtocol.initialTTL &&
        hasDirectedRecipient &&
        !addressedToLocalNode
    case IOSMeshProtocol.rangingControl:
      return false
    case IOSMeshProtocol.noiseHandshake, IOSMeshProtocol.noiseEncrypted:
      return !addressedToLocalNode
    default:
      return true
    }
  }
}
enum IOSEmergencySMSPolicy {
  static func normalizeRecipient(_ value: String) -> String? {
    let normalized = String(value.trimmingCharacters(in: .whitespacesAndNewlines).filter {
      !$0.isWhitespace && $0 != "(" && $0 != ")" && $0 != "-"
    })
    let digits = normalized.hasPrefix("+") ? normalized.dropFirst() : normalized[...]
    guard (5...15).contains(digits.count) else { return nil }
    guard digits.unicodeScalars.allSatisfy({
      $0.value >= 48 && $0.value <= 57
    }) else { return nil }
    return normalized
  }
}

final class IOSGenericBLEPresenceTracker {
  struct Presence {
    let localID: String
    let rssi: Int
    let lastSeen: Int64

    var eventMap: [String: Any] {
      [
        "id": localID,
        "role": IOSMeshNodeRole.phoneBeacon.rawValue,
        "kind": "genericBle",
        "chatAvailable": false,
        "rssi": rssi,
        "lastSeen": lastSeen,
      ]
    }
  }

  private struct Observation {
    var localID: String
    var rssi: Int
    var lastSeen: Int64
  }

  static let rotationMilliseconds: Int64 = 15 * 60 * 1_000
  static let staleMilliseconds: Int64 = 45 * 1_000
  static let emitInterval: TimeInterval = 1
  static let staleAfter: TimeInterval = 45
  static let maximumObservations = 64

  private let sessionSecret: Data
  private let rotation: Int64
  private let stale: Int64
  private let maximum: Int
  private var observations: [String: Observation] = [:]

  init(
    sessionSecret: Data,
    rotationMilliseconds: Int64 = IOSGenericBLEPresenceTracker.rotationMilliseconds,
    staleMilliseconds: Int64 = IOSGenericBLEPresenceTracker.staleMilliseconds,
    maximumObservations: Int = IOSGenericBLEPresenceTracker.maximumObservations
  ) {
    precondition(!sessionSecret.isEmpty)
    precondition(rotationMilliseconds > 0)
    precondition(staleMilliseconds > 0)
    precondition(maximumObservations > 0)
    self.sessionSecret = sessionSecret
    rotation = rotationMilliseconds
    stale = staleMilliseconds
    maximum = maximumObservations
  }

  static func secure() -> IOSGenericBLEPresenceTracker? {
    guard let secret = IOSSecureRandom.data(count: 32) else { return nil }
    return IOSGenericBLEPresenceTracker(sessionSecret: secret)
  }

  @discardableResult
  func record(material: Data, rssi: Int, now: Int64) -> Bool {
    guard !material.isEmpty else { return false }
    prune(now: now)
    let trackingDigest = hmac(Data([0x01]) + material)
    let trackingKey = trackingDigest.hex
    let localID = rotatingID(trackingDigest: trackingDigest, now: now)
    observations[trackingKey] = Observation(
      localID: localID,
      rssi: rssi,
      lastSeen: now
    )
    while observations.count > maximum,
          let oldest = observations.min(by: {
            $0.value.lastSeen < $1.value.lastSeen
          }) {
      observations.removeValue(forKey: oldest.key)
    }
    return true
  }

  func snapshot(now: Int64) -> [Presence] {
    prune(now: now)
    return observations.values
      .map { Presence(localID: $0.localID, rssi: $0.rssi, lastSeen: $0.lastSeen) }
      .sorted { $0.lastSeen > $1.lastSeen }
  }

  func clear() {
    observations.removeAll()
  }

  private func rotatingID(trackingDigest: Data, now: Int64) -> String {
    let epoch = UInt64(max(0, now / rotation))
    var epochBytes = Data()
    epochBytes.appendInteger(epoch)
    return Data(hmac(Data([0x02]) + epochBytes + trackingDigest).prefix(12)).hex
  }

  private func prune(now: Int64) {
    observations = observations.filter { now - $0.value.lastSeen <= stale }
  }

  private func hmac(_ data: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(
      for: data,
      using: SymmetricKey(data: sessionSecret)
    ))
  }

}

enum IOSGenericBLEAdvertisement {
  static func isMesh(
    _ advertisementData: [String: Any],
    meshServiceUUID: CBUUID
  ) -> Bool {
    let serviceLists = [
      advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
      advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID],
      advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID],
    ]
    if serviceLists.compactMap({ $0 }).flatMap({ $0 }).contains(meshServiceUUID) {
      return true
    }
    let serviceData =
      advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
    return serviceData.keys.contains(meshServiceUUID)
  }

  static func material(_ advertisementData: [String: Any]) -> Data {
    var output = Data()
    func appendField(tag: UInt8, key: Data, value: Data = Data()) {
      let size = key.count + value.count
      guard size <= Int(UInt16.max) else { return }
      output.append(tag)
      output.appendInteger(UInt16(size))
      output.append(key)
      output.append(value)
    }

    let advertisedServices = [
      advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
      advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID],
    ]
      .compactMap { $0 }
      .flatMap { $0 }
      .map { $0.uuidString.lowercased() }
      .sorted()
    for uuid in advertisedServices {
      appendField(tag: 0x01, key: Data(uuid.utf8))
    }

    let solicitedServices =
      advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []
    for uuid in solicitedServices.map({ $0.uuidString.lowercased() }).sorted() {
      appendField(tag: 0x02, key: Data(uuid.utf8))
    }

    let serviceData =
      advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
    for (uuid, value) in serviceData.sorted(by: {
      $0.key.uuidString < $1.key.uuidString
    }) {
      appendField(
        tag: 0x03,
        key: Data(uuid.uuidString.lowercased().utf8),
        value: value
      )
    }

    if
      let manufacturer =
        advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
      !manufacturer.isEmpty
    {
      if manufacturer.count >= 2 {
        let identifier = UInt16(manufacturer[0]) | UInt16(manufacturer[1]) << 8
        appendField(
          tag: 0x04,
          key: Data([
            UInt8(truncatingIfNeeded: identifier >> 8),
            UInt8(truncatingIfNeeded: identifier),
          ]),
          value: manufacturer.dropFirst(2)
        )
      } else {
        appendField(tag: 0x04, key: Data(), value: manufacturer)
      }
    }
    return output
  }
}
enum IOSMeshInteropPolicy {
  static let linkProof = Data("HB-LINK1".utf8)
  static let identityPacketTypes: Set<UInt8> = [
    IOSMeshProtocol.announce,
    IOSMeshProtocol.hbtCapability,
    IOSMeshProtocol.emergencyCapability,
    IOSMeshProtocol.nodeCapability,
    IOSMeshProtocol.keyRotation,
  ]

  static func shouldProcessPublicMessage(
    privateMode: Bool,
    hearthbitVerified: Bool,
    emergency: Bool
  ) -> Bool {
    !privateMode || hearthbitVerified || emergency
  }

  static func isExternalEmergency(
    privateMode: Bool,
    hearthbitVerified: Bool,
    emergency: Bool
  ) -> Bool {
    privateMode && !hearthbitVerified && emergency
  }

  static func canSendIdentityToLink(
    privateMode: Bool,
    hearthbitProven: Bool,
    emergencyException: Bool
  ) -> Bool {
    !privateMode || hearthbitProven || emergencyException
  }
}
enum IOSEmergencyRetryPolicy {
  static func rebuild(
    packet: IOSMeshPacket,
    localSenderID: Data,
    now: UInt64,
    sign: (IOSMeshPacket) -> IOSMeshPacket
  ) -> IOSMeshPacket? {
    guard
      IOSMeshProtocol.isEmergency(packet),
      packet.senderID == localSenderID,
      packet.timestamp < UInt64.max
    else { return nil }
    var retry = packet
    retry.ttl = IOSMeshProtocol.defaultTTL
    retry.timestamp = max(now, packet.timestamp + 1)
    retry.signature = nil
    retry.isRSR = false
    let signed = sign(retry)
    return signed.signature == nil ? nil : signed
  }
}
enum IOSNoiseReplayPolicy {
  static func isCurrent(
    packetTimestamp: UInt64,
    latestAnnouncementTimestamp: UInt64?
  ) -> Bool {
    guard let latestAnnouncementTimestamp else { return true }
    return packetTimestamp >= latestAnnouncementTimestamp
  }

  static func isStoreForwardSafe(_ packet: IOSMeshPacket) -> Bool {
    let effectiveType = packet.type == IOSMeshProtocol.fragment
      ? IOSMeshProtocol.decodeFragmentPayload(packet.payload)?.originalType ?? packet.type
      : packet.type
    return effectiveType != IOSMeshProtocol.noiseHandshake &&
      effectiveType != IOSMeshProtocol.noiseEncrypted &&
      effectiveType != IOSMeshProtocol.beaconControl &&
      effectiveType != IOSMeshProtocol.rangingControl &&
      effectiveType != IOSMeshProtocol.keyRotation
  }
}
