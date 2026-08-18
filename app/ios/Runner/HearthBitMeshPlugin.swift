import CoreBluetooth
import CoreLocation
import CryptoKit
import Compression
import Flutter
import Foundation
import MessageUI
import Security
import UIKit
import UserNotifications
import zlib

private func hearthBitDebugLog(_ format: String, _ arguments: CVarArg...) {
  #if DEBUG
  withVaList(arguments) { Foundation.NSLogv(format, $0) }
  #endif
}

final class HearthBitMeshPlugin: NSObject, FlutterStreamHandler {
  private struct PendingCentralWrite {
    let data: Data
    let characteristic: CBCharacteristic
    let type: CBCharacteristicWriteType
  }

  private struct PendingNeighborReplacement {
    let victimID: UUID
    let candidate: CBPeripheral
  }

  private struct PendingRelay {
    let packet: IOSMeshPacket
    let source: UUID?
    let emergency: Bool
    let sequence: UInt64
    let token: UUID
    let workItem: DispatchWorkItem
    var sourceKeys: Set<String>
  }

  private static let serviceUUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
  private static let characteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
  private static let maximumPendingBLEFrames = 256
  private static let emergencyBLEFrameReserve = 64
  private static let maximumPendingRelays = 1024
  private static let maximumSeenFingerprints = 8192
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
  private let unknownIngressRateLimiter = IOSUnknownIngressRateLimiter()
  private let openEmergencyRateLimiter = IOSOpenEmergencyRateLimiter()
  private let packetCounters = IOSMeshPacketCounters()
  private let emergencyFingerprints = IOSEmergencyFingerprintCache()
  private var central: CBCentralManager?
  private var peripheralManager: CBPeripheralManager?
  private var localCharacteristic: CBMutableCharacteristic?
  private var connectedPeripherals: [UUID: CBPeripheral] = [:]
  private var remoteCharacteristics: [UUID: CBCharacteristic] = [:]
  private var knownMeshPeripherals: [UUID: CBPeripheral] = [:]
  private var peripheralLastSeen: [UUID: Date] = [:]
  private var preferredPeripheralIDs: Set<UUID> = []
  private var establishedPeripheralIDs: Set<UUID> = []
  private var peripheralRSSI: [UUID: Int] = [:]
  private var intentionalDisconnectPeripheralIDs: Set<UUID> = []
  private var pendingNeighborReplacement: PendingNeighborReplacement?
  private var reconnectAttempts: [UUID: Int] = [:]
  private var reconnectTokens: [UUID: UUID] = [:]
  private var reconnectExhaustedUntil: [UUID: Date] = [:]
  private var peers: [String: IOSMeshPeer] = [:]
  private var peerLastSeen: [String: Date] = [:]
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
  private var pendingPrivate = IOSBoundedPeerPendingQueue<(String, String)>()
  private var pendingFrames = IOSBoundedPeerPendingQueue<Data>()
  private var pendingCourier = IOSBoundedPeerPendingQueue<IOSMeshPacket>()
  private var seen: [String: Date] = [:]
  private var pendingRelays: [String: PendingRelay] = [:]
  private var pendingRelaySequence: UInt64 = 0
  private let relayOperationalCounters = IOSRelayOperationalCounters()
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
  // CoreBluetooth administra `subscribedCentrals` y no permite rechazar desde
  // didSubscribeTo; este conjunto delimita las centrales que el servidor acepta.
  private var acceptedSubscribedCentralIDs: Set<UUID> = []
  private let packetFragmenter = IOSMeshPacketFragmenter()
  private let fragmentReassembler = IOSMeshFragmentReassembler()
  private let genericPresenceTracker = IOSGenericBLEPresenceTracker.secure()
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
  private lazy var multipeerTransport = HearthBitMultipeerTransport(
    onFrame: { [weak self] frame, _ in
      self?.receive(frame, source: nil)
    },
    onState: { [weak self] state in
      var event: [String: Any] = [
        "type": "transportStatus",
        "transport": "multipeer",
        "available": true,
        "active": state.active,
        "connected": state.connectedPeers > 0,
        "connectedPeers": state.connectedPeers,
        "foregroundOnly": true,
      ]
      if let reason = state.reason { event["reason"] = reason }
      self?.emit(event)
    }
  )
  private lazy var locationManager = CLLocationManager()

  /// Identificador de periférico -> peerId de vecinos directos. Se alimenta
  /// con el service data del anuncio (teléfonos Android) y con anuncios de
  /// malla recibidos con TTL intacto, que solo pueden venir del emisor.
  private var peripheralPeers: [UUID: String] = [:]
  private var hearthbitProvenLinks: Set<UUID> = []
  /// Peer objetivo del radar de rescate; nil cuando el radar está apagado.
  private var radarPeerID: String?
  private var radarTimer: Timer?
  private var radarReportTimer: Timer?
  private var lastRadarReportAtByPeer: [String: UInt64] = [:]
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

