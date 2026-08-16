import CryptoKit
import Foundation
import MultipeerConnectivity

enum IOSMultipeerFilePolicy {
  static let maximumContainerBytes: Int64 = 600 * 1024 * 1024

  static func acceptsContainerSize(_ bytes: Int64) -> Bool {
    bytes > 0 && bytes <= maximumContainerBytes
  }

  static func rendezvousToken(_ transferId: String) -> String {
    precondition(!transferId.isEmpty)
    let digest = SHA256.hash(
      data: Data("hearthbit-multipeer-discovery-v1:\(transferId)".utf8)
    )
    return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
  }
}

/// Transporta el contenedor HBT ya cifrado mediante `MCSession.sendResource`.
///
/// El token de discovery se deriva del transferId negociado por Noise. La
/// sesión Multipeer exige cifrado y solo conecta extremos con el mismo token y
/// roles opuestos.
final class HearthBitMultipeerFileTransport: NSObject {
  private static let serviceType = "hearthbit-hbt"
  private let emit: ([String: Any]) -> Void
  private var localPeer: MCPeerID?
  private var session: MCSession?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var transferId: String?
  private var sending = false
  private var sourceURL: URL?
  private var destinationURL: URL?
  private var resourceProgress: Progress?
  private var progressTimer: Timer?
  private var sentResource = false

  init(emit: @escaping ([String: Any]) -> Void) {
    self.emit = emit
    super.init()
  }

  func sendFile(transferId: String, filePath: String) {
    let url = URL(fileURLWithPath: filePath)
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    let size = Int64(values?.fileSize ?? 0)
    guard IOSMultipeerFilePolicy.acceptsContainerSize(size) else {
      error(transferId, "Invalid HBT container")
      return
    }
    start(transferId: transferId, sending: true, path: url)
  }

  func receiveFile(transferId: String, destinationPath: String) {
    start(
      transferId: transferId,
      sending: false,
      path: URL(fileURLWithPath: destinationPath)
    )
  }

  func stop() {
    progressTimer?.invalidate()
    progressTimer = nil
    resourceProgress?.cancel()
    resourceProgress = nil
    advertiser?.stopAdvertisingPeer()
    browser?.stopBrowsingForPeers()
    session?.disconnect()
    advertiser = nil
    browser = nil
    session = nil
    localPeer = nil
    transferId = nil
    sourceURL = nil
    destinationURL = nil
    sentResource = false
  }

  private func start(transferId: String, sending: Bool, path: URL) {
    stop()
    self.transferId = transferId
    self.sending = sending
    sourceURL = sending ? path : nil
    destinationURL = sending ? nil : path
    let token = IOSMultipeerFilePolicy.rendezvousToken(transferId)
    let peer = MCPeerID(displayName: "hbt-\(UUID().uuidString.prefix(8))")
    let session = MCSession(
      peer: peer,
      securityIdentity: nil,
      encryptionPreference: .required
    )
    session.delegate = self
    let advertiser = MCNearbyServiceAdvertiser(
      peer: peer,
      discoveryInfo: [
        "v": "1",
        "token": token,
        "role": sending ? "sender" : "receiver",
      ],
      serviceType: Self.serviceType
    )
    advertiser.delegate = self
    let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
    browser.delegate = self
    localPeer = peer
    self.session = session
    self.advertiser = advertiser
    self.browser = browser
    advertiser.startAdvertisingPeer()
    browser.startBrowsingForPeers()
  }

  private func invitationContext() -> Data? {
    guard let transferId else { return nil }
    let value = [
      "token": IOSMultipeerFilePolicy.rendezvousToken(transferId),
      "role": sending ? "sender" : "receiver",
    ]
    return try? JSONSerialization.data(withJSONObject: value)
  }

  private func accepts(context: Data?) -> Bool {
    guard
      let transferId,
      let context,
      let value = try? JSONSerialization.jsonObject(with: context) as? [String: String],
      value["token"] == IOSMultipeerFilePolicy.rendezvousToken(transferId),
      value["role"] == (sending ? "receiver" : "sender")
    else { return false }
    return true
  }

  private func sendResourceIfReady() {
    guard
      sending,
      !sentResource,
      let transferId,
      let sourceURL,
      let session,
      let peer = session.connectedPeers.first
    else { return }
    sentResource = true
    let token = IOSMultipeerFilePolicy.rendezvousToken(transferId)
    resourceProgress = session.sendResource(
      at: sourceURL,
      withName: "hbt-\(token).enc",
      toPeer: peer
    ) { [weak self] error in
      DispatchQueue.main.async {
        guard let self, self.transferId == transferId else { return }
        self.progressTimer?.invalidate()
        self.progressTimer = nil
        if let error {
          self.error(transferId, "Multipeer transfer failed: \(error.localizedDescription)")
        } else {
          self.emit(["type": "multipeerDone", "transferId": transferId])
        }
      }
    }
    observeProgress(transferId: transferId)
  }

  private func observeProgress(transferId: String) {
    progressTimer?.invalidate()
    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
      [weak self] timer in
      guard
        let self,
        self.transferId == transferId,
        let progress = self.resourceProgress
      else {
        timer.invalidate()
        return
      }
      self.emit([
        "type": "multipeerProgress",
        "transferId": transferId,
        "bytes": progress.completedUnitCount,
        "total": progress.totalUnitCount,
      ])
    }
  }

  private func error(_ transferId: String, _ message: String) {
    emit(["type": "multipeerError", "transferId": transferId, "message": message])
  }
}

extension HearthBitMultipeerFileTransport: MCNearbyServiceAdvertiserDelegate {
  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    let accepted = accepts(context: context)
    invitationHandler(accepted, accepted ? session : nil)
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didNotStartAdvertisingPeer error: Error
  ) {
    guard let transferId else { return }
    self.error(transferId, "Multipeer advertising failed: \(error.localizedDescription)")
  }
}

extension HearthBitMultipeerFileTransport: MCNearbyServiceBrowserDelegate {
  func browser(
    _ browser: MCNearbyServiceBrowser,
    foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    guard
      sending,
      let transferId,
      info?["v"] == "1",
      info?["token"] == IOSMultipeerFilePolicy.rendezvousToken(transferId),
      info?["role"] == "receiver",
      let session
    else { return }
    browser.invitePeer(peerID, to: session, withContext: invitationContext(), timeout: 15)
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

  func browser(
    _ browser: MCNearbyServiceBrowser,
    didNotStartBrowsingForPeers error: Error
  ) {
    guard let transferId else { return }
    self.error(transferId, "Multipeer discovery failed: \(error.localizedDescription)")
  }
}

extension HearthBitMultipeerFileTransport: MCSessionDelegate {
  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    guard state == .connected else { return }
    DispatchQueue.main.async { [weak self] in self?.sendResourceIfReady() }
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}

  func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}

  func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {
    guard !sending, let transferId else {
      progress.cancel()
      return
    }
    resourceProgress = progress
    DispatchQueue.main.async { [weak self] in self?.observeProgress(transferId: transferId) }
  }

  func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {
    guard !sending, let transferId, let destinationURL else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.transferId == transferId else { return }
      self.progressTimer?.invalidate()
      self.progressTimer = nil
      if let error {
        self.error(transferId, "Multipeer transfer failed: \(error.localizedDescription)")
        return
      }
      guard let localURL else {
        self.error(transferId, "Multipeer did not provide the received file")
        return
      }
      do {
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: localURL, to: destinationURL)
        self.emit(["type": "multipeerDone", "transferId": transferId])
      } catch {
        self.error(transferId, "Unable to save Multipeer file: \(error.localizedDescription)")
      }
    }
  }
}
