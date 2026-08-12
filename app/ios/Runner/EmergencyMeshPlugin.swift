import CoreBluetooth
import CryptoKit
import Flutter
import Foundation
import Security

final class EmergencyMeshPlugin: NSObject, FlutterStreamHandler {
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
  private var seen: [String: Date] = [:]
  private var notifyQueue: [Data] = []
  private var eventSink: FlutterEventSink?
  private var running = false

  static func register(with messenger: FlutterBinaryMessenger) -> EmergencyMeshPlugin {
    let plugin = EmergencyMeshPlugin()
    let methods = FlutterMethodChannel(
      name: "com.emergencycom.mesh/methods",
      binaryMessenger: messenger
    )
    methods.setMethodCallHandler(plugin.handle)
    FlutterEventChannel(
      name: "com.emergencycom.mesh/events",
      binaryMessenger: messenger
    ).setStreamHandler(plugin)
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
        let description = arguments["content"] as? String ?? "Necesito ayuda"
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
      case "panicWipe":
        stop()
        IOSMeshIdentity.clear()
        identity = IOSMeshIdentity()
        storeForward.clear()
        peers.removeAll()
        sessions.removeAll()
        result(nil)
        emit(["type": "wiped"])
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "mesh_error", message: error.localizedDescription, details: nil))
    }
  }

  private func start() {
    guard !running else { return }
    running = true
    central = CBCentralManager(
      delegate: self,
      queue: nil,
      options: [CBCentralManagerOptionRestoreIdentifierKey: "EmergencyCom.central"]
    )
    peripheralManager = CBPeripheralManager(
      delegate: self,
      queue: nil,
      options: [CBPeripheralManagerOptionRestoreIdentifierKey: "EmergencyCom.peripheral"]
    )
    emitStatus("active")
  }

  private func stop() {
    guard running else { return }
    running = false
    central?.stopScan()
    connectedPeripherals.values.forEach { central?.cancelPeripheralConnection($0) }
    connectedPeripherals.removeAll()
    remoteCharacteristics.removeAll()
    peripheralManager?.stopAdvertising()
    peripheralManager?.removeAllServices()
    sessions.removeAll()
    emitStatus("stopped")
  }

  @discardableResult
  private func sendPublic(content: String, channel: String?) throws -> String {
    guard running else { throw IOSMeshError.notRunning }
    let message = IOSMeshProtocol.publicMessage(
      nickname: identity.nickname,
      peerID: identity.peerIDHex,
      content: String(content.prefix(2000)),
      channel: channel
    )
    let packet = identity.sign(
      IOSMeshPacket(
        type: IOSMeshProtocol.message,
        ttl: IOSMeshProtocol.defaultTTL,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
        senderID: identity.peerID,
        payload: message.data
      )
    )
    broadcast(packet)
    emitMessage(
      id: message.id,
      sender: identity.nickname,
      content: content,
      senderPeerID: identity.peerIDHex,
      isPrivate: false,
      isMine: true,
      timestamp: packet.timestamp,
      channel: channel
    )
    return message.id
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
  }

  private func broadcast(_ packet: IOSMeshPacket, excluding: UUID? = nil) {
    let bytes = IOSMeshProtocol.encode(packet)
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
        lastSeen: Date()
      )
      emit(["type": "peers", "peers": peerMaps()])
      for stored in storeForward.packets(for: packet.senderID) {
        broadcast(stored)
      }
    case IOSMeshProtocol.message:
      guard
        let peer = peers[senderID],
        IOSMeshIdentity.verify(packet, key: peer.signingPublicKey),
        let message = IOSMeshProtocol.decodePublicMessage(packet.payload)
      else { return }
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
    default:
      break
    }
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
      }
    } catch {
      sessions.removeValue(forKey: senderID)
      emitError("Un canal privado fue rechazado por identidad inválida")
    }
  }

  private func processEncrypted(_ packet: IOSMeshPacket, senderID: String) {
    guard let session = sessions[senderID], session.established else { return }
    do {
      let plaintext = try session.decrypt(packet.payload)
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
    peers.values.map {
      [
        "id": $0.id,
        "nickname": $0.nickname,
        "lastSeen": Int($0.lastSeen.timeIntervalSince1970 * 1000),
        "secure": sessions[$0.id]?.established ?? false,
      ]
    }
  }

  private func emitStatus(_ status: String) {
    emit([
      "type": "status",
      "status": status,
      "peerId": identity.peerIDHex,
      "nickname": identity.nickname,
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

extension EmergencyMeshPlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard running, central.state == .poweredOn else { return }
    central.scanForPeripherals(
      withServices: [Self.serviceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
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
}

extension EmergencyMeshPlugin: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard running, peripheral.state == .poweredOn else { return }
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
    peripheral.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
      CBAdvertisementDataLocalNameKey: "EmergencyCom",
    ])
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
  let lastSeen: Date
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
    return IOSMeshProtocol.encode(copy, padded: false)
  }
}

private enum IOSMeshProtocol {
  static let announce: UInt8 = 0x01
  static let message: UInt8 = 0x02
  static let noiseHandshake: UInt8 = 0x10
  static let noiseEncrypted: UInt8 = 0x11
  static let noisePrivate: UInt8 = 0x01
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
  }

  struct PrivateMessage {
    let id: String
    let content: String
  }

  static func encode(_ packet: IOSMeshPacket, padded: Bool = true) -> Data {
    var flags: UInt8 = 0
    if packet.recipientID != nil { flags |= 0x01 }
    if packet.signature != nil { flags |= 0x02 }
    var output = Data([
      packet.version,
      packet.type,
      packet.ttl,
    ])
    output.appendInteger(packet.timestamp)
    output.append(flags)
    output.appendInteger(UInt16(packet.payload.count))
    output.append(packet.senderID)
    if let recipient = packet.recipientID { output.append(recipient) }
    output.append(packet.payload)
    if let signature = packet.signature { output.append(signature) }
    return padded ? pad(output) : output
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
    guard flags & 0x04 == 0, let payload = reader.data(count: payloadLength) else { return nil }
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
    return output
  }

  static func decodeAnnouncement(_ payload: Data) -> Announcement? {
    var reader = DataReader(payload)
    var nickname: String?
    var noise: Data?
    var signing: Data?
    while let type = reader.byte(), let length = reader.byte(),
          let value = reader.data(count: Int(length)) {
      switch type {
      case 0x01: nickname = String(data: value, encoding: .utf8)
      case 0x02: noise = value
      case 0x03: signing = value
      default: break
      }
    }
    guard let nickname, let noise, noise.count == 32,
          let signing, signing.count == 32 else { return nil }
    return Announcement(nickname: nickname, noisePublicKey: noise, signingPublicKey: signing)
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
}

private final class IOSStoreForward {
  private let key = "emergency.store_forward"
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

  var nickname: String {
    get {
      UserDefaults.standard.string(forKey: "emergency.nickname")
        ?? "Emergencia-\(peerIDHex.suffix(4))"
    }
    set { UserDefaults.standard.set(newValue, forKey: "emergency.nickname") }
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

  static func clear() {
    for account in ["noise", "signing"] {
      SecItemDelete([
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "EmergencyCom",
        kSecAttrAccount: account,
      ] as CFDictionary)
    }
    UserDefaults.standard.removeObject(forKey: "emergency.nickname")
  }

  private static func load(_ account: String) -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "EmergencyCom",
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
      kSecAttrService: "EmergencyCom",
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

private enum IOSMeshError: LocalizedError {
  case notRunning
  case peerUnavailable
  case invalidPeerID
  case identityMismatch
  case noise

  var errorDescription: String? {
    switch self {
    case .notRunning: return "La malla no está activa"
    case .peerUnavailable: return "El dispositivo ya no está disponible"
    case .invalidPeerID: return "La identidad del dispositivo no es válida"
    case .identityMismatch: return "La identidad Noise no coincide"
    case .noise: return "Falló el canal cifrado Noise"
    }
  }
}
