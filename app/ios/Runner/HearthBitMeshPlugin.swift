import CoreBluetooth
import CoreLocation
import CryptoKit
import Compression
import Flutter
import Foundation
import Security
import UIKit
import UserNotifications
import zlib

private func hearthBitDebugLog(_ format: String, _ arguments: CVarArg...) {
  #if DEBUG
  withVaList(arguments) { Foundation.NSLogv(format, $0) }
  #endif
}

private enum IOSPowerProfile: String {
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
    case .performance, .balanced, .powerSaver: return .max
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

final class HearthBitMeshPlugin: NSObject, FlutterStreamHandler {
  private struct PendingCentralWrite {
    let data: Data
    let characteristic: CBCharacteristic
    let type: CBCharacteristicWriteType
  }

  private static let serviceUUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
  private static let characteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
  private static let maximumPendingBLEFrames = 256
  private static let emergencyBLEFrameReserve = 64
  private static let reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 16, 30]
  private static let reconnectCooldown: TimeInterval = 120
  private static let linkLossScanBurst: TimeInterval = 15
  private static let subscriptionAnnouncementCooldown: TimeInterval = 10
  private static let autoHandshakeCooldown: TimeInterval = 60
  private static let handshakeTimeout: TimeInterval = 20
  private static let maximumHandshakeRestarts = 3
  private static let peerReachabilityWindow = IOSPeerReachabilityPolicy.window
  private static let maximumDecryptFailures = 3

  private var identity: IOSMeshIdentity!
  private var identityFailure: Error?
  private var localRole = IOSMeshNodeRole.load()
  private var privateMode = true
  private var bitchatInteropEnabled = false
  private var announcementTTL: UInt8 {
    privateMode && !bitchatInteropEnabled ? 1 : IOSMeshProtocol.defaultTTL
  }
  private let storeForward = IOSStoreForward()
  private let peerIdentityPins = IOSPeerIdentityPinStore()
  private let emergencyFingerprints = IOSEmergencyFingerprintCache()
  private var central: CBCentralManager?
  private var peripheralManager: CBPeripheralManager?
  private var localCharacteristic: CBMutableCharacteristic?
  private var connectedPeripherals: [UUID: CBPeripheral] = [:]
  private var remoteCharacteristics: [UUID: CBCharacteristic] = [:]
  private var knownMeshPeripherals: [UUID: CBPeripheral] = [:]
  private var preferredPeripheralIDs: Set<UUID> = []
  private var establishedPeripheralIDs: Set<UUID> = []
  private var reconnectAttempts: [UUID: Int] = [:]
  private var reconnectTokens: [UUID: UUID] = [:]
  private var reconnectExhaustedUntil: [UUID: Date] = [:]
  private var peers: [String: IOSMeshPeer] = [:]
  private var sessions: [String: IOSNoiseSession] = [:]
  private var responderCandidates: [String: IOSNoiseSession] = [:]
  private var securePeerIDs: Set<String> = []
  private var privateChatPeerIDs: Set<String> = []
  private var decryptFailures: [String: Int] = [:]
  private var lastAutoHandshake: [String: Date] = [:]
  private var lastNoisePeerActivity: [String: Date] = [:]
  private var latestAnnouncementTimestampByPeer: [String: UInt64] = [:]
  private var handshakeRestartAttempts: [String: Int] = [:]
  private var autoHandshakeTokens: [String: UUID] = [:]
  private var activeHandshakeTimeoutTokens: [String: UUID] = [:]
  private var candidateHandshakeTimeoutTokens: [String: UUID] = [:]
  private var pendingPrivate: [String: [(String, String)]] = [:]
  private var pendingFrames: [String: [Data]] = [:]
  private var pendingCourier: [String: [IOSMeshPacket]] = [:]
  private var seen: [String: Date] = [:]
  private var syncPackets: [String: IOSMeshPacket] = [:]
  private var syncResponseTimes: [UUID: [Date]] = [:]
  private var lastSyncRequestBySource: [UUID: Date] = [:]
  private var remoteRadarConsents: [String: IOSRemoteRadarConsent] = [:]
  private var pendingBeaconRequests: [String: IOSPendingBeaconRequest] = [:]
  private var outgoingBeaconRequests: [String: IOSOutgoingBeaconRequest] = [:]
  private var seenBeaconActions: [String: Date] = [:]
  private var activeBeaconRequest: IOSPendingBeaconRequest?
  private let beaconActuator = IOSBeaconActuator()
  private var centralWriteQueues: [UUID: IOSBLEPriorityQueue<PendingCentralWrite>] = [:]
  private var centralWritesInFlight: Set<UUID> = []
  private var peripheralNotifyQueues: [UUID: IOSBLEPriorityQueue<Data>] = [:]
  private let packetFragmenter = IOSMeshPacketFragmenter()
  private let fragmentReassembler = IOSMeshFragmentReassembler()
  private let genericPresenceTracker = IOSGenericBLEPresenceTracker()
  private var genericPresenceEmitWorkItem: DispatchWorkItem?
  private var genericPresenceExpiryWorkItem: DispatchWorkItem?
  private var genericPresenceScanEnabled = false
  private var genericPresenceWindowActive = false
  private var genericPresenceWindowStartTimer: Timer?
  private var genericPresenceWindowEndTimer: Timer?
  private var restoredPeripheralService = false
  private var configuredPeripheralRole: IOSMeshNodeRole?
  private var lastSubscriptionAnnouncement: [UUID: Date] = [:]
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var eventSink: FlutterEventSink?
  private var running = false
  private var batteryLevel = 100
  private var powerProfile = IOSPowerProfile.balanced
  private var adaptivePowerSaving = false
  private var adaptiveScanTimer: Timer?
  private var linkLossScanTimer: Timer?
  private var lanBridgeGatewayID: String?
  private var lanBridgeMaximumFrameSize = 2048
  private var suppressLanBridge = false
  private lazy var locationManager = CLLocationManager()

  /// Identificador de periférico -> peerId de vecinos directos. Se alimenta
  /// con el service data del anuncio (teléfonos Android) y con anuncios de
  /// malla recibidos con TTL intacto, que solo pueden venir del emisor.
  private var peripheralPeers: [UUID: String] = [:]
  private var hearthbitProvenLinks: Set<UUID> = []
  /// Peer objetivo del radar de rescate; nil cuando el radar está apagado.
  private var radarPeerID: String?
  private var radarTimer: Timer?
  private var secureScreenEnabled = false
  private var secureOverlay: UIView?

  override init() {
    do {
      identity = try IOSMeshIdentity()
    } catch {
      identityFailure = error
      identity = nil
    }
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    initializeBluetoothRestoration()
  }

  static func register(with messenger: FlutterBinaryMessenger) -> HearthBitMeshPlugin {
    let plugin = HearthBitMeshPlugin()
    let methods = FlutterMethodChannel(
      name: "com.hearthbit.mesh/methods",
      binaryMessenger: messenger
    )
    methods.setMethodCallHandler(plugin.handle)
    FlutterEventChannel(
      name: "com.hearthbit.mesh/events",
      binaryMessenger: messenger
    ).setStreamHandler(plugin)

    // Canal de transferencias: en iOS todavía no hay Nearby Connections ni
    // Wi-Fi Aware (requiere iOS 26 + entitlement + DeviceDiscoveryUI), así
    // que se responde con capacidades vacías y el selector Dart usa LAN/BLE.
    let transferMethods = FlutterMethodChannel(
      name: "com.hearthbit.transfer/methods",
      binaryMessenger: messenger
    )
    transferMethods.setMethodCallHandler { call, result in
      switch call.method {
      case "getTransferCapabilities":
        result(["nearby": false, "wifiAware": false])
      case "nearbyStop", "wifiAwareStop":
        result(nil)
      case "nearbySendFile", "nearbyReceiveFile":
        result(
          FlutterError(
            code: "nearby_unavailable",
            message: HearthBitL10n.string("nearby_unavailable"),
            details: nil
          )
        )
      case "wifiAwareSendFile", "wifiAwareReceiveFile":
        result(
          FlutterError(
            code: "wifi_aware_unavailable",
            message: HearthBitL10n.string("wifi_aware_unavailable"),
            details: nil
          )
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(
      name: "com.hearthbit.transfer/events",
      binaryMessenger: messenger
    ).setStreamHandler(HearthBitTransferEventStub())
    return plugin
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    if identityFailure != nil {
      emitStatus("error")
    } else if let storageFailure = storeForward.failure {
      emit([
        "type": "error",
        "code": "store_forward_failed",
        "message": storageFailure.localizedDescription,
      ])
    } else if let pinFailure = peerIdentityPins.failure {
      emit([
        "type": "error",
        "code": "peer_identity_store_failed",
        "message": pinFailure.localizedDescription,
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopLocalBeacon()
    eventSink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "getCapabilities":
        result([
          "platform": "ios",
          "backgroundRelay": true,
          "peripheralMode": true,
          "acousticSonar": true,
          "radioRanging": false,
          "meshtastic": false,
          "nodeRoles": IOSMeshNodeRole.allCases.map(\.rawValue),
        ])
      case "getInstalledApkForShare":
        result(["status": "unsupported"])
      case "getSimCountry":
        // Carrier-country APIs are deprecated on iOS. Flutter falls back to
        // the system region or a country explicitly selected by the user.
        result(nil)
      case "requestPermissions":
        result(true)
      case "requestFamilyNotificationPermission":
        UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        ) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      case "showFamilyNotification":
        let messageID = arguments["messageId"] as? String ?? UUID().uuidString
        let nickname = String((arguments["nickname"] as? String ?? "").prefix(64))
        let statusKey: String
        switch arguments["status"] as? String {
        case "SOS": statusKey = "family_status_sos"
        case "OK": statusKey = "family_status_ok"
        case "HELP": statusKey = "family_status_help"
        case "INJURED": statusKey = "family_status_injured"
        default: statusKey = "family_status_check_in"
        }
        let content = UNMutableNotificationContent()
        content.title = HearthBitL10n.string("family_notification_title")
        content.body = "\(nickname) · \(HearthBitL10n.string(statusKey))"
        content.sound = .default
        content.userInfo = ["openEmergency": true]
        UNUserNotificationCenter.current().add(
          UNNotificationRequest(identifier: messageID, content: content, trigger: nil)
        ) { _ in }
        result(nil)
      case "startMesh":
        try start()
        result(nil)
      case "stopMesh":
        stop()
        result(nil)
      case "getRescueModeState":
        let state = try IOSRescueModeStore.load()
        configureRescueLocationUpdates(for: state)
        result(state.asMap)
      case "configureRescueMode":
        let active = arguments["active"] as? Bool ?? false
        let state: IOSRescueModeState
        if active {
          state = try IOSRescueModeStore.configure(
            description: arguments["description"] as? String ?? "",
            startedAt: (arguments["startedAt"] as? NSNumber)?.int64Value ?? 0,
            lastPingAt: (arguments["lastPingAt"] as? NSNumber)?.int64Value ?? 0,
            expiresAt: (arguments["expiresAt"] as? NSNumber)?.int64Value ?? 0,
            intervalMs: (arguments["intervalMs"] as? NSNumber)?.int64Value ?? 120_000,
            locationPrecision: arguments["locationPrecision"] as? String ?? "approximate"
          )
        } else {
          try IOSRescueModeStore.clear()
          state = try IOSRescueModeStore.load()
        }
        configureRescueLocationUpdates(for: state)
        result(state.asMap)
      case "setLanDiscoveryEnabled":
        // Network.framework/Dart owns Bonjour. The method keeps the native
        // bridge API symmetric with Android, where a MulticastLock is needed.
        result(nil)
      case "setSecureScreen":
        secureScreenEnabled = arguments["enabled"] as? Bool ?? false
        updateSecureOverlay()
        result(nil)
      case "excludeFromBackup":
        guard let path = arguments["path"] as? String else {
          throw IOSMeshError.invalidPayload
        }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        guard standardized.path.hasPrefix(home + "/") else {
          throw IOSMeshError.invalidPayload
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = standardized
        try protectedURL.setResourceValues(values)
        result(nil)
      case "configurePrivacyMode":
        let interop = arguments["bitchatInteropEnabled"] as? Bool ?? false
        bitchatInteropEnabled = interop
        privateMode = (arguments["privateMode"] as? Bool ?? true) && !interop
        if running {
          if privateMode {
            let linkIDs = Set(remoteCharacteristics.keys).union(
              localCharacteristic?.subscribedCentrals?.map(\.identifier) ?? []
            )
            linkIDs.forEach { sendHearthBitLinkProof(to: $0) }
          } else {
            sendAnnouncement()
          }
        }
        result(nil)
      case "setGenericPresenceScanEnabled":
        guard
          let enabled = (call.arguments as? Bool) ?? (arguments["enabled"] as? Bool)
        else {
          throw IOSMeshError.invalidPayload
        }
        setGenericPresenceScanEnabled(enabled)
        result(nil)
      case "configureLanBridge":
        let enabled = arguments["enabled"] as? Bool ?? false
        if !enabled {
          lanBridgeGatewayID = nil
          result(nil)
          return
        }
        guard
          let gatewayID = (arguments["gatewayId"] as? String)?.lowercased(),
          gatewayID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
        else { throw IOSMeshError.invalidPayload }
        let maximum = arguments["maxFrameSize"] as? Int ?? 2048
        guard (1...65_535).contains(maximum) else { throw IOSMeshError.invalidPayload }
        lanBridgeGatewayID = gatewayID
        lanBridgeMaximumFrameSize = maximum
        result(nil)
      case "injectRawMeshFrame":
        guard
          let gatewayID = (arguments["gatewayId"] as? String)?.lowercased(),
          gatewayID == lanBridgeGatewayID,
          let frame = arguments["frame"] as? FlutterStandardTypedData,
          !frame.data.isEmpty,
          frame.data.count <= lanBridgeMaximumFrameSize
        else { throw IOSMeshError.invalidPayload }
        suppressLanBridge = true
        defer { suppressLanBridge = false }
        receive(frame.data, source: nil)
        result(nil)
      case "sendPublic":
        let content = arguments["content"] as? String ?? ""
        result(try sendPublic(content: content, channel: arguments["channel"] as? String))
      case "sendPrivate":
        result(
          try sendPrivate(
            peerID: arguments["peerId"] as? String ?? "",
            content: arguments["content"] as? String ?? "",
            messageID: arguments["messageId"] as? String
          )
        )
      case "ensurePrivateChannel":
        try ensurePrivateChannel(peerID: arguments["peerId"] as? String ?? "")
        result(nil)
      case "sendSos":
        let description =
          arguments["content"] as? String ?? HearthBitL10n.string("sos_default")
        let latitude = arguments["latitude"] as? Double
        let longitude = arguments["longitude"] as? Double
        let location = latitude != nil && longitude != nil
          ? "|\(latitude!)|\(longitude!)" : "||"
        if privateMode {
          sendAnnouncement(
            ttl: IOSMeshProtocol.defaultTTL,
            allowUnprovenIdentity: true
          )
        }
        result(try sendPublic(content: "SOS|\(description)\(location)", channel: "sos"))
      case "sendEmergency":
        let messageID = arguments["messageId"] as? String ?? ""
        let content = arguments["content"] as? String ?? ""
        let channel = arguments["channel"] as? String ?? ""
        guard channel == "sos" || channel == "checkin" else {
          throw IOSMeshError.invalidPayload
        }
        guard content.hasPrefix("SOS|") || content.contains("[HB-CHECKIN|") else {
          throw IOSMeshError.invalidPayload
        }
        if privateMode {
          sendAnnouncement(
            ttl: IOSMeshProtocol.defaultTTL,
            allowUnprovenIdentity: true
          )
        }
        let transmitted = try transmitPublic(
          messageID: String(messageID.prefix(255)),
          content: content,
          channel: channel
        )
        result([
          "messageId": transmitted.id,
          "canonicalHash": IOSMeshProtocol
            .emergencyCanonicalHash(transmitted.packet).hex,
        ])
      case "retryEmergency":
        let canonicalHash = arguments["canonicalHash"] as? String ?? ""
        guard let packet = try storeForward.emergency(hash: canonicalHash) else {
          result(false)
          return
        }
        broadcast(packet)
        result(true)
      case "setNickname":
        guard identity != nil else { throw identityFailure ?? IOSMeshError.identityUnavailable }
        identity.nickname = String((arguments["nickname"] as? String ?? "").prefix(31))
        sendAnnouncement()
        result(nil)
      case "setNodeRole":
        guard
          let value = arguments["role"] as? String,
          let role = IOSMeshNodeRole(rawValue: value)
        else { throw IOSMeshError.invalidPayload }
        let previousRole = localRole
        localRole = role
        role.persist()
        refreshPowerState(emitEvent: false)
        broadcastNodeCapability()
        if running, previousRole != role {
          if role == .phoneBeacon {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
              guard let self, self.running, self.localRole == role else { return }
              self.applyRolePolicy()
            }
          } else {
            applyRolePolicy()
          }
        }
        emitStatus(running ? "active" : "stopped")
        result(nil)
      case "getPeers":
        result(peerMaps())
      case "sendTransferFrame":
        guard
          let peerID = arguments["peerId"] as? String,
          let frame = arguments["frame"] as? FlutterStandardTypedData
        else { throw IOSMeshError.peerUnavailable }
        try sendTransferFrame(peerID: peerID, frame: frame.data)
        result(nil)
      case "sendRangingControl":
        guard
          let peerID = arguments["peerId"] as? String,
          let payload = arguments["payload"] as? FlutterStandardTypedData
        else { throw IOSMeshError.peerUnavailable }
        try sendRangingControl(peerID: peerID.lowercased(), payload: payload.data)
        result(nil)
      case "signPayload":
        guard identity != nil else { throw identityFailure ?? IOSMeshError.identityUnavailable }
        guard let data = arguments["data"] as? FlutterStandardTypedData
        else { throw IOSMeshError.peerUnavailable }
        result(FlutterStandardTypedData(bytes: try identity.signBytes(data.data)))
      case "verifyPeerSignature":
        guard
          let peerID = arguments["peerId"] as? String,
          let data = arguments["data"] as? FlutterStandardTypedData,
          let signature = arguments["signature"] as? FlutterStandardTypedData
        else { throw IOSMeshError.peerUnavailable }
        let verified = peers[peerID].map {
          IOSMeshIdentity.verifyBytes(
            data.data,
            signature: signature.data,
            key: $0.signingPublicKey
          )
        } ?? false
        result(verified)
      case "panicWipe":
        // Limpiar también si Flutter cree que la malla ya estaba detenida.
        stopInternal(notify: true)
        beaconActuator.stop()
        activeBeaconRequest = nil
        try peerIdentityPins.clear()
        identity = nil
        do {
          try IOSMeshIdentity.clear()
          identity = try IOSMeshIdentity()
          identityFailure = nil
        } catch {
          identityFailure = error
          throw error
        }
        try storeForward.clear()
        emergencyFingerprints.clear()
        try IOSRescueModeStore.clear()
        locationManager.stopUpdatingLocation()
        peers.removeAll()
        sessions.removeAll()
        responderCandidates.removeAll()
        securePeerIDs.removeAll()
        privateChatPeerIDs.removeAll()
        pendingPrivate.removeAll()
        pendingFrames.removeAll()
        pendingCourier.removeAll()
        seen.removeAll()
        syncPackets.removeAll()
        syncResponseTimes.removeAll()
        lastSyncRequestBySource.removeAll()
        remoteRadarConsents.removeAll()
        pendingBeaconRequests.removeAll()
        outgoingBeaconRequests.removeAll()
        seenBeaconActions.removeAll()
        fragmentReassembler.clear()
        genericPresenceTracker.clear()
        let wipedState: [String: Any] = [
          "type": "wiped",
          "status": "stopped",
          "peerId": identity.peerIDHex,
          "nickname": identity.nickname,
          "signingPublicKey": FlutterStandardTypedData(
            bytes: identity.signingPrivateKey.publicKey.rawRepresentation
          ),
          "role": localRole.rawValue,
          "peers": [],
        ]
        emit(wipedState)
        result(wipedState)
      case "getPowerStatus":
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshPowerState(emitEvent: false)
        result([
          // iOS no tiene equivalente a Doze configurable por app.
          "ignoringBatteryOptimizations": true,
          "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
          "backgroundLocation": locationAuthorization() == .authorizedAlways,
          "batteryLevel": batteryLevel,
          "adaptivePowerSaving": adaptivePowerSaving,
          "powerProfile": powerProfile.rawValue,
        ])
      case "requestBackgroundLocation":
        // Pide «Permitir siempre»; el sistema decide cuándo mostrar el
        // diálogo. Flutter refresca el estado al volver a primer plano.
        if locationAuthorization() == .notDetermined {
          locationManager.requestWhenInUseAuthorization()
        }
        locationManager.requestAlwaysAuthorization()
        result(locationAuthorization() == .authorizedAlways)
      case "requestDisableBatteryOptimizations":
        // No aplica en iOS; el consejo equivalente es no forzar el cierre de
        // la app y desactivar el Modo de bajo consumo.
        result(true)
      case "startRadar":
        guard let peerID = arguments["peerId"] as? String else {
          throw IOSMeshError.peerUnavailable
        }
        try startRadar(peerID: peerID.lowercased())
        result(nil)
      case "getRangingCapabilities":
        result([
          "available": false,
          "bluetoothChannelSounding": false,
          "wifiNanRtt": false,
          "bleRssi": false,
        ])
      case "startRadioRanging":
        throw IOSMeshError.invalidPayload
      case "stopRadioRanging":
        result(nil)
      case "stopRadar":
        stopRadar()
        result(nil)
      case "setRadarConsent":
        let enabled = arguments["enabled"] as? Bool ?? false
        let minutes = min(max(arguments["minutes"] as? Int ?? 15, 1), 20)
        setRadarConsent(enabled: enabled, duration: TimeInterval(minutes * 60))
        result(nil)
      case "startLocalBeacon":
        guard let flags = UInt8(
          exactly: arguments["flags"] as? Int ?? Int(IOSBeaconControlProtocol.allowedFlags)
        ) else { throw IOSMeshError.invalidPayload }
        let seconds = min(max(arguments["durationSeconds"] as? Int ?? 300, 1), 300)
        try startLocalBeacon(flags: flags, duration: TimeInterval(seconds))
        result(nil)
      case "stopLocalBeacon":
        stopLocalBeacon()
        result(nil)
      case "requestRemoteBeacon":
        guard let peerID = arguments["peerId"] as? String else {
          throw IOSMeshError.peerUnavailable
        }
        guard let flags = UInt8(
          exactly: arguments["flags"] as? Int ?? Int(IOSBeaconControlProtocol.allowedFlags)
        ) else { throw IOSMeshError.invalidPayload }
        let seconds = min(max(arguments["durationSeconds"] as? Int ?? 300, 1), 300)
        result(
          try requestRemoteBeacon(
            peerID: peerID.lowercased(),
            flags: flags,
            duration: TimeInterval(seconds)
          )
        )
      case "respondToBeaconRequest":
        guard let requestID = arguments["requestId"] as? String else {
          throw IOSMeshError.invalidPayload
        }
        try respondToBeaconRequest(
          requestID: requestID.lowercased(),
          accept: arguments["accept"] as? Bool ?? false
        )
        result(nil)
      case "stopRemoteBeacon":
        guard
          let peerID = arguments["peerId"] as? String,
          let requestID = arguments["requestId"] as? String
        else { throw IOSMeshError.invalidPayload }
        try stopRemoteBeacon(peerID: peerID.lowercased(), requestID: requestID.lowercased())
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "mesh_error", message: error.localizedDescription, details: nil))
    }
  }

  @objc private func screenCaptureChanged() {
    updateSecureOverlay()
  }

  private func updateSecureOverlay() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let shouldCover = secureScreenEnabled && UIScreen.main.isCaptured
      if !shouldCover {
        secureOverlay?.removeFromSuperview()
        secureOverlay = nil
        return
      }
      guard secureOverlay == nil else { return }
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
      guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
      let overlay = UIView(frame: window.bounds)
      overlay.backgroundColor = .black
      overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(overlay)
      secureOverlay = overlay
    }
  }

