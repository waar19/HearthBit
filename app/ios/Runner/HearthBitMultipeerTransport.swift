import Foundation
import MultipeerConnectivity

enum IOSMultipeerPolicy {
  static func shouldRun(
    meshRunning: Bool,
    foreground: Bool,
    rescueActive: Bool,
    radarActive: Bool
  ) -> Bool {
    meshRunning && foreground && (rescueActive || radarActive)
  }
}

enum IOSEmergencyTransportEscalation {
  static func channels(ble: Bool, lan: Bool, multipeer: Bool) -> [String] {
    var channels: [String] = []
    if ble { channels.append("ble") }
    if lan { channels.append("lan") }
    if multipeer { channels.append("multipeer") }
    return channels
  }
}

struct IOSMultipeerState {
  let active: Bool
  let connectedPeers: Int
  let reason: String?
}

final class HearthBitMultipeerTransport: NSObject {
  static let maximumFrameSize = 2_048
  private static let serviceType = "hearthbit-sos"

  private let localPeer = MCPeerID(displayName: "hb-\(UUID().uuidString.prefix(8))")
  private let onFrame: (Data, String) -> Void
  private let onState: (IOSMultipeerState) -> Void
  private lazy var session = MCSession(
    peer: localPeer,
    securityIdentity: nil,
    encryptionPreference: .required
  )
  private lazy var advertiser = MCNearbyServiceAdvertiser(
    peer: localPeer,
    discoveryInfo: ["v": "1"],
    serviceType: Self.serviceType
  )
  private lazy var browser = MCNearbyServiceBrowser(
    peer: localPeer,
    serviceType: Self.serviceType
  )
  private var active = false

  init(
    onFrame: @escaping (Data, String) -> Void,
    onState: @escaping (IOSMultipeerState) -> Void
  ) {
    self.onFrame = onFrame
    self.onState = onState
    super.init()
    session.delegate = self
    advertiser.delegate = self
    browser.delegate = self
  }

  func start() {
    guard !active else { return }
    active = true
    advertiser.startAdvertisingPeer()
    browser.startBrowsingForPeers()
    emit()
  }

  func stop() {
    guard active else { return }
    active = false
    advertiser.stopAdvertisingPeer()
    browser.stopBrowsingForPeers()
    session.disconnect()
    emit()
  }

  @discardableResult
  func send(_ frame: Data) -> Bool {
    guard active,
          !frame.isEmpty,
          frame.count <= Self.maximumFrameSize,
          !session.connectedPeers.isEmpty
    else { return false }
    do {
      try session.send(frame, toPeers: session.connectedPeers, with: .reliable)
      return true
    } catch {
      emit(reason: "send_failed")
      return false
    }
  }

  private func emit(reason: String? = nil) {
    onState(
      IOSMultipeerState(
        active: active,
        connectedPeers: session.connectedPeers.count,
        reason: reason
      )
    )
  }
}

extension HearthBitMultipeerTransport: MCNearbyServiceAdvertiserDelegate {
  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    invitationHandler(active, active ? session : nil)
  }

  func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didNotStartAdvertisingPeer error: Error
  ) {
    emit(reason: "advertise_failed")
  }
}

extension HearthBitMultipeerTransport: MCNearbyServiceBrowserDelegate {
  func browser(
    _ browser: MCNearbyServiceBrowser,
    foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    guard active,
          info?["v"] == "1",
          localPeer.displayName < peerID.displayName
    else { return }
    browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

  func browser(
    _ browser: MCNearbyServiceBrowser,
    didNotStartBrowsingForPeers error: Error
  ) {
    emit(reason: "browse_failed")
  }
}

extension HearthBitMultipeerTransport: MCSessionDelegate {
  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    DispatchQueue.main.async { [weak self] in self?.emit() }
  }

  func session(
    _ session: MCSession,
    didReceive data: Data,
    fromPeer peerID: MCPeerID
  ) {
    guard !data.isEmpty, data.count <= Self.maximumFrameSize else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.active else { return }
      self.onFrame(data, peerID.displayName)
    }
  }

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
  ) {}

  func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {}
}
