import CoreBluetooth
import CoreLocation
import CryptoKit
import Compression
import Flutter
import Foundation
import Security

final class HearthBitMeshPlugin: NSObject, FlutterStreamHandler {
  private static let serviceUUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
  private static let characteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")

  private var identity = IOSMeshIdentity()
  private let storeForward = IOSStoreForward()
  private var central: CBCentralManager?
  private var peripheralManager: CBPeripheralManager?
  private var localCharacteristic: CBMutableCharacteristic?
  private var connectedPeripherals: [UUID: CBPeripheral] = [:]
  private var remoteCharacteristics: [UUID: CBCharacteristic] = [:]
  private var peers: [String: IOSMeshPeer] = [:]
  private var sessions: [String: IOSNoiseSession] = [:]
  private var pendingPrivate: [String: [(String, String)]] = [:]
  private var pendingFrames: [String: [Data]] = [:]
  private var seen: [String: Date] = [:]
  private var remoteRadarConsents: [String: IOSRemoteRadarConsent] = [:]
  private var notifyQueue: [Data] = []
  private var eventSink: FlutterEventSink?
  private var running = false
  private lazy var locationManager = CLLocationManager()

  /// Identificador de periférico -> peerId de vecinos directos. Se alimenta
  /// con el service data del anuncio (teléfonos Android) y con anuncios de
  /// malla recibidos con TTL intacto, que solo pueden venir del emisor.
  private var peripheralPeers: [UUID: String] = [:]
  /// Peer objetivo del radar de rescate; nil cuando el radar está apagado.
  private var radarPeerID: String?
  private var radarTimer: Timer?

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
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
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
        ])
      case "requestPermissions":
        result(true)
      case "startMesh":
        start()
        result(nil)
      case "stopMesh":
        stop()
        result(nil)
      case "sendPublic":
        let content = arguments["content"] as? String ?? ""
        result(try sendPublic(content: content, channel: arguments["channel"] as? String))
      case "sendPrivate":
        result(
          try sendPrivate(
            peerID: arguments["peerId"] as? String ?? "",
            content: arguments["content"] as? String ?? ""
          )
        )
      case "sendSos":
        let description =
          arguments["content"] as? String ?? HearthBitL10n.string("sos_default")
        let latitude = arguments["latitude"] as? Double
        let longitude = arguments["longitude"] as? Double
        let location = latitude != nil && longitude != nil
          ? "|\(latitude!)|\(longitude!)" : "||"
        result(try sendPublic(content: "SOS|\(description)\(location)", channel: "sos"))
      case "setNickname":
        identity.nickname = String((arguments["nickname"] as? String ?? "").prefix(31))
        sendAnnouncement()
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
      case "signPayload":
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
        stop()
        IOSMeshIdentity.clear()
        identity = IOSMeshIdentity()
        storeForward.clear()
        peers.removeAll()
        sessions.removeAll()
        remoteRadarConsents.removeAll()
        result(nil)
        emit(["type": "wiped"])
      case "getPowerStatus":
        result([
          // iOS no tiene equivalente a Doze configurable por app.
          "ignoringBatteryOptimizations": true,
          "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
          "backgroundLocation": locationAuthorization() == .authorizedAlways,
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
      case "stopRadar":
        stopRadar()
        result(nil)
      case "setRadarConsent":
        let enabled = arguments["enabled"] as? Bool ?? false
        let minutes = min(max(arguments["minutes"] as? Int ?? 15, 1), 20)
        setRadarConsent(enabled: enabled, duration: TimeInterval(minutes * 60))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "mesh_error", message: error.localizedDescription, details: nil))
    }
  }

  private func locationAuthorization() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func start() {
    // Reinicio real: liberar recursos previos permite reintentar tras un fallo.
    if running { stopInternal(notify: false) }
    running = true
    emitStatus("starting")
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

  private func stop() {
    guard running else { return }
    stopInternal(notify: true)
  }

  private func stopInternal(notify: Bool) {
    running = false
    stopRadar()
    central?.stopScan()
    connectedPeripherals.values.forEach { central?.cancelPeripheralConnection($0) }
    connectedPeripherals.removeAll()
    remoteCharacteristics.removeAll()
    peripheralPeers.removeAll()
    peripheralManager?.stopAdvertising()
    peripheralManager?.removeAllServices()
    sessions.removeAll()
    remoteRadarConsents.removeAll()
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
    radarTimer?.invalidate()
    radarTimer = nil
    restartScan()
  }

  private func setRadarConsent(enabled: Bool, duration: TimeInterval) {
    let expiresAt = enabled
      ? Date().addingTimeInterval(duration).timeIntervalSince1970 * 1000
      : 0
    UserDefaults.standard.set(expiresAt, forKey: IOSRadarConsentProtocol.localConsentKey)
    broadcastRadarConsent(grant: enabled)
    emitRadarConsent()
  }

  /// Reinicia el escaneo BLE; con radar activo se permiten duplicados para
  /// recibir un RSSI por cada anuncio (solo funciona en primer plano).
  private func restartScan() {
    guard running, let central, central.state == .poweredOn else { return }
    central.stopScan()
    central.scanForPeripherals(
      withServices: [Self.serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: radarPeerID != nil]
    )
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
    guard running else { throw IOSMeshError.notRunning }
    let id = UUID().uuidString.uppercased()
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
    return id
  }

  private func sendPrivate(peerID: String, content: String) throws -> String {
    guard peers[peerID] != nil else { throw IOSMeshError.peerUnavailable }
    let id = UUID().uuidString.uppercased()
    if let session = sessions[peerID], session.established {
      try sendEncryptedPrivate(peerID: peerID, id: id, content: content)
    } else {
      pendingPrivate[peerID, default: []].append((id, content))
      if sessions[peerID] == nil {
        let claimed = try Data(hex: peerID)
        let session = IOSNoiseSession(
          claimedPeerID: claimed,
          initiator: true,
          localStatic: identity.noisePrivateKey
        )
        sessions[peerID] = session
        sendNoise(
          type: IOSMeshProtocol.noiseHandshake,
          recipient: claimed,
          payload: try session.start()
        )
      }
    }
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
    if sessions[peerID] == nil {
      let claimed = try Data(hex: peerID)
      let session = IOSNoiseSession(
        claimedPeerID: claimed,
        initiator: true,
        localStatic: identity.noisePrivateKey
      )
      sessions[peerID] = session
      sendNoise(
        type: IOSMeshProtocol.noiseHandshake,
        recipient: claimed,
        payload: try session.start()
      )
    }
  }

  private func sendEncryptedFrame(peerID: String, frame: Data) throws {
    guard let session = sessions[peerID] else { return }
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
    let privatePayload = IOSMeshProtocol.privateMessage(id: id, content: content)
    let encrypted = try session.encrypt(Data([IOSMeshProtocol.noisePrivate]) + privatePayload)
    sendNoise(
      type: IOSMeshProtocol.noiseEncrypted,
      recipient: try Data(hex: peerID),
      payload: encrypted
    )
  }

  private func sendNoise(type: UInt8, recipient: Data, payload: Data) {
    broadcast(
      IOSMeshPacket(
        type: type,
        ttl: IOSMeshProtocol.defaultTTL,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
        senderID: identity.peerID,
        recipientID: recipient,
        payload: payload
      )
    )
  }

  private func sendAnnouncement() {
    guard running else { return }
    let payload = IOSMeshProtocol.announcement(
      nickname: identity.nickname,
      noisePublicKey: identity.noisePrivateKey.publicKey.rawRepresentation,
      signingPublicKey: identity.signingPrivateKey.publicKey.rawRepresentation
    )
    broadcast(
      identity.sign(
        IOSMeshPacket(
          type: IOSMeshProtocol.announce,
          ttl: IOSMeshProtocol.defaultTTL,
          timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
          senderID: identity.peerID,
          payload: payload
        )
      )
    )
    if activeLocalRadarConsentUntil() > currentMilliseconds() {
      broadcastRadarConsent(grant: true)
    }
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

  private func broadcast(_ packet: IOSMeshPacket, excluding: UUID? = nil) {
    let bytes = IOSMeshProtocol.encodeForBLE(packet)
    if let recipient = packet.recipientID,
       recipient != Data(repeating: 0xff, count: 8) {
      storeForward.put(packet)
    }
    if let characteristic = localCharacteristic, let manager = peripheralManager {
      if !manager.updateValue(bytes, for: characteristic, onSubscribedCentrals: nil) {
        notifyQueue.append(bytes)
      }
    }
    for (identifier, characteristic) in remoteCharacteristics where identifier != excluding {
      guard let peripheral = connectedPeripherals[identifier] else { continue }
      let writeType: CBCharacteristicWriteType =
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
      if bytes.count <= peripheral.maximumWriteValueLength(for: writeType) {
        peripheral.writeValue(bytes, for: characteristic, type: writeType)
      }
    }
  }

  private func receive(_ data: Data, source: UUID?) {
    guard let packet = IOSMeshProtocol.decode(data) else { return }
    // Un anuncio con TTL intacto solo puede venir del emisor original: eso
    // identifica al vecino directo detrás de este periférico (clave para el
    // radar, ya que iOS no incluye el peerId en su anuncio BLE).
    if packet.type == IOSMeshProtocol.announce,
       packet.ttl == IOSMeshProtocol.defaultTTL,
       let source,
       connectedPeripherals[source] != nil,
       packet.senderID.hex != identity.peerIDHex {
      peripheralPeers[source] = packet.senderID.hex
    }
    let fingerprint = IOSMeshProtocol.fingerprint(packet)
    if seen[fingerprint] != nil { return }
    seen[fingerprint] = Date()
    if seen.count > 2000 {
      seen = seen.filter { Date().timeIntervalSince($0.value) < 3600 }
    }
    let senderID = packet.senderID.hex
    if senderID == identity.peerIDHex { return }
    let forUs = packet.recipientID == nil ||
      packet.recipientID == identity.peerID ||
      packet.recipientID == Data(repeating: 0xff, count: 8)
    if forUs { process(packet, senderID: senderID) }
    let controlForUs = forUs &&
      (packet.type == IOSMeshProtocol.noiseHandshake ||
       packet.type == IOSMeshProtocol.noiseEncrypted)
    if packet.ttl > 1 && !controlForUs {
      var relayed = packet
      relayed.ttl -= 1
      broadcast(relayed, excluding: source)
    }
  }

  private func process(_ packet: IOSMeshPacket, senderID: String) {
    switch packet.type {
    case IOSMeshProtocol.announce:
      guard
        let announcement = IOSMeshProtocol.decodeAnnouncement(packet.payload),
        IOSMeshProtocol.peerID(announcement.noisePublicKey) == packet.senderID,
        IOSMeshIdentity.verify(packet, key: announcement.signingPublicKey)
      else { return }
      peers[senderID] = IOSMeshPeer(
        id: senderID,
        nickname: announcement.nickname,
        signingPublicKey: announcement.signingPublicKey,
        supportsTransfers: announcement.supportsTransfers,
        lastSeen: Date()
      )
      emit(["type": "peers", "peers": peerMaps()])
      for stored in storeForward.packets(for: packet.senderID) {
        broadcast(stored)
      }
    case IOSMeshProtocol.message:
      guard
        let peer = peers[senderID],
        IOSMeshIdentity.verify(packet, key: peer.signingPublicKey)
      else { return }
      let message = IOSMeshProtocol.decodePublicMessage(packet.payload) ??
        IOSMeshProtocol.PublicMessage(
          id: IOSMeshProtocol.fingerprint(packet).uppercased(),
          sender: peer.nickname,
          content: String(data: packet.payload, encoding: .utf8) ?? "",
          timestamp: packet.timestamp,
          channel: packet.payload.starts(with: Data("SOS|".utf8)) ? "sos" : nil
        )
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
        channel: message.channel
      )
    case IOSMeshProtocol.noiseHandshake:
      processHandshake(packet, senderID: senderID)
    case IOSMeshProtocol.noiseEncrypted:
      processEncrypted(packet, senderID: senderID)
    case IOSMeshProtocol.radarControl:
      processRadarControl(packet, senderID: senderID)
    default:
      break
    }
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

  private func processHandshake(_ packet: IOSMeshPacket, senderID: String) {
    do {
      let session = sessions[senderID] ?? IOSNoiseSession(
        claimedPeerID: packet.senderID,
        initiator: false,
        localStatic: identity.noisePrivateKey
      )
      sessions[senderID] = session
      if let response = try session.process(packet.payload) {
        sendNoise(
          type: IOSMeshProtocol.noiseHandshake,
          recipient: packet.senderID,
          payload: response
        )
      }
      if session.established {
        emit(["type": "peers", "peers": peerMaps()])
        let queued = pendingPrivate.removeValue(forKey: senderID) ?? []
        for item in queued {
          try sendEncryptedPrivate(peerID: senderID, id: item.0, content: item.1)
        }
        let queuedFrames = pendingFrames.removeValue(forKey: senderID) ?? []
        for frame in queuedFrames {
          try sendEncryptedFrame(peerID: senderID, frame: frame)
        }
      }
    } catch {
      sessions.removeValue(forKey: senderID)
      emitError(HearthBitL10n.string("identity_rejected"))
    }
  }

  private func processEncrypted(_ packet: IOSMeshPacket, senderID: String) {
    guard let session = sessions[senderID], session.established else { return }
    do {
      let plaintext = try session.decrypt(packet.payload)
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
      return
    }
  }

  private func peerMaps() -> [[String: Any]] {
    pruneRadarConsents()
    return peers.values.map {
      let consent = remoteRadarConsents[$0.id]
      return [
        "id": $0.id,
        "nickname": $0.nickname,
        "lastSeen": Int($0.lastSeen.timeIntervalSince1970 * 1000),
        "secure": sessions[$0.id]?.established ?? false,
        "supportsTransfers": $0.supportsTransfers,
        "radarAllowedUntil": consent?.expiresAt ?? 0,
        "radarConsentSource": consent?.source ?? "",
      ]
    }
  }

  private func emitStatus(_ status: String) {
    emit([
      "type": "status",
      "status": status,
      "peerId": identity.peerIDHex,
      "nickname": identity.nickname,
      "radarConsentUntil": activeLocalRadarConsentUntil(),
    ])
  }

  private func emitMessage(
    id: String,
    sender: String,
    content: String,
    senderPeerID: String,
    isPrivate: Bool,
    isMine: Bool,
    timestamp: UInt64,
    channel: String?
  ) {
    var message: [String: Any] = [
      "id": id,
      "sender": sender,
      "content": content,
      "senderPeerId": senderPeerID,
      "private": isPrivate,
      "mine": isMine,
      "timestamp": Int(timestamp),
    ]
    if let channel { message["channel"] = channel }
    emit(["type": "message", "message": message])
  }

  private func emitError(_ message: String) {
    emit(["type": "error", "message": message])
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.eventSink?(event) }
  }
}