  private func locationAuthorization() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func configureRescueLocationUpdates(for state: IOSRescueModeState) {
    guard state.active else {
      if radarPeerID == nil { locationManager.stopUpdatingLocation() }
      return
    }
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    locationManager.distanceFilter = 25
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.showsBackgroundLocationIndicator = true
    locationManager.startUpdatingLocation()
  }

  private func handleRescueLocation(_ location: CLLocation) {
    let state: IOSRescueModeState
    do {
      state = try IOSRescueModeStore.load()
    } catch {
      locationManager.stopUpdatingLocation()
      emit(["type": "error", "code": "rescue_storage_failed", "message": error.localizedDescription])
      return
    }
    guard state.active else {
      configureRescueLocationUpdates(for: state)
      return
    }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    guard state.lastPingAt <= 0 || now - state.lastPingAt >= state.intervalMs else {
      return
    }
    if !running {
      do {
        try start()
      } catch {
        emit(["type": "error", "code": "mesh_start_failed", "message": error.localizedDescription])
        return
      }
    }
    let locationSuffix: String
    switch state.locationPrecision ?? "approximate" {
    case "none":
      locationSuffix = "||"
    case "exact":
      locationSuffix = "|\(location.coordinate.latitude)|\(location.coordinate.longitude)"
    default:
      let latitude = (location.coordinate.latitude * 1_000).rounded() / 1_000
      let longitude = (location.coordinate.longitude * 1_000).rounded() / 1_000
      locationSuffix = "|\(latitude)|\(longitude)"
    }
    do {
      _ = try sendPublic(
        content: "SOS|\(state.description)\(locationSuffix)",
        channel: "sos"
      )
      try IOSRescueModeStore.recordPing(now)
      emit(["type": "rescuePing", "timestamp": now])
    } catch {
      emit(["type": "error", "message": error.localizedDescription])
    }
  }

  private func initializeBluetoothRestoration() {
    guard central == nil, peripheralManager == nil else { return }
    central = CBCentralManager(
      delegate: self,
      queue: nil,
      options: [CBCentralManagerOptionRestoreIdentifierKey: "HearthBit.central"]
    )
    peripheralManager = CBPeripheralManager(
      delegate: self,
      queue: nil,
      options: [CBPeripheralManagerOptionRestoreIdentifierKey: "HearthBit.peripheral"]
    )
  }

  private func start() throws {
    guard identity != nil else {
      throw identityFailure ?? IOSMeshError.identityUnavailable
    }
    if let storageFailure = storeForward.failure {
      throw storageFailure
    }
    if let pinFailure = peerIdentityPins.failure {
      throw pinFailure
    }
    // Reinicio real: liberar recursos previos permite reintentar tras un fallo.
    if running { stopInternal(notify: false) }
    running = true
    UIDevice.current.isBatteryMonitoringEnabled = true
    refreshPowerState(emitEvent: false)
    emitStatus("starting")
    initializeBluetoothRestoration()
    // Los managers sobreviven a stopInternal(). Si ya están encendidos, sus
    // callbacks de cambio de estado no volverán a ejecutarse al reactivar.
    if peripheralManager?.state == .poweredOn {
      configurePeripheralMode()
    }
    if central?.state == .poweredOn {
      restartScan()
      reconnectKnownPeripherals()
    }
    if lifecycleObservers.isEmpty {
      let center = NotificationCenter.default
      lifecycleObservers = [
        center.addObserver(
          forName: UIApplication.didEnterBackgroundNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.stopLocalBeacon()
          self?.refreshPowerState()
          self?.restartScan()
        },
        center.addObserver(
          forName: UIApplication.didBecomeActiveNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.refreshPowerState()
          self?.restartScan()
        },
        center.addObserver(
          forName: UIDevice.batteryLevelDidChangeNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.refreshPowerState() },
        center.addObserver(
          forName: UIDevice.batteryStateDidChangeNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.refreshPowerState() },
        center.addObserver(
          forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
          object: nil,
          queue: .main
        ) { [weak self] _ in self?.refreshPowerState() },
      ]
    }
    do {
      configureRescueLocationUpdates(for: try IOSRescueModeStore.load())
    } catch {
      emit(["type": "error", "code": "rescue_storage_failed", "message": error.localizedDescription])
    }
  }

  private func stop() {
    guard running else { return }
    stopInternal(notify: true)
  }

  private func stopInternal(notify: Bool) {
    running = false
    stopRadar()
    beaconActuator.stop()
    pendingBeaconRequests.removeAll()
    outgoingBeaconRequests.removeAll()
    seenBeaconActions.removeAll()
    activeBeaconRequest = nil
    adaptiveScanTimer?.invalidate()
    adaptiveScanTimer = nil
    linkLossScanTimer?.invalidate()
    linkLossScanTimer = nil
    central?.stopScan()
    connectedPeripherals.values.forEach { central?.cancelPeripheralConnection($0) }
    connectedPeripherals.removeAll()
    remoteCharacteristics.removeAll()
    knownMeshPeripherals.removeAll()
    preferredPeripheralIDs.removeAll()
    establishedPeripheralIDs.removeAll()
    reconnectAttempts.removeAll()
    reconnectTokens.removeAll()
    reconnectExhaustedUntil.removeAll()
    centralWriteQueues.removeAll()
    centralWritesInFlight.removeAll()
    peripheralNotifyQueues.removeAll()
    peripheralPeers.removeAll()
    hearthbitProvenLinks.removeAll()
    peripheralManager?.stopAdvertising()
    peripheralManager?.removeAllServices()
    localCharacteristic = nil
    restoredPeripheralService = false
    configuredPeripheralRole = nil
    sessions.removeAll()
    responderCandidates.removeAll()
    securePeerIDs.removeAll()
    privateChatPeerIDs.removeAll()
    decryptFailures.removeAll()
    lastAutoHandshake.removeAll()
    lastNoisePeerActivity.removeAll()
    latestAnnouncementTimestampByPeer.removeAll()
    handshakeRestartAttempts.removeAll()
    autoHandshakeTokens.removeAll()
    activeHandshakeTimeoutTokens.removeAll()
    candidateHandshakeTimeoutTokens.removeAll()
    pendingPrivate.removeAll()
    pendingFrames.removeAll()
    pendingCourier.removeAll()
    lastSubscriptionAnnouncement.removeAll()
    syncResponseTimes.removeAll()
    lastSyncRequestBySource.removeAll()
    remoteRadarConsents.removeAll()
    fragmentReassembler.clear()
    genericPresenceEmitWorkItem?.cancel()
    genericPresenceEmitWorkItem = nil
    genericPresenceExpiryWorkItem?.cancel()
    genericPresenceExpiryWorkItem = nil
    cancelGenericPresenceScanWindows()
    genericPresenceTracker.clear()
    lanBridgeGatewayID = nil
    suppressLanBridge = false
    lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    lifecycleObservers.removeAll()
    if notify { emitStatus("stopped") }
  }