    // Canal de transferencias: Nearby Connections no existe en iOS, así que
    // `nearby` sigue en false. Wi-Fi Aware está disponible en iOS 26+ vía
    // HearthBitWiFiAwareTransport (solo entre dispositivos emparejados; Apple
    // no ofrece data path por passphrase PSK, por lo que no interopera con
    // Android). Si no está soportado, Dart cae automáticamente a LAN/BLE.
    let transferEvents = HearthBitTransferEventHandler()
    HearthBitFileImportBridge.shared.setEmitter { event in
      transferEvents.emit(event)
    }
    let wifiAwareTransport = HearthBitWiFiAwareTransport { event in
      DispatchQueue.main.async {
        transferEvents.emit(event)
      }
    }
    let multipeerFileTransport = HearthBitMultipeerFileTransport { event in
      DispatchQueue.main.async {
        transferEvents.emit(event)
      }
    }
    let transferMethods = FlutterMethodChannel(
      name: "com.hearthbit.transfer/methods",
      binaryMessenger: messenger
    )
    transferMethods.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "getTransferCapabilities":
        result([
          "nearby": false,
          "wifiAware": HearthBitWiFiAwareTransport.isSupported,
          "wifiDirect": false,
          "multipeer": true,
        ])
      case "consumeInitialHbtImport":
        result(HearthBitFileImportBridge.shared.consumeInitial())
      case "nearbyStop":
        result(nil)
      case "wifiAwareStop":
        if let transferId = arguments?["transferId"] as? String {
          wifiAwareTransport.stop(transferId: transferId)
        }
        result(nil)
      case "multipeerStop":
        multipeerFileTransport.stop()
        result(nil)
      case "nearbySendFile", "nearbyReceiveFile":
        result(
          FlutterError(
            code: "nearby_unavailable",
            message: HearthBitL10n.string("nearby_unavailable"),
            details: nil
          )
        )
      case "wifiAwareSendFile":
        guard HearthBitWiFiAwareTransport.isSupported else {
          result(
            FlutterError(
              code: "wifi_aware_unavailable",
              message: HearthBitL10n.string("wifi_aware_unavailable"),
              details: nil
            )
          )
          return
        }
        guard
          let transferId = arguments?["transferId"] as? String,
          let filePath = arguments?["filePath"] as? String
        else {
          result(
            FlutterError(
              code: "bad_arguments",
              message: "wifiAwareSendFile requires transferId and filePath",
              details: nil
            )
          )
          return
        }
        wifiAwareTransport.sendFile(transferId: transferId, filePath: filePath)
        result(nil)
      case "wifiAwareReceiveFile":
        guard HearthBitWiFiAwareTransport.isSupported else {
          result(
            FlutterError(
              code: "wifi_aware_unavailable",
              message: HearthBitL10n.string("wifi_aware_unavailable"),
              details: nil
            )
          )
          return
        }
        guard
          let transferId = arguments?["transferId"] as? String,
          let destinationPath = arguments?["destinationPath"] as? String
        else {
          result(
            FlutterError(
              code: "bad_arguments",
              message: "wifiAwareReceiveFile requires transferId and destinationPath",
              details: nil
            )
          )
          return
        }
        wifiAwareTransport.receiveFile(
          transferId: transferId,
          destinationPath: destinationPath
        )
        result(nil)
      case "multipeerSendFile":
        guard
          let transferId = arguments?["transferId"] as? String,
          let filePath = arguments?["filePath"] as? String
        else {
          result(
            FlutterError(
              code: "bad_arguments",
              message: "multipeerSendFile requires transferId and filePath",
              details: nil
            )
          )
          return
        }
        multipeerFileTransport.sendFile(transferId: transferId, filePath: filePath)
        result(nil)
      case "multipeerReceiveFile":
        guard
          let transferId = arguments?["transferId"] as? String,
          let destinationPath = arguments?["destinationPath"] as? String
        else {
          result(
            FlutterError(
              code: "bad_arguments",
              message: "multipeerReceiveFile requires transferId and destinationPath",
              details: nil
            )
          )
          return
        }
        multipeerFileTransport.receiveFile(
          transferId: transferId,
          destinationPath: destinationPath
        )
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(
      name: "com.hearthbit.transfer/events",
      binaryMessenger: messenger
    ).setStreamHandler(transferEvents)
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
      case "getMeshDiagnostics":
        result(diagnosticSnapshot())
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
            intervalMs: (arguments["intervalMs"] as? NSNumber)?.int64Value ??
              IOSRescueModeStore.defaultInterval,
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
              acceptedSubscribedCentralIDs
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
      case "injectEmergencyQrFrames":
        guard
          let announcementData =
            (arguments["announcementFrame"] as? FlutterStandardTypedData)?.data,
          let messageData = (arguments["messageFrame"] as? FlutterStandardTypedData)?.data,
          let announcement = IOSMeshProtocol.decode(announcementData),
          let message = IOSMeshProtocol.decode(messageData),
          announcement.type == IOSMeshProtocol.announce,
          message.type == IOSMeshProtocol.message,
          announcement.senderID == message.senderID,
          announcement.isDrill == message.isDrill,
          IOSMeshProtocol.decodeAnnouncement(announcement.payload)?.emergencyPreannounce == true,
          message.isDrill
            ? IOSMeshProtocol.isDrill(message)
            : IOSMeshProtocol.isEmergency(message)
        else { throw IOSMeshError.invalidPayload }
        receive(announcementData, source: nil)
        receive(messageData, source: nil)
        result(nil)
      case "injectEmergencyLanFrame":
        guard
          let data = (arguments["frame"] as? FlutterStandardTypedData)?.data,
          let packet = IOSMeshProtocol.decode(data),
          isOpenEmergencyLanPacket(packet)
        else { throw IOSMeshError.invalidPayload }
        receive(data, source: nil)
        result(nil)
      case "injectEmergencyAudioFrame":
        guard
          let data = (arguments["frame"] as? FlutterStandardTypedData)?.data,
          let packet = IOSMeshProtocol.decode(data),
          isOpenEmergencyLanPacket(packet) || isDrillAudioPacket(packet)
        else { throw IOSMeshError.invalidPayload }
        receive(data, source: nil)
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
      case "composeEmergencySms":
        guard MFMessageComposeViewController.canSendText() else {
          result(false)
          return
        }
        guard
          let rawRecipient = arguments["recipient"] as? String,
          let recipient = IOSEmergencySMSPolicy.normalizeRecipient(rawRecipient),
          let body = arguments["body"] as? String,
          let presenter = topViewController()
        else {
          throw IOSMeshError.invalidPayload
        }
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.recipients = [recipient]
        composer.body = body
        presenter.present(composer, animated: true)
        result(true)
      case "sendSos":
        let description =
          arguments["content"] as? String ?? HearthBitL10n.string("sos_default")
        let latitude = arguments["latitude"] as? Double
        let longitude = arguments["longitude"] as? Double
        let location = latitude != nil && longitude != nil
          ? "|\(latitude!)|\(longitude!)" : "||"
        sendAnnouncement(
          ttl: IOSMeshProtocol.defaultTTL,
          allowUnprovenIdentity: true,
          emergencyPreannounce: true
        )
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
        let announcement = createAnnouncementPacket(
          ttl: IOSMeshProtocol.defaultTTL,
          emergencyPreannounce: true
        )
        broadcast(announcement, allowUnprovenIdentity: true)
        let transmitted = try transmitPublic(
          messageID: String(messageID.prefix(255)),
          content: content,
          channel: channel
        )
        result([
          "messageId": transmitted.id,
          "canonicalHash": IOSMeshProtocol
            .emergencyCanonicalHash(transmitted.packet).hex,
          "announcementFrame": FlutterStandardTypedData(
            bytes: IOSMeshProtocol.encode(announcement, padded: false)
          ),
          "messageFrame": FlutterStandardTypedData(
            bytes: IOSMeshProtocol.encode(transmitted.packet, padded: false)
          ),
        ])
      case "sendDrill":
        let messageID = arguments["messageId"] as? String ?? ""
        let content = arguments["content"] as? String ?? ""
        guard IOSMeshProtocol.isDrillPayload(content) else {
          throw IOSMeshError.invalidPayload
        }
        let announcement = createAnnouncementPacket(
          ttl: IOSMeshProtocol.defaultTTL,
          emergencyPreannounce: true,
          isDrill: true
        )
        broadcast(announcement, allowUnprovenIdentity: true)
        let transmitted = try transmitPublic(
          messageID: String(messageID.prefix(255)),
          content: content,
          channel: "drill",
          isDrill: true
        )
        result([
          "messageId": transmitted.id,
          "announcementFrame": FlutterStandardTypedData(
            bytes: IOSMeshProtocol.encode(announcement, padded: false)
          ),
          "messageFrame": FlutterStandardTypedData(
            bytes: IOSMeshProtocol.encode(transmitted.packet, padded: false)
          ),
        ])
      case "retryEmergency":
        let canonicalHash = arguments["canonicalHash"] as? String ?? ""
        guard
          let identity,
          let packet = try storeForward.emergency(hash: canonicalHash),
          let retry = IOSEmergencyRetryPolicy.rebuild(
            packet: packet,
            localSenderID: identity.peerID,
            now: currentMilliseconds(),
            sign: identity.sign
          )
        else {
          result(nil)
          return
        }
        try storeForward.put(retry)
        broadcast(retry)
        result([
          "canonicalHash": IOSMeshProtocol.emergencyCanonicalHash(retry).hex,
        ])
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
      case "verifySignatureWithPublicKey":
        guard
          let signingPublicKey =
            (arguments["signingPublicKey"] as? FlutterStandardTypedData)?.data,
          let data = (arguments["data"] as? FlutterStandardTypedData)?.data,
          let signature = (arguments["signature"] as? FlutterStandardTypedData)?.data
        else { throw IOSMeshError.invalidPayload }
        result(
          IOSMeshIdentity.verifyBytes(
            data,
            signature: signature,
            key: signingPublicKey
          )
        )
      case "importRescueRosterPins":
        guard let rawPins = arguments["pins"] as? [[String: Any]],
              rawPins.count <= IOSPeerIdentityPinStore.defaultMaximumPins
        else { throw IOSMeshError.invalidPayload }
        let rosterPins = try rawPins.map { raw -> IOSRescueRosterPin in
          guard
            let peerID = raw["peerId"] as? String,
            let key = (raw["signingPublicKey"] as? FlutterStandardTypedData)?.data
          else { throw IOSMeshError.invalidPayload }
          return IOSRescueRosterPin(peerID: peerID, signingPublicKey: key)
        }
        try peerIdentityPins.importRescueRosterPins(rosterPins)
        result(nil)
      case "rotateLocalIdentity":
        guard running, identity != nil else { throw IOSMeshError.identityUnavailable }
        let oldPeerID = identity.peerIDHex
        let prepared = try identity.prepareRotation(timestamp: currentMilliseconds())
        let newPeerID = IOSMeshProtocol.peerID(
          prepared.noisePrivateKey.publicKey.rawRepresentation
        ).hex
        try identity.activateRotation(prepared)
        broadcast(prepared.packet)
        identity = try IOSMeshIdentity()
        sessions.removeAll()
        responderCandidates.removeAll()
        securePeerIDs.removeAll()
        privateChatPeerIDs.removeAll()
        decryptFailures.removeAll()
        latestAnnouncementTimestampByPeer.removeAll()
        openEmergencyRateLimiter.clear()
        sendAnnouncement()
        let event: [String: Any] = [
          "type": "keyRotation",
          "status": "local",
          "oldPeerId": oldPeerID,
          "newPeerId": newPeerID,
          "sequence": prepared.sequence,
          "timestamp": prepared.packet.timestamp,
        ]
        emit(event)
        result(event)
      case "verifyPeerSignature":
        guard
          let peerID = arguments["peerId"] as? String,
          let data = arguments["data"] as? FlutterStandardTypedData,
          let signature = arguments["signature"] as? FlutterStandardTypedData
        else { throw IOSMeshError.peerUnavailable }
        let signingKey = peers[peerID.lowercased()]?.signingPublicKey
          ?? peerIdentityPins.pin(for: peerID)?.signingPublicKey
          ?? peerIdentityPins.rescueSigningKey(for: peerID)
        let verified = signingKey.map {
          IOSMeshIdentity.verifyBytes(data.data, signature: signature.data, key: $0)
        } ?? false
        result(verified)
      case "getSealedTransferRecipient":
        guard
          identity != nil,
          let peerID = arguments["peerId"] as? String,
          let pin = peerIdentityPins.pin(for: peerID)
        else { throw IOSMeshError.peerUnavailable }
        result([
          "senderPeerId": identity.peerIDHex,
          "recipientPeerId": peerID.lowercased(),
          "noisePublicKey": FlutterStandardTypedData(bytes: pin.noisePublicKey),
          "signingPublicKey": FlutterStandardTypedData(bytes: pin.signingPublicKey),
          "verified": true,
        ])
      case "deriveSealedOpenSecret":
        guard
          identity != nil,
          let ephemeral = arguments["ephemeralPublicKey"] as? FlutterStandardTypedData,
          let recipientPeerID = arguments["recipientPeerId"] as? String,
          recipientPeerID.lowercased() == identity.peerIDHex,
          let publicKey = try? Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: ephemeral.data
          )
        else { throw IOSMeshError.peerUnavailable }
        let shared = try identity.noisePrivateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let secret = shared.withUnsafeBytes { Data($0) }
        result(FlutterStandardTypedData(bytes: secret))
      case "panicWipe":
        // Limpiar también si Flutter cree que la malla ya estaba detenida.
        stopInternal(notify: true)
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
        openEmergencyRateLimiter.clear()
        try IOSRescueModeStore.clear()
        locationManager.stopUpdatingLocation()
        peers.removeAll()
        peerLastSeen.removeAll()
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
        genericPresenceTracker?.clear()
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
          "meshPermissionsGranted": CBManager.authorization == .allowedAlways,
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
        let minutes = min(max(arguments["minutes"] as? Int ?? 15, 1), 30)
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
    updateMultipeerTransport(rescueState: state)
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

  private func updateMultipeerTransport(rescueState: IOSRescueModeState? = nil) {
    let rescueActive = rescueState?.active ?? ((try? IOSRescueModeStore.load())?.active ?? false)
    if IOSMultipeerPolicy.shouldRun(
      meshRunning: running,
      foreground: UIApplication.shared.applicationState == .active,
      rescueActive: rescueActive,
      radarActive: radarPeerID != nil
    ) {
      multipeerTransport.start()
    } else {
      multipeerTransport.stop()
    }
  }

  private func handleRescueLocation(_ location: CLLocation) {
    var state: IOSRescueModeState
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
    do {
      state = try IOSRescueModeStore.load(now: now)
    } catch {
      emit(["type": "error", "code": "rescue_storage_failed", "message": error.localizedDescription])
      return
    }
    guard state.active else {
      configureRescueLocationUpdates(for: state)
      return
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
      setRadarConsent(
        enabled: true,
        duration: TimeInterval(IOSRadarConsentProtocol.sosDurationMilliseconds / 1_000)
      )
      sendAnnouncement(
        ttl: IOSMeshProtocol.defaultTTL,
        allowUnprovenIdentity: true,
        emergencyPreannounce: true
      )
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
    clearPendingRelays()
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
          self?.updateMultipeerTransport()
        },
        center.addObserver(
          forName: UIApplication.didBecomeActiveNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.refreshPowerState()
          self?.restartScan()
          self?.updateMultipeerTransport()
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
    guard running else {
      clearPendingRelays()
      return
    }
    stopInternal(notify: true)
  }

  private func stopInternal(notify: Bool) {
    stopLocalBeacon()
    running = false
    clearPendingRelays()
    multipeerTransport.stop()
    stopRadar()
    stopRadarReportTimer()
    pendingBeaconRequests.removeAll()
    outgoingBeaconRequests.removeAll()
    seenBeaconActions.removeAll()
    adaptiveScanTimer?.invalidate()
    adaptiveScanTimer = nil
    linkLossScanTimer?.invalidate()
    linkLossScanTimer = nil
    central?.stopScan()
    connectedPeripherals.values.forEach { central?.cancelPeripheralConnection($0) }
    connectedPeripherals.removeAll()
    remoteCharacteristics.removeAll()
    knownMeshPeripherals.removeAll()
    peripheralLastSeen.removeAll()
    preferredPeripheralIDs.removeAll()
    establishedPeripheralIDs.removeAll()
    peripheralRSSI.removeAll()
    intentionalDisconnectPeripheralIDs.removeAll()
    pendingNeighborReplacement = nil
    reconnectAttempts.removeAll()
    reconnectTokens.removeAll()
    reconnectExhaustedUntil.removeAll()
    centralWriteQueues.removeAll()
    centralWritesInFlight.removeAll()
    peripheralNotifyQueues.removeAll()
    acceptedSubscribedCentralIDs.removeAll()
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
    lastRadarReportAtByPeer.removeAll()
    fragmentReassembler.clear()
    genericPresenceEmitWorkItem?.cancel()
    genericPresenceEmitWorkItem = nil
    genericPresenceExpiryWorkItem?.cancel()
    genericPresenceExpiryWorkItem = nil
    cancelGenericPresenceScanWindows()
    genericPresenceTracker?.clear()
    if IOSLanBridgeLifecyclePolicy.shouldClearOnStop(notify: notify) {
      lanBridgeGatewayID = nil
    }
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
    updateMultipeerTransport()
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
    updateMultipeerTransport()
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
    clearPendingRelays()
    radarPeerID = nil
    radarTimer?.invalidate()
    radarTimer = nil
    stopRadarReportTimer()
    adaptiveScanTimer?.invalidate()
    adaptiveScanTimer = nil
    linkLossScanTimer?.invalidate()
    linkLossScanTimer = nil
    central?.stopScan()
    connectedPeripherals.values.forEach { central?.cancelPeripheralConnection($0) }
    connectedPeripherals.removeAll()
    remoteCharacteristics.removeAll()
    knownMeshPeripherals.removeAll()
    peripheralLastSeen.removeAll()
    preferredPeripheralIDs.removeAll()
    establishedPeripheralIDs.removeAll()
    peripheralRSSI.removeAll()
    intentionalDisconnectPeripheralIDs.removeAll()
    pendingNeighborReplacement = nil
    reconnectAttempts.removeAll()
    reconnectTokens.removeAll()
    reconnectExhaustedUntil.removeAll()
    centralWriteQueues.removeAll()
    centralWritesInFlight.removeAll()
    peripheralNotifyQueues.removeAll()
    acceptedSubscribedCentralIDs.removeAll()
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
    genericPresenceTracker?.clear()
    emit(["type": "presences", "presences": []])
    configurePeripheralMode()
  }

  private func enterDataRelayMode() {
    restartScan()
    configurePeripheralMode()
    updateRadarReportTimer()
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
    acceptedSubscribedCentralIDs.removeAll()

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
    let boundedDuration = min(
      max(duration, 0.001),
      TimeInterval(IOSRadarConsentProtocol.maximumGrantMilliseconds) / 1_000
    )
    let expiresAt = enabled
      ? Date().addingTimeInterval(boundedDuration).timeIntervalSince1970 * 1000
      : 0
    UserDefaults.standard.set(expiresAt, forKey: IOSRadarConsentProtocol.localConsentKey)
    updateRadarReportTimer()
    broadcastRadarConsent(grant: enabled)
    emitRadarConsent()
  }

  private func updateRadarReportTimer() {
    guard
      running,
      localRole.allowsDataPlane,
      activeLocalRadarConsentUntil() > currentMilliseconds()
    else {
      stopRadarReportTimer()
      return
    }
    guard radarReportTimer == nil else { return }
    sampleLocalRadarConsentRssi()
    radarReportTimer = Timer.scheduledTimer(
      withTimeInterval: 1.0,
      repeats: true
    ) { [weak self] _ in
      self?.sampleLocalRadarConsentRssi()
    }
  }

  private func stopRadarReportTimer() {
    radarReportTimer?.invalidate()
    radarReportTimer = nil
    lastRadarReportAtByPeer.removeAll()
  }

  private func sampleLocalRadarConsentRssi() {
    guard activeLocalRadarConsentUntil() > currentMilliseconds() else {
      stopRadarReportTimer()
      return
    }
    for (identifier, peripheral) in connectedPeripherals
    where peripheralPeers[identifier] != nil && peripheral.state == .connected {
      peripheral.readRSSI()
    }
  }

  private func startLocalBeacon(flags: UInt8, duration: TimeInterval) throws {
    let expiresAt = currentMilliseconds() +
      UInt64(min(max(duration, 0.001), 300) * 1000)
    guard startBeaconActuator(flags: flags, expiresAt: expiresAt) else {
      throw IOSMeshError.invalidPayload
    }
  }

  private func stopLocalBeacon(
    status: String = "stopped",
    sendRemoteStop: Bool = true,
    actuationAlreadyStopped: Bool = false
  ) {
    let active = activeBeaconRequest
    let shouldEmit = actuationAlreadyStopped || active != nil || beaconActuator.isActive
    beaconActuator.stop()
    if let active, sendRemoteStop, running {
      try? sendBeaconControl(
        peerID: active.peerID,
        payload: IOSBeaconControlProtocol.stop(nonce: active.control.nonce)
      )
    }
    if let active,
       activeBeaconRequest?.peerID == active.peerID,
       activeBeaconRequest?.control.nonce == active.control.nonce {
      activeBeaconRequest = nil
    }
    if shouldEmit {
      emitLocalBeaconState(status: status)
    }
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
    guard let payload = IOSBeaconControlProtocol.request(
      expiresAt: expiresAt,
      flags: flags
    ) else {
      throw IOSMeshError.secureRandomUnavailable
    }
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
        ttl: IOSBeaconControlProtocol.initialTTL,
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
      self.stopLocalBeacon(status: "expired", actuationAlreadyStopped: true)
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
      genericPresenceTracker?.clear()
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

  private func emitRssi(
    peerID: String,
    rssi: Int,
    remote: Bool = false,
    measuredAt: UInt64? = nil
  ) {
    emit([
      "type": "rssi",
      "peerId": peerID,
      "rssi": rssi,
      "remote": remote,
      "at": Int(measuredAt ?? currentMilliseconds()),
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
    channel: String?,
    isDrill: Bool = false
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
        payload: payload,
        isDrill: isDrill
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
      channel: channel,
      canonicalHash: IOSMeshProtocol.isEmergency(packet)
        ? IOSMeshProtocol.emergencyCanonicalHash(packet).hex
        : nil
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
    enqueuePendingFrame(frame, peerID: peerID)
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
    isKnownRelationship(peerID)
  }

  private func hasPendingRelationship(_ peerID: String) -> Bool {
    pendingPrivate.contains(peerID: peerID) ||
      pendingFrames.contains(peerID: peerID) ||
      pendingCourier.contains(peerID: peerID)
  }

  private func isKnownRelationship(_ peerID: String) -> Bool {
    securePeerIDs.contains(peerID) ||
      privateChatPeerIDs.contains(peerID) ||
      hasPendingRelationship(peerID)
  }

  private func protectedRelationshipPeerIDs() -> Set<String> {
    var protected = securePeerIDs.union(privateChatPeerIDs)
    protected.formUnion(peerIdentityPins.rescueProtectedPeerIDs)
    let pendingIDs = pendingPrivate.peerIDs
      .union(pendingFrames.peerIDs)
      .union(pendingCourier.peerIDs)
    protected.formUnion(pendingIDs.filter(hasPendingRelationship))
    return protected
  }

  private func enqueuePendingPrivate(
    id: String,
    content: String,
    peerID: String
  ) {
    pendingPrivate.enqueue(
      (id, content),
      for: peerID,
      protectedPeerIDs: activeRetentionPeerIDs()
    )
  }

  private func enqueuePendingFrame(_ frame: Data, peerID: String) {
    pendingFrames.enqueue(
      frame,
      for: peerID,
      protectedPeerIDs: activeRetentionPeerIDs()
    )
  }

  private func enqueuePendingCourier(_ packet: IOSMeshPacket, peerID: String) {
    pendingCourier.enqueue(
      packet,
      for: peerID,
      protectedPeerIDs: activeRetentionPeerIDs()
    )
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
    where anchor.role.acceptsCourierDeposits && directPeerIDs.contains(anchor.id) {
      if sessions[anchor.id]?.established == true {
        sendCourierDeposit(anchorID: anchor.id, innerPacket: innerPacket)
      } else {
        enqueuePendingCourier(innerPacket, peerID: anchor.id)
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
    allowUnprovenIdentity: Bool = false,
    emergencyPreannounce: Bool = false
  ) {
    guard running, identity != nil else { return }
    broadcast(
      createAnnouncementPacket(
        ttl: ttl ?? announcementTTL,
        emergencyPreannounce: emergencyPreannounce
      ),
      allowUnprovenIdentity: allowUnprovenIdentity
    )
    if emergencyPreannounce { return }
    broadcastHbtCapability()
    broadcastEmergencyCapability()
    broadcastNodeCapability()
    if activeLocalRadarConsentUntil() > currentMilliseconds() {
      updateRadarReportTimer()
      broadcastRadarConsent(grant: true)
    }
  }

  private func createAnnouncementPacket(
    ttl: UInt8,
    emergencyPreannounce: Bool,
    isDrill: Bool = false
  ) -> IOSMeshPacket {
    identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.announce,
        ttl: ttl,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        payload: IOSMeshProtocol.announcement(
          nickname: identity.nickname,
          noisePublicKey: identity.noisePrivateKey.publicKey.rawRepresentation,
          signingPublicKey: identity.signingPrivateKey.publicKey.rawRepresentation,
          emergencyPreannounce: emergencyPreannounce
        ),
        isDrill: isDrill
      )
    )
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
    let payload = grant
      ? IOSRadarConsentProtocol.grant(expiresAt: expiresAt)
      : IOSRadarConsentProtocol.revoke()
    guard let payload else {
      emit([
        "type": "error",
        "code": "secure_random_unavailable",
        "message": HearthBitL10n.string("secure_random_unavailable"),
      ])
      return
    }
    let packet = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.radarControl,
        ttl: 1,
        timestamp: currentMilliseconds(),
        senderID: identity.peerID,
        payload: payload
      )
    )
    broadcast(packet)
  }

  private func sendRadarRssiReport(peerID: String, rssi: Int, measuredAt: UInt64) {
    let lastSentAt = lastRadarReportAtByPeer[peerID] ?? 0
    guard measuredAt >= lastSentAt + 800 else { return }
    guard
      let recipient = try? Data(hex: peerID),
      recipient.count == 8,
      let payload = IOSRadarConsentProtocol.rssiReport(
        rssi: rssi,
        measuredAt: measuredAt
      )
    else { return }
    let packet = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.radarControl,
        ttl: 0,
        timestamp: measuredAt,
        senderID: identity.peerID,
        recipientID: recipient,
        payload: payload
      )
    )
    lastRadarReportAtByPeer[peerID] = measuredAt
    send(packet: packet, toPeerID: peerID)
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
    let storedPacketType = packet.type == IOSMeshProtocol.fragment
      ? IOSMeshProtocol.decodeFragmentPayload(packet.payload)?.originalType ?? packet.type
      : packet.type
    let restrictIdentity = privateMode &&
      !allowUnprovenIdentity &&
      packet.senderID == identity.peerID &&
      IOSMeshInteropPolicy.identityPacketTypes.contains(packet.type)
    let multipeerSent = !restrictIdentity && multipeerTransport.send(bytes)
    if (localRole.storesDirectedPackets || emergency && localRole.relaysPackets),
       storedPacketType != IOSMeshProtocol.radarControl,
       storedPacketType != IOSMeshProtocol.beaconControl,
       storedPacketType != IOSMeshProtocol.rangingControl,
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
      where acceptedSubscribedCentralIDs.contains(central.identifier) &&
        central.identifier != excluding &&
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
    if !packet.isDrill,
       !suppressLanBridge,
       let gatewayID = lanBridgeGatewayID,
       bytes.count <= lanBridgeMaximumFrameSize {
      emit([
        "type": "rawMeshFrame",
        "gatewayId": gatewayID,
        "frame": FlutterStandardTypedData(bytes: bytes),
        "emergencyEligible": isOpenEmergencyLanPacket(packet),
      ])
    }
    if isOpenEmergencyLanPacket(packet) {
      let bleSent =
        !acceptedSubscribedCentralIDs.isEmpty ||
        !remoteCharacteristics.isEmpty
      let lanSent =
        !suppressLanBridge &&
        lanBridgeGatewayID != nil &&
        bytes.count <= lanBridgeMaximumFrameSize
      emit([
        "type": "emergencyTransport",
        "channels": IOSEmergencyTransportEscalation.channels(
          ble: bleSent,
          lan: lanSent,
          multipeer: multipeerSent
        ),
        "timestamp": currentMilliseconds(),
      ])
    }
  }

  private func isOpenEmergencyLanPacket(_ packet: IOSMeshPacket) -> Bool {
    if packet.isDrill { return false }
    switch packet.type {
    case IOSMeshProtocol.announce:
      return IOSMeshProtocol
        .decodeAnnouncement(packet.payload)?.emergencyPreannounce == true
    case IOSMeshProtocol.message:
      return IOSMeshProtocol.isEmergency(packet)
    case IOSMeshProtocol.emergencyAck, IOSMeshProtocol.legacyEmergencyAck:
      return true
    default:
      return false
    }
  }

  private func isDrillAudioPacket(_ packet: IOSMeshPacket) -> Bool {
    switch packet.type {
    case IOSMeshProtocol.announce:
      return packet.isDrill &&
        IOSMeshProtocol.decodeAnnouncement(packet.payload)?.emergencyPreannounce == true
    case IOSMeshProtocol.message:
      return IOSMeshProtocol.isDrill(packet)
    default:
      return false
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
        acceptedSubscribedCentralIDs.contains(identifier),
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
      acceptedSubscribedCentralIDs.contains(identifier),
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
      acceptedSubscribedCentralIDs.contains(central.identifier),
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
    guard acceptedSubscribedCentralIDs.contains(identifier) else { return }
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
      acceptedSubscribedCentralIDs.contains(identifier),
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
    packetCounters.recordTransportFailure(code: code)
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
        if acceptedSubscribedCentralIDs.contains(source),
           let central = localCharacteristic?.subscribedCentrals?.first(where: {
          $0.identifier == source
        }) {
          sendSubscriptionAnnouncement(to: central, bypassCooldown: true)
        } else {
          sendAnnouncement()
        }
      }
      return
    }
    packetCounters.recordReceived()
    guard let packet = IOSMeshProtocol.decode(data) else {
      packetCounters.recordRejected()
      return
    }
    guard let fingerprint = IOSMeshProtocol.relayFingerprint(data) else {
      packetCounters.recordRejected()
      return
    }
    let senderID = packet.senderID.hex
    if senderID == identity.peerIDHex { return }
    let pinnedIdentity = peerIdentityPins.pin(for: senderID)
    if pinnedIdentity == nil {
      let rateLimitKey = source?.uuidString ?? senderID
      guard unknownIngressRateLimiter.allow(source: rateLimitKey) else {
        packetCounters.recordDroppedRateLimit()
        return
      }
    }
    var validatedAnnouncement: IOSMeshProtocol.Announcement?
    var validatedKeyRotation: IOSMeshProtocol.KeyRotation?
    if packet.type == IOSMeshProtocol.announce {
      guard let announcement = validateAnnouncementIdentity(
        packet,
        senderID: senderID
      ) else {
        packetCounters.recordRejected()
        return
      }
      validatedAnnouncement = announcement
    } else if packet.type == IOSMeshProtocol.keyRotation {
      guard let rotation = validateKeyRotation(packet, senderID: senderID) else {
        packetCounters.recordRejected()
        return
      }
      validatedKeyRotation = rotation
    } else {
      let originalType = packet.type == IOSMeshProtocol.fragment
        ? IOSMeshProtocol.decodeFragmentPayload(packet.payload)?.originalType
        : nil
      let effectiveType = originalType ?? packet.type
      if IOSMeshIngressPolicy.requiresPublicSignature(effectiveType) {
        guard let pinnedIdentity else {
          packetCounters.recordRejected()
          return
        }
        if packet.type != IOSMeshProtocol.fragment {
          guard IOSMeshIngressPolicy.accepts(
            packet,
            signingPublicKey: pinnedIdentity.signingPublicKey
          ) else {
            packetCounters.recordRejected()
            return
          }
        }
      }
    }
    if var pendingRelay = pendingRelays[fingerprint] {
      pendingRelay.sourceKeys = IOSRelayDampingPolicy.sourceKeys(
        afterObserving: IOSRelayDampingPolicy.sourceKey(source),
        in: pendingRelay.sourceKeys
      )
      pendingRelays[fingerprint] = pendingRelay
      packetCounters.recordDeduplicated()
      return
    }
    if seen[fingerprint] != nil {
      packetCounters.recordDeduplicated()
      return
    }
    if isOpenEmergencyLanPacket(packet) {
      guard openEmergencyRateLimiter.allow(
        knownRelationship: isKnownRelationship(senderID)
      ) else {
        packetCounters.recordDroppedRateLimit()
        return
      }
    }
    rememberSeenFingerprint(fingerprint)
    packetCounters.recordAccepted()
    let forUs = packet.recipientID == nil ||
      packet.recipientID == identity.peerID ||
      packet.recipientID == Data(repeating: 0xff, count: 8)
    if forUs {
      process(
        packet,
        senderID: senderID,
        source: source,
        validatedAnnouncement: validatedAnnouncement,
        validatedKeyRotation: validatedKeyRotation
      )
    }
    let fragmentOriginalType = packet.type == IOSMeshProtocol.fragment
      ? IOSMeshProtocol.decodeFragmentPayload(packet.payload)?.originalType
      : nil
    let effectiveType = fragmentOriginalType ?? packet.type
    let addressedToLocalNode = packet.recipientID == identity.peerID
    let directedRecipient = packet.recipientID.map {
      $0 != Data(repeating: 0xff, count: 8)
    } ?? false
    let shouldRelay = IOSMeshRelayPolicy.shouldRelay(
      role: localRole,
      packetType: effectiveType,
      ttl: packet.ttl,
      addressedToLocalNode: addressedToLocalNode,
      hasDirectedRecipient: directedRecipient
    )
    if shouldRelay {
      var relayed = packet
      relayed.ttl -= 1
      let emergency =
        IOSMeshProtocol.isEmergency(packet) ||
        effectiveType == IOSMeshProtocol.emergencyAck ||
        effectiveType == IOSMeshProtocol.legacyEmergencyAck ||
        effectiveType == IOSMeshProtocol.beaconControl
      scheduleRelay(
        relayed,
        fingerprint: fingerprint,
        source: source,
        emergency: emergency
      )
    } else if packet.ttl <= 1 {
      let candidateTTL = effectiveType == IOSMeshProtocol.beaconControl
        ? IOSBeaconControlProtocol.initialTTL
        : 2
      if IOSMeshRelayPolicy.shouldRelay(
        role: localRole,
        packetType: effectiveType,
        ttl: candidateTTL,
        addressedToLocalNode: addressedToLocalNode,
        hasDirectedRecipient: directedRecipient
      ) {
        packetCounters.recordDroppedTtl()
      }
    }
  }

  private func rememberSeenFingerprint(_ fingerprint: String) {
    let now = Date()
    seen[fingerprint] = now
    guard seen.count > Self.maximumSeenFingerprints else { return }
    seen = seen.filter { now.timeIntervalSince($0.value) < 3600 }
    guard seen.count > Self.maximumSeenFingerprints else { return }
    let overflow = seen.count - Self.maximumSeenFingerprints
    for entry in seen.sorted(by: { $0.value < $1.value }).prefix(overflow) {
      seen.removeValue(forKey: entry.key)
    }
  }

  private func scheduleRelay(
    _ packet: IOSMeshPacket,
    fingerprint: String,
    source: UUID?,
    emergency: Bool
  ) {
    while pendingRelays.count >= Self.maximumPendingRelays,
          let oldest = pendingRelays.min(by: {
            $0.value.sequence < $1.value.sequence
          }) {
      pendingRelays.removeValue(forKey: oldest.key)?.workItem.cancel()
    }
    pendingRelaySequence &+= 1
    let token = UUID()
    let workItem = DispatchWorkItem { [weak self] in
      guard
        let self,
        self.pendingRelays[fingerprint]?.token == token,
        let pending = self.pendingRelays.removeValue(forKey: fingerprint)
      else { return }
      let shouldRelay = IOSRelayDampingPolicy.shouldRelay(
          additionalCopies: IOSRelayDampingPolicy.additionalCopies(
            sourceKeys: pending.sourceKeys
          ),
          emergency: pending.emergency
        )
      self.relayOperationalCounters.recordExpiration(suppressed: !shouldRelay)
      guard self.running, self.localRole.relaysPackets, shouldRelay else { return }
      self.packetCounters.recordForwarded()
      self.broadcast(pending.packet, excluding: pending.source)
    }
    pendingRelays[fingerprint] = PendingRelay(
      packet: packet,
      source: source,
      emergency: emergency,
      sequence: pendingRelaySequence,
      token: token,
      workItem: workItem,
      sourceKeys: [IOSRelayDampingPolicy.sourceKey(source)]
    )
    relayOperationalCounters.recordScheduled()
    let delay = IOSRelayDampingPolicy.jitterMilliseconds(
      fingerprint: fingerprint,
      salt: identity.peerID,
      emergency: emergency
    )
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(delay),
      execute: workItem
    )
  }

  private func clearPendingRelays() {
    let workItems = pendingRelays.values.map(\.workItem)
    pendingRelays.removeAll()
    pendingRelaySequence = 0
    workItems.forEach { $0.cancel() }
  }

  private func operationalCounters() -> [String: UInt64] {
    return openEmergencyRateLimiter.operationalCounters()
      .merging(peerIdentityPins.operationalCounters()) { _, latest in latest }
      .merging(relayOperationalCounters.snapshot()) { _, latest in latest }
      .merging(packetCounters.snapshot()) { _, latest in latest }
  }

  private func validateAnnouncementIdentity(
    _ packet: IOSMeshPacket,
    senderID: String
  ) -> IOSMeshProtocol.Announcement? {
    let now = currentMilliseconds()
    guard
      let announcement = IOSMeshProtocol.decodeAnnouncement(packet.payload),
      IOSMeshIdentity.verify(packet, key: announcement.signingPublicKey),
      IOSAnnouncementClockPolicy.accepts(
        timestamp: packet.timestamp,
        emergencyPreannounce: announcement.emergencyPreannounce && !packet.isDrill,
        now: now
      )
    else { return nil }

    if let previous = peers[senderID] {
      let noiseChanged = previous.noisePublicKey != announcement.noisePublicKey
      let signingChanged = previous.signingPublicKey != announcement.signingPublicKey
      if noiseChanged || signingChanged {
        peerIdentityPins.recordObservedConflict()
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
        signingPublicKey: announcement.signingPublicKey,
        protectedPeerIDs: protectedRelationshipPeerIDs()
      ) {
      case .firstBinding:
        emit(["type": "identityPinned", "peerId": senderID, "method": "tofu"])
      case .matched:
        break
      case let .conflict(noiseChanged, signingChanged):
        // Los cambios de identidad solo se aceptan mediante KEY_ROTATION
        // firmado por la clave anterior. Un ANNOUNCE conflictivo se rechaza.
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

  private func validateKeyRotation(
    _ packet: IOSMeshPacket,
    senderID: String
  ) -> IOSMeshProtocol.KeyRotation? {
    let now = currentMilliseconds()
    guard
      let oldPin = peerIdentityPins.pin(for: senderID),
      let rotation = IOSMeshProtocol.decodeKeyRotation(packet.payload),
      packet.recipientID == nil,
      !packet.isDrill,
      rotation.oldPeerID == packet.senderID,
      rotation.timestamp == packet.timestamp,
      rotation.timestampIsCurrent(now: now),
      IOSMeshIdentity.verify(packet, key: oldPin.signingPublicKey),
      IOSMeshIdentity.verifyBytes(
        rotation.authorizationBytes,
        signature: rotation.authorizationSignature,
        key: oldPin.signingPublicKey
      )
    else { return nil }
    do {
      guard try peerIdentityPins.rotate(
        oldPeerID: senderID,
        noisePublicKey: rotation.newNoisePublicKey,
        signingPublicKey: rotation.newSigningPublicKey,
        sequence: rotation.sequence
      ) != nil else { return nil }
      return rotation
    } catch {
      emit([
        "type": "error",
        "code": "peer_identity_rotation_store_failed",
        "peerId": senderID,
        "message": error.localizedDescription,
      ])
      return nil
    }
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
    validatedAnnouncement: IOSMeshProtocol.Announcement? = nil,
    validatedKeyRotation: IOSMeshProtocol.KeyRotation? = nil
  ) {
    switch packet.type {
    case IOSMeshProtocol.announce:
      guard let announcement = validatedAnnouncement ??
        validateAnnouncementIdentity(packet, senderID: senderID)
      else { return }
      // Solo una identidad ya validada y fijada puede promover presencia.
      if (packet.ttl == announcementTTL ||
          packet.ttl == IOSMeshProtocol.defaultTTL), let source {
        rememberPeripheralPeer(senderID, source: source)
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
      rememberPeer(IOSMeshPeer(
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
      ), seenAt: now)
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
        } else if pendingPrivate.contains(peerID: senderID) ||
                    pendingFrames.contains(peerID: senderID) ||
                    pendingCourier.contains(peerID: senderID) {
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
      let drill = IOSMeshProtocol.isDrill(packet)
      guard IOSMeshInteropPolicy.shouldProcessPublicMessage(
        privateMode: privateMode,
        hearthbitVerified: peer.hearthbitVerified,
        emergency: emergency || drill
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
      let decodedMessage = IOSMeshProtocol.decodePublicMessage(packet.payload) ??
        IOSMeshProtocol.PublicMessage(
          id: IOSMeshProtocol.fingerprint(packet).uppercased(),
          sender: peer.nickname,
          content: String(data: packet.payload, encoding: .utf8) ?? "",
          timestamp: packet.timestamp,
          channel: packet.payload.starts(with: Data("SOS|".utf8)) ? "sos" : nil
        )
      let message = IOSMeshProtocol.PublicMessage(
        id: decodedMessage.id,
        sender: decodedMessage.sender,
        content: decodedMessage.content,
        timestamp: decodedMessage.timestamp,
        channel: drill
          ? "drill"
          : (decodedMessage.channel?.lowercased() == "drill" ? nil : decodedMessage.channel)
      )
      rememberSyncPacket(packet)
      if message.channel == "sos" {
        let now = currentMilliseconds()
        let expiresAt = IOSRadarConsentProtocol.sosConsentExpiresAt(
          packetTimestamp: packet.timestamp,
          now: now
        )
        if expiresAt > now {
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
        external: external,
        canonicalHash: emergencyHash
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
    case IOSMeshProtocol.hbtCapability, IOSMeshProtocol.legacyHbtCapability:
      processHbtCapability(packet, senderID: senderID, source: source)
    case IOSMeshProtocol.nodeCapability:
      processNodeCapability(packet, senderID: senderID)
    case IOSMeshProtocol.beaconControl:
      processBeaconControl(packet, senderID: senderID)
    case IOSMeshProtocol.rangingControl:
      processRangingControl(packet, senderID: senderID)
    case IOSMeshProtocol.emergencyCapability:
      processEmergencyCapability(packet, senderID: senderID)
    case IOSMeshProtocol.emergencyAck, IOSMeshProtocol.legacyEmergencyAck:
      processEmergencyAcknowledgement(packet, senderID: senderID)
    case IOSMeshProtocol.keyRotation:
      guard let rotation = validatedKeyRotation else { return }
      let newPeerID = rotation.newPeerID.hex
      let previous = peers.removeValue(forKey: senderID)
      peerLastSeen.removeValue(forKey: senderID)
      invalidateNoiseState(peerID: senderID)
      latestAnnouncementTimestampByPeer.removeValue(forKey: senderID)
      let rotatedSources = peripheralPeers.compactMap {
        $0.value == senderID ? $0.key : nil
      }
      for sourceID in rotatedSources {
        rememberPeripheralPeer(newPeerID, source: sourceID)
      }
      if let previous {
        let now = Date()
        rememberPeer(IOSMeshPeer(
          id: newPeerID,
          nickname: previous.nickname,
          noisePublicKey: rotation.newNoisePublicKey,
          signingPublicKey: rotation.newSigningPublicKey,
          supportsTransfers: previous.supportsTransfers,
          hearthbitVerified: previous.hearthbitVerified,
          supportsEmergencyAck: previous.supportsEmergencyAck,
          isInfrastructure: previous.isInfrastructure,
          role: previous.role,
          hasLongRangeTrunk: previous.hasLongRangeTrunk,
          lastSeen: now
        ), seenAt: now)
      }
      emit([
        "type": "keyRotation",
        "status": "accepted",
        "oldPeerId": senderID,
        "newPeerId": newPeerID,
        "sequence": rotation.sequence,
        "timestamp": rotation.timestamp,
      ])
      emit(["type": "peers", "peers": peerMaps()])
    case IOSMeshProtocol.fragment:
      if let reassembled = fragmentReassembler.accept(packet) {
        var validatedAnnouncement: IOSMeshProtocol.Announcement?
        var fragmentKeyRotation: IOSMeshProtocol.KeyRotation?
        if reassembled.type == IOSMeshProtocol.announce {
          guard let announcement = validateAnnouncementIdentity(
            reassembled,
            senderID: senderID
          ) else { return }
          validatedAnnouncement = announcement
          if (packet.ttl == announcementTTL ||
              packet.ttl == IOSMeshProtocol.defaultTTL), let source {
            rememberPeripheralPeer(senderID, source: source)
          }
        } else if reassembled.type == IOSMeshProtocol.keyRotation {
          guard let rotation = validateKeyRotation(
            reassembled,
            senderID: senderID
          ) else { return }
          fragmentKeyRotation = rotation
        } else if IOSMeshIngressPolicy.requiresPublicSignature(reassembled.type) {
          guard
            let pinnedIdentity = peerIdentityPins.pin(for: senderID),
            IOSMeshIngressPolicy.accepts(
              reassembled,
              signingPublicKey: pinnedIdentity.signingPublicKey
            )
          else { return }
        }
        process(
          reassembled,
          senderID: senderID,
          source: source,
          validatedAnnouncement: validatedAnnouncement,
          validatedKeyRotation: fragmentKeyRotation
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
    let now = Date()
    peer.lastSeen = now
    rememberPeer(peer, seenAt: now)
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
    let now = Date()
    peer.lastSeen = now
    rememberPeer(peer, seenAt: now)
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
    let now = Date()
    peer.lastSeen = now
    rememberPeer(peer, seenAt: now)
    emit(["type": "peers", "peers": peerMaps()])
  }

  private func processRadarControl(_ packet: IOSMeshPacket, senderID: String) {
    guard
      let peer = peers[senderID],
      IOSMeshIdentity.verify(packet, key: peer.signingPublicKey)
    else { return }
    if packet.payload.dropFirst().first == IOSRadarConsentProtocol.rssiReportAction {
      guard
        packet.recipientID == identity.peerID,
        packet.ttl <= 1,
        radarPeerID == senderID,
        isRadarAllowed(peerID: senderID),
        let report = IOSRadarConsentProtocol.decodeRssiReport(packet.payload),
        IOSRadarConsentProtocol.isValidReport(
          report,
          packetTimestamp: packet.timestamp,
          now: currentMilliseconds()
        )
      else { return }
      emitRssi(
        peerID: senderID,
        rssi: report.rssi,
        remote: true,
        measuredAt: report.measuredAt
      )
      return
    }
    guard
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
      IOSBeaconControlProtocol.isValidTTL(packet.ttl),
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
      let rescueModeActive = (try? IOSRescueModeStore.load().active) ?? false
      let autoAccepted = IOSBeaconControlProtocol.shouldAutoAccept(
        rescueModeActive: rescueModeActive,
        localRadarConsentUntil: activeLocalRadarConsentUntil(),
        hearthbitVerified: peer.hearthbitVerified,
        knownRelationship: securePeerIDs.contains(senderID),
        now: currentMilliseconds()
      )
      emit([
        "type": "beaconRequest",
        "requestId": requestID,
        "peerId": senderID,
        "nickname": peer.nickname,
        "expiresAt": control.expiresAt,
        "flags": Int(control.flags),
        "autoAccepted": autoAccepted,
      ])
      if autoAccepted {
        pendingBeaconRequests.removeValue(forKey: requestID)
        respondToBeaconRequest(request, accept: true, autoAccepted: true)
      }
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
        stopLocalBeacon(sendRemoteStop: false)
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
    let now = Date()
    lastNoisePeerActivity[senderID] = now
    touchRememberedPeer(senderID, seenAt: now)
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
        let queued = pendingPrivate.removeValues(for: senderID)
        for item in queued {
          try sendEncryptedPrivate(peerID: senderID, id: item.0, content: item.1)
        }
        let queuedFrames = pendingFrames.removeValues(for: senderID)
        for frame in queuedFrames {
          try sendEncryptedFrame(peerID: senderID, frame: frame)
        }
        let queuedCourier = pendingCourier.removeValues(for: senderID)
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
    let now = Date()
    lastNoisePeerActivity[senderID] = now
    touchRememberedPeer(senderID, seenAt: now)
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

  private func diagnosticSnapshot() -> [String: Any] {
    let scanning = central?.isScanning ?? false
    let advertising = peripheralManager?.isAdvertising ?? false
    let subscribedCount = acceptedSubscribedCentralIDs.count
    let bleLinkCount = connectedPeripherals.count + subscribedCount
    var transports: [String] = []
    if scanning || advertising || bleLinkCount > 0 {
      transports.append("ble")
    }
    if lanBridgeGatewayID != nil {
      transports.append("lan")
    }
    return [
      "platform": "ios",
      "meshRunning": running,
      "meshStatus": running ? "active" : "stopped",
      "advertising": advertising,
      "meshScanActive": scanning,
      "genericScanActive": genericPresenceWindowActive && scanning,
      "genericScanEnabled": genericPresenceScanEnabled,
      "powerProfile": powerProfile.rawValue,
      "adaptivePowerSaving": adaptivePowerSaving,
      "batteryLevel": batteryLevel,
      "bleDutyCyclePercent": 0,
      "activeScans": scanning ? 1 : 0,
      "scanStarts": 0,
      "storeForwardEntries": 0,
      "operationalCounters": operationalCounters(),
      "operationalCountersLifetime": "process",
      "linkCount": bleLinkCount,
      "nearbyCount": peerMaps().filter { ($0["online"] as? Bool) == true }.count,
      "presenceCount": genericPresenceTracker?
        .snapshot(now: Int64(Date().timeIntervalSince1970 * 1000))
        .count ?? 0,
      "transports": transports,
    ]
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    if let navigation = current as? UINavigationController {
      return navigation.visibleViewController ?? navigation
    }
    if let tabs = current as? UITabBarController {
      return tabs.selectedViewController ?? tabs
    }
    return current
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
    external: Bool = false,
    canonicalHash: String? = nil
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
    if let canonicalHash { message["canonicalHash"] = canonicalHash }
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

  private func activeRetentionPeerIDs() -> Set<String> {
    var protected = securePeerIDs.union(privateChatPeerIDs)
    protected.formUnion(peerIdentityPins.rescueProtectedPeerIDs)
    if let radarPeerID { protected.insert(radarPeerID) }
    protected.formUnion(remoteRadarConsents.keys)
    protected.formUnion(sessions.compactMap {
      $0.value.established || $0.value.handshaking ? $0.key : nil
    })
    protected.formUnion(responderCandidates.compactMap {
      $0.value.established || $0.value.handshaking ? $0.key : nil
    })
    protected.formUnion(pendingBeaconRequests.values.map(\.peerID))
    protected.formUnion(outgoingBeaconRequests.values.map(\.peerID))
    if let activeBeaconRequest {
      protected.insert(activeBeaconRequest.peerID)
    }
    let activePeripheralIDs = Set(connectedPeripherals.keys)
      .union(establishedPeripheralIDs)
      .union(reconnectTokens.keys)
      .union(acceptedSubscribedCentralIDs)
    protected.formUnion(activePeripheralIDs.compactMap { peripheralPeers[$0] })
    let activePreferredIDs = preferredPeripheralIDs.intersection(activePeripheralIDs)
    protected.formUnion(activePreferredIDs.compactMap { peripheralPeers[$0] })
    return protected
  }

  private func retentionProtectedPeerIDs() -> Set<String> {
    activeRetentionPeerIDs()
      .union(pendingPrivate.peerIDs)
      .union(pendingFrames.peerIDs)
      .union(pendingCourier.peerIDs)
  }

  private func rememberPeer(_ peer: IOSMeshPeer, seenAt: Date) {
    peers[peer.id] = peer
    peerLastSeen[peer.id] = seenAt
    pruneRememberedPeers()
  }

  private func touchRememberedPeer(_ peerID: String, seenAt: Date) {
    guard peers[peerID] != nil else { return }
    peerLastSeen[peerID] = seenAt
    pruneRememberedPeers()
  }

  private func pruneRememberedPeers() {
    let evictions = IOSMeshRetentionPolicy.evictions(
      lastSeen: peerLastSeen,
      protected: retentionProtectedPeerIDs(),
      stableKey: { $0 }
    )
    for peerID in evictions {
      peers.removeValue(forKey: peerID)
      peerLastSeen.removeValue(forKey: peerID)
      decryptFailures.removeValue(forKey: peerID)
      lastAutoHandshake.removeValue(forKey: peerID)
      lastNoisePeerActivity.removeValue(forKey: peerID)
      latestAnnouncementTimestampByPeer.removeValue(forKey: peerID)
      handshakeRestartAttempts.removeValue(forKey: peerID)
      autoHandshakeTokens.removeValue(forKey: peerID)
      activeHandshakeTimeoutTokens.removeValue(forKey: peerID)
      candidateHandshakeTimeoutTokens.removeValue(forKey: peerID)
      lastRadarReportAtByPeer.removeValue(forKey: peerID)
    }
  }

  private func protectedPeripheralIDs() -> Set<UUID> {
    var protected = Set(connectedPeripherals.keys)
      .union(establishedPeripheralIDs)
      .union(remoteCharacteristics.keys)
      .union(reconnectTokens.keys)
      .union(centralWriteQueues.keys)
      .union(centralWritesInFlight)
      .union(intentionalDisconnectPeripheralIDs)
    if let replacement = pendingNeighborReplacement {
      protected.insert(replacement.victimID)
      protected.insert(replacement.candidate.identifier)
    }
    let protectedPeers = retentionProtectedPeerIDs()
    protected.formUnion(peripheralPeers.compactMap {
      protectedPeers.contains($0.value) ? $0.key : nil
    })
    let activePreferred = preferredPeripheralIDs.filter {
      connectedPeripherals[$0] != nil ||
        establishedPeripheralIDs.contains($0) ||
        reconnectTokens[$0] != nil
    }
    protected.formUnion(activePreferred)
    return protected
  }

  private func rememberMeshPeripheral(
    _ peripheral: CBPeripheral,
    peerID: String? = nil,
    seenAt: Date = Date()
  ) {
    let identifier = peripheral.identifier
    knownMeshPeripherals[identifier] = peripheral
    peripheralLastSeen[identifier] = seenAt
    if let peerID {
      peripheralPeers[identifier] = peerID
    }
    peripheral.delegate = self
    pruneRememberedPeripherals()
  }

  private func rememberPeripheralPeer(
    _ peerID: String,
    source: UUID,
    seenAt: Date = Date()
  ) {
    peripheralPeers[source] = peerID
    peripheralLastSeen[source] = seenAt
    pruneRememberedPeripherals()
  }

  private func recordPeripheralRSSI(
    _ rssi: Int,
    for peripheral: CBPeripheral,
    seenAt: Date = Date()
  ) {
    rememberMeshPeripheral(peripheral, seenAt: seenAt)
    peripheralRSSI[peripheral.identifier] = rssi
  }

  private func pruneRememberedPeripherals() {
    let evictions = IOSMeshRetentionPolicy.evictions(
      lastSeen: peripheralLastSeen,
      protected: protectedPeripheralIDs(),
      stableKey: { $0.uuidString }
    )
    for identifier in evictions {
      knownMeshPeripherals.removeValue(forKey: identifier)
      peripheralLastSeen.removeValue(forKey: identifier)
      peripheralRSSI.removeValue(forKey: identifier)
      preferredPeripheralIDs.remove(identifier)
      establishedPeripheralIDs.remove(identifier)
      intentionalDisconnectPeripheralIDs.remove(identifier)
      reconnectAttempts.removeValue(forKey: identifier)
      reconnectTokens.removeValue(forKey: identifier)
      reconnectExhaustedUntil.removeValue(forKey: identifier)
      peripheralPeers.removeValue(forKey: identifier)
      hearthbitProvenLinks.remove(identifier)
      lastSubscriptionAnnouncement.removeValue(forKey: identifier)
      centralWriteQueues.removeValue(forKey: identifier)
      centralWritesInFlight.remove(identifier)
      lastSyncRequestBySource.removeValue(forKey: identifier)
      syncResponseTimes.removeValue(forKey: identifier)
    }
  }

  private func neighborCandidate(
    for peripheral: CBPeripheral,
    rssi: Int? = nil
  ) -> IOSBLENeighborCandidate {
    let identifier = peripheral.identifier
    let peerID = peripheralPeers[identifier]
    let hasKnownPeer = preferredPeripheralIDs.contains(identifier) ||
      (peerID.map {
        peers[$0] != nil ||
          peerIdentityPins.pin(for: $0) != nil ||
          securePeerIDs.contains($0)
      } ?? false)
    let hasPreferredRelationship = peerID.map {
      privateChatPeerIDs.contains($0) ||
        pendingPrivate.contains(peerID: $0) ||
        pendingFrames.contains(peerID: $0) ||
        pendingCourier.contains(peerID: $0) ||
        radarPeerID == $0
    } ?? false
    let hasProtectedSession = peerID.map {
      sessions[$0]?.established == true || sessions[$0]?.handshaking == true
    } ?? false
    return IOSBLENeighborCandidate(
      identifier: identifier,
      rssi: rssi ?? peripheralRSSI[identifier] ?? -127,
      knownPeer: hasKnownPeer,
      preferred: hasPreferredRelationship,
      protected: hasProtectedSession || hasPreferredRelationship
    )
  }

  private func considerDiscoveredPeripheral(
    _ peripheral: CBPeripheral,
    rssi: Int,
    using central: CBCentralManager
  ) {
    let candidate = neighborCandidate(for: peripheral, rssi: rssi)
    let current = connectedPeripherals.values.map { neighborCandidate(for: $0) }
    switch IOSBLENeighborSelectionPolicy.decision(
      candidate: candidate,
      current: current,
      maximum: powerProfile.maximumOutgoingConnections
    ) {
    case .accept:
      connectKnownPeripheral(peripheral, using: central)
    case .reject:
      return
    case .replace(let victimID):
      guard
        pendingNeighborReplacement == nil,
        let victim = connectedPeripherals[victimID]
      else { return }
      pendingNeighborReplacement = PendingNeighborReplacement(
        victimID: victimID,
        candidate: peripheral
      )
      intentionalDisconnectPeripheralIDs.insert(victimID)
      reconnectTokens.removeValue(forKey: victimID)
      central.cancelPeripheralConnection(victim)
    }
  }

  private func takeReplacementCandidate(for victimID: UUID) -> CBPeripheral? {
    guard
      intentionalDisconnectPeripheralIDs.remove(victimID) != nil,
      pendingNeighborReplacement?.victimID == victimID
    else { return nil }
    let candidate = pendingNeighborReplacement?.candidate
    pendingNeighborReplacement = nil
    return candidate
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
    let hasPeripheralLink = acceptedSubscribedCentralIDs.contains(source)
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
    guard genericPresenceTracker?.record(material: material, rssi: rssi, now: now) == true else {
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
      "presences": genericPresenceTracker?.snapshot(now: now).map(\.eventMap) ?? [],
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

extension HearthBitMeshPlugin: MFMessageComposeViewControllerDelegate {
  func messageComposeViewController(
    _ controller: MFMessageComposeViewController,
    didFinishWith result: MessageComposeResult
  ) {
    controller.dismiss(animated: true)
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
    let advertisedPeerID: String?
    if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
       let advertisedPeer = serviceData[Self.serviceUUID],
       advertisedPeer.count >= 8 {
      advertisedPeerID = advertisedPeer.prefix(8).hex
    } else {
      advertisedPeerID = nil
    }
    rememberMeshPeripheral(peripheral, peerID: advertisedPeerID)
    if RSSI.intValue != 127 {
      recordPeripheralRSSI(RSSI.intValue, for: peripheral)
    }
    if let peerID = advertisedPeerID {
      if peers[peerID] != nil ||
         securePeerIDs.contains(peerID) ||
         privateChatPeerIDs.contains(peerID) ||
         pendingPrivate.contains(peerID: peerID) ||
         pendingFrames.contains(peerID: peerID) ||
         pendingCourier.contains(peerID: peerID) {
        preferredPeripheralIDs.insert(peripheral.identifier)
      }
    }
    // 127 significa «RSSI no disponible» según CoreBluetooth.
    if let target = radarPeerID,
       peripheralPeers[peripheral.identifier] == target,
       RSSI.intValue != 127 {
      emitRssi(peerID: target, rssi: RSSI.intValue)
    }
    guard connectedPeripherals[peripheral.identifier] == nil else { return }
    considerDiscoveredPeripheral(
      peripheral,
      rssi: RSSI.intValue == 127 ? -127 : RSSI.intValue,
      using: central
    )
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
    if let replacement = takeReplacementCandidate(for: identifier) {
      guard running, localRole.allowsDataPlane else { return }
      connectKnownPeripheral(replacement, using: central)
      return
    }
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
    if let replacement = takeReplacementCandidate(for: identifier) {
      guard running, localRole.allowsDataPlane else { return }
      connectKnownPeripheral(replacement, using: central)
      return
    }
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
      guard
        powerProfile.maximumOutgoingConnections > 0,
        connectedPeripherals.count < powerProfile.maximumOutgoingConnections
      else {
        central.cancelPeripheralConnection(peripheral)
        continue
      }
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
      RSSI.intValue != 127
    else { return }
    recordPeripheralRSSI(RSSI.intValue, for: peripheral)
    guard let peerID = peripheralPeers[peripheral.identifier] else { return }
    if radarPeerID == peerID {
      emitRssi(peerID: peerID, rssi: RSSI.intValue)
    }
    let now = currentMilliseconds()
    if activeLocalRadarConsentUntil() > now {
      sendRadarRssiReport(peerID: peerID, rssi: RSSI.intValue, measuredAt: now)
    } else {
      stopRadarReportTimer()
    }
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
      acceptedSubscribedCentralIDs.removeAll()
      for central in localCharacteristic?.subscribedCentrals ?? [] {
        guard
          acceptedSubscribedCentralIDs.count <
            IOSBLENeighborSelectionPolicy.maximumSubscribedCentrals
        else { continue }
        acceptedSubscribedCentralIDs.insert(central.identifier)
        sendSubscriptionAnnouncement(to: central)
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
      if request.characteristic.uuid == Self.characteristicUUID {
        guard acceptedSubscribedCentralIDs.contains(request.central.identifier) else {
          peripheral.respond(to: request, withResult: .insufficientResources)
          continue
        }
        if let value = request.value {
          receive(value, source: request.central.identifier)
        }
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
    let identifier = central.identifier
    guard
      acceptedSubscribedCentralIDs.contains(identifier) ||
        acceptedSubscribedCentralIDs.count <
          IOSBLENeighborSelectionPolicy.maximumSubscribedCentrals
    else {
      peripheralNotifyQueues.removeValue(forKey: identifier)
      emitBLETransportFailure(
        code: "peripheral_subscription_limit",
        identifier: identifier,
        emergency: false,
        frames: 0
      )
      return
    }
    acceptedSubscribedCentralIDs.insert(identifier)
    peripheralNotifyQueues.removeValue(forKey: identifier)
    if let peerID = peripheralPeers[identifier] {
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
    acceptedSubscribedCentralIDs.remove(identifier)
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