extension HearthBitMeshPlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard running, central.state == .poweredOn else { return }
    central.scanForPeripherals(
      withServices: [Self.serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: radarPeerID != nil]
    )
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
       let advertisedPeer = serviceData[Self.serviceUUID],
       advertisedPeer.count >= 8 {
      peripheralPeers[peripheral.identifier] = advertisedPeer.prefix(8).hex
    }
    // 127 significa «RSSI no disponible» según CoreBluetooth.
    if let target = radarPeerID,
       peripheralPeers[peripheral.identifier] == target,
       RSSI.intValue != 127 {
      emitRssi(peerID: target, rssi: RSSI.intValue)
    }
    guard connectedPeripherals[peripheral.identifier] == nil else { return }
    connectedPeripherals[peripheral.identifier] = peripheral
    peripheral.delegate = self
    central.connect(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.discoverServices([Self.serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    connectedPeripherals.removeValue(forKey: peripheral.identifier)
    remoteCharacteristics.removeValue(forKey: peripheral.identifier)
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    for peripheral in restored {
      connectedPeripherals[peripheral.identifier] = peripheral
      peripheral.delegate = self
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    peripheral.services?
      .filter { $0.uuid == Self.serviceUUID }
      .forEach { peripheral.discoverCharacteristics([Self.characteristicUUID], for: $0) }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard
      let characteristic = service.characteristics?.first(where: {
        $0.uuid == Self.characteristicUUID
      })
    else { return }
    remoteCharacteristics[peripheral.identifier] = characteristic
    peripheral.setNotifyValue(true, for: characteristic)
    sendAnnouncement()
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard let value = characteristic.value else { return }
    receive(value, source: peripheral.identifier)
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
    guard running else { return }
    guard peripheral.state == .poweredOn else {
      if peripheral.state == .unsupported || peripheral.state == .unauthorized {
        emitError(HearthBitL10n.string("no_advertising"))
        emitStatus("degraded")
      }
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
    peripheral.add(service)
    // Solo el UUID de servicio: la identidad viaja en el anuncio GATT firmado,
    // manteniendo el paquete publicitario dentro del presupuesto BLE.
    peripheral.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
    ])
  }

  func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager,
    error: Error?
  ) {
    guard running else { return }
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
    sendAnnouncement()
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    for request in requests {
      if request.characteristic.uuid == Self.characteristicUUID, let value = request.value {
        receive(value, source: request.central.identifier)
      }
      peripheral.respond(to: request, withResult: .success)
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    guard let characteristic = localCharacteristic else { return }
    while let data = notifyQueue.first {
      guard peripheral.updateValue(data, for: characteristic, onSubscribedCentrals: nil) else {
        return
      }
      notifyQueue.removeFirst()
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
    if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
      localCharacteristic = services
        .flatMap { $0.characteristics ?? [] }
        .compactMap { $0 as? CBMutableCharacteristic }
        .first(where: { $0.uuid == Self.characteristicUUID })
    }
  }
}

private struct IOSMeshPeer {
  let id: String
  let nickname: String
  let signingPublicKey: Data
  let supportsTransfers: Bool
  let lastSeen: Date
}

private struct IOSRemoteRadarConsent {
  let expiresAt: UInt64
  let source: String
}

private enum IOSRadarConsentProtocol {
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

private struct IOSMeshPacket {
  var version: UInt8 = 1
  var type: UInt8
  var ttl: UInt8
  var timestamp: UInt64
  var senderID: Data
  var recipientID: Data?
  var payload: Data
  var signature: Data?

  func canonical() -> Data {
    var copy = self
    copy.ttl = 0
    copy.signature = nil
    return IOSMeshProtocol.encode(copy, padded: true)
  }
}

private enum IOSMeshProtocol {
  static let announce: UInt8 = 0x01
  static let message: UInt8 = 0x02
  static let noiseHandshake: UInt8 = 0x10
  static let noiseEncrypted: UInt8 = 0x11
  static let radarControl: UInt8 = 0x23
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
  }

  struct PrivateMessage {
    let id: String
    let content: String
  }

  static func encode(_ packet: IOSMeshPacket, padded: Bool = true) -> Data {
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
    if version >= 2, flags & 0x08 != 0 {
      guard let count = reader.byte(), reader.skip(Int(count) * 8) else { return nil }
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
    return IOSMeshPacket(
      version: version,
      type: type,
      ttl: ttl,
      timestamp: timestamp,
      senderID: sender,
      recipientID: recipient,
      payload: payload,
      signature: signature
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
    output.appendTLV(type: 0xF0, value: Data([0x01]))
    return output
  }

  static func decodeAnnouncement(_ payload: Data) -> Announcement? {
    var reader = DataReader(payload)
    var nickname: String?
    var noise: Data?
    var signing: Data?
    var supportsTransfers = false
    while let type = reader.byte(), let length = reader.byte(),
          let value = reader.data(count: Int(length)) {
      switch type {
      case 0x01: nickname = String(data: value, encoding: .utf8)
      case 0x02: noise = value
      case 0x03: signing = value
      case 0xF0: supportsTransfers = value == Data([0x01])
      default: break
      }
    }
    guard let nickname, let noise, noise.count == 32,
          let signing, signing.count == 32 else { return nil }
    return Announcement(
      nickname: nickname,
      noisePublicKey: noise,
      signingPublicKey: signing,
      supportsTransfers: supportsTransfers
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

  static func peerID(_ noisePublicKey: Data) -> Data {
    Data(SHA256.hash(data: noisePublicKey).prefix(8))
  }

  static func fingerprint(_ packet: IOSMeshPacket) -> String {
    Data(SHA256.hash(data: packet.canonical()).prefix(12)).hex
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
    var output = Data(count: originalSize)
    let decompressedSize = output.withUnsafeMutableBytes { destination in
      data.withUnsafeBytes { source in
        guard
          let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
          let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
        else { return 0 }
        return compression_decode_buffer(
          destinationBase,
          originalSize,
          sourceBase,
          data.count,
          nil,
          COMPRESSION_ZLIB
        )
      }
    }
    guard decompressedSize == originalSize else { return nil }
    return output
  }

  private static let compressionThreshold = 100
  private static let maximumPayloadLength = 10_485_760
}

private final class IOSStoreForward {
  private let key = "hearthbit.store_forward"
  private let lifetime: TimeInterval = 12 * 60 * 60
  private let maximum = 100

  func put(_ packet: IOSMeshPacket) {
    let now = Date().timeIntervalSince1970
    var entries = validEntries(now: now)
    let encoded = IOSMeshProtocol.encode(packet, padded: false).base64EncodedString()
    if !entries.contains(where: { $0.encoded == encoded }) {
      entries.append((now + lifetime, encoded))
    }
    save(Array(entries.suffix(maximum)))
  }

  func packets(for recipient: Data) -> [IOSMeshPacket] {
    let entries = validEntries(now: Date().timeIntervalSince1970)
    save(entries)
    return entries.compactMap {
      guard
        let data = Data(base64Encoded: $0.encoded),
        let packet = IOSMeshProtocol.decode(data),
        packet.recipientID == recipient
      else { return nil }
      return packet
    }
  }

  func clear() {
    UserDefaults.standard.removeObject(forKey: key)
  }

  private func validEntries(now: TimeInterval) -> [(expiry: TimeInterval, encoded: String)] {
    let stored = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
    return stored.compactMap {
      guard
        let expiry = $0["expiry"] as? TimeInterval,
        let encoded = $0["encoded"] as? String,
        expiry > now
      else { return nil }
      return (expiry, encoded)
    }.sorted { $0.expiry < $1.expiry }
  }

  private func save(_ entries: [(expiry: TimeInterval, encoded: String)]) {
    UserDefaults.standard.set(
      entries.map { ["expiry": $0.expiry, "encoded": $0.encoded] },
      forKey: key
    )
  }
}

private final class IOSMeshIdentity {
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

  init() {
    noisePrivateKey = Self.load("noise").flatMap {
      try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0)
    } ?? Curve25519.KeyAgreement.PrivateKey()
    signingPrivateKey = Self.load("signing").flatMap {
      try? Curve25519.Signing.PrivateKey(rawRepresentation: $0)
    } ?? Curve25519.Signing.PrivateKey()
    Self.save(noisePrivateKey.rawRepresentation, "noise")
    Self.save(signingPrivateKey.rawRepresentation, "signing")
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

  static func clear() {
    for account in ["noise", "signing"] {
      SecItemDelete([
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "HearthBit",
        kSecAttrAccount: account,
      ] as CFDictionary)
    }
    UserDefaults.standard.removeObject(forKey: "hearthbit.nickname")
    UserDefaults.standard.removeObject(forKey: IOSRadarConsentProtocol.localConsentKey)
  }

  private static func load(_ account: String) -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "HearthBit",
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
      return nil
    }
    return result as? Data
  }

  private static func save(_ data: Data, _ account: String) {
    let base: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "HearthBit",
      kSecAttrAccount: account,
    ]
    SecItemDelete(base as CFDictionary)
    var item = base
    item[kSecValueData] = data
    item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
  }
}

private final class IOSNoiseSession {
  private let claimedPeerID: Data
  private let initiator: Bool
  private let localStatic: Curve25519.KeyAgreement.PrivateKey
  private var handshake: IOSNoiseHandshake
  private var sendCipher: IOSNoiseCipher?
  private var receiveCipher: IOSNoiseCipher?

  private(set) var established = false

  init(
    claimedPeerID: Data,
    initiator: Bool,
    localStatic: Curve25519.KeyAgreement.PrivateKey
  ) {
    self.claimedPeerID = claimedPeerID
    self.initiator = initiator
    self.localStatic = localStatic
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

private final class IOSNoiseCipher {
  private let key: SymmetricKey?
  private var nonce: UInt64 = 0
  private var received: Set<UInt64> = []

  var hasKey: Bool { key != nil }

  init(key: SymmetricKey? = nil) {
    self.key = key
  }

  func encrypt(
    _ plaintext: Data,
    associatedData: Data = Data(),
    extractedNonce: Bool = false
  ) throws -> Data {
    guard let key else { throw IOSMeshError.noise }
    let current = nonce
    let box = try ChaChaPoly.seal(
      plaintext,
      using: key,
      nonce: try ChaChaPoly.Nonce(data: nonceData(current)),
      authenticating: associatedData
    )
    nonce += 1
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
    var reader = DataReader(input)
    let current: UInt64
    if extractedNonce {
      guard let transmitted: UInt32 = reader.integer(),
            !received.contains(UInt64(transmitted)) else {
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
      received.insert(current)
      if received.count > 1024 {
        received.remove(received.min()!)
      }
    }
    nonce += 1
    return plaintext
  }

  private func nonceData(_ value: UInt64) -> Data {
    var data = Data(repeating: 0, count: 4)
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    return data
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
  case noise
  case invalidPayload
  case radarConsentRequired

  var errorDescription: String? {
    switch self {
    case .notRunning: return HearthBitL10n.string("not_running")
    case .peerUnavailable: return HearthBitL10n.string("peer_unavailable")
    case .invalidPeerID: return HearthBitL10n.string("invalid_peer_id")
    case .identityMismatch: return HearthBitL10n.string("identity_mismatch")
    case .noise: return HearthBitL10n.string("noise_failed")
    case .invalidPayload: return HearthBitL10n.string("invalid_payload")
    case .radarConsentRequired: return HearthBitL10n.string("radar_consent_required")
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
      "noise_failed": "The Noise encrypted channel failed",
      "invalid_payload": "The transfer payload is not valid",
      "radar_consent_required": "This person has not allowed radar location",
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
      "noise_failed": "Falló el canal cifrado Noise",
      "invalid_payload": "La carga de la transferencia no es válida",
      "radar_consent_required": "Esta persona no ha permitido la ubicación por radar",
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
    ],
  ]
}