  /// Radar de rescate: emite lecturas RSSI del peer objetivo combinando los
  /// anuncios captados por el escaneo (con duplicados activados) y lecturas
  /// periódicas `readRSSI()` sobre periféricos conectados.
  private func startRadar(peerID: String) throws {
    guard isRadarAllowed(peerID: peerID) else {
      throw IOSMeshError.radarConsentRequired
    }
    radarPeerID = peerID
    refreshPowerState()
    restartScan()
    radarTimer?.invalidate()
    radarTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self, let target = self.radarPeerID else { return }
      guard self.isRadarAllowed(peerID: target) else {
        self.stopRadar()
        self.emit(["type": "radarExpired", "peerId": target])
        return
      }
      for (identifier, peripheral) in self.connectedPeripherals
      where self.peripheralPeers[identifier] == target && peripheral.state == .connected {
        peripheral.readRSSI()
      }
    }
  }

  private func stopRadar() {
    radarPeerID = nil
    refreshPowerState()
    radarTimer?.invalidate()
    radarTimer = nil
    restartScan()
  }

  private func applyRolePolicy() {
    if localRole == .phoneBeacon {
      enterPresenceOnlyMode()
    } else {
      enterDataRelayMode()
    }
  }

  private func enterPresenceOnlyMode() {
    radarPeerID = nil
    radarTimer?.invalidate()
    radarTimer = nil
    adaptiveScanTimer?.invalidate()
    adaptiveScanTimer = nil
    linkLossScanTimer?.invalidate()
    linkLossScanTimer = nil
    central?.stopScan()
    connectedPeripherals.values.forEach { central?.cancelPeripheralConnection($0) }
    connectedPeripherals.removeAll()
    remoteCharacteristics.removeAll()
    knownMeshPeripherals.removeAll()
    preferredPeripheralIDs.removeAll()
    establishedPeripheralIDs.removeAll()
    reconnectAttempts.removeAll()
    reconnectTokens.removeAll()
    reconnectExhaustedUntil.removeAll()
    centralWriteQueues.removeAll()
    centralWritesInFlight.removeAll()
    peripheralNotifyQueues.removeAll()
    peripheralPeers.removeAll()
    hearthbitProvenLinks.removeAll()
    sessions.removeAll()
    responderCandidates.removeAll()
    securePeerIDs.removeAll()
    privateChatPeerIDs.removeAll()
    decryptFailures.removeAll()
    lastAutoHandshake.removeAll()
    lastNoisePeerActivity.removeAll()
    latestAnnouncementTimestampByPeer.removeAll()
    handshakeRestartAttempts.removeAll()
    autoHandshakeTokens.removeAll()
    activeHandshakeTimeoutTokens.removeAll()
    candidateHandshakeTimeoutTokens.removeAll()
    pendingPrivate.removeAll()
    pendingFrames.removeAll()
    pendingCourier.removeAll()
    lastSubscriptionAnnouncement.removeAll()
    fragmentReassembler.clear()
    lastSyncRequestBySource.removeAll()
    syncResponseTimes.removeAll()
    genericPresenceEmitWorkItem?.cancel()
    genericPresenceEmitWorkItem = nil
    genericPresenceExpiryWorkItem?.cancel()
    genericPresenceExpiryWorkItem = nil
    cancelGenericPresenceScanWindows()
    genericPresenceTracker.clear()
    emit(["type": "presences", "presences": []])
    configurePeripheralMode()
  }

  private func enterDataRelayMode() {
    restartScan()
    configurePeripheralMode()
  }

  private func configurePeripheralMode() {
    guard let peripheralManager, peripheralManager.state == .poweredOn else { return }
    if configuredPeripheralRole == localRole {
      if !peripheralManager.isAdvertising {
        peripheralManager.startAdvertising([
          CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
        ])
      }
      return
    }
    restoredPeripheralService = false
    peripheralManager.stopAdvertising()
    peripheralManager.removeAllServices()
    localCharacteristic = nil
    peripheralNotifyQueues.removeAll()

    if localRole == .phoneBeacon {
      // CoreBluetooth no ofrece un flag para advertising no conectable. Sin
      // servicio GATT no hay suscripciones ni plano de datos que restaurar.
      peripheralManager.startAdvertising([
        CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
      ])
      configuredPeripheralRole = localRole
      return
    }

    let characteristic = CBMutableCharacteristic(
      type: Self.characteristicUUID,
      properties: [.read, .write, .writeWithoutResponse, .notify],
      value: nil,
      permissions: [.readable, .writeable]
    )
    let service = CBMutableService(type: Self.serviceUUID, primary: true)
    service.characteristics = [characteristic]
    localCharacteristic = characteristic
    peripheralManager.add(service)
    configuredPeripheralRole = localRole
    peripheralManager.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
    ])
  }

  private func setRadarConsent(enabled: Bool, duration: TimeInterval) {
    let expiresAt = enabled
      ? Date().addingTimeInterval(duration).timeIntervalSince1970 * 1000
      : 0
    UserDefaults.standard.set(expiresAt, forKey: IOSRadarConsentProtocol.localConsentKey)
    broadcastRadarConsent(grant: enabled)
    emitRadarConsent()
  }

  private func startLocalBeacon(flags: UInt8, duration: TimeInterval) throws {
    let expiresAt = currentMilliseconds() +
      UInt64(min(max(duration, 0.001), 300) * 1000)
    guard startBeaconActuator(flags: flags, expiresAt: expiresAt) else {
      throw IOSMeshError.invalidPayload
    }
  }

  private func stopLocalBeacon() {
    let active = activeBeaconRequest
    beaconActuator.stop()
    activeBeaconRequest = nil
    if let active {
      try? sendBeaconControl(
        peerID: active.peerID,
        payload: IOSBeaconControlProtocol.stop(nonce: active.control.nonce)
      )
    }
    emitLocalBeaconState(status: "stopped")
  }

  private func requestRemoteBeacon(
    peerID: String,
    flags: UInt8,
    duration: TimeInterval
  ) throws -> String {
    guard peers[peerID] != nil else { throw IOSMeshError.peerUnavailable }
    guard flags != 0, flags & ~IOSBeaconControlProtocol.allowedFlags == 0 else {
      throw IOSMeshError.invalidPayload
    }
    let expiresAt = currentMilliseconds() +
      UInt64(min(max(duration, 0.001), 300) * 1000)
    let now = currentMilliseconds()
    outgoingBeaconRequests = outgoingBeaconRequests.filter { $0.value.expiresAt > now }
    let payload = IOSBeaconControlProtocol.request(expiresAt: expiresAt, flags: flags)
    guard let control = IOSBeaconControlProtocol.decode(payload) else {
      throw IOSMeshError.invalidPayload
    }
    let requestID = control.nonce.hex
    outgoingBeaconRequests[requestID] = IOSOutgoingBeaconRequest(
      peerID: peerID,
      expiresAt: expiresAt,
      flags: flags
    )
    try sendBeaconControl(peerID: peerID, payload: payload)
    emitRemoteBeaconState(
      peerID: peerID,
      requestID: requestID,
      status: "requested",
      expiresAt: expiresAt,
      flags: flags
    )
    return requestID
  }

  private func respondToBeaconRequest(requestID: String, accept: Bool) throws {
    guard let request = pendingBeaconRequests.removeValue(forKey: requestID) else {
      throw IOSMeshError.invalidPayload
    }
    guard IOSBeaconControlProtocol.isValid(
      request.control,
      packetTimestamp: currentMilliseconds()
    ) else {
      try? sendBeaconControl(
        peerID: request.peerID,
        payload: IOSBeaconControlProtocol.revoke(nonce: request.control.nonce)
      )
      throw IOSMeshError.invalidPayload
    }
    respondToBeaconRequest(request, accept: accept, autoAccepted: false)
  }

  private func stopRemoteBeacon(peerID: String, requestID: String) throws {
    guard
      let outgoing = outgoingBeaconRequests.removeValue(forKey: requestID),
      outgoing.peerID == peerID,
      let nonce = try? Data(hex: requestID),
      nonce.count == IOSBeaconControlProtocol.nonceSize
    else { throw IOSMeshError.invalidPayload }
    try sendBeaconControl(
      peerID: peerID,
      payload: IOSBeaconControlProtocol.stop(nonce: nonce)
    )
    emitRemoteBeaconState(
      peerID: peerID,
      requestID: requestID,
      status: "stopped",
      expiresAt: 0,
      flags: 0
    )
  }

  private func sendBeaconControl(peerID: String, payload: Data) throws {
    guard running else { throw IOSMeshError.notRunning }
    let packet = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.beaconControl,
        ttl: 1,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        recipientID: try Data(hex: peerID),
        payload: payload
      )
    )
    broadcast(packet)
  }

  private func sendRangingControl(peerID: String, payload: Data) throws {
    guard running else { throw IOSMeshError.notRunning }
    guard IOSRangingControlProtocol.decode(payload) != nil else {
      throw IOSMeshError.invalidPayload
    }
    let packet = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.rangingControl,
        ttl: 1,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        recipientID: try Data(hex: peerID),
        payload: payload
      )
    )
    broadcast(packet)
  }

  private func respondToBeaconRequest(
    _ request: IOSPendingBeaconRequest,
    accept: Bool,
    autoAccepted: Bool
  ) {
    let requestID = request.control.nonce.hex
    guard accept, startBeaconActuator(
      flags: request.control.flags,
      expiresAt: request.control.expiresAt
    ) else {
      try? sendBeaconControl(
        peerID: request.peerID,
        payload: IOSBeaconControlProtocol.revoke(nonce: request.control.nonce)
      )
      emit([
        "type": "beaconRequestResolved",
        "requestId": requestID,
        "peerId": request.peerID,
        "accepted": false,
        "autoAccepted": autoAccepted,
      ])
      return
    }
    activeBeaconRequest = request
    try? sendBeaconControl(
      peerID: request.peerID,
      payload: IOSBeaconControlProtocol.grant(
        expiresAt: request.control.expiresAt,
        flags: request.control.flags,
        nonce: request.control.nonce
      )
    )
    emit([
      "type": "beaconRequestResolved",
      "requestId": requestID,
      "peerId": request.peerID,
      "accepted": true,
      "autoAccepted": autoAccepted,
    ])
  }

  private func startBeaconActuator(flags: UInt8, expiresAt: UInt64) -> Bool {
    let started = beaconActuator.start(flags: flags, expiresAt: expiresAt) { [weak self] in
      guard let self else { return }
      let expired = self.activeBeaconRequest
      self.activeBeaconRequest = nil
      if let expired, self.running {
        try? self.sendBeaconControl(
          peerID: expired.peerID,
          payload: IOSBeaconControlProtocol.stop(nonce: expired.control.nonce)
        )
      }
      self.emitLocalBeaconState(status: "expired")
    }
    if started {
      emitLocalBeaconState(status: "active", flags: flags, expiresAt: expiresAt)
    }
    return started
  }

  private func emitLocalBeaconState(
    status: String,
    flags: UInt8 = 0,
    expiresAt: UInt64 = 0
  ) {
    emit([
      "type": "beaconState",
      "scope": "local",
      "status": status,
      "flags": Int(flags),
      "expiresAt": expiresAt,
    ])
  }

  private func emitRemoteBeaconState(
    peerID: String,
    requestID: String,
    status: String,
    expiresAt: UInt64,
    flags: UInt8
  ) {
    emit([
      "type": "beaconState",
      "scope": "remote",
      "peerId": peerID,
      "requestId": requestID,
      "status": status,
      "expiresAt": expiresAt,
      "flags": Int(flags),
    ])
  }

  private func setGenericPresenceScanEnabled(_ enabled: Bool) {
    genericPresenceScanEnabled = enabled
    cancelGenericPresenceScanWindows()
    if !enabled {
      genericPresenceEmitWorkItem?.cancel()
      genericPresenceEmitWorkItem = nil
      genericPresenceExpiryWorkItem?.cancel()
      genericPresenceExpiryWorkItem = nil
      genericPresenceTracker.clear()
      emit(["type": "presences", "presences": []])
    }
    if running {
      restartScan()
    }
  }

  private func cancelGenericPresenceScanWindows() {
    genericPresenceWindowStartTimer?.invalidate()
    genericPresenceWindowStartTimer = nil
    genericPresenceWindowEndTimer?.invalidate()
    genericPresenceWindowEndTimer = nil
    genericPresenceWindowActive = false
  }

  private func genericPresenceWindowIsAllowed() -> Bool {
    running &&
      genericPresenceScanEnabled &&
      localRole.allowsDataPlane &&
      !powerProfile.savesPower &&
      UIApplication.shared.applicationState == .active &&
      radarPeerID == nil &&
      linkLossScanTimer == nil
  }

  private func startFilteredMeshScan(
    using central: CBCentralManager,
    allowDuplicates: Bool
  ) {
    let safeAllowDuplicates = allowDuplicates && radarPeerID != nil
    central.stopScan()
    central.scanForPeripherals(
      withServices: [Self.serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: safeAllowDuplicates]
    )
  }

  private func beginGenericPresenceWindow() {
    genericPresenceWindowStartTimer?.invalidate()
    genericPresenceWindowStartTimer = nil
    guard
      genericPresenceWindowIsAllowed(),
      let central = central,
      central.state == .poweredOn
    else {
      genericPresenceWindowActive = false
      return
    }

    genericPresenceWindowActive = true
    let selection = IOSGenericBLEScanPolicy.selection(
      genericEnabled: genericPresenceScanEnabled,
      genericWindowActive: genericPresenceWindowActive,
      foreground: UIApplication.shared.applicationState == .active,
      radarActive: radarPeerID != nil,
      recoveryActive: linkLossScanTimer != nil
    )
    guard selection == .genericUnfiltered else {
      genericPresenceWindowActive = false
      return
    }
    central.stopScan()
    central.scanForPeripherals(
      withServices: nil,
      options: [
        CBCentralManagerScanOptionAllowDuplicatesKey: false
      ]
    )
    genericPresenceWindowEndTimer?.invalidate()
    genericPresenceWindowEndTimer = Timer.scheduledTimer(
      withTimeInterval: IOSGenericBLEScanPolicy.windowDuration,
      repeats: false
    ) { [weak self] _ in
      guard let self = self else { return }
      self.genericPresenceWindowEndTimer = nil
      self.genericPresenceWindowActive = false
      guard
        self.running,
        let central = self.central,
        central.state == .poweredOn,
        self.localRole.allowsDataPlane
      else { return }

      let foreground = UIApplication.shared.applicationState == .active
      let selection = IOSGenericBLEScanPolicy.selection(
        genericEnabled: self.genericPresenceScanEnabled,
        genericWindowActive: false,
        foreground: foreground,
        radarActive: self.radarPeerID != nil,
        recoveryActive: self.linkLossScanTimer != nil
      )
      switch selection {
      case .meshFiltered:
        let allowDuplicates = foreground && self.radarPeerID != nil
        self.startFilteredMeshScan(
          using: central,
          allowDuplicates: allowDuplicates
        )
      case .genericUnfiltered:
        break
      }
      self.scheduleNextGenericPresenceWindow()
    }
  }

  private func scheduleNextGenericPresenceWindow() {
    genericPresenceWindowStartTimer?.invalidate()
    genericPresenceWindowStartTimer = nil
    guard genericPresenceWindowIsAllowed() else { return }
    genericPresenceWindowStartTimer = Timer.scheduledTimer(
      withTimeInterval: IOSGenericBLEScanPolicy.pauseDuration,
      repeats: false
    ) { [weak self] _ in
      self?.beginGenericPresenceWindow()
    }
  }

  /// El filtro HearthBit es la base. La presencia genérica, si Flutter la
  /// habilita, sustituye ese scan solo durante ventanas acotadas en foreground.
  private func restartScan() {
    guard running, let central, central.state == .poweredOn else { return }
    adaptiveScanTimer?.invalidate()
    adaptiveScanTimer = nil
    cancelGenericPresenceScanWindows()
    central.stopScan()
    guard localRole.allowsDataPlane else { return }
    let foreground = UIApplication.shared.applicationState == .active
    guard powerProfile != .survival || radarPeerID != nil else { return }
    if radarPeerID != nil {
      startFilteredMeshScan(using: central, allowDuplicates: true)
      return
    }
    if linkLossScanTimer != nil {
      startFilteredMeshScan(using: central, allowDuplicates: false)
      return
    }
    // En segundo plano iOS ya coalescea y limita el escaneo. Mantener un scan
    // filtrado continuo es más fiable que depender de timers que el SO suspende.
    if !foreground {
      startFilteredMeshScan(using: central, allowDuplicates: false)
      return
    }
    if genericPresenceScanEnabled {
      startFilteredMeshScan(
        using: central,
        allowDuplicates: false
      )
      beginGenericPresenceWindow()
      return
    }
    if powerProfile.scanBurst > 0 {
      startAdaptiveScanBurst()
      return
    }
    startFilteredMeshScan(
      using: central,
      allowDuplicates: false
    )
  }

  private func startAdaptiveScanBurst() {
    guard
      running,
      let central,
      central.state == .poweredOn,
      localRole.allowsDataPlane,
      powerProfile.scanBurst > 0
    else { return }
    let profile = powerProfile
    central.stopScan()
    central.scanForPeripherals(
      withServices: [Self.serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    adaptiveScanTimer = Timer.scheduledTimer(
      withTimeInterval: profile.scanBurst,
      repeats: false
    ) { [weak self] _ in
      guard let self, self.running, self.powerProfile == profile else { return }
      self.central?.stopScan()
      self.adaptiveScanTimer = Timer.scheduledTimer(
        withTimeInterval: profile.scanPause,
        repeats: false
      ) { [weak self] _ in
        guard let self, self.running, self.powerProfile == profile else { return }
        self.restartScan()
      }
    }
  }

  private func refreshPowerState(emitEvent: Bool = true) {
    let deviceLevel = UIDevice.current.batteryLevel
    let level = deviceLevel < 0 ? 100 : Int((deviceLevel * 100).rounded())
    let charging: Bool
    switch UIDevice.current.batteryState {
    case .charging, .full: charging = true
    case .unknown, .unplugged: charging = false
    @unknown default: charging = false
    }
    let nextProfile = IOSPowerProfile.resolve(
      batteryLevel: level,
      charging: charging,
      foreground: UIApplication.shared.applicationState == .active,
      lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
      survivalMode: localRole == .phoneBeacon,
      highPerformanceRequested: radarPeerID != nil ||
        ((try? IOSRescueModeStore.load().active) ?? false)
    )
    let changed = nextProfile != powerProfile
    batteryLevel = level
    powerProfile = nextProfile
    adaptivePowerSaving = powerProfile.savesPower
    if changed && running && radarPeerID == nil {
      restartScan()
    }
    if emitEvent {
      emit([
        "type": "power",
        "batteryLevel": batteryLevel,
        "adaptivePowerSaving": adaptivePowerSaving,
        "powerProfile": powerProfile.rawValue,
      ])
    }
  }

  private func emitRssi(peerID: String, rssi: Int) {
    emit([
      "type": "rssi",
      "peerId": peerID,
      "rssi": rssi,
      "at": Int(Date().timeIntervalSince1970 * 1000),
    ])
  }

  @discardableResult
  private func sendPublic(content: String, channel: String?) throws -> String {
    try transmitPublic(
      messageID: UUID().uuidString.uppercased(),
      content: content,
      channel: channel
    ).id
  }

  private func transmitPublic(
    messageID: String,
    content: String,
    channel: String?
  ) throws -> (id: String, packet: IOSMeshPacket) {
    guard running else { throw IOSMeshError.notRunning }
    guard localRole.canChat else { throw IOSMeshError.roleCannotChat }
    let id = messageID.isEmpty ? UUID().uuidString.uppercased() : messageID
    let payload = Data(String(content.prefix(2000)).utf8)
    let packet = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.message,
        ttl: IOSMeshProtocol.defaultTTL,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
        senderID: identity.peerID,
        payload: payload
      )
    )
    broadcast(packet)
    emitMessage(
      id: id,
      sender: identity.nickname,
      content: content,
      senderPeerID: identity.peerIDHex,
      isPrivate: false,
      isMine: true,
      timestamp: packet.timestamp,
      channel: channel
    )
    return (id, packet)
  }

  private func ensurePrivateChannel(peerID: String) throws {
    guard localRole.canChat else { throw IOSMeshError.roleCannotChat }
    guard peers[peerID]?.role.canChat == true, isPeerReachable(peerID) else {
      throw IOSMeshError.peerUnavailable
    }
    privateChatPeerIDs.insert(peerID)
    if sessions[peerID]?.requiresRekey == true {
      invalidateNoiseState(peerID: peerID)
    }
    if sessions[peerID]?.established != true {
      try initiateHandshake(peerID: peerID)
    }
  }

  private func sendPrivate(
    peerID: String,
    content: String,
    messageID: String? = nil
  ) throws -> String {
    guard localRole.canChat else { throw IOSMeshError.roleCannotChat }
    guard peers[peerID]?.role.canChat == true, isPeerReachable(peerID) else {
      throw IOSMeshError.peerUnavailable
    }
    privateChatPeerIDs.insert(peerID)
    let requestedID = messageID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let id: String
    if let requestedID, !requestedID.isEmpty {
      id = String(requestedID.prefix(255))
    } else {
      id = UUID().uuidString.uppercased()
    }
    if sessions[peerID]?.requiresRekey == true {
      invalidateNoiseState(peerID: peerID)
      try initiateHandshake(peerID: peerID)
      throw IOSMeshError.noiseRekeyRequired
    }
    guard let session = sessions[peerID], session.established else {
      try initiateHandshake(peerID: peerID)
      throw IOSMeshError.peerUnavailable
    }
    try sendEncryptedPrivate(peerID: peerID, id: id, content: content)
    emitMessage(
      id: id,
      sender: identity.nickname,
      content: content,
      senderPeerID: peerID,
      isPrivate: true,
      isMine: true,
      timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
      channel: nil
    )
    return id
  }

  /// Envía una trama HBT al peer por la sesión Noise; si aún no hay sesión,
  /// la deja en cola y dispara el handshake.
  private func sendTransferFrame(peerID: String, frame: Data) throws {
    guard peers[peerID] != nil else { throw IOSMeshError.peerUnavailable }
    guard frame.count <= 2048 else { throw IOSMeshError.invalidPayload }
    if let session = sessions[peerID], session.established {
      try sendEncryptedFrame(peerID: peerID, frame: frame)
      return
    }
    pendingFrames[peerID, default: []].append(frame)
    try initiateHandshake(peerID: peerID)
  }

  private func initiateHandshake(peerID: String) throws {
    guard running, localRole.allowsDataPlane else { return }
    guard sessions[peerID] == nil, responderCandidates[peerID] == nil else { return }
    let claimed = try Data(hex: peerID)
    let session = IOSNoiseSession(
      claimedPeerID: claimed,
      initiator: true,
      localStatic: identity.noisePrivateKey
    )
    sessions[peerID] = session
    touchActiveHandshake(peerID: peerID)
    do {
      sendNoise(
        type: IOSMeshProtocol.noiseHandshake,
        recipient: claimed,
        payload: try session.start()
      )
    } catch {
      sessions.removeValue(forKey: peerID)
      activeHandshakeTimeoutTokens.removeValue(forKey: peerID)
      throw error
    }
  }

  private func shouldAutoHandshake(peerID: String) -> Bool {
    securePeerIDs.contains(peerID) ||
      privateChatPeerIDs.contains(peerID) ||
      !(pendingPrivate[peerID] ?? []).isEmpty ||
      !(pendingFrames[peerID] ?? []).isEmpty ||
      !(pendingCourier[peerID] ?? []).isEmpty
  }

  private func isPeerReachable(_ peerID: String) -> Bool {
    IOSPeerReachabilityPolicy.isOnline(
      lastActivity: lastPeerActivity(peerID),
      now: Date(),
      window: Self.peerReachabilityWindow
    )
  }

  private func lastPeerActivity(_ peerID: String) -> Date? {
    let announcement = peers[peerID]?.lastSeen
    let noise = lastNoisePeerActivity[peerID]
    return [announcement, noise].compactMap { $0 }.max()
  }

  private func scheduleAutoHandshake(
    peerID: String,
    force: Bool = false,
    delay: TimeInterval = 1.5
  ) {
    guard
      running,
      localRole.allowsDataPlane,
      peerID != identity.peerIDHex,
      sessions[peerID]?.established != true,
      autoHandshakeTokens[peerID] == nil
    else { return }
    if !force {
      guard shouldAutoHandshake(peerID: peerID) else { return }
      if let previous = lastAutoHandshake[peerID],
         Date().timeIntervalSince(previous) < Self.autoHandshakeCooldown {
        return
      }
    }
    let token = UUID()
    autoHandshakeTokens[peerID] = token
    lastAutoHandshake[peerID] = Date()
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard
        let self,
        self.autoHandshakeTokens[peerID] == token
      else { return }
      self.autoHandshakeTokens.removeValue(forKey: peerID)
      guard
        self.running,
        self.localRole.allowsDataPlane,
        self.isPeerReachable(peerID),
        self.sessions[peerID] == nil,
        self.responderCandidates[peerID] == nil
      else { return }
      try? self.initiateHandshake(peerID: peerID)
    }
  }

  private func touchActiveHandshake(peerID: String) {
    guard sessions[peerID]?.handshaking == true else {
      activeHandshakeTimeoutTokens.removeValue(forKey: peerID)
      return
    }
    let token = UUID()
    activeHandshakeTimeoutTokens[peerID] = token
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.handshakeTimeout) { [weak self] in
      guard
        let self,
        self.activeHandshakeTimeoutTokens[peerID] == token,
        self.sessions[peerID]?.handshaking == true
      else { return }
      self.activeHandshakeTimeoutTokens.removeValue(forKey: peerID)
      self.sessions.removeValue(forKey: peerID)
      self.decryptFailures.removeValue(forKey: peerID)
      self.emit(["type": "peers", "peers": self.peerMaps()])
      let restarts = (self.handshakeRestartAttempts[peerID] ?? 0) + 1
      self.handshakeRestartAttempts[peerID] = restarts
      if restarts <= Self.maximumHandshakeRestarts, self.isPeerReachable(peerID) {
        self.scheduleAutoHandshake(peerID: peerID, force: true, delay: 0.5)
      }
    }
  }

  private func touchCandidateHandshake(peerID: String) {
    guard responderCandidates[peerID]?.handshaking == true else {
      candidateHandshakeTimeoutTokens.removeValue(forKey: peerID)
      return
    }
    let token = UUID()
    candidateHandshakeTimeoutTokens[peerID] = token
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.handshakeTimeout) { [weak self] in
      guard
        let self,
        self.candidateHandshakeTimeoutTokens[peerID] == token,
        self.responderCandidates[peerID]?.handshaking == true
      else { return }
      self.candidateHandshakeTimeoutTokens.removeValue(forKey: peerID)
      self.responderCandidates.removeValue(forKey: peerID)
    }
  }

  private func invalidateNoiseState(peerID: String) {
    if sessions[peerID]?.established == true {
      securePeerIDs.insert(peerID)
    }
    sessions.removeValue(forKey: peerID)
    responderCandidates.removeValue(forKey: peerID)
    decryptFailures.removeValue(forKey: peerID)
    autoHandshakeTokens.removeValue(forKey: peerID)
    activeHandshakeTimeoutTokens.removeValue(forKey: peerID)
    candidateHandshakeTimeoutTokens.removeValue(forKey: peerID)
    handshakeRestartAttempts.removeValue(forKey: peerID)
    lastAutoHandshake.removeValue(forKey: peerID)
    lastNoisePeerActivity.removeValue(forKey: peerID)
  }

  private func registerDecryptFailure(peerID: String) {
    guard sessions[peerID]?.established == true else { return }
    let failures = (decryptFailures[peerID] ?? 0) + 1
    guard failures >= Self.maximumDecryptFailures else {
      decryptFailures[peerID] = failures
      return
    }
    hearthBitDebugLog(
      "HearthBitMesh: Noise session with %@ stale after %d decrypt failures",
      String(peerID.prefix(8)),
      failures
    )
    invalidateNoiseState(peerID: peerID)
    emit(["type": "peers", "peers": peerMaps()])
    if isPeerReachable(peerID) {
      scheduleAutoHandshake(peerID: peerID, force: true, delay: 0.5)
    }
  }

  private func sendEncryptedFrame(peerID: String, frame: Data) throws {
    guard let session = sessions[peerID] else { return }
    guard !session.requiresRekey else {
      invalidateNoiseState(peerID: peerID)
      scheduleAutoHandshake(peerID: peerID, force: true, delay: 0)
      throw IOSMeshError.noiseRekeyRequired
    }
    let encrypted = try session.encrypt(
      Data([IOSMeshProtocol.noiseTransferFrame]) + frame
    )
    sendNoise(
      type: IOSMeshProtocol.noiseEncrypted,
      recipient: try Data(hex: peerID),
      payload: encrypted
    )
  }

  private func sendEncryptedPrivate(peerID: String, id: String, content: String) throws {
    guard let session = sessions[peerID] else { return }
    guard !session.requiresRekey else {
      invalidateNoiseState(peerID: peerID)
      scheduleAutoHandshake(peerID: peerID, force: true, delay: 0)
      throw IOSMeshError.noiseRekeyRequired
    }
    let privatePayload = IOSMeshProtocol.privateMessage(id: id, content: content)
    let encrypted = try session.encrypt(Data([IOSMeshProtocol.noisePrivate]) + privatePayload)
    let packet = sendNoise(
      type: IOSMeshProtocol.noiseEncrypted,
      recipient: try Data(hex: peerID),
      payload: encrypted
    )
    depositCourierWithDirectAnchors(innerPacket: packet)
  }

  @discardableResult
  private func sendNoise(type: UInt8, recipient: Data, payload: Data) -> IOSMeshPacket {
    let packet = IOSMeshPacket(
      type: type,
      ttl: IOSMeshProtocol.defaultTTL,
      timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
      senderID: identity.peerID,
      recipientID: recipient,
      payload: payload
    )
    broadcast(packet)
    return packet
  }

  private func depositCourierWithDirectAnchors(innerPacket: IOSMeshPacket) {
    let directPeerIDs = Set(peripheralPeers.values)
    for anchor in peers.values
    where anchor.isInfrastructure && directPeerIDs.contains(anchor.id) {
      if sessions[anchor.id]?.established == true {
        sendCourierDeposit(anchorID: anchor.id, innerPacket: innerPacket)
      } else {
        pendingCourier[anchor.id, default: []].append(innerPacket)
        try? initiateHandshake(peerID: anchor.id)
      }
    }
  }

  private func sendCourierDeposit(anchorID: String, innerPacket: IOSMeshPacket) {
    guard
      let recipientID = innerPacket.recipientID,
      let recipient = peers[recipientID.hex],
      let payload = IOSMeshProtocol.courierEnvelope(
        recipientNoiseKey: recipient.noisePublicKey,
        ciphertext: IOSMeshProtocol.encode(innerPacket, padded: false)
      ),
      let anchorBytes = try? Data(hex: anchorID)
    else { return }
    let courier = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.courierEnvelope,
        ttl: IOSMeshProtocol.defaultTTL,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        recipientID: anchorBytes,
        payload: payload
      )
    )
    send(packet: courier, toPeerID: anchorID)
  }

  private func sendAnnouncement(
    ttl: UInt8? = nil,
    allowUnprovenIdentity: Bool = false
  ) {
    guard running, identity != nil else { return }
    let payload = IOSMeshProtocol.announcement(
      nickname: identity.nickname,
      noisePublicKey: identity.noisePrivateKey.publicKey.rawRepresentation,
      signingPublicKey: identity.signingPrivateKey.publicKey.rawRepresentation
    )
    broadcast(
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.announce,
          ttl: ttl ?? announcementTTL,
          timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
          senderID: identity.peerID,
          payload: payload
        )
      ),
      allowUnprovenIdentity: allowUnprovenIdentity
    )
    broadcastHbtCapability()
    broadcastEmergencyCapability()
    broadcastNodeCapability()
    if activeLocalRadarConsentUntil() > currentMilliseconds() {
      broadcastRadarConsent(grant: true)
    }
  }

  private func broadcastHbtCapability() {
    guard running else { return }
    broadcast(
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.hbtCapability,
          ttl: IOSMeshProtocol.defaultTTL,
          timestamp: currentMilliseconds(),
          senderID: identity.peerID,
          payload: Data([IOSMeshProtocol.hbtVersion])
        )
      )
    )
  }

  private func broadcastEmergencyCapability() {
    guard running else { return }
    broadcast(
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.emergencyCapability,
          ttl: IOSMeshProtocol.defaultTTL,
          timestamp: currentMilliseconds(),
          senderID: identity.peerID,
          payload: IOSMeshProtocol.emergencyCapabilityPayload()
        )
      )
    )
  }

  private func broadcastNodeCapability() {
    guard running else { return }
    broadcast(
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.nodeCapability,
          ttl: IOSMeshProtocol.defaultTTL,
          timestamp: currentMilliseconds(),
          senderID: identity.peerID,
          payload: localRole.capabilityPayload
        )
      )
    )
  }

  private func broadcastRadarConsent(grant: Bool) {
    guard running else { return }
    let expiresAt = grant ? activeLocalRadarConsentUntil() : 0
    guard !grant || expiresAt > currentMilliseconds() else { return }
    let packet = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.radarControl,
        ttl: 1,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        payload: grant
          ? IOSRadarConsentProtocol.grant(expiresAt: expiresAt)
          : IOSRadarConsentProtocol.revoke()
      )
    )
    broadcast(packet)
  }

  private func activeLocalRadarConsentUntil() -> UInt64 {
    let value = UserDefaults.standard.double(
      forKey: IOSRadarConsentProtocol.localConsentKey
    )
    let expiresAt = value > 0 ? UInt64(value) : 0
    if expiresAt <= currentMilliseconds() {
      if value != 0 {
        UserDefaults.standard.removeObject(forKey: IOSRadarConsentProtocol.localConsentKey)
      }
      return 0
    }
    return expiresAt
  }

  private func currentMilliseconds() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000)
  }

  private func isRadarAllowed(peerID: String) -> Bool {
    guard let consent = remoteRadarConsents[peerID] else { return false }
    if consent.expiresAt <= currentMilliseconds() {
      remoteRadarConsents.removeValue(forKey: peerID)
      return false
    }
    return true
  }

  private func pruneRadarConsents() {
    let now = currentMilliseconds()
    remoteRadarConsents = remoteRadarConsents.filter { $0.value.expiresAt > now }
    if let target = radarPeerID, remoteRadarConsents[target] == nil {
      stopRadar()
    }
  }

  private func emitRadarConsent() {
    emit([
      "type": "radarConsent",
      "radarConsentUntil": activeLocalRadarConsentUntil(),
      "peers": peerMaps(),
    ])
  }

  private func broadcast(
    _ packet: IOSMeshPacket,
    excluding: UUID? = nil,
    allowUnprovenIdentity: Bool = false
  ) {
    rememberSyncPacket(packet)
    let bytes = IOSMeshProtocol.encodeForBLE(packet)
    let emergency = IOSMeshProtocol.isEmergency(packet)
    let priority = IOSBLEFramePriority.forPacket(packet)
    let directed = packet.recipientID.map {
      $0 != Data(repeating: 0xff, count: 8)
    } ?? false
    let restrictIdentity = privateMode &&
      !allowUnprovenIdentity &&
      packet.senderID == identity.peerID &&
      IOSMeshInteropPolicy.identityPacketTypes.contains(packet.type)
    if (localRole.storesDirectedPackets || emergency && localRole.relaysPackets),
       packet.type != IOSMeshProtocol.beaconControl,
       packet.type != IOSMeshProtocol.rangingControl,
       directed || emergency {
      do {
        try storeForward.put(packet)
      } catch {
        emit([
          "type": "error",
          "code": "store_forward_failed",
          "message": error.localizedDescription,
          "emergency": emergency,
        ])
      }
    }
    if let characteristic = localCharacteristic, let manager = peripheralManager {
      for central in characteristic.subscribedCentrals ?? []
      where central.identifier != excluding &&
        (!restrictIdentity || IOSMeshInteropPolicy.canSendIdentityToLink(
          privateMode: privateMode,
          hearthbitProven: hearthbitProvenLinks.contains(central.identifier),
          emergencyException: false
        )) {
        guard
          let frames = packetFragmenter.prepare(
            packet: packet,
            encoded: bytes,
            maximumValueLength: central.maximumUpdateValueLength
          )
        else {
          hearthBitDebugLog(
            "HearthBitMesh: dropping %d-byte notification for %@ (limit=%d)",
            bytes.count,
            central.identifier.uuidString,
            central.maximumUpdateValueLength
          )
          continue
        }
        enqueuePeripheralUpdates(
          frames,
          central: central,
          manager: manager,
          characteristic: characteristic,
          priority: priority
        )
      }
    }
    for (identifier, characteristic) in remoteCharacteristics
    where identifier != excluding &&
      (!restrictIdentity || IOSMeshInteropPolicy.canSendIdentityToLink(
        privateMode: privateMode,
        hearthbitProven: hearthbitProvenLinks.contains(identifier),
        emergencyException: false
      )) {
      guard let peripheral = connectedPeripherals[identifier] else { continue }
      let writeType: CBCharacteristicWriteType =
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
      let maximum = peripheral.maximumWriteValueLength(for: writeType)
      guard
        let frames = packetFragmenter.prepare(
          packet: packet,
          encoded: bytes,
          maximumValueLength: maximum
        )
      else {
        hearthBitDebugLog(
          "HearthBitMesh: dropping %d-byte central write for %@ (limit=%d)",
          bytes.count,
          identifier.uuidString,
          maximum
        )
        continue
      }
      enqueueCentralWrites(
        frames,
        peripheral: peripheral,
        characteristic: characteristic,
        type: writeType,
        priority: priority
      )
    }
    if !suppressLanBridge,
       let gatewayID = lanBridgeGatewayID,
       bytes.count <= lanBridgeMaximumFrameSize {
      emit([
        "type": "rawMeshFrame",
        "gatewayId": gatewayID,
        "frame": FlutterStandardTypedData(bytes: bytes),
      ])
    }
  }

  private func send(packet: IOSMeshPacket, toPeerID peerID: String) {
    let bytes = IOSMeshProtocol.encodeForBLE(packet)
    let priority = IOSBLEFramePriority.forPacket(packet)
    for (identifier, mappedPeerID) in peripheralPeers where mappedPeerID == peerID {
      if
        let characteristic = remoteCharacteristics[identifier],
        let peripheral = connectedPeripherals[identifier]
      {
        let writeType: CBCharacteristicWriteType =
          characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let maximum = peripheral.maximumWriteValueLength(for: writeType)
        if
          let frames = packetFragmenter.prepare(
            packet: packet,
            encoded: bytes,
            maximumValueLength: maximum
          )
        {
          enqueueCentralWrites(
            frames,
            peripheral: peripheral,
            characteristic: characteristic,
            type: writeType,
            priority: priority
          )
        }
      }
      if
        let characteristic = localCharacteristic,
        let manager = peripheralManager,
        let central = characteristic.subscribedCentrals?.first(where: {
          $0.identifier == identifier
        })
      {
        if
          let frames = packetFragmenter.prepare(
            packet: packet,
            encoded: bytes,
            maximumValueLength: central.maximumUpdateValueLength
          )
        {
          enqueuePeripheralUpdates(
            frames,
            central: central,
            manager: manager,
            characteristic: characteristic,
            priority: priority
          )
        }
      }
    }
  }

  private func sendHearthBitLinkProof(to identifier: UUID) {
    guard running, privateMode else { return }
    let proof = IOSMeshInteropPolicy.linkProof
    if
      let characteristic = remoteCharacteristics[identifier],
      let peripheral = connectedPeripherals[identifier]
    {
      let writeType: CBCharacteristicWriteType =
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
      enqueueCentralWrites(
        [proof],
        peripheral: peripheral,
        characteristic: characteristic,
        type: writeType,
        priority: .normal
      )
    }
    if
      let characteristic = localCharacteristic,
      let manager = peripheralManager,
      let central = characteristic.subscribedCentrals?.first(where: {
        $0.identifier == identifier
      })
    {
      enqueuePeripheralUpdates(
        [proof],
        central: central,
        manager: manager,
        characteristic: characteristic,
        priority: .normal
      )
    }
  }

  private func sendSubscriptionAnnouncement(
    to central: CBCentral,
    bypassCooldown: Bool = false
  ) {
    guard
      running,
      localRole.allowsDataPlane,
      let manager = peripheralManager,
      let characteristic = localCharacteristic,
      characteristic.subscribedCentrals?.contains(where: {
        $0.identifier == central.identifier
      }) == true
    else { return }
    if privateMode && !hearthbitProvenLinks.contains(central.identifier) {
      sendHearthBitLinkProof(to: central.identifier)
      return
    }
    let now = Date()
    if !bypassCooldown,
       let previous = lastSubscriptionAnnouncement[central.identifier],
       now.timeIntervalSince(previous) < Self.subscriptionAnnouncementCooldown {
      return
    }
    lastSubscriptionAnnouncement[central.identifier] = now

    let packets = [
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.announce,
          ttl: announcementTTL,
          timestamp: currentMilliseconds(),
          senderID: identity.peerID,
          payload: IOSMeshProtocol.announcement(
            nickname: identity.nickname,
            noisePublicKey: identity.noisePrivateKey.publicKey.rawRepresentation,
            signingPublicKey: identity.signingPrivateKey.publicKey.rawRepresentation
          )
        )
      ),
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.hbtCapability,
          ttl: IOSMeshProtocol.defaultTTL,
          timestamp: currentMilliseconds(),
          senderID: identity.peerID,
          payload: Data([IOSMeshProtocol.hbtVersion])
        )
      ),
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.nodeCapability,
          ttl: IOSMeshProtocol.defaultTTL,
          timestamp: currentMilliseconds(),
          senderID: identity.peerID,
          payload: localRole.capabilityPayload
        )
      ),
    ]
    for packet in packets {
      rememberSyncPacket(packet)
      let encoded = IOSMeshProtocol.encodeForBLE(packet)
      guard
        let frames = packetFragmenter.prepare(
          packet: packet,
          encoded: encoded,
          maximumValueLength: central.maximumUpdateValueLength
        )
      else { continue }
      enqueuePeripheralUpdates(
        frames,
        central: central,
        manager: manager,
        characteristic: characteristic,
        priority: .normal
      )
    }
  }

  private func enqueueCentralWrites(
    _ frames: [Data],
    peripheral: CBPeripheral,
    characteristic: CBCharacteristic,
    type: CBCharacteristicWriteType,
    priority: IOSBLEFramePriority
  ) {
    guard !frames.isEmpty else { return }
    let identifier = peripheral.identifier
    var queue = centralWriteQueues[identifier] ?? IOSBLEPriorityQueue(
      normalCapacity: Self.maximumPendingBLEFrames,
      emergencyReserve: Self.emergencyBLEFrameReserve
    )
    let writes = frames.map {
      PendingCentralWrite(data: $0, characteristic: characteristic, type: type)
    }
    guard queue.enqueue(writes, priority: priority) else {
      emitBLETransportFailure(
        code: "central_queue_full",
        identifier: identifier,
        emergency: priority == .emergency,
        frames: frames.count
      )
      return
    }
    centralWriteQueues[identifier] = queue
    drainCentralWriteQueue(peripheral)
  }

  private func drainCentralWriteQueue(_ peripheral: CBPeripheral) {
    let identifier = peripheral.identifier
    while var queue = centralWriteQueues[identifier], let next = queue.next() {
      centralWriteQueues[identifier] = queue
      if next.type == .withResponse {
        guard !centralWritesInFlight.contains(identifier) else { return }
        centralWritesInFlight.insert(identifier)
        peripheral.writeValue(next.data, for: next.characteristic, type: next.type)
        return
      }
      guard peripheral.canSendWriteWithoutResponse else { return }
      peripheral.writeValue(next.data, for: next.characteristic, type: next.type)
      queue.completeCurrent()
      if queue.isEmpty {
        centralWriteQueues.removeValue(forKey: identifier)
      } else {
        centralWriteQueues[identifier] = queue
      }
    }
  }

  private func enqueuePeripheralUpdates(
    _ frames: [Data],
    central: CBCentral,
    manager: CBPeripheralManager,
    characteristic: CBMutableCharacteristic,
    priority: IOSBLEFramePriority
  ) {
    guard !frames.isEmpty else { return }
    let identifier = central.identifier
    var queue = peripheralNotifyQueues[identifier] ?? IOSBLEPriorityQueue(
      normalCapacity: Self.maximumPendingBLEFrames,
      emergencyReserve: Self.emergencyBLEFrameReserve
    )
    guard queue.enqueue(frames, priority: priority) else {
      emitBLETransportFailure(
        code: "peripheral_queue_full",
        identifier: identifier,
        emergency: priority == .emergency,
        frames: frames.count
      )
      return
    }
    peripheralNotifyQueues[identifier] = queue
    drainPeripheralNotifyQueue(
      identifier,
      manager: manager,
      characteristic: characteristic
    )
  }

  private func drainPeripheralNotifyQueue(
    _ identifier: UUID,
    manager: CBPeripheralManager,
    characteristic: CBMutableCharacteristic
  ) {
    guard
      let central = characteristic.subscribedCentrals?.first(where: {
        $0.identifier == identifier
      })
    else {
      peripheralNotifyQueues.removeValue(forKey: identifier)
      return
    }
    while var queue = peripheralNotifyQueues[identifier], let data = queue.next() {
      peripheralNotifyQueues[identifier] = queue
      guard manager.updateValue(
        data,
        for: characteristic,
        onSubscribedCentrals: [central]
      ) else { return }
      queue.completeCurrent()
      if queue.isEmpty {
        peripheralNotifyQueues.removeValue(forKey: identifier)
      } else {
        peripheralNotifyQueues[identifier] = queue
      }
    }
  }

  private func emitBLETransportFailure(
    code: String,
    identifier: UUID,
    emergency: Bool,
    frames: Int,
    message: String? = nil
  ) {
    var event: [String: Any] = [
      "type": "bleTransportFailure",
      "code": code,
      "peripheralId": identifier.uuidString,
      "emergency": emergency,
      "frames": frames,
    ]
    if let message { event["message"] = message }
    emit(event)
  }

  private func receive(_ data: Data, source: UUID?) {
    if data == IOSMeshInteropPolicy.linkProof, let source {
      if hearthbitProvenLinks.insert(source).inserted {
        if let central = localCharacteristic?.subscribedCentrals?.first(where: {
          $0.identifier == source
        }) {
          sendSubscriptionAnnouncement(to: central, bypassCooldown: true)
        } else {
          sendAnnouncement()
        }
      }
      return
    }
    guard
      let fingerprint = IOSMeshProtocol.relayFingerprint(data),
      let packet = IOSMeshProtocol.decode(data)
    else { return }
    let senderID = packet.senderID.hex
    if senderID == identity.peerIDHex { return }
    var validatedAnnouncement: IOSMeshProtocol.Announcement?
    if packet.type == IOSMeshProtocol.announce {
      guard let announcement = validateAnnouncementIdentity(
        packet,
        senderID: senderID
      ) else { return }
      validatedAnnouncement = announcement
    }
    if seen[fingerprint] != nil { return }
    seen[fingerprint] = Date()
    if seen.count > 2000 {
      seen = seen.filter { Date().timeIntervalSince($0.value) < 3600 }
    }
    let forUs = packet.recipientID == nil ||
      packet.recipientID == identity.peerID ||
      packet.recipientID == Data(repeating: 0xff, count: 8)
    if forUs {
      process(
        packet,
        senderID: senderID,
        source: source,
        validatedAnnouncement: validatedAnnouncement
      )
    }
    let fragmentOriginalType = packet.type == IOSMeshProtocol.fragment
      ? IOSMeshProtocol.decodeFragmentPayload(packet.payload)?.originalType
      : nil
    let controlForUs = forUs &&
      (packet.type == IOSMeshProtocol.noiseHandshake ||
       packet.type == IOSMeshProtocol.noiseEncrypted ||
       fragmentOriginalType == IOSMeshProtocol.noiseHandshake ||
       fragmentOriginalType == IOSMeshProtocol.noiseEncrypted)
    if localRole.relaysPackets &&
       packet.type != IOSMeshProtocol.beaconControl &&
       packet.type != IOSMeshProtocol.rangingControl &&
       packet.ttl > 1 &&
       !controlForUs {
      var relayed = packet
      relayed.ttl -= 1
      broadcast(relayed, excluding: source)
    }
  }

  private func validateAnnouncementIdentity(
    _ packet: IOSMeshPacket,
    senderID: String
  ) -> IOSMeshProtocol.Announcement? {
    let now = currentMilliseconds()
    let age = packet.timestamp > now
      ? packet.timestamp - now
      : now - packet.timestamp
    guard
      age <= 10 * 60 * 1_000,
      let announcement = IOSMeshProtocol.decodeAnnouncement(packet.payload),
      IOSMeshIdentity.verify(packet, key: announcement.signingPublicKey)
    else { return nil }

    if let previous = peers[senderID] {
      let noiseChanged = previous.noisePublicKey != announcement.noisePublicKey
      let signingChanged = previous.signingPublicKey != announcement.signingPublicKey
      if noiseChanged || signingChanged {
        emitIdentityConflict(
          peerID: senderID,
          noiseChanged: noiseChanged,
          signingChanged: signingChanged
        )
        return nil
      }
    }
    if peerIdentityPins.pin(for: senderID) == nil,
       IOSMeshProtocol.peerID(announcement.noisePublicKey) != packet.senderID {
      return nil
    }

    do {
      switch try peerIdentityPins.validateAndPin(
        peerID: senderID,
        noisePublicKey: announcement.noisePublicKey,
        signingPublicKey: announcement.signingPublicKey
      ) {
      case .firstBinding:
        emit(["type": "identityPinned", "peerId": senderID, "method": "tofu"])
      case .matched:
        break
      case let .conflict(noiseChanged, signingChanged):
        // No existe un protocolo autenticado de rotación de identidad. Se
        // rechaza cerrado; panic wipe (o un futuro olvido explícito con UX)
        // es el único mecanismo local para retirar este pin.
        emitIdentityConflict(
          peerID: senderID,
          noiseChanged: noiseChanged,
          signingChanged: signingChanged
        )
        return nil
      }
    } catch {
      emit([
        "type": "error",
        "code": "peer_identity_store_failed",
        "peerId": senderID,
        "message": error.localizedDescription,
      ])
      return nil
    }
    return announcement
  }

  private func emitIdentityConflict(
    peerID: String,
    noiseChanged: Bool,
    signingChanged: Bool
  ) {
    emit([
      "type": "identityConflict",
      "peerId": peerID,
      "noiseKeyChanged": noiseChanged,
      "signingKeyChanged": signingChanged,
      "action": "rejected",
    ])
  }

  private func process(
    _ packet: IOSMeshPacket,
    senderID: String,
    source: UUID? = nil,
    validatedAnnouncement: IOSMeshProtocol.Announcement? = nil
  ) {
    switch packet.type {
    case IOSMeshProtocol.announce:
      guard let announcement = validatedAnnouncement ??
        validateAnnouncementIdentity(packet, senderID: senderID)
      else { return }
      // Solo una identidad ya validada y fijada puede promover presencia.
      if (packet.ttl == announcementTTL ||
          packet.ttl == IOSMeshProtocol.defaultTTL), let source {
        peripheralPeers[source] = senderID
      }
      let now = Date()
      let previousPeer = peers[senderID]
      let requiresTransportRekey = IOSPeerReachabilityPolicy.requiresTransportRekey(
        previousLastSeen: previousPeer?.lastSeen,
        now: now
      )
      if requiresTransportRekey {
        hearthBitDebugLog(
          "HearthBitMesh: ANNOUNCE after reachability gap from %@; resetting Noise epoch",
          String(senderID.prefix(8))
        )
        invalidateNoiseState(peerID: senderID)
      }
      peers[senderID] = IOSMeshPeer(
        id: senderID,
        nickname: announcement.nickname,
        noisePublicKey: announcement.noisePublicKey,
        signingPublicKey: announcement.signingPublicKey,
        supportsTransfers: announcement.supportsTransfers ||
          (previousPeer?.supportsTransfers ?? false),
        hearthbitVerified: announcement.supportsTransfers ||
          (previousPeer?.hearthbitVerified ?? false),
        supportsEmergencyAck: previousPeer?.supportsEmergencyAck ?? false,
        isInfrastructure: announcement.isInfrastructure ||
          (previousPeer?.isInfrastructure ?? false),
        role: previousPeer?.role ?? .phoneRelay,
        hasLongRangeTrunk: false,
        lastSeen: now
      )
      if
        announcement.supportsTransfers,
        (packet.ttl == announcementTTL ||
         packet.ttl == IOSMeshProtocol.defaultTTL),
        let source,
        hearthbitProvenLinks.insert(source).inserted
      {
        sendAnnouncement()
      }
      latestAnnouncementTimestampByPeer[senderID] = max(
        latestAnnouncementTimestampByPeer[senderID] ?? 0,
        packet.timestamp
      )
      rememberSyncPacket(packet)
      emit(["type": "peers", "peers": peerMaps()])
      let verifiedHearthBit = peers[senderID]?.hearthbitVerified == true
      if let source {
        preferredPeripheralIDs.insert(source)
        if !privateMode || verifiedHearthBit {
          requestMissingMessages(peerID: senderID, source: source)
        }
      }
      do {
        for stored in try storeForward.packets(for: packet.senderID) {
          broadcast(stored)
        }
        for emergency in try storeForward.emergencyPackets() {
          broadcast(emergency)
        }
      } catch {
        emit([
          "type": "error",
          "code": "store_forward_failed",
          "message": error.localizedDescription,
        ])
      }
      if !privateMode || verifiedHearthBit {
        if requiresTransportRekey {
          if shouldAutoHandshake(peerID: senderID) {
            scheduleAutoHandshake(peerID: senderID, force: true, delay: 0.5)
          }
        } else if !(pendingPrivate[senderID] ?? []).isEmpty ||
                    !(pendingFrames[senderID] ?? []).isEmpty ||
                    !(pendingCourier[senderID] ?? []).isEmpty {
          try? initiateHandshake(peerID: senderID)
        } else {
          scheduleAutoHandshake(peerID: senderID)
        }
      }
    case IOSMeshProtocol.message:
      guard
        let peer = peers[senderID],
        IOSMeshIdentity.verify(packet, key: peer.signingPublicKey)
      else { return }
      let emergency = IOSMeshProtocol.isEmergency(packet)
      guard IOSMeshInteropPolicy.shouldProcessPublicMessage(
        privateMode: privateMode,
        hearthbitVerified: peer.hearthbitVerified,
        emergency: emergency
      ) else { return }
      let external = IOSMeshInteropPolicy.isExternalEmergency(
        privateMode: privateMode,
        hearthbitVerified: peer.hearthbitVerified,
        emergency: emergency
      )
      let emergencyHash = emergency
        ? IOSMeshProtocol.emergencyCanonicalHash(packet).hex
        : nil
      let duplicateEmergency = emergencyHash.map {
        emergencyFingerprints.seenOrRemember($0)
      } ?? false
      if emergency && peer.supportsEmergencyAck {
        sendEmergencyAcknowledgement(for: packet)
      }
      if duplicateEmergency { return }
      let message = IOSMeshProtocol.decodePublicMessage(packet.payload) ??
        IOSMeshProtocol.PublicMessage(
          id: IOSMeshProtocol.fingerprint(packet).uppercased(),
          sender: peer.nickname,
          content: String(data: packet.payload, encoding: .utf8) ?? "",
          timestamp: packet.timestamp,
          channel: packet.payload.starts(with: Data("SOS|".utf8)) ? "sos" : nil
        )
      rememberSyncPacket(packet)
      if message.channel == "sos" {
        let expiresAt = packet.timestamp + IOSRadarConsentProtocol.sosDurationMilliseconds
        if expiresAt > currentMilliseconds() {
          remoteRadarConsents[senderID] = IOSRemoteRadarConsent(
            expiresAt: expiresAt,
            source: "sos"
          )
          emit(["type": "peers", "peers": peerMaps()])
        }
      }
      emitMessage(
        id: message.id,
        sender: message.sender,
        content: message.content,
        senderPeerID: senderID,
        isPrivate: false,
        isMine: false,
        timestamp: message.timestamp,
        channel: message.channel,
        external: external
      )
    case IOSMeshProtocol.noiseHandshake:
      processHandshake(packet, senderID: senderID)
    case IOSMeshProtocol.noiseEncrypted:
      processEncrypted(packet, senderID: senderID)
    case IOSMeshProtocol.courierEnvelope:
      processCourier(packet, senderID: senderID)
    case IOSMeshProtocol.requestSync:
      if let source { processSyncRequest(packet, senderID: senderID, source: source) }
    case IOSMeshProtocol.radarControl:
      processRadarControl(packet, senderID: senderID)
    case IOSMeshProtocol.hbtCapability:
      processHbtCapability(packet, senderID: senderID, source: source)
    case IOSMeshProtocol.nodeCapability:
      processNodeCapability(packet, senderID: senderID)
    case IOSMeshProtocol.beaconControl:
      processBeaconControl(packet, senderID: senderID)
    case IOSMeshProtocol.rangingControl:
      processRangingControl(packet, senderID: senderID)
    case IOSMeshProtocol.emergencyCapability:
      processEmergencyCapability(packet, senderID: senderID)
    case IOSMeshProtocol.emergencyAck:
      processEmergencyAcknowledgement(packet, senderID: senderID)
    case IOSMeshProtocol.fragment:
      if let reassembled = fragmentReassembler.accept(packet) {
        if (reassembled.type == IOSMeshProtocol.beaconControl ||
            reassembled.type == IOSMeshProtocol.rangingControl),
           packet.ttl != 1 {
          return
        }
        var accepted = reassembled
        if accepted.type == IOSMeshProtocol.beaconControl ||
           accepted.type == IOSMeshProtocol.rangingControl {
          accepted.ttl = 1
        }
        var validatedAnnouncement: IOSMeshProtocol.Announcement?
        if accepted.type == IOSMeshProtocol.announce {
          guard let announcement = validateAnnouncementIdentity(
            accepted,
            senderID: senderID
          ) else { return }
          validatedAnnouncement = announcement
          if (packet.ttl == announcementTTL ||
              packet.ttl == IOSMeshProtocol.defaultTTL), let source {
            peripheralPeers[source] = senderID
          }
        }
        process(
          accepted,
          senderID: senderID,
          source: source,
          validatedAnnouncement: validatedAnnouncement
        )
      }
    default:
      break
    }
  }

  private func processHbtCapability(
    _ packet: IOSMeshPacket,
    senderID: String,
    source: UUID?
  ) {
    guard
      var peer = peers[senderID],
      packet.payload == Data([IOSMeshProtocol.hbtVersion]),
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey)
    else { return }
    peer.supportsTransfers = true
    peer.hearthbitVerified = true
    peer.lastSeen = Date()
    peers[senderID] = peer
    if
      packet.ttl == IOSMeshProtocol.defaultTTL,
      let source,
      hearthbitProvenLinks.insert(source).inserted
    {
      sendAnnouncement()
      requestMissingMessages(peerID: senderID, source: source)
    }
    emit(["type": "peers", "peers": peerMaps()])
  }

  private func processEmergencyCapability(_ packet: IOSMeshPacket, senderID: String) {
    guard
      var peer = peers[senderID],
      IOSMeshProtocol.supportsEmergencyAcknowledgements(packet.payload),
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey)
    else { return }
    peer.supportsEmergencyAck = true
    peer.lastSeen = Date()
    peers[senderID] = peer
    emit(["type": "peers", "peers": peerMaps()])
  }

  private func processEmergencyAcknowledgement(
    _ packet: IOSMeshPacket,
    senderID: String
  ) {
    let now = currentMilliseconds()
    let age = packet.timestamp > now
      ? packet.timestamp - now
      : now - packet.timestamp
    guard
      packet.recipientID == identity.peerID,
      let peer = peers[senderID],
      peer.supportsEmergencyAck,
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey),
      age <= 48 * 60 * 60 * 1_000,
      let hash = IOSMeshProtocol.decodeEmergencyAcknowledgement(packet.payload)
    else { return }
    emit([
      "type": "emergencyAck",
      "canonicalHash": hash.hex,
      "peerId": senderID,
      "at": now,
    ])
  }

  private func sendEmergencyAcknowledgement(for packet: IOSMeshPacket) {
    let acknowledgement = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.emergencyAck,
        ttl: IOSMeshProtocol.defaultTTL,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        recipientID: packet.senderID,
        payload: IOSMeshProtocol.emergencyAcknowledgementPayload(
          hash: IOSMeshProtocol.emergencyCanonicalHash(packet)
        )
      )
    )
    broadcast(acknowledgement)
  }

  private func processNodeCapability(_ packet: IOSMeshPacket, senderID: String) {
    guard
      var peer = peers[senderID],
      let capability = IOSMeshNodeRole.decodeCapability(packet.payload),
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey)
    else { return }
    peer.role = capability.role
    peer.hasLongRangeTrunk = capability.hasLongRangeTrunk
    peer.isInfrastructure = capability.role.isInfrastructure || peer.isInfrastructure
    peer.lastSeen = Date()
    peers[senderID] = peer
    emit(["type": "peers", "peers": peerMaps()])
  }

  private func processRadarControl(_ packet: IOSMeshPacket, senderID: String) {
    guard
      let peer = peers[senderID],
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey),
      let consent = IOSRadarConsentProtocol.decode(packet.payload),
      IOSRadarConsentProtocol.hasValidTimestamp(
        packet.timestamp,
        now: currentMilliseconds()
      )
    else { return }
    if consent.action == IOSRadarConsentProtocol.revokeAction {
      remoteRadarConsents.removeValue(forKey: senderID)
      if radarPeerID == senderID { stopRadar() }
    } else if IOSRadarConsentProtocol.isValidGrant(
      consent,
      packetTimestamp: packet.timestamp
    ) {
      remoteRadarConsents[senderID] = IOSRemoteRadarConsent(
        expiresAt: consent.expiresAt,
        source: "temporary"
      )
    } else {
      return
    }
    emit(["type": "peers", "peers": peerMaps()])
  }

  private func processBeaconControl(_ packet: IOSMeshPacket, senderID: String) {
    guard
      packet.ttl == 1,
      packet.recipientID == identity.peerID,
      let peer = peers[senderID],
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey),
      let control = IOSBeaconControlProtocol.decode(packet.payload),
      IOSBeaconControlProtocol.isValid(
        control,
        packetTimestamp: packet.timestamp,
        now: currentMilliseconds()
      )
    else { return }
    let requestID = control.nonce.hex
    let now = Date()
    seenBeaconActions = seenBeaconActions.filter { $0.value > now }
    let replayKey = "\(senderID):\(requestID):\(control.action)"
    guard seenBeaconActions[replayKey] == nil else { return }
    seenBeaconActions[replayKey] = now.addingTimeInterval(10 * 60)
    switch control.action {
    case IOSBeaconControlProtocol.requestAction:
      if activeBeaconRequest != nil {
        try? sendBeaconControl(
          peerID: senderID,
          payload: IOSBeaconControlProtocol.revoke(nonce: control.nonce)
        )
        return
      }
      pendingBeaconRequests = pendingBeaconRequests.filter {
        $0.value.control.expiresAt > currentMilliseconds()
      }
      guard pendingBeaconRequests.isEmpty else {
        try? sendBeaconControl(
          peerID: senderID,
          payload: IOSBeaconControlProtocol.revoke(nonce: control.nonce)
        )
        return
      }
      let request = IOSPendingBeaconRequest(
        peerID: senderID,
        nickname: peer.nickname,
        control: control
      )
      pendingBeaconRequests[requestID] = request
      // Radar y rescate autorizan medición, no control del hardware.
      // Sonido, flash y vibración siempre requieren confirmación.
      emit([
        "type": "beaconRequest",
        "requestId": requestID,
        "peerId": senderID,
        "nickname": peer.nickname,
        "expiresAt": control.expiresAt,
        "flags": Int(control.flags),
        "autoAccepted": false,
      ])
    case IOSBeaconControlProtocol.grantAction:
      guard
        let outgoing = outgoingBeaconRequests[requestID],
        outgoing.peerID == senderID,
        outgoing.flags == control.flags,
        control.expiresAt <= outgoing.expiresAt
      else { return }
      emitRemoteBeaconState(
        peerID: senderID,
        requestID: requestID,
        status: "active",
        expiresAt: control.expiresAt,
        flags: control.flags
      )
    case IOSBeaconControlProtocol.revokeAction:
      guard
        let outgoing = outgoingBeaconRequests.removeValue(forKey: requestID),
        outgoing.peerID == senderID
      else { return }
      emitRemoteBeaconState(
        peerID: senderID,
        requestID: requestID,
        status: "rejected",
        expiresAt: 0,
        flags: 0
      )
    case IOSBeaconControlProtocol.stopAction:
      if
        let active = activeBeaconRequest,
        active.peerID == senderID,
        active.control.nonce == control.nonce
      {
        beaconActuator.stop()
        activeBeaconRequest = nil
        emitLocalBeaconState(status: "stopped")
      }
      if
        let outgoing = outgoingBeaconRequests.removeValue(forKey: requestID),
        outgoing.peerID == senderID
      {
        emitRemoteBeaconState(
          peerID: senderID,
          requestID: requestID,
          status: "stopped",
          expiresAt: 0,
          flags: 0
        )
      }
    default:
      break
    }
  }

  private func processRangingControl(_ packet: IOSMeshPacket, senderID: String) {
    guard
      packet.ttl == 1,
      packet.recipientID == identity.peerID,
      let peer = peers[senderID],
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey),
      IOSRangingControlProtocol.hasValidTimestamp(
        packet.timestamp,
        now: currentMilliseconds()
      ),
      let control = IOSRangingControlProtocol.decode(packet.payload)
    else { return }
    if control.action == 2, activeLocalRadarConsentUntil() <= currentMilliseconds() {
      return
    }
    emit([
      "type": "rangingControl",
      "peerId": senderID,
      "action": Int(control.action),
      "technology": Int(control.technology),
      "payload": FlutterStandardTypedData(bytes: packet.payload),
      "at": Int64(packet.timestamp),
    ])
  }

  private func processHandshake(_ packet: IOSMeshPacket, senderID: String) {
    guard !privateMode || peers[senderID]?.hearthbitVerified == true else { return }
    guard IOSNoiseReplayPolicy.isCurrent(
      packetTimestamp: packet.timestamp,
      latestAnnouncementTimestamp: latestAnnouncementTimestampByPeer[senderID]
    ) else { return }
    lastNoisePeerActivity[senderID] = Date()
    handshakeRestartAttempts.removeValue(forKey: senderID)
    let isMessageOne = packet.payload.count == 32
    var session: IOSNoiseSession
    var isCandidate = false

    if responderCandidates[senderID] != nil {
      if isMessageOne {
        responderCandidates.removeValue(forKey: senderID)
        responderCandidates[senderID] = IOSNoiseSession(
          claimedPeerID: packet.senderID,
          initiator: false,
          localStatic: identity.noisePrivateKey
        )
      }
      session = responderCandidates[senderID]!
      isCandidate = true
    } else if let active = sessions[senderID] {
      if active.handshaking && active.initiator && isMessageOne {
        // El peerID menor conserva el rol iniciador; el mayor cede.
        guard identity.peerIDHex > senderID else { return }
        sessions.removeValue(forKey: senderID)
        session = IOSNoiseSession(
          claimedPeerID: packet.senderID,
          initiator: false,
          localStatic: identity.noisePrivateKey
        )
        sessions[senderID] = session
      } else if active.established && isMessageOne {
        session = IOSNoiseSession(
          claimedPeerID: packet.senderID,
          initiator: false,
          localStatic: identity.noisePrivateKey
        )
        responderCandidates[senderID] = session
        isCandidate = true
      } else if active.established {
        return
      } else if active.handshaking && !active.initiator && isMessageOne {
        session = IOSNoiseSession(
          claimedPeerID: packet.senderID,
          initiator: false,
          localStatic: identity.noisePrivateKey
        )
        sessions[senderID] = session
      } else {
        session = active
      }
    } else {
      session = IOSNoiseSession(
        claimedPeerID: packet.senderID,
        initiator: false,
        localStatic: identity.noisePrivateKey
      )
      sessions[senderID] = session
    }

    if isCandidate {
      touchCandidateHandshake(peerID: senderID)
    } else {
      touchActiveHandshake(peerID: senderID)
    }
    do {
      if let response = try session.process(packet.payload) {
        sendNoise(
          type: IOSMeshProtocol.noiseHandshake,
          recipient: packet.senderID,
          payload: response
        )
      }
      if session.established {
        securePeerIDs.insert(senderID)
        decryptFailures.removeValue(forKey: senderID)
        handshakeRestartAttempts.removeValue(forKey: senderID)
        autoHandshakeTokens.removeValue(forKey: senderID)
        activeHandshakeTimeoutTokens.removeValue(forKey: senderID)
        candidateHandshakeTimeoutTokens.removeValue(forKey: senderID)
        if isCandidate {
          responderCandidates.removeValue(forKey: senderID)
          sessions[senderID] = session
        }
        emit(["type": "peers", "peers": peerMaps()])
        let queued = pendingPrivate.removeValue(forKey: senderID) ?? []
        for item in queued {
          try sendEncryptedPrivate(peerID: senderID, id: item.0, content: item.1)
        }
        let queuedFrames = pendingFrames.removeValue(forKey: senderID) ?? []
        for frame in queuedFrames {
          try sendEncryptedFrame(peerID: senderID, frame: frame)
        }
        let queuedCourier = pendingCourier.removeValue(forKey: senderID) ?? []
        for innerPacket in queuedCourier {
          sendCourierDeposit(anchorID: senderID, innerPacket: innerPacket)
        }
      }
    } catch {
      if isCandidate {
        if let candidate = responderCandidates[senderID], candidate === session {
          responderCandidates.removeValue(forKey: senderID)
          candidateHandshakeTimeoutTokens.removeValue(forKey: senderID)
        }
      } else if let active = sessions[senderID], active === session {
        sessions.removeValue(forKey: senderID)
        activeHandshakeTimeoutTokens.removeValue(forKey: senderID)
      }
      if let meshError = error as? IOSMeshError, case .identityMismatch = meshError {
        emitError(HearthBitL10n.string("identity_rejected"))
      } else {
        hearthBitDebugLog(
          "HearthBitMesh: Noise handshake state/protocol failure from %@: %@",
          String(senderID.prefix(8)),
          error.localizedDescription
        )
        if sessions[senderID]?.established != true, isPeerReachable(senderID) {
          scheduleAutoHandshake(peerID: senderID, force: true, delay: 1)
        }
      }
    }
  }

  private func processEncrypted(_ packet: IOSMeshPacket, senderID: String) {
    guard !privateMode || peers[senderID]?.hearthbitVerified == true else { return }
    guard IOSNoiseReplayPolicy.isCurrent(
      packetTimestamp: packet.timestamp,
      latestAnnouncementTimestamp: latestAnnouncementTimestampByPeer[senderID]
    ) else { return }
    lastNoisePeerActivity[senderID] = Date()
    guard let session = sessions[senderID], session.established else {
      securePeerIDs.insert(senderID)
      scheduleAutoHandshake(peerID: senderID, force: true, delay: 0.5)
      return
    }
    do {
      let plaintext = try session.decrypt(packet.payload)
      securePeerIDs.insert(senderID)
      decryptFailures.removeValue(forKey: senderID)
      if plaintext.first == IOSMeshProtocol.noiseTransferFrame {
        emit([
          "type": "transferFrame",
          "peerId": senderID,
          "frame": FlutterStandardTypedData(bytes: Data(plaintext.dropFirst())),
        ])
        return
      }
      guard
        plaintext.first == IOSMeshProtocol.noisePrivate,
        let message = IOSMeshProtocol.decodePrivateMessage(plaintext.dropFirst())
      else { return }
      privateChatPeerIDs.insert(senderID)
      emitMessage(
        id: message.id,
        sender: peers[senderID]?.nickname ?? String(senderID.prefix(8)),
        content: message.content,
        senderPeerID: senderID,
        isPrivate: true,
        isMine: false,
        timestamp: packet.timestamp,
        channel: nil
      )
    } catch {
      if let meshError = error as? IOSMeshError,
         case .noiseRekeyRequired = meshError {
        invalidateNoiseState(peerID: senderID)
        scheduleAutoHandshake(peerID: senderID, force: true, delay: 0)
        emit([
          "type": "noiseRekey",
          "peerId": senderID,
          "reason": "transport_limit",
        ])
        return
      }
      registerDecryptFailure(peerID: senderID)
      return
    }
  }

  private func processCourier(_ packet: IOSMeshPacket, senderID: String) {
    guard
      let carrier = peers[senderID],
      IOSMeshIdentity.verify(packet, key: carrier.signingPublicKey),
      let envelope = IOSMeshProtocol.decodeCourierEnvelope(packet.payload),
      IOSMeshProtocol.courierEnvelopeIsFor(
        envelope,
        noisePublicKey: identity.noisePrivateKey.publicKey.rawRepresentation
      ),
      let fingerprint = IOSMeshProtocol.relayFingerprint(envelope.ciphertext),
      let inner = IOSMeshProtocol.decode(envelope.ciphertext),
      inner.type == IOSMeshProtocol.noiseEncrypted,
      inner.recipientID == identity.peerID
    else { return }
    guard seen[fingerprint] == nil else { return }
    seen[fingerprint] = Date()
    processEncrypted(inner, senderID: inner.senderID.hex)
  }

  private func requestMissingMessages(peerID: String, source: UUID) {
    let now = Date()
    if let previous = lastSyncRequestBySource[source],
       now.timeIntervalSince(previous) < 60 {
      return
    }
    lastSyncRequestBySource[source] = now
    let request = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.requestSync,
        ttl: 0,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        recipientID: try? Data(hex: peerID),
        payload: IOSMeshProtocol.encodeSyncRequest(syncSnapshot())
      )
    )
    send(packet: request, toPeerID: peerID)
  }

  private func processSyncRequest(
    _ packet: IOSMeshPacket,
    senderID: String,
    source: UUID
  ) {
    guard
      packet.ttl == 0,
      allowSyncResponse(source: source),
      let peer = peers[senderID],
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey),
      let request = IOSMeshProtocol.decodeSyncRequest(packet.payload)
    else { return }
    let remoteBuckets = IOSMeshProtocol.decodeGCS(request)
    var sent = 0
    for candidate in syncSnapshot() where sent < 40 {
      if
        privateMode,
        candidate.senderID == identity.peerID,
        IOSMeshInteropPolicy.identityPacketTypes.contains(candidate.type),
        !IOSMeshInteropPolicy.canSendIdentityToLink(
          privateMode: true,
          hearthbitProven: hearthbitProvenLinks.contains(source),
          emergencyException:
            candidate.type == IOSMeshProtocol.announce &&
            candidate.ttl == IOSMeshProtocol.defaultTTL
        )
      {
        continue
      }
      let typeFlag: UInt64
      switch candidate.type {
      case IOSMeshProtocol.announce:
        typeFlag = IOSMeshProtocol.syncFlagAnnounce
      case IOSMeshProtocol.message:
        typeFlag = IOSMeshProtocol.syncFlagMessage
      default:
        continue
      }
      guard request.typeFlags & typeFlag != 0 else { continue }
      if
        let since = request.since,
        candidate.type != IOSMeshProtocol.announce,
        candidate.timestamp < since
      {
        continue
      }
      let bucket = IOSMeshProtocol.gcsBucket(
        packetID: IOSMeshProtocol.packetID(candidate),
        m: request.m
      )
      if !remoteBuckets.isEmpty && remoteBuckets.contains(bucket) {
        continue
      }
      var replay = candidate
      replay.ttl = 0
      replay.isRSR = true
      send(packet: replay, toPeerID: senderID)
      sent += 1
    }
  }

  private func allowSyncResponse(source: UUID) -> Bool {
    let now = Date()
    var timestamps = syncResponseTimes[source, default: []]
      .filter { now.timeIntervalSince($0) <= 30 }
    guard timestamps.count < 8 else {
      syncResponseTimes[source] = timestamps
      return false
    }
    timestamps.append(now)
    syncResponseTimes[source] = timestamps
    return true
  }

  private func rememberSyncPacket(_ packet: IOSMeshPacket) {
    let broadcast = packet.recipientID == nil ||
      packet.recipientID == Data(repeating: 0xff, count: 8)
    guard
      packet.signature != nil,
      packet.type == IOSMeshProtocol.announce ||
        (packet.type == IOSMeshProtocol.message && broadcast),
      isSyncFresh(packet)
    else { return }
    if packet.type == IOSMeshProtocol.announce {
      if syncPackets.values.contains(where: {
        $0.type == IOSMeshProtocol.announce &&
          $0.senderID == packet.senderID &&
          $0.timestamp >= packet.timestamp
      }) {
        return
      }
      syncPackets = syncPackets.filter {
        !($0.value.type == IOSMeshProtocol.announce &&
          $0.value.senderID == packet.senderID &&
          $0.value.timestamp <= packet.timestamp)
      }
    }
    syncPackets[IOSMeshProtocol.packetID(packet).hex] = packet
    while syncPackets.count > 80,
          let oldest = syncPackets.min(by: { $0.value.timestamp < $1.value.timestamp }) {
      syncPackets.removeValue(forKey: oldest.key)
    }
  }

  private func syncSnapshot() -> [IOSMeshPacket] {
    syncPackets = syncPackets.filter { isSyncFresh($0.value) }
    return syncPackets.values.sorted { $0.timestamp > $1.timestamp }
  }

  private func isSyncFresh(_ packet: IOSMeshPacket) -> Bool {
    let now = currentMilliseconds()
    let window: UInt64 = packet.type == IOSMeshProtocol.announce
      ? 15 * 60 * 1000
      : 6 * 60 * 60 * 1000
    return packet.timestamp <= now + 15 * 60 * 1000 &&
      (now < window || packet.timestamp >= now - window)
  }

  private func peerMaps() -> [[String: Any]] {
    pruneRadarConsents()
    let now = Date()
    return peers.values.map { peer in
      let activity = lastPeerActivity(peer.id) ?? peer.lastSeen
      let online = IOSPeerReachabilityPolicy.isOnline(
        lastActivity: activity,
        now: now,
        window: Self.peerReachabilityWindow
      )
      let consent = remoteRadarConsents[peer.id]
      return [
        "id": peer.id,
        "nickname": peer.nickname,
        "lastSeen": Int(activity.timeIntervalSince1970 * 1000),
        "online": online,
        "secure": online && (sessions[peer.id]?.established ?? false),
        "signingPublicKey": FlutterStandardTypedData(bytes: peer.signingPublicKey),
        "supportsTransfers": peer.supportsTransfers,
        "supportsEmergencyAck": peer.supportsEmergencyAck,
        "hearthbitVerified": peer.hearthbitVerified,
        "role": peer.role.rawValue,
        "hasLongRangeTrunk": peer.hasLongRangeTrunk,
        "radarAllowedUntil": consent?.expiresAt ?? 0,
        "radarConsentSource": consent?.source ?? "",
      ]
    }
  }

  private func emitStatus(_ status: String) {
    var event: [String: Any] = [
      "type": "status",
      "status": status,
      "role": localRole.rawValue,
      "batteryLevel": batteryLevel,
      "adaptivePowerSaving": adaptivePowerSaving,
      "powerProfile": powerProfile.rawValue,
      "radarConsentUntil": activeLocalRadarConsentUntil(),
      "localBeaconActive": beaconActuator.isActive,
      "localBeaconExpiresAt": beaconActuator.expiresAt,
    ]
    if let identity {
      event["peerId"] = identity.peerIDHex
      event["nickname"] = identity.nickname
      event["signingPublicKey"] = FlutterStandardTypedData(
        bytes: identity.signingPrivateKey.publicKey.rawRepresentation
      )
    } else {
      event["status"] = "error"
      event["errorCode"] = "identity_unavailable"
      event["message"] = identityFailure?.localizedDescription ??
        IOSMeshError.identityUnavailable.localizedDescription
    }
    emit(event)
  }

  private func emitMessage(
    id: String,
    sender: String,
    content: String,
    senderPeerID: String,
    isPrivate: Bool,
    isMine: Bool,
    timestamp: UInt64,
    channel: String?,
    external: Bool = false
  ) {
    var message: [String: Any] = [
      "id": id,
      "sender": sender,
      "content": content,
      "senderPeerId": senderPeerID,
      "private": isPrivate,
      "mine": isMine,
      "timestamp": Int(timestamp),
      "external": external,
    ]
    if let channel { message["channel"] = channel }
    emit(["type": "message", "message": message])
  }

  private func emitError(_ message: String) {
    emit(["type": "error", "message": message])
  }

  private func clearCentralTransportState(_ identifier: UUID) {
    connectedPeripherals.removeValue(forKey: identifier)
    remoteCharacteristics.removeValue(forKey: identifier)
    centralWriteQueues.removeValue(forKey: identifier)
    centralWritesInFlight.remove(identifier)
    lastSyncRequestBySource.removeValue(forKey: identifier)
    syncResponseTimes.removeValue(forKey: identifier)
  }

  private func rememberMeshPeripheral(_ peripheral: CBPeripheral) {
    knownMeshPeripherals[peripheral.identifier] = peripheral
    peripheral.delegate = self
  }

  private func connectKnownPeripheral(_ peripheral: CBPeripheral, using central: CBCentralManager) {
    guard running, localRole.allowsDataPlane, central.state == .poweredOn else { return }
    let identifier = peripheral.identifier
    guard
      connectedPeripherals[identifier] == nil,
      reconnectTokens[identifier] == nil
    else { return }
    if let exhaustedUntil = reconnectExhaustedUntil[identifier] {
      guard exhaustedUntil <= Date() else { return }
      reconnectExhaustedUntil.removeValue(forKey: identifier)
      reconnectAttempts.removeValue(forKey: identifier)
    }

    let maximum = powerProfile.maximumOutgoingConnections
    guard maximum > 0 else { return }
    guard connectedPeripherals.count < maximum else { return }
    if powerProfile == .critical,
       !preferredPeripheralIDs.contains(identifier),
       connectedPeripherals.count >= maximum - 1 {
      // Conserva el último slot para un enlace ya conocido que reaparezca.
      return
    }

    rememberMeshPeripheral(peripheral)
    switch peripheral.state {
    case .connected:
      connectedPeripherals[identifier] = peripheral
      establishedPeripheralIDs.insert(identifier)
      preferredPeripheralIDs.insert(identifier)
      peripheral.discoverServices([Self.serviceUUID])
    case .connecting:
      connectedPeripherals[identifier] = peripheral
    case .disconnected:
      connectedPeripherals[identifier] = peripheral
      central.connect(peripheral)
    case .disconnecting:
      scheduleReconnect(peripheral)
    @unknown default:
      scheduleReconnect(peripheral)
    }
  }

  private func scheduleReconnect(_ peripheral: CBPeripheral) {
    let identifier = peripheral.identifier
    rememberMeshPeripheral(peripheral)
    guard
      running,
      localRole.allowsDataPlane,
      reconnectTokens[identifier] == nil
    else { return }
    let attempt = (reconnectAttempts[identifier] ?? 0) + 1
    guard attempt <= Self.reconnectDelays.count else {
      reconnectAttempts.removeValue(forKey: identifier)
      reconnectExhaustedUntil[identifier] = Date().addingTimeInterval(
        Self.reconnectCooldown
      )
      return
    }
    reconnectAttempts[identifier] = attempt
    let token = UUID()
    reconnectTokens[identifier] = token
    let delay = Self.reconnectDelays[attempt - 1]
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard
        let self,
        self.reconnectTokens[identifier] == token
      else { return }
      self.reconnectTokens.removeValue(forKey: identifier)
      guard let central = self.central else { return }
      self.connectKnownPeripheral(peripheral, using: central)
    }
  }

  private func reconnectKnownPeripherals() {
    guard running, localRole.allowsDataPlane, let central else { return }
    for peripheral in knownMeshPeripherals.values
    where connectedPeripherals[peripheral.identifier] == nil {
      connectKnownPeripheral(peripheral, using: central)
    }
  }

  private func triggerLinkLossScanBurst() {
    guard
      running,
      localRole.allowsDataPlane,
      powerProfile != .survival,
      radarPeerID == nil,
      let central,
      central.state == .poweredOn
    else { return }
    adaptiveScanTimer?.invalidate()
    adaptiveScanTimer = nil
    cancelGenericPresenceScanWindows()
    linkLossScanTimer?.invalidate()
    central.stopScan()
    central.scanForPeripherals(
      withServices: [Self.serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    linkLossScanTimer = Timer.scheduledTimer(
      withTimeInterval: Self.linkLossScanBurst,
      repeats: false
    ) { [weak self] _ in
      guard let self else { return }
      self.linkLossScanTimer = nil
      guard self.running, self.localRole.allowsDataPlane else { return }
      self.restartScan()
    }
  }

  private func handleDirectLinkLost(source: UUID) {
    let hasCentralLink = remoteCharacteristics[source] != nil &&
      connectedPeripherals[source]?.state == .connected
    let hasPeripheralLink = localCharacteristic?.subscribedCentrals?.contains {
      $0.identifier == source
    } ?? false
    guard !hasCentralLink, !hasPeripheralLink else { return }
    hearthbitProvenLinks.remove(source)
    guard let disconnectedPeer = peripheralPeers.removeValue(forKey: source) else { return }
    guard !peripheralPeers.values.contains(disconnectedPeer) else { return }
    invalidateNoiseState(peerID: disconnectedPeer)
    emit(["type": "peers", "peers": peerMaps()])
  }

  private func recordGenericPresence(
    advertisementData: [String: Any],
    rssi: Int
  ) {
    let material = genericAdvertisementMaterial(advertisementData)
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    guard genericPresenceTracker.record(material: material, rssi: rssi, now: now) else {
      return
    }
    if genericPresenceEmitWorkItem == nil {
      let workItem = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.genericPresenceEmitWorkItem = nil
        guard self.running, self.localRole.allowsDataPlane else { return }
        self.emitGenericPresenceSnapshot()
      }
      genericPresenceEmitWorkItem = workItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + IOSGenericBLEPresenceTracker.emitInterval,
        execute: workItem
      )
    }
    genericPresenceExpiryWorkItem?.cancel()
    let expiryWorkItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.genericPresenceExpiryWorkItem = nil
      guard self.running, self.localRole.allowsDataPlane else { return }
      self.emitGenericPresenceSnapshot()
    }
    genericPresenceExpiryWorkItem = expiryWorkItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + IOSGenericBLEPresenceTracker.staleAfter + 0.1,
      execute: expiryWorkItem
    )
  }

  private func emitGenericPresenceSnapshot() {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    emit([
      "type": "presences",
      "presences": genericPresenceTracker.snapshot(now: now).map(\.eventMap),
    ])
  }

  private func isMeshAdvertisement(_ advertisementData: [String: Any]) -> Bool {
    IOSGenericBLEAdvertisement.isMesh(
      advertisementData,
      meshServiceUUID: Self.serviceUUID
    )
  }

  private func genericAdvertisementMaterial(_ advertisementData: [String: Any]) -> Data {
    IOSGenericBLEAdvertisement.material(advertisementData)
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.eventSink?(event) }
  }
}

extension HearthBitMeshPlugin: CLLocationManagerDelegate {
  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.last else { return }
    handleRescueLocation(location)
  }

  func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error
  ) {
    emit(["type": "error", "message": error.localizedDescription])
  }
}

extension HearthBitMeshPlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard
      let activeCentral = self.central,
      activeCentral === central,
      running,
      central.state == .poweredOn
    else { return }
    restartScan()
    reconnectKnownPeripherals()
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    guard
      let activeCentral = self.central,
      activeCentral === central,
      running,
      localRole.allowsDataPlane
    else { return }
    guard isMeshAdvertisement(advertisementData) else {
      if genericPresenceScanEnabled &&
         genericPresenceWindowActive &&
         UIApplication.shared.applicationState == .active &&
         RSSI.intValue != 127 {
        recordGenericPresence(advertisementData: advertisementData, rssi: RSSI.intValue)
      }
      return
    }
    rememberMeshPeripheral(peripheral)
    if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
       let advertisedPeer = serviceData[Self.serviceUUID],
       advertisedPeer.count >= 8 {
      let peerID = advertisedPeer.prefix(8).hex
      if peers[peerID] != nil ||
         securePeerIDs.contains(peerID) ||
         privateChatPeerIDs.contains(peerID) ||
         !(pendingPrivate[peerID] ?? []).isEmpty ||
         !(pendingFrames[peerID] ?? []).isEmpty ||
         !(pendingCourier[peerID] ?? []).isEmpty {
        preferredPeripheralIDs.insert(peripheral.identifier)
      }
      peripheralPeers[peripheral.identifier] = peerID
    }
    // 127 significa «RSSI no disponible» según CoreBluetooth.
    if let target = radarPeerID,
       peripheralPeers[peripheral.identifier] == target,
       RSSI.intValue != 127 {
      emitRssi(peerID: target, rssi: RSSI.intValue)
    }
    guard connectedPeripherals[peripheral.identifier] == nil else { return }
    connectKnownPeripheral(peripheral, using: central)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard
      let activeCentral = self.central,
      activeCentral === central
    else { return }
    guard running, localRole.allowsDataPlane else {
      central.cancelPeripheralConnection(peripheral)
      return
    }
    let identifier = peripheral.identifier
    rememberMeshPeripheral(peripheral)
    connectedPeripherals[identifier] = peripheral
    establishedPeripheralIDs.insert(identifier)
    preferredPeripheralIDs.insert(identifier)
    reconnectAttempts.removeValue(forKey: identifier)
    reconnectTokens.removeValue(forKey: identifier)
    reconnectExhaustedUntil.removeValue(forKey: identifier)
    peripheral.discoverServices([Self.serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    guard
      let activeCentral = self.central,
      activeCentral === central
    else { return }
    let identifier = peripheral.identifier
    establishedPeripheralIDs.remove(identifier)
    clearCentralTransportState(identifier)
    guard running, localRole.allowsDataPlane else { return }
    scheduleReconnect(peripheral)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    guard
      let activeCentral = self.central,
      activeCentral === central
    else { return }
    let identifier = peripheral.identifier
    let wasEstablished = establishedPeripheralIDs.remove(identifier) != nil
    clearCentralTransportState(identifier)
    handleDirectLinkLost(source: identifier)
    guard running, localRole.allowsDataPlane else { return }
    if wasEstablished { triggerLinkLossScanBurst() }
    scheduleReconnect(peripheral)
    reconnectKnownPeripherals()
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    guard
      let activeCentral = self.central,
      activeCentral === central
    else { return }
    let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    let restoredScanServices =
      dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] ?? []
    guard identity != nil else {
      restored.forEach { central.cancelPeripheralConnection($0) }
      emitStatus("error")
      return
    }
    if !restored.isEmpty || !restoredScanServices.isEmpty {
      running = true
      UIDevice.current.isBatteryMonitoringEnabled = true
      refreshPowerState(emitEvent: false)
    }
    guard running, localRole.allowsDataPlane else {
      restored.forEach { central.cancelPeripheralConnection($0) }
      return
    }
    for peripheral in restored {
      let identifier = peripheral.identifier
      rememberMeshPeripheral(peripheral)
      preferredPeripheralIDs.insert(identifier)
      switch peripheral.state {
      case .connected:
        connectedPeripherals[identifier] = peripheral
        establishedPeripheralIDs.insert(identifier)
        reconnectAttempts.removeValue(forKey: identifier)
        reconnectTokens.removeValue(forKey: identifier)
        reconnectExhaustedUntil.removeValue(forKey: identifier)
        peripheral.discoverServices([Self.serviceUUID])
      case .connecting:
        connectedPeripherals[identifier] = peripheral
      case .disconnected, .disconnecting:
        if central.state == .poweredOn {
          connectKnownPeripheral(peripheral, using: central)
        }
      @unknown default:
        break
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard localRole.allowsDataPlane else { return }
    peripheral.services?
      .filter { $0.uuid == Self.serviceUUID }
      .forEach { peripheral.discoverCharacteristics([Self.characteristicUUID], for: $0) }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard localRole.allowsDataPlane else { return }
    guard
      let characteristic = service.characteristics?.first(where: {
        $0.uuid == Self.characteristicUUID
      })
    else { return }
    remoteCharacteristics[peripheral.identifier] = characteristic
    peripheral.setNotifyValue(true, for: characteristic)
    sendHearthBitLinkProof(to: peripheral.identifier)
    sendAnnouncement()
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard localRole.allowsDataPlane else { return }
    guard let value = characteristic.value else { return }
    receive(value, source: peripheral.identifier)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    let identifier = peripheral.identifier
    guard
      characteristic.uuid == Self.characteristicUUID,
      centralWritesInFlight.remove(identifier) != nil
    else { return }
    if let error {
      guard var queue = centralWriteQueues[identifier] else { return }
      let emergency = queue.currentPriority == .emergency
      guard let failure = queue.failCurrent() else { return }
      hearthBitDebugLog(
        "HearthBitMesh: central write failed for %@ (attempt %d): %@",
        identifier.uuidString,
        failure.attempt,
        error.localizedDescription
      )
      if queue.isEmpty {
        centralWriteQueues.removeValue(forKey: identifier)
      } else {
        centralWriteQueues[identifier] = queue
      }
      if failure.discarded {
        emitBLETransportFailure(
          code: "central_write_failed",
          identifier: identifier,
          emergency: emergency,
          frames: 1,
          message: error.localizedDescription
        )
        drainCentralWriteQueue(peripheral)
      } else {
        emit([
          "type": "bleTransportRetry",
          "code": "central_write_retry",
          "peripheralId": identifier.uuidString,
          "emergency": emergency,
          "attempt": failure.attempt,
          "message": error.localizedDescription,
        ])
        let delay = min(2.0, 0.25 * pow(2.0, Double(failure.attempt - 1)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak peripheral] in
          guard
            let self,
            let peripheral,
            self.connectedPeripherals[identifier] === peripheral
          else { return }
          self.drainCentralWriteQueue(peripheral)
        }
      }
      return
    }
    if var queue = centralWriteQueues[identifier] {
      queue.completeCurrent()
      if queue.isEmpty {
        centralWriteQueues.removeValue(forKey: identifier)
      } else {
        centralWriteQueues[identifier] = queue
      }
    }
    drainCentralWriteQueue(peripheral)
  }

  func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    drainCentralWriteQueue(peripheral)
  }

  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    guard
      error == nil,
      let target = radarPeerID,
      peripheralPeers[peripheral.identifier] == target,
      RSSI.intValue != 127
    else { return }
    emitRssi(peerID: target, rssi: RSSI.intValue)
  }
}

extension HearthBitMeshPlugin: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard
      let activePeripheralManager = peripheralManager,
      activePeripheralManager === peripheral,
      running
    else { return }
    guard peripheral.state == .poweredOn else {
      configuredPeripheralRole = nil
      if peripheral.state == .unsupported || peripheral.state == .unauthorized {
        emitError(HearthBitL10n.string("no_advertising"))
        emitStatus("degraded")
      }
      return
    }
    if
      restoredPeripheralService,
      localRole.allowsDataPlane,
      localCharacteristic != nil
    {
      restoredPeripheralService = false
      configuredPeripheralRole = localRole
      peripheral.startAdvertising([
        CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
      ])
      localCharacteristic?.subscribedCentrals?.forEach {
        sendSubscriptionAnnouncement(to: $0)
      }
    } else {
      restoredPeripheralService = false
      configurePeripheralMode()
    }
  }

  func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager,
    error: Error?
  ) {
    guard
      let activePeripheralManager = peripheralManager,
      activePeripheralManager === peripheral,
      running
    else { return }
    if let error {
      emitError(
        String(
          format: HearthBitL10n.string("advertise_failed"),
          error.localizedDescription
        )
      )
      emitStatus("degraded")
      return
    }
    emitStatus("active")
    if localRole.allowsDataPlane {
      sendAnnouncement()
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    guard
      let activePeripheralManager = peripheralManager,
      activePeripheralManager === peripheral
    else { return }
    guard localRole.allowsDataPlane else {
      requests.forEach { peripheral.respond(to: $0, withResult: .writeNotPermitted) }
      return
    }
    for request in requests {
      if request.characteristic.uuid == Self.characteristicUUID, let value = request.value {
        receive(value, source: request.central.identifier)
      }
      peripheral.respond(to: request, withResult: .success)
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    guard
      let activePeripheralManager = peripheralManager,
      activePeripheralManager === peripheral
    else { return }
    guard let characteristic = localCharacteristic else { return }
    for identifier in Array(peripheralNotifyQueues.keys) {
      drainPeripheralNotifyQueue(
        identifier,
        manager: peripheral,
        characteristic: characteristic
      )
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    central: CBCentral,
    didSubscribeTo characteristic: CBCharacteristic
  ) {
    guard
      let activePeripheralManager = peripheralManager,
      activePeripheralManager === peripheral
    else { return }
    guard characteristic.uuid == Self.characteristicUUID else { return }
    peripheralNotifyQueues.removeValue(forKey: central.identifier)
    if let peerID = peripheralPeers[central.identifier] {
      invalidateNoiseState(peerID: peerID)
    }
    sendSubscriptionAnnouncement(to: central)
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    central: CBCentral,
    didUnsubscribeFrom characteristic: CBCharacteristic
  ) {
    guard
      let activePeripheralManager = peripheralManager,
      activePeripheralManager === peripheral
    else { return }
    let identifier = central.identifier
    let hasCentralLink = remoteCharacteristics[identifier] != nil &&
      connectedPeripherals[identifier]?.state == .connected
    peripheralNotifyQueues.removeValue(forKey: identifier)
    handleDirectLinkLost(source: identifier)
    if !hasCentralLink {
      triggerLinkLossScanBurst()
      reconnectKnownPeripherals()
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
    guard
      let activePeripheralManager = peripheralManager,
      activePeripheralManager === peripheral
    else { return }
    let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? []
    let restoredAdvertisement =
      dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] as? [String: Any]
    guard identity != nil else {
      peripheral.stopAdvertising()
      peripheral.removeAllServices()
      emitStatus("error")
      return
    }
    if !services.isEmpty || restoredAdvertisement != nil {
      running = true
      UIDevice.current.isBatteryMonitoringEnabled = true
      refreshPowerState(emitEvent: false)
    }
    guard localRole.allowsDataPlane else {
      localCharacteristic = nil
      restoredPeripheralService = false
      configuredPeripheralRole = localRole
      peripheral.stopAdvertising()
      peripheral.removeAllServices()
      return
    }
    if !services.isEmpty {
      localCharacteristic = services
        .flatMap { $0.characteristics ?? [] }
        .compactMap { $0 as? CBMutableCharacteristic }
        .first(where: { $0.uuid == Self.characteristicUUID })
      restoredPeripheralService = localCharacteristic != nil
      if restoredPeripheralService {
        configuredPeripheralRole = localRole
      }
    }
  }
}

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
    sessionSecret: Data? = nil,
    rotationMilliseconds: Int64 = IOSGenericBLEPresenceTracker.rotationMilliseconds,
    staleMilliseconds: Int64 = IOSGenericBLEPresenceTracker.staleMilliseconds,
    maximumObservations: Int = IOSGenericBLEPresenceTracker.maximumObservations
  ) {
    let secret = sessionSecret ?? Self.secureSessionSecret()
    precondition(!secret.isEmpty)
    precondition(rotationMilliseconds > 0)
    precondition(staleMilliseconds > 0)
    precondition(maximumObservations > 0)
    self.sessionSecret = secret
    rotation = rotationMilliseconds
    stale = staleMilliseconds
    maximum = maximumObservations
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

  private static func secureSessionSecret() -> Data {
    let secretSize = 32
    var output = Data(count: secretSize)
    let status = output.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, secretSize, address)
    }
    if status == errSecSuccess { return output }
    return Data(SHA256.hash(data: Data(UUID().uuidString.utf8)))
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

private struct IOSMeshPeer {
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

enum IOSMeshInteropPolicy {
  static let linkProof = Data("HB-LINK1".utf8)
  static let identityPacketTypes: Set<UInt8> = [
    IOSMeshProtocol.announce,
    IOSMeshProtocol.hbtCapability,
    IOSMeshProtocol.emergencyCapability,
    IOSMeshProtocol.nodeCapability,
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

private struct IOSRemoteRadarConsent {
  let expiresAt: UInt64
  let source: String
}

private struct IOSPendingBeaconRequest {
  let peerID: String
  let nickname: String
  let control: IOSBeaconControlProtocol.Control
}

private struct IOSOutgoingBeaconRequest {
  let peerID: String
  let expiresAt: UInt64
  let flags: UInt8
}

enum IOSBeaconControlProtocol {
  static let version: UInt8 = 1
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

  static func request(expiresAt: UInt64, flags: UInt8, nonce: Data? = nil) -> Data {
    encode(action: requestAction, expiresAt: expiresAt, nonce: nonce ?? randomNonce(), flags: flags)
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

  static func shouldAutoAccept(localRadarConsentUntil: UInt64, now: UInt64) -> Bool {
    localRadarConsentUntil > now
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

  private static func randomNonce() -> Data {
    var nonce = Data(count: nonceSize)
    let status = nonce.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, nonceSize, address)
    }
    if status != errSecSuccess {
      return Data(SHA256.hash(data: Data(UUID().uuidString.utf8))).prefix(nonceSize)
    }
    return nonce
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
  static let nonceSize = 16
  static let payloadSize = 26
  static let sosDurationMilliseconds: UInt64 = 10 * 60 * 1000
  static let maximumGrantMilliseconds: UInt64 = 20 * 60 * 1000
  static let clockSkewMilliseconds: UInt64 = 2 * 60 * 1000

  struct Consent {
    let action: UInt8
    let expiresAt: UInt64
    let nonce: Data
  }

  static func grant(expiresAt: UInt64) -> Data {
    encode(action: grantAction, expiresAt: expiresAt)
  }

  static func revoke() -> Data {
    encode(action: revokeAction, expiresAt: 0)
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

  static func hasValidTimestamp(_ timestamp: UInt64, now: UInt64) -> Bool {
    timestamp <= now + clockSkewMilliseconds &&
      timestamp + clockSkewMilliseconds >= now
  }

  static func isValidGrant(
    _ consent: Consent,
    packetTimestamp: UInt64,
    now: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
  ) -> Bool {
    consent.action == grantAction &&
      hasValidTimestamp(packetTimestamp, now: now) &&
      consent.expiresAt > now &&
      consent.expiresAt <= now + maximumGrantMilliseconds + clockSkewMilliseconds
  }

  private static func encode(action: UInt8, expiresAt: UInt64) -> Data {
    var output = Data([version, action])
    output.appendInteger(expiresAt)
    var nonce = Data(count: nonceSize)
    let randomStatus = nonce.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, nonceSize, address)
    }
    if randomStatus != errSecSuccess {
      nonce = Data(SHA256.hash(data: Data(UUID().uuidString.utf8))).prefix(nonceSize)
    }
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
  static let hbtCapability: UInt8 = 0x24
  static let nodeCapability: UInt8 = 0x25
  static let beaconControl: UInt8 = 0x26
  static let rangingControl: UInt8 = 0x27
  static let emergencyCapability: UInt8 = 0x28
  static let emergencyAck: UInt8 = 0x29
  static let emergencyVersion: UInt8 = 0x01
  static let hbtVersion: UInt8 = 0x01
  static let noisePrivate: UInt8 = 0x01
  /// Trama HBT (HearthBit Transfer) encapsulada dentro de la sesión Noise.
  static let noiseTransferFrame: UInt8 = 0x30
  static let defaultTTL: UInt8 = 7

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
    guard packet.type == message,
          let content = String(data: packet.payload, encoding: .utf8)
    else { return false }
    return content.hasPrefix("SOS|") || content.contains("[HB-CHECKIN|")
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
    if shouldCompress(payload), let compressed = compress(payload) {
      originalPayloadSize = payload.count
      payload = compressed
    }
    var flags: UInt8 = 0
    if packet.recipientID != nil { flags |= 0x01 }
    if packet.signature != nil { flags |= 0x02 }
    if originalPayloadSize != nil { flags |= 0x04 }
    if packet.version >= 2 && !packet.route.isEmpty { flags |= 0x08 }
    if packet.isRSR { flags |= 0x10 }
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
    return IOSMeshPacket(
      version: version,
      type: type,
      ttl: ttl,
      timestamp: timestamp,
      senderID: sender,
      recipientID: recipient,
      payload: payload,
      signature: signature,
      route: route,
      isRSR: flags & 0x10 != 0
    )
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
    signingPublicKey: Data
  ) -> Data {
    var output = Data()
    output.appendTLV(type: 0x01, value: Data(nickname.utf8).prefix(31))
    output.appendTLV(type: 0x02, value: noisePublicKey)
    output.appendTLV(type: 0x03, value: signingPublicKey)
    output.appendTLV(type: 0x05, value: Data([0x00]))
    return output
  }

  static func decodeAnnouncement(_ payload: Data) -> Announcement? {
    var reader = DataReader(payload)
    var nickname: String?
    var noise: Data?
    var signing: Data?
    var supportsTransfers = false
    var isInfrastructure = false
    while let type = reader.byte(), let length = reader.byte(),
          let value = reader.data(count: Int(length)) {
      switch type {
      case 0x01: nickname = String(data: value, encoding: .utf8)
      case 0x02: noise = value
      case 0x03: signing = value
      case 0xF0: supportsTransfers = value == Data([0x01])
      case 0xB1: isInfrastructure = value.first.map { $0 & 0x01 != 0 } ?? false
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
      isInfrastructure: isInfrastructure
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

private extension IOSBLEFramePriority {
  static func forPacket(_ packet: IOSMeshPacket) -> IOSBLEFramePriority {
    if IOSMeshProtocol.isEmergency(packet) ||
       packet.type == IOSMeshProtocol.emergencyAck ||
       packet.type == IOSMeshProtocol.beaconControl {
      return .emergency
    }
    return .normal
  }
}

final class IOSMeshPacketFragmenter {
  static let maximumGATTValueLength = 512
  static let maximumFragmentDataLength = 469
  static let maximumFragments = 256
  static let maximumReassembledBytes = 1_048_576

  private let fragmentIDGenerator: () -> Data

  init(fragmentIDGenerator: (() -> Data)? = nil) {
    self.fragmentIDGenerator = fragmentIDGenerator ?? Self.secureFragmentID
  }

  func prepare(
    packet: IOSMeshPacket,
    encoded: Data,
    maximumValueLength: Int
  ) -> [Data]? {
    let linkLimit = min(maximumValueLength, Self.maximumGATTValueLength)
    guard linkLimit > 0 else { return nil }
    guard packet.type != IOSMeshProtocol.fragment else { return nil }
    if encoded.count <= linkLimit { return [encoded] }

    let originalData = IOSMeshProtocol.removeBLETransportPadding(packet, encoded: encoded)
    guard originalData.count <= Self.maximumReassembledBytes else { return nil }
    let fragmentID = fragmentIDGenerator()
    guard fragmentID.count == IOSMeshProtocol.fragmentIDSize else { return nil }

    guard
      let emptyPacket = fragmentPacket(
        source: packet,
        fragmentID: fragmentID,
        index: 0,
        total: 1,
        data: Data()
      )
    else { return nil }
    let fixedSize = IOSMeshProtocol.encodeForBLE(emptyPacket).count
    var chunkSize = min(Self.maximumFragmentDataLength, linkLimit - fixedSize)
    guard chunkSize > 0 else { return nil }

    while chunkSize > 0 {
      let total = (originalData.count + chunkSize - 1) / chunkSize
      guard total <= Self.maximumFragments else { return nil }
      var frames: [Data] = []
      frames.reserveCapacity(total)
      var offset = 0
      var fits = true
      for index in 0..<total {
        let end = min(offset + chunkSize, originalData.count)
        guard
          let fragment = fragmentPacket(
            source: packet,
            fragmentID: fragmentID,
            index: index,
            total: total,
            data: originalData.subdata(in: offset..<end)
          )
        else { return nil }
        let frame = IOSMeshProtocol.encodeForBLE(fragment)
        if frame.count > linkLimit {
          fits = false
          break
        }
        frames.append(frame)
        offset = end
      }
      if fits { return frames }
      chunkSize -= 1
    }
    return nil
  }

  private func fragmentPacket(
    source: IOSMeshPacket,
    fragmentID: Data,
    index: Int,
    total: Int,
    data: Data
  ) -> IOSMeshPacket? {
    guard
      let payload = IOSMeshProtocol.encodeFragmentPayload(
        IOSMeshProtocol.FragmentPayload(
          fragmentID: fragmentID,
          index: index,
          total: total,
          originalType: source.type,
          data: data
        )
      )
    else { return nil }
    return IOSMeshPacket(
      version: source.version,
      type: IOSMeshProtocol.fragment,
      ttl: source.ttl,
      timestamp: source.timestamp,
      senderID: source.senderID,
      recipientID: source.recipientID,
      payload: payload,
      signature: nil,
      route: source.route,
      isRSR: false
    )
  }

  private static func secureFragmentID() -> Data {
    var output = Data(count: IOSMeshProtocol.fragmentIDSize)
    let status = output.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, IOSMeshProtocol.fragmentIDSize, address)
    }
    if status == errSecSuccess { return output }
    return Data(SHA256.hash(data: Data(UUID().uuidString.utf8)))
      .prefix(IOSMeshProtocol.fragmentIDSize)
  }
}

final class IOSMeshFragmentReassembler {
  private struct FragmentSet {
    let originalType: UInt8
    let total: Int
    let senderID: Data
    let recipientID: Data?
    var updatedAt: Date
    var parts: [Int: Data] = [:]
    var bytes = 0
  }

  private static let maximumFragments = 256
  private static let maximumSetBytes = 1_048_576
  private static let maximumActiveSets = 64
  private static let maximumGlobalBytes = 4 * 1_048_576
  private static let timeout: TimeInterval = 30

  private var sets: [String: FragmentSet] = [:]
  private var bufferedBytes = 0

  func accept(_ packet: IOSMeshPacket, now: Date = Date()) -> IOSMeshPacket? {
    guard
      packet.type == IOSMeshProtocol.fragment,
      let fragment = IOSMeshProtocol.decodeFragmentPayload(packet.payload),
      fragment.total <= Self.maximumFragments,
      fragment.originalType != IOSMeshProtocol.fragment,
      !fragment.data.isEmpty
    else { return nil }

    pruneExpired(now: now)
    let key = "\(packet.senderID.hex):\(fragment.fragmentID.hex)"
    var set: FragmentSet
    if let existing = sets[key] {
      set = existing
    } else {
      guard sets.count < Self.maximumActiveSets else { return nil }
      set = FragmentSet(
        originalType: fragment.originalType,
        total: fragment.total,
        senderID: packet.senderID,
        recipientID: packet.recipientID,
        updatedAt: now
      )
    }
    guard
      set.originalType == fragment.originalType,
      set.total == fragment.total,
      set.senderID == packet.senderID,
      set.recipientID == packet.recipientID
    else {
      remove(key)
      return nil
    }
    if let existing = set.parts[fragment.index] {
      if existing != fragment.data { remove(key) }
      return nil
    }
    guard
      set.bytes + fragment.data.count <= Self.maximumSetBytes,
      bufferedBytes + fragment.data.count <= Self.maximumGlobalBytes
    else {
      remove(key)
      return nil
    }

    set.parts[fragment.index] = fragment.data
    set.bytes += fragment.data.count
    set.updatedAt = now
    bufferedBytes += fragment.data.count
    sets[key] = set
    guard set.parts.count == set.total else { return nil }

    var reassembled = Data()
    reassembled.reserveCapacity(set.bytes)
    for index in 0..<set.total {
      guard let part = set.parts[index] else { return nil }
      reassembled.append(part)
    }
    let decoded = IOSMeshProtocol.decode(reassembled)
    remove(key)
    guard
      var original = decoded,
      original.type == set.originalType,
      original.senderID == packet.senderID,
      original.recipientID == packet.recipientID
    else { return nil }
    original.ttl = 0
    return original
  }

  func clear() {
    sets.removeAll()
    bufferedBytes = 0
  }

  private func pruneExpired(now: Date) {
    for key in sets.compactMap({
      now.timeIntervalSince($0.value.updatedAt) > Self.timeout ? $0.key : nil
    }) {
      remove(key)
    }
  }

  private func remove(_ key: String) {
    guard let removed = sets.removeValue(forKey: key) else { return }
    bufferedBytes = max(0, bufferedBytes - removed.bytes)
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
    packet.type != IOSMeshProtocol.noiseHandshake &&
      packet.type != IOSMeshProtocol.noiseEncrypted &&
      packet.type != IOSMeshProtocol.beaconControl
  }
}

private final class IOSEmergencyFingerprintCache {
  private let key = "hearthbit.emergency_fingerprints"
  private let lifetime: UInt64 = 24 * 60 * 60 * 1_000
  private let maximum = 512

  func seenOrRemember(_ fingerprint: String, now: UInt64? = nil) -> Bool {
    let timestamp = now ?? UInt64(Date().timeIntervalSince1970 * 1000)
    let normalized = fingerprint.lowercased()
    var entries = validEntries(now: timestamp)
    let duplicate = entries.contains { $0.fingerprint == normalized }
    if !duplicate {
      entries.append((timestamp, normalized))
    }
    UserDefaults.standard.set(
      entries.suffix(maximum).map {
        ["at": $0.at, "fingerprint": $0.fingerprint]
      },
      forKey: key
    )
    return duplicate
  }

  func clear() {
    UserDefaults.standard.removeObject(forKey: key)
  }

  private func validEntries(
    now: UInt64
  ) -> [(at: UInt64, fingerprint: String)] {
    let values = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
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

struct IOSPeerIdentityPin: Codable, Equatable {
  let peerID: String
  let noisePublicKey: Data
  let signingPublicKey: Data
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
  private static let maximumPins = 512
  static let legacyDefaultsKey = "hearthbit.peer_identity_pins"

  private let defaults: UserDefaults
  private let read: Read
  private let upsert: Upsert
  private let delete: Delete
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
      }
    )
  }

  init(
    defaults: UserDefaults,
    read: @escaping Read,
    upsert: @escaping Upsert,
    delete: @escaping Delete
  ) {
    self.defaults = defaults
    self.read = read
    self.upsert = upsert
    self.delete = delete
    do {
      try restore()
    } catch {
      failure = error
      pins.removeAll()
    }
  }

  func pin(for peerID: String) -> IOSPeerIdentityPin? {
    pins[peerID.lowercased()]
  }

  func validateAndPin(
    peerID: String,
    noisePublicKey: Data,
    signingPublicKey: Data
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
    guard pins.count < Self.maximumPins else {
      throw IOSSecureStorageError.logicalTransactionFailed(
        "Peer identity pin capacity reached"
      )
    }

    let pin = IOSPeerIdentityPin(
      peerID: normalized,
      noisePublicKey: noisePublicKey,
      signingPublicKey: signingPublicKey
    )
    pins[normalized] = pin
    do {
      try persist()
    } catch {
      pins.removeValue(forKey: normalized)
      failure = error
      throw error
    }
    return .firstBinding
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
    guard values.count <= Self.maximumPins else {
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
        signingPublicKey: pin.signingPublicKey
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
        intervalMs: 120_000,
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

private final class IOSNoiseHandshake {
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

private final class IOSNoiseSymmetric {
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

private struct DataReader {
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

private extension Data {
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

/// Stream handler vacío para el canal de eventos de transferencia en iOS.
final class HearthBitTransferEventStub: NSObject, FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? { nil }

  func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}

private enum IOSMeshError: LocalizedError {
  case notRunning
  case peerUnavailable
  case invalidPeerID
  case identityMismatch
  case identityUnavailable
  case noise
  case noiseRekeyRequired
  case storageUnavailable
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
    case .invalidPayload: return HearthBitL10n.string("invalid_payload")
    case .radarConsentRequired: return HearthBitL10n.string("radar_consent_required")
    case .roleCannotChat: return HearthBitL10n.string("role_cannot_chat")
    }
  }
}

/// Localización nativa mínima sin tocar el proyecto de Xcode: elige el idioma
/// preferido del sistema entre los seis que soporta la app y cae a inglés si
/// no hay coincidencia. Las traducciones espejan los ARB de Flutter.
enum HearthBitL10n {
  private static let supported = ["en", "es", "de", "fr", "zh", "ja"]

  static var language: String {
    for preferred in Locale.preferredLanguages {
      let code = String(preferred.prefix(2)).lowercased()
      if supported.contains(code) { return code }
    }
    return "en"
  }

  static func string(_ key: String) -> String {
    table[language]?[key] ?? table["en"]?[key] ?? key
  }

  private static let table: [String: [String: String]] = [
    "en": [
      "sos_default": "I need help",
      "nearby_unavailable": "Nearby Connections is not available on iOS",
      "wifi_aware_unavailable": "Wi-Fi Aware is not available on this iOS version",
      "identity_rejected": "A private channel was rejected due to an invalid identity",
      "no_advertising": "This device cannot advertise over BLE; receive-only mode",
      "advertise_failed": "Could not advertise the BLE mesh: %@",
      "not_running": "The mesh is not active",
      "peer_unavailable": "The device is no longer available",
      "invalid_peer_id": "The device identity is not valid",
      "identity_mismatch": "The Noise identity does not match",
      "identity_unavailable": "The secure device identity is unavailable",
      "noise_failed": "The Noise encrypted channel failed",
      "noise_rekey_required": "The private channel must be renewed",
      "storage_unavailable": "Secure emergency storage is unavailable",
      "invalid_payload": "The transfer payload is not valid",
      "radar_consent_required": "This person has not allowed radar location",
      "role_cannot_chat": "Presence-only mode cannot send messages",
      "family_notification_title": "HearthBit family alert",
      "family_status_sos": "SOS",
      "family_status_ok": "I am safe",
      "family_status_help": "Needs help",
      "family_status_injured": "Injured",
      "family_status_check_in": "Check-in",
    ],
    "es": [
      "sos_default": "Necesito ayuda",
      "nearby_unavailable": "Nearby Connections no está disponible en iOS",
      "wifi_aware_unavailable": "Wi-Fi Aware no está disponible en esta versión de iOS",
      "identity_rejected": "Un canal privado fue rechazado por identidad inválida",
      "no_advertising": "Este dispositivo no puede anunciarse por BLE; modo solo recepción",
      "advertise_failed": "No se pudo anunciar la malla BLE: %@",
      "not_running": "La malla no está activa",
      "peer_unavailable": "El dispositivo ya no está disponible",
      "invalid_peer_id": "La identidad del dispositivo no es válida",
      "identity_mismatch": "La identidad Noise no coincide",
      "identity_unavailable": "La identidad segura del dispositivo no está disponible",
      "noise_failed": "Falló el canal cifrado Noise",
      "noise_rekey_required": "El canal privado debe renovarse",
      "storage_unavailable": "El almacenamiento seguro de emergencia no está disponible",
      "invalid_payload": "La carga de la transferencia no es válida",
      "radar_consent_required": "Esta persona no ha permitido la ubicación por radar",
      "role_cannot_chat": "El modo de solo presencia no puede enviar mensajes",
      "family_notification_title": "Alerta familiar de HearthBit",
      "family_status_sos": "SOS",
      "family_status_ok": "Estoy bien",
      "family_status_help": "Necesita ayuda",
      "family_status_injured": "Herido",
      "family_status_check_in": "Estado familiar",
    ],
    "de": [
      "sos_default": "Ich brauche Hilfe",
      "nearby_unavailable": "Nearby Connections ist auf iOS nicht verfügbar",
      "wifi_aware_unavailable": "Wi-Fi Aware ist in dieser iOS-Version nicht verfügbar",
      "identity_rejected": "Ein privater Kanal wurde wegen ungültiger Identität abgelehnt",
      "no_advertising": "Dieses Gerät kann sich nicht über BLE ankündigen; Nur-Empfangsmodus",
      "advertise_failed": "Das BLE-Mesh konnte nicht angekündigt werden: %@",
      "not_running": "Das Mesh ist nicht aktiv",
      "peer_unavailable": "Das Gerät ist nicht mehr verfügbar",
      "invalid_peer_id": "Die Geräteidentität ist ungültig",
      "identity_mismatch": "Die Noise-Identität stimmt nicht überein",
      "noise_failed": "Der verschlüsselte Noise-Kanal ist fehlgeschlagen",
      "invalid_payload": "Die Übertragungsdaten sind ungültig",
      "radar_consent_required": "Diese Person hat die Ortung per Radar nicht erlaubt",
      "role_cannot_chat": "Im reinen Anwesenheitsmodus können keine Nachrichten gesendet werden",
      "family_notification_title": "HearthBit-Familienmeldung",
      "family_status_sos": "SOS",
      "family_status_ok": "Mir geht es gut",
      "family_status_help": "Benötigt Hilfe",
      "family_status_injured": "Verletzt",
      "family_status_check_in": "Statusmeldung",
    ],
    "fr": [
      "sos_default": "J'ai besoin d'aide",
      "nearby_unavailable": "Nearby Connections n'est pas disponible sur iOS",
      "wifi_aware_unavailable": "Wi-Fi Aware n'est pas disponible sur cette version d'iOS",
      "identity_rejected": "Un canal privé a été rejeté pour identité invalide",
      "no_advertising": "Cet appareil ne peut pas s'annoncer en BLE ; mode réception seule",
      "advertise_failed": "Impossible d'annoncer le maillage BLE : %@",
      "not_running": "Le maillage n'est pas actif",
      "peer_unavailable": "L'appareil n'est plus disponible",
      "invalid_peer_id": "L'identité de l'appareil n'est pas valide",
      "identity_mismatch": "L'identité Noise ne correspond pas",
      "noise_failed": "Le canal chiffré Noise a échoué",
      "invalid_payload": "La charge du transfert n'est pas valide",
      "radar_consent_required": "Cette personne n'a pas autorisé la localisation par radar",
      "role_cannot_chat": "Le mode présence seule ne peut pas envoyer de messages",
      "family_notification_title": "Alerte familiale HearthBit",
      "family_status_sos": "SOS",
      "family_status_ok": "Je vais bien",
      "family_status_help": "A besoin d'aide",
      "family_status_injured": "Blessé",
      "family_status_check_in": "État familial",
    ],
    "zh": [
      "sos_default": "我需要帮助",
      "nearby_unavailable": "Nearby Connections 在 iOS 上不可用",
      "wifi_aware_unavailable": "此 iOS 版本不支持 Wi-Fi Aware",
      "identity_rejected": "一个私密通道因身份无效被拒绝",
      "no_advertising": "此设备无法进行 BLE 广播；仅接收模式",
      "advertise_failed": "无法广播 BLE 网状网络：%@",
      "not_running": "网状网络未激活",
      "peer_unavailable": "该设备已不可用",
      "invalid_peer_id": "设备身份无效",
      "identity_mismatch": "Noise 身份不匹配",
      "noise_failed": "Noise 加密通道失败",
      "invalid_payload": "传输数据无效",
      "radar_consent_required": "对方尚未允许通过雷达定位",
      "role_cannot_chat": "仅在线状态模式无法发送消息",
      "family_notification_title": "HearthBit 家庭警报",
      "family_status_sos": "SOS",
      "family_status_ok": "我很安全",
      "family_status_help": "需要帮助",
      "family_status_injured": "受伤",
      "family_status_check_in": "家庭状态",
    ],
    "ja": [
      "sos_default": "助けが必要です",
      "nearby_unavailable": "Nearby Connections は iOS では利用できません",
      "wifi_aware_unavailable": "このバージョンの iOS では Wi-Fi Aware を利用できません",
      "identity_rejected": "無効な ID のためプライベートチャネルが拒否されました",
      "no_advertising": "この端末は BLE アドバタイズができません。受信専用モードです",
      "advertise_failed": "BLE メッシュをアドバタイズできませんでした：%@",
      "not_running": "メッシュが有効ではありません",
      "peer_unavailable": "端末が利用できなくなりました",
      "invalid_peer_id": "端末の ID が無効です",
      "identity_mismatch": "Noise の ID が一致しません",
      "noise_failed": "Noise 暗号化チャネルに失敗しました",
      "invalid_payload": "転送ペイロードが無効です",
      "radar_consent_required": "相手はレーダーによる位置確認を許可していません",
      "role_cannot_chat": "プレゼンス専用モードではメッセージを送信できません",
      "family_notification_title": "HearthBit 家族通知",
      "family_status_sos": "SOS",
      "family_status_ok": "無事です",
      "family_status_help": "助けが必要です",
      "family_status_injured": "負傷しています",
      "family_status_check_in": "家族の安否情報",
    ],
  ]
}
