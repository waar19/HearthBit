import CoreBluetooth
import CryptoKit
import Flutter
import Foundation
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  private let sender = Data([1, 2, 3, 4, 5, 6, 7, 8])
  private let fragmentID = Data([9, 8, 7, 6, 5, 4, 3, 2])

  func testEmergencyRetriesRenewTimestampFingerprintAndHash() throws {
    let original = IOSMeshPacket(
      type: IOSMeshProtocol.message,
      ttl: 1,
      timestamp: 100,
      senderID: sender,
      payload: Data("SOS|Ayuda||".utf8),
      signature: Data(repeating: 1, count: 64),
      isRSR: true
    )
    let sign: (IOSMeshPacket) -> IOSMeshPacket = { packet in
      var signed = packet
      let digest = Data(SHA256.hash(data: packet.canonical()))
      signed.signature = digest + digest
      return signed
    }

    let first = try XCTUnwrap(
      IOSEmergencyRetryPolicy.rebuild(
        packet: original,
        localSenderID: sender,
        now: 100,
        sign: sign
      )
    )
    let second = try XCTUnwrap(
      IOSEmergencyRetryPolicy.rebuild(
        packet: first,
        localSenderID: sender,
        now: 100,
        sign: sign
      )
    )

    XCTAssertEqual(first.timestamp, 101)
    XCTAssertEqual(second.timestamp, 102)
    XCTAssertEqual(first.ttl, IOSMeshProtocol.defaultTTL)
    XCTAssertEqual(second.ttl, IOSMeshProtocol.defaultTTL)
    XCTAssertFalse(first.isRSR)
    XCTAssertFalse(second.isRSR)
    XCTAssertNotEqual(
      IOSMeshProtocol.fingerprint(original),
      IOSMeshProtocol.fingerprint(first)
    )
    XCTAssertNotEqual(
      IOSMeshProtocol.fingerprint(first),
      IOSMeshProtocol.fingerprint(second)
    )
    XCTAssertNotEqual(
      IOSMeshProtocol.emergencyCanonicalHash(original),
      IOSMeshProtocol.emergencyCanonicalHash(first)
    )
    XCTAssertNotEqual(
      IOSMeshProtocol.emergencyCanonicalHash(first),
      IOSMeshProtocol.emergencyCanonicalHash(second)
    )
    XCTAssertNil(
      IOSEmergencyRetryPolicy.rebuild(
        packet: original,
        localSenderID: Data(repeating: 0, count: 8),
        now: 101,
        sign: sign
      )
    )
    XCTAssertNil(
      IOSEmergencyRetryPolicy.rebuild(
        packet: IOSMeshPacket(
          type: original.type,
          ttl: original.ttl,
          timestamp: UInt64.max,
          senderID: original.senderID,
          payload: original.payload,
          signature: original.signature
        ),
        localSenderID: sender,
        now: UInt64.max,
        sign: sign
      )
    )
  }

  func testFragmentPayloadMatchesBitChatWireFormat() {
    let encoded = IOSMeshProtocol.encodeFragmentPayload(
      IOSMeshProtocol.FragmentPayload(
        fragmentID: Data([1, 2, 3, 4, 5, 6, 7, 8]),
        index: 0x0102,
        total: 0x0304,
        originalType: IOSMeshProtocol.message,
        data: Data([0x55, 0x66])
      )
    )

    XCTAssertEqual(encoded?.hexString, "010203040506070801020304025566")
    let decoded = encoded.flatMap(IOSMeshProtocol.decodeFragmentPayload)
    XCTAssertEqual(decoded?.fragmentID, Data([1, 2, 3, 4, 5, 6, 7, 8]))
    XCTAssertEqual(decoded?.index, 0x0102)
    XCTAssertEqual(decoded?.total, 0x0304)
    XCTAssertEqual(decoded?.originalType, IOSMeshProtocol.message)
    XCTAssertEqual(decoded?.data, Data([0x55, 0x66]))
  }

  func testFragmentRoundTripOutOfOrderPreservesSignatureAndFingerprint() throws {
    let original = IOSMeshPacket(
      version: 2,
      type: IOSMeshProtocol.message,
      ttl: 7,
      timestamp: 1234,
      senderID: sender,
      recipientID: Data(repeating: 0xff, count: 8),
      payload: Data((0..<700).map { UInt8(truncatingIfNeeded: $0 * 31) }),
      signature: Data(repeating: 0x55, count: 64),
      route: [
        Data((0..<8).map { UInt8(0x10 + $0) }),
        Data((0..<8).map { UInt8(0x20 + $0) }),
      ]
    )
    let encoded = IOSMeshProtocol.encodeForBLE(original)
    let fragmenter = IOSMeshPacketFragmenter(fragmentIDGenerator: { self.fragmentID })
    let frames = try XCTUnwrap(
      fragmenter.prepare(packet: original, encoded: encoded, maximumValueLength: 100)
    )
    XCTAssertGreaterThan(frames.count, 1)
    XCTAssertTrue(frames.allSatisfy { $0.count <= 100 })

    let fragments = try frames.map { try XCTUnwrap(IOSMeshProtocol.decode($0)) }
    for (index, fragment) in fragments.enumerated() {
      XCTAssertEqual(fragment.type, IOSMeshProtocol.fragment)
      XCTAssertNil(fragment.signature)
      let payload = try XCTUnwrap(IOSMeshProtocol.decodeFragmentPayload(fragment.payload))
      XCTAssertEqual(payload.fragmentID, fragmentID)
      XCTAssertEqual(payload.index, index)
      XCTAssertEqual(payload.total, fragments.count)
      XCTAssertEqual(payload.originalType, IOSMeshProtocol.message)
    }

    let reassembler = IOSMeshFragmentReassembler()
    var result: IOSMeshPacket?
    for fragment in fragments.reversed() {
      result = reassembler.accept(fragment) ?? result
    }
    let reassembled = try XCTUnwrap(result)
    XCTAssertEqual(reassembled.type, original.type)
    XCTAssertEqual(reassembled.ttl, 0)
    XCTAssertEqual(reassembled.payload, original.payload)
    XCTAssertEqual(reassembled.signature, original.signature)
    XCTAssertEqual(reassembled.route, original.route)
    XCTAssertEqual(
      IOSMeshProtocol.fingerprint(reassembled),
      IOSMeshProtocol.fingerprint(original)
    )
  }

  func testRejectsNestedAndExcessiveFragmentSets() throws {
    let nested = IOSMeshPacket(
      type: IOSMeshProtocol.fragment,
      ttl: 7,
      timestamp: 1,
      senderID: sender,
      payload: Data(repeating: 1, count: 200)
    )
    let fragmenter = IOSMeshPacketFragmenter(fragmentIDGenerator: { self.fragmentID })
    XCTAssertNil(
      fragmenter.prepare(
        packet: nested,
        encoded: IOSMeshProtocol.encodeForBLE(nested),
        maximumValueLength: 100
      )
    )

    let excessivePayload = try XCTUnwrap(
      IOSMeshProtocol.encodeFragmentPayload(
        IOSMeshProtocol.FragmentPayload(
          fragmentID: fragmentID,
          index: 0,
          total: 257,
          originalType: IOSMeshProtocol.message,
          data: Data([1])
        )
      )
    )
    let excessive = IOSMeshPacket(
      type: IOSMeshProtocol.fragment,
      ttl: 7,
      timestamp: 1,
      senderID: sender,
      payload: excessivePayload
    )
    XCTAssertNil(IOSMeshFragmentReassembler().accept(excessive))
  }

  func testNoisePaddingIsNotIncludedInReassembledPacket() throws {
    let original = IOSMeshPacket(
      type: IOSMeshProtocol.noiseHandshake,
      ttl: 7,
      timestamp: 1,
      senderID: sender,
      payload: Data((0..<40).map { UInt8(truncatingIfNeeded: $0 * 17) })
    )
    let padded = IOSMeshProtocol.encodeForBLE(original)
    XCTAssertEqual(padded.count, 256)
    let frame = try XCTUnwrap(
      IOSMeshPacketFragmenter(fragmentIDGenerator: { self.fragmentID }).prepare(
        packet: original,
        encoded: padded,
        maximumValueLength: 100
      )?.first
    )
    XCTAssertLessThanOrEqual(frame.count, 100)

    let fragment = try XCTUnwrap(IOSMeshProtocol.decode(frame))
    let reassembled = try XCTUnwrap(IOSMeshFragmentReassembler().accept(fragment))
    XCTAssertEqual(reassembled.type, IOSMeshProtocol.noiseHandshake)
    XCTAssertEqual(reassembled.payload, original.payload)
  }

  func testFragmentSetExpiresAfterThirtySeconds() throws {
    let original = IOSMeshPacket(
      type: IOSMeshProtocol.message,
      ttl: 7,
      timestamp: 1,
      senderID: sender,
      payload: Data((0..<300).map { UInt8(truncatingIfNeeded: $0) })
    )
    let frames = try XCTUnwrap(
      IOSMeshPacketFragmenter(fragmentIDGenerator: { self.fragmentID }).prepare(
        packet: original,
        encoded: IOSMeshProtocol.encodeForBLE(original),
        maximumValueLength: 80
      )
    )
    let fragments = try frames.map { try XCTUnwrap(IOSMeshProtocol.decode($0)) }
    XCTAssertGreaterThan(fragments.count, 1)

    let reassembler = IOSMeshFragmentReassembler()
    let start = Date(timeIntervalSince1970: 1_000)
    XCTAssertNil(reassembler.accept(fragments[0], now: start))
    var result: IOSMeshPacket?
    for fragment in fragments.dropFirst() {
      result = reassembler.accept(
        fragment,
        now: start.addingTimeInterval(31)
      ) ?? result
    }
    XCTAssertNil(result)
  }

  func testGenericPresenceUsesPrivateRotatingLocalIdentifiers() throws {
    XCTAssertEqual(IOSGenericBLEPresenceTracker.rotationMilliseconds, 900_000)
    XCTAssertEqual(IOSGenericBLEPresenceTracker.staleMilliseconds, 45_000)
    XCTAssertEqual(IOSGenericBLEPresenceTracker.emitInterval, 1)
    XCTAssertEqual(IOSGenericBLEPresenceTracker.maximumObservations, 64)
    let material = Data("manufacturer-stable-material".utf8)
    let firstSession = IOSGenericBLEPresenceTracker(
      sessionSecret: Data((0..<32).map { UInt8($0) }),
      rotationMilliseconds: 1_000,
      staleMilliseconds: 10_000
    )
    let secondSession = IOSGenericBLEPresenceTracker(
      sessionSecret: Data((1...32).map { UInt8($0) }),
      rotationMilliseconds: 1_000,
      staleMilliseconds: 10_000
    )

    XCTAssertTrue(firstSession.record(material: material, rssi: -70, now: 100))
    let first = try XCTUnwrap(firstSession.snapshot(now: 100).first)
    XCTAssertTrue(firstSession.record(material: material, rssi: -65, now: 900))
    let sameWindow = try XCTUnwrap(firstSession.snapshot(now: 900).first)
    XCTAssertEqual(first.localID, sameWindow.localID)
    XCTAssertEqual(sameWindow.rssi, -65)
    XCTAssertEqual(first.localID.count, 24)
    XCTAssertFalse(first.localID.contains("manufacturer"))
    XCTAssertNil(first.eventMap["name"])
    XCTAssertNil(first.eventMap["mac"])
    XCTAssertNil(first.eventMap["uuid"])
    XCTAssertEqual(first.eventMap["kind"] as? String, "genericBle")
    XCTAssertEqual(first.eventMap["chatAvailable"] as? Bool, false)

    XCTAssertTrue(firstSession.record(material: material, rssi: -60, now: 1_000))
    let rotated = try XCTUnwrap(firstSession.snapshot(now: 1_000).first)
    XCTAssertNotEqual(first.localID, rotated.localID)

    XCTAssertTrue(secondSession.record(material: material, rssi: -70, now: 100))
    let otherSession = try XCTUnwrap(secondSession.snapshot(now: 100).first)
    XCTAssertNotEqual(first.localID, otherSession.localID)
  }

  func testGenericAdvertisementMaterialExcludesNamesAndMeshAds() {
    let meshUUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
    let serviceUUID = CBUUID(string: "180D")
    let meshAdvertisement: [String: Any] = [
      CBAdvertisementDataServiceUUIDsKey: [meshUUID],
      CBAdvertisementDataLocalNameKey: "private-device-name",
    ]
    XCTAssertTrue(
      IOSGenericBLEAdvertisement.isMesh(
        meshAdvertisement,
        meshServiceUUID: meshUUID
      )
    )
    XCTAssertTrue(
      IOSGenericBLEAdvertisement.isMesh(
        [CBAdvertisementDataServiceDataKey: [meshUUID: Data([1])]],
        meshServiceUUID: meshUUID
      )
    )

    let first: [String: Any] = [
      CBAdvertisementDataLocalNameKey: "first-private-name",
      CBAdvertisementDataServiceDataKey: [serviceUUID: Data([1, 2, 3])],
      CBAdvertisementDataManufacturerDataKey: Data([0x4c, 0x00, 9, 8, 7]),
    ]
    let renamed: [String: Any] = [
      CBAdvertisementDataLocalNameKey: "second-private-name",
      CBAdvertisementDataServiceDataKey: [serviceUUID: Data([1, 2, 3])],
      CBAdvertisementDataManufacturerDataKey: Data([0x4c, 0x00, 9, 8, 7]),
    ]
    let firstMaterial = IOSGenericBLEAdvertisement.material(first)
    XCTAssertFalse(firstMaterial.isEmpty)
    XCTAssertEqual(firstMaterial, IOSGenericBLEAdvertisement.material(renamed))
    XCTAssertFalse(String(decoding: firstMaterial, as: UTF8.self).contains("private"))
    XCTAssertTrue(
      IOSGenericBLEAdvertisement.material([
        CBAdvertisementDataLocalNameKey: "name-only",
      ]).isEmpty
    )
  }

  func testGenericPresenceBoundsAndExpiresObservations() {
    let tracker = IOSGenericBLEPresenceTracker(
      sessionSecret: Data(repeating: 7, count: 32),
      rotationMilliseconds: 10_000,
      staleMilliseconds: 100,
      maximumObservations: 2
    )

    XCTAssertFalse(tracker.record(material: Data(), rssi: -90, now: 0))
    XCTAssertTrue(tracker.record(material: Data([1]), rssi: -51, now: 0))
    XCTAssertTrue(tracker.record(material: Data([2]), rssi: -52, now: 10))
    XCTAssertTrue(tracker.record(material: Data([3]), rssi: -53, now: 20))
    let bounded = tracker.snapshot(now: 20)
    XCTAssertEqual(bounded.count, 2)
    XCTAssertEqual(Set(bounded.map(\.rssi)), Set([-52, -53]))
    XCTAssertTrue(tracker.snapshot(now: 121).isEmpty)
  }

  func testGenericScanPolicyKeepsMeshFilterOutsideForegroundWindows() {
    XCTAssertEqual(IOSGenericBLEScanPolicy.windowDuration, 10)
    XCTAssertEqual(IOSGenericBLEScanPolicy.pauseDuration, 50)
    XCTAssertEqual(
      IOSGenericBLEScanPolicy.selection(
        genericEnabled: false,
        genericWindowActive: true,
        foreground: true,
        radarActive: false,
        recoveryActive: false
      ),
      .meshFiltered
    )
    XCTAssertEqual(
      IOSGenericBLEScanPolicy.selection(
        genericEnabled: true,
        genericWindowActive: true,
        foreground: true,
        radarActive: false,
        recoveryActive: false
      ),
      .genericUnfiltered
    )
    XCTAssertEqual(
      IOSGenericBLEScanPolicy.selection(
        genericEnabled: true,
        genericWindowActive: false,
        foreground: true,
        radarActive: false,
        recoveryActive: false
      ),
      .meshFiltered
    )
    XCTAssertEqual(
      IOSGenericBLEScanPolicy.selection(
        genericEnabled: true,
        genericWindowActive: true,
        foreground: false,
        radarActive: false,
        recoveryActive: false
      ),
      .meshFiltered
    )
    XCTAssertEqual(
      IOSGenericBLEScanPolicy.selection(
        genericEnabled: true,
        genericWindowActive: true,
        foreground: true,
        radarActive: true,
        recoveryActive: false
      ),
      .meshFiltered
    )
    XCTAssertEqual(
      IOSGenericBLEScanPolicy.selection(
        genericEnabled: true,
        genericWindowActive: true,
        foreground: true,
        radarActive: false,
        recoveryActive: true
      ),
      .meshFiltered
    )
  }

  func testAnnouncementClockPolicyAppliesStandardWindowBothDirections() {
    let now: UInt64 = 100_000_000
    let window = IOSAnnouncementClockPolicy.standardWindowMilliseconds

    XCTAssertTrue(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now,
        emergencyPreannounce: false,
        now: now
      )
    )
    XCTAssertTrue(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now - window,
        emergencyPreannounce: false,
        now: now
      )
    )
    XCTAssertTrue(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now + window,
        emergencyPreannounce: false,
        now: now
      )
    )
    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now - window - 1,
        emergencyPreannounce: false,
        now: now
      )
    )
    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now + window + 1,
        emergencyPreannounce: false,
        now: now
      )
    )
  }

  func testEmergencyMarkerExtendsOnlyPastWindow() {
    let now: UInt64 = 100_000_000
    let emergencyWindow = IOSAnnouncementClockPolicy.emergencyPastWindowMilliseconds
    let futureWindow = IOSAnnouncementClockPolicy.standardWindowMilliseconds

    XCTAssertTrue(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now - emergencyWindow,
        emergencyPreannounce: true,
        now: now
      )
    )
    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now - emergencyWindow - 1,
        emergencyPreannounce: true,
        now: now
      )
    )
    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now + futureWindow + 1,
        emergencyPreannounce: true,
        now: now
      )
    )
  }

  func testAnnouncementClockPolicyHandlesUInt64Extremes() {
    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: UInt64.max,
        emergencyPreannounce: true,
        now: 0
      )
    )
    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: 0,
        emergencyPreannounce: true,
        now: UInt64.max
      )
    )
  }

  func testEmergencyPreannounceRequiresExactSignedTLVValue() throws {
    let marked = IOSMeshProtocol.announcement(
      nickname: "Ana",
      noisePublicKey: Data(repeating: 2, count: 32),
      signingPublicKey: Data(repeating: 3, count: 32),
      emergencyPreannounce: true
    )
    var unknownValue = marked
    unknownValue[unknownValue.index(before: unknownValue.endIndex)] = 0x02
    let corrupt = marked.dropLast()

    XCTAssertTrue(try XCTUnwrap(IOSMeshProtocol.decodeAnnouncement(marked)).emergencyPreannounce)
    XCTAssertFalse(
      try XCTUnwrap(IOSMeshProtocol.decodeAnnouncement(unknownValue)).emergencyPreannounce
    )
    XCTAssertFalse(
      try XCTUnwrap(IOSMeshProtocol.decodeAnnouncement(Data(corrupt))).emergencyPreannounce
    )
  }

  func testTTLMutationCannotExtendOrdinaryAnnouncementWindow() {
    let now: UInt64 = 100_000_000
    let signedAtTTL1 = IOSMeshPacket(
      type: IOSMeshProtocol.announce,
      ttl: 1,
      timestamp: now - IOSAnnouncementClockPolicy.standardWindowMilliseconds - 1,
      senderID: sender,
      payload: Data()
    )
    var relayed = signedAtTTL1
    relayed.ttl = IOSMeshProtocol.defaultTTL

    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: relayed.timestamp,
        emergencyPreannounce: false,
        now: now
      )
    )
  }

  func testEmergencyMarkerRejectsThirtyMinutesInFuture() {
    let now: UInt64 = 100_000_000
    XCTAssertFalse(
      IOSAnnouncementClockPolicy.accepts(
        timestamp: now + 30 * 60 * 1_000,
        emergencyPreannounce: true,
        now: now
      )
    )
  }

  func testOnlyExplicitStopClearsLanBridge() {
    XCTAssertFalse(IOSLanBridgeLifecyclePolicy.shouldClearOnStop(notify: false))
    XCTAssertTrue(IOSLanBridgeLifecyclePolicy.shouldClearOnStop(notify: true))
  }

  func testPhoneBeaconDisablesDataPlanePolicy() {
    XCTAssertFalse(IOSMeshNodeRole.phoneBeacon.allowsDataPlane)
    XCTAssertFalse(IOSMeshNodeRole.phoneBeacon.relaysPackets)
    XCTAssertFalse(IOSMeshNodeRole.phoneBeacon.canChat)

    XCTAssertTrue(IOSMeshNodeRole.phoneRelay.allowsDataPlane)
    XCTAssertTrue(IOSMeshNodeRole.phoneRelay.relaysPackets)
    XCTAssertTrue(IOSMeshNodeRole.phoneRelay.canChat)
  }

  func testPeerReachabilityAllowsNinetySecondKeepaliveAndBoundary() {
    let now = Date(timeIntervalSince1970: 10_000)

    XCTAssertTrue(
      IOSPeerReachabilityPolicy.isOnline(
        lastActivity: now.addingTimeInterval(-90),
        now: now
      )
    )
    XCTAssertTrue(
      IOSPeerReachabilityPolicy.isOnline(
        lastActivity: now.addingTimeInterval(-IOSPeerReachabilityPolicy.window),
        now: now
      )
    )
  }

  func testLongReachabilityGapRequiresOneTransportRekey() {
    let now = Date(timeIntervalSince1970: 10_000)
    let stale = now.addingTimeInterval(-IOSPeerReachabilityPolicy.window - 0.001)

    XCTAssertFalse(
      IOSPeerReachabilityPolicy.isOnline(lastActivity: stale, now: now)
    )
    XCTAssertTrue(
      IOSPeerReachabilityPolicy.requiresTransportRekey(
        previousLastSeen: stale,
        now: now
      )
    )
    XCTAssertFalse(
      IOSPeerReachabilityPolicy.requiresTransportRekey(
        previousLastSeen: now,
        now: now
      )
    )
    XCTAssertFalse(
      IOSPeerReachabilityPolicy.requiresTransportRekey(
        previousLastSeen: nil,
        now: now
      )
    )
  }

  func testLongRangeTrunkCapabilityUsesBitFourWithoutChangingRole() throws {
    let original = IOSMeshNodeRole.infraRelay.capabilityPayload
    let withTrunk = IOSMeshNodeRole.infraRelay.capabilityPayload(
      hasLongRangeTrunk: true
    )
    let decoded = try XCTUnwrap(IOSMeshNodeRole.decodeCapability(withTrunk))

    XCTAssertEqual(original.count, 3)
    XCTAssertEqual(withTrunk.count, 3)
    XCTAssertEqual(original[2] | 0x10, withTrunk[2])
    XCTAssertEqual(decoded.role, .infraRelay)
    XCTAssertTrue(decoded.hasLongRangeTrunk)
    XCTAssertFalse(
      try XCTUnwrap(IOSMeshNodeRole.decodeCapability(original)).hasLongRangeTrunk
    )
  }

  func testBeaconControlUsesDirectedSignedType26WithStrictFiveMinutePayload() throws {
    let now: UInt64 = 1_000_000
    let nonce = Data((0..<IOSBeaconControlProtocol.nonceSize).map { UInt8($0) })
    let flags = IOSBeaconControlProtocol.flashFlag | IOSBeaconControlProtocol.vibrateFlag
    let payload = IOSBeaconControlProtocol.request(
      expiresAt: now + IOSBeaconControlProtocol.maximumDurationMilliseconds,
      flags: flags,
      nonce: nonce
    )
    let control = try XCTUnwrap(IOSBeaconControlProtocol.decode(payload))
    XCTAssertEqual(payload.count, 27)
    XCTAssertEqual(control.action, IOSBeaconControlProtocol.requestAction)
    XCTAssertEqual(control.nonce, nonce)
    XCTAssertTrue(
      IOSBeaconControlProtocol.isValid(control, packetTimestamp: now, now: now)
    )
    XCTAssertFalse(
      IOSBeaconControlProtocol.isValid(
        IOSBeaconControlProtocol.Control(
          action: control.action,
          expiresAt: now + IOSBeaconControlProtocol.maximumDurationMilliseconds + 1,
          nonce: nonce,
          flags: flags
        ),
        packetTimestamp: now,
        now: now
      )
    )
    var malformed = payload
    malformed[malformed.count - 1] = 0x08
    XCTAssertNil(IOSBeaconControlProtocol.decode(malformed))

    let packet = IOSMeshPacket(
      type: IOSMeshProtocol.beaconControl,
      ttl: IOSBeaconControlProtocol.initialTTL,
      timestamp: now,
      senderID: sender,
      recipientID: Data(repeating: 2, count: 8),
      payload: payload,
      signature: Data(repeating: 3, count: 64)
    )
    let decoded = try XCTUnwrap(
      IOSMeshProtocol.decode(IOSMeshProtocol.encode(packet, padded: false))
    )
    XCTAssertEqual(decoded.type, 0x26)
    XCTAssertEqual(decoded.ttl, 2)
    XCTAssertNotNil(decoded.recipientID)
    XCTAssertNotNil(decoded.signature)
    XCTAssertFalse(IOSBeaconControlProtocol.isValidTTL(0))
    XCTAssertTrue(IOSBeaconControlProtocol.isValidTTL(1))
    XCTAssertTrue(IOSBeaconControlProtocol.isValidTTL(2))
    XCTAssertFalse(IOSBeaconControlProtocol.isValidTTL(3))
    XCTAssertFalse(IOSNoiseReplayPolicy.isStoreForwardSafe(decoded))
    XCTAssertFalse(
      IOSBeaconControlProtocol.shouldAutoAccept(localRadarConsentUntil: now, now: now)
    )
    XCTAssertTrue(
      IOSBeaconControlProtocol.shouldAutoAccept(localRadarConsentUntil: now + 1, now: now)
    )
  }

  func testSignedIngressRequiresPinnedKeyAndValidSignature() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    var packet = IOSMeshPacket(
      type: IOSMeshProtocol.message,
      ttl: IOSMeshProtocol.defaultTTL,
      timestamp: 1,
      senderID: sender,
      payload: Data("hello".utf8)
    )
    packet.signature = try privateKey.signature(for: packet.canonical())

    XCTAssertFalse(
      IOSMeshIngressPolicy.accepts(packet, signingPublicKey: nil)
    )
    XCTAssertTrue(
      IOSMeshIngressPolicy.accepts(
        packet,
        signingPublicKey: privateKey.publicKey.rawRepresentation
      )
    )
    packet.payload = Data("tampered".utf8)
    XCTAssertFalse(
      IOSMeshIngressPolicy.accepts(
        packet,
        signingPublicKey: privateKey.publicKey.rawRepresentation
      )
    )
  }

  func testUnknownIngressRateLimitIsPerSourceAndResets() {
    let limiter = IOSUnknownIngressRateLimiter(maximumPackets: 2, window: 10)

    XCTAssertTrue(limiter.allow(source: "source-a", now: 100))
    XCTAssertTrue(limiter.allow(source: "source-a", now: 101))
    XCTAssertFalse(limiter.allow(source: "source-a", now: 102))
    XCTAssertTrue(limiter.allow(source: "source-b", now: 102))
    XCTAssertTrue(limiter.allow(source: "source-a", now: 110))
  }

  func testEmergencySMSRecipientIsRevalidatedNatively() {
    XCTAssertEqual(
      IOSEmergencySMSPolicy.normalizeRecipient(" (+56) 9-1234-5678 "),
      "+56912345678"
    )
    XCTAssertEqual(IOSEmergencySMSPolicy.normalizeRecipient("13 100"), "13100")
    XCTAssertNil(IOSEmergencySMSPolicy.normalizeRecipient("smsto:+56912345678"))
    XCTAssertNil(IOSEmergencySMSPolicy.normalizeRecipient("+56CALLHELP"))
    XCTAssertNil(IOSEmergencySMSPolicy.normalizeRecipient("1234"))
    XCTAssertNil(IOSEmergencySMSPolicy.normalizeRecipient("+1234567890123456"))
  }

  func testBeaconControlRelaysExactlyOnceOnlyToAnotherDirectedRecipient() {
    XCTAssertTrue(
      IOSMeshRelayPolicy.shouldRelay(
        role: .phoneRelay,
        packetType: IOSMeshProtocol.beaconControl,
        ttl: 2,
        addressedToLocalNode: false,
        hasDirectedRecipient: true
      )
    )
    XCTAssertFalse(
      IOSMeshRelayPolicy.shouldRelay(
        role: .phoneRelay,
        packetType: IOSMeshProtocol.beaconControl,
        ttl: 1,
        addressedToLocalNode: false,
        hasDirectedRecipient: true
      )
    )
    XCTAssertFalse(
      IOSMeshRelayPolicy.shouldRelay(
        role: .phoneRelay,
        packetType: IOSMeshProtocol.beaconControl,
        ttl: 2,
        addressedToLocalNode: true,
        hasDirectedRecipient: true
      )
    )
    XCTAssertFalse(
      IOSMeshRelayPolicy.shouldRelay(
        role: .phoneRelay,
        packetType: IOSMeshProtocol.beaconControl,
        ttl: 2,
        addressedToLocalNode: false,
        hasDirectedRecipient: false
      )
    )
    XCTAssertFalse(
      IOSMeshRelayPolicy.shouldRelay(
        role: .phoneRelay,
        packetType: IOSMeshProtocol.beaconControl,
        ttl: 3,
        addressedToLocalNode: false,
        hasDirectedRecipient: true
      )
    )
    XCTAssertFalse(
      IOSMeshRelayPolicy.shouldRelay(
        role: .phoneRelay,
        packetType: IOSMeshProtocol.rangingControl,
        ttl: 2,
        addressedToLocalNode: false,
        hasDirectedRecipient: true
      )
    )
  }

  func testFragmentedBeaconControlPreservesDirectOrRelayedTTL() throws {
    let now: UInt64 = 1_000_000
    let original = IOSMeshPacket(
      type: IOSMeshProtocol.beaconControl,
      ttl: IOSBeaconControlProtocol.initialTTL,
      timestamp: now,
      senderID: sender,
      recipientID: Data(repeating: 2, count: 8),
      payload: IOSBeaconControlProtocol.request(
        expiresAt: now + 60_000,
        flags: IOSBeaconControlProtocol.flashFlag,
        nonce: Data((0..<IOSBeaconControlProtocol.nonceSize).map(UInt8.init))
      ),
      signature: Data(repeating: 3, count: 64)
    )
    let frames = try XCTUnwrap(
      IOSMeshPacketFragmenter(fragmentIDGenerator: { self.fragmentID }).prepare(
        packet: original,
        encoded: IOSMeshProtocol.encodeForBLE(original),
        maximumValueLength: 100
      )
    )
    XCTAssertGreaterThan(frames.count, 1)

    func reassemble(ttl: UInt8) throws -> IOSMeshPacket? {
      let reassembler = IOSMeshFragmentReassembler()
      var result: IOSMeshPacket?
      for frame in frames {
        var fragment = try XCTUnwrap(IOSMeshProtocol.decode(frame))
        fragment.ttl = ttl
        result = reassembler.accept(fragment) ?? result
      }
      return result
    }

    XCTAssertEqual(try XCTUnwrap(reassemble(ttl: 2)).ttl, 2)
    XCTAssertEqual(try XCTUnwrap(reassemble(ttl: 1)).ttl, 1)
    XCTAssertNil(try reassemble(ttl: 0))
    XCTAssertNil(try reassemble(ttl: 3))

    let mixedReassembler = IOSMeshFragmentReassembler()
    var mixedResult: IOSMeshPacket?
    for (index, frame) in frames.enumerated() {
      var fragment = try XCTUnwrap(IOSMeshProtocol.decode(frame))
      fragment.ttl = index == 0 ? 2 : 1
      mixedResult = mixedReassembler.accept(fragment) ?? mixedResult
    }
    XCTAssertEqual(try XCTUnwrap(mixedResult).ttl, 1)
  }

  func testBLEPriorityQueuePrioritizesEmergencyWithoutStarvingNormalFrames() throws {
    var queue = IOSBLEPriorityQueue<String>(normalCapacity: 32, emergencyReserve: 8)
    XCTAssertTrue(queue.enqueue(["n0", "n1"], priority: .normal))
    XCTAssertTrue(
      queue.enqueue((0..<10).map { "e\($0)" }, priority: .emergency)
    )

    var drained: [String] = []
    while let next = queue.next() {
      drained.append(next)
      queue.completeCurrent()
    }

    XCTAssertEqual(Array(drained.prefix(8)), (0..<8).map { "e\($0)" })
    XCTAssertEqual(drained[8], "n0")
    XCTAssertEqual(Array(drained[9...10]), ["e8", "e9"])
    XCTAssertEqual(drained.last, "n1")
  }

  func testBLEPriorityQueueRetainsFailedWriteUntilRetryBudgetExpires() throws {
    var queue = IOSBLEPriorityQueue<String>(normalCapacity: 2, emergencyReserve: 1)
    XCTAssertTrue(queue.enqueue(["sos"], priority: .emergency))
    XCTAssertEqual(queue.next(), "sos")

    for attempt in 1...IOSBLEPriorityQueue<String>.maximumRetries {
      let failure = try XCTUnwrap(queue.failCurrent())
      XCTAssertEqual(failure.attempt, attempt)
      XCTAssertFalse(failure.discarded)
      XCTAssertEqual(queue.next(), "sos")
    }
    let terminal = try XCTUnwrap(queue.failCurrent())
    XCTAssertTrue(terminal.discarded)
    XCTAssertTrue(queue.isEmpty)
  }

  func testBLEPriorityQueueReportsCapacityInsteadOfSilentlyDroppingSOS() {
    var queue = IOSBLEPriorityQueue<Int>(normalCapacity: 2, emergencyReserve: 1)
    XCTAssertTrue(queue.enqueue([1, 2], priority: .normal))
    XCTAssertTrue(queue.enqueue([3], priority: .emergency))
    XCTAssertFalse(queue.enqueue([4], priority: .emergency))
    XCTAssertEqual(queue.count, 3)
  }

  func testNoiseReplayWindowRejectsDuplicatesAndNoncesOlderThan1024() {
    // Misma semántica que NoiseReplayWindow.kt en Android: los duplicados
    // dentro de la ventana de 1024 se rechazan y los más antiguos quedan
    // obsoletos.
    var window = IOSNoiseReplayWindow()
    for nonce in UInt32(0)...UInt32(1_100) {
      XCTAssertTrue(window.canAccept(nonce))
      window.markAccepted(nonce)
    }
    XCTAssertFalse(window.canAccept(1_100))
    // 77 está a distancia 1023: sigue dentro de la ventana y ya fue visto.
    XCTAssertFalse(window.canAccept(77))
    // 76 está a distancia 1024: más antiguo que la ventana.
    XCTAssertFalse(window.canAccept(76))
    XCTAssertFalse(window.canAccept(0))

    // Fuera de orden: un nonce no visto dentro de la ventana se acepta una
    // sola vez (espejo del caso Android con 1100/100/76).
    var sparse = IOSNoiseReplayWindow()
    sparse.markAccepted(1_100)
    XCTAssertTrue(sparse.canAccept(100))
    sparse.markAccepted(100)
    XCTAssertFalse(sparse.canAccept(100))
    XCTAssertFalse(sparse.canAccept(76))
  }

  func testNoiseCipherRejectsReplayAfterMoreThan1024AuthenticatedNonces() throws {
    let key = SymmetricKey(data: Data(repeating: 0x5a, count: 32))
    let sender = IOSNoiseCipher(key: key, messageLimit: 2_000)
    let receiver = IOSNoiseCipher(key: key, messageLimit: 2_000)
    var frames: [Data] = []
    for index in 0...1_100 {
      frames.append(
        try sender.encrypt(Data("frame-\(index)".utf8), extractedNonce: true)
      )
    }
    for (index, frame) in frames.enumerated() {
      XCTAssertEqual(
        try receiver.decrypt(frame, extractedNonce: true),
        Data("frame-\(index)".utf8)
      )
    }
    XCTAssertThrowsError(try receiver.decrypt(frames[0], extractedNonce: true))
    XCTAssertThrowsError(try receiver.decrypt(frames[1_100], extractedNonce: true))
  }

  func testNoiseCipherRequiresRekeyAtUInt32Boundary() throws {
    let cipher = IOSNoiseCipher(
      key: SymmetricKey(data: Data(repeating: 0x6b, count: 32)),
      messageLimit: UInt64(UInt32.max) + 2,
      initialNonce: UInt64(UInt32.max)
    )
    _ = try cipher.encrypt(Data([1]), extractedNonce: true)
    XCTAssertTrue(cipher.requiresRekey)
    XCTAssertThrowsError(try cipher.encrypt(Data([2]), extractedNonce: true))
  }

  func testStoreForwardMigratesPlaintextOnceThenFailsClosed() throws {
    let suiteName = "HearthBit.StoreForwardTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let packet = IOSMeshPacket(
      type: IOSMeshProtocol.message,
      ttl: 7,
      timestamp: 123,
      senderID: sender,
      recipientID: Data(repeating: 9, count: 8),
      payload: Data("SOS|migration".utf8)
    )
    let plaintext = IOSMeshProtocol.encode(packet, padded: false)
    defaults.set([
      [
        "expiry": Date().timeIntervalSince1970 + 3_600,
        "encoded": plaintext.base64EncodedString(),
      ],
    ], forKey: IOSStoreForward.entriesKey)
    let key = SymmetricKey(data: Data(repeating: 0x33, count: 32))

    let migrated = IOSStoreForward(defaults: defaults, testingKey: key)
    XCTAssertNil(migrated.failure)
    XCTAssertEqual(
      defaults.integer(forKey: IOSStoreForward.migrationVersionKey),
      IOSStoreForward.currentMigrationVersion
    )
    let persisted = try XCTUnwrap(
      (defaults.array(forKey: IOSStoreForward.entriesKey) as? [[String: Any]])?.first?["encoded"]
        as? String
    )
    XCTAssertNotEqual(persisted, plaintext.base64EncodedString())
    XCTAssertEqual(
      try migrated.validEntries(now: Date().timeIntervalSince1970).first?.encoded,
      plaintext
    )

    defaults.set([
      [
        "expiry": Date().timeIntervalSince1970 + 3_600,
        "encoded": plaintext.base64EncodedString(),
      ],
    ], forKey: IOSStoreForward.entriesKey)
    let failClosed = IOSStoreForward(defaults: defaults, testingKey: key)
    XCTAssertNil(failClosed.failure)
    XCTAssertThrowsError(
      try failClosed.validEntries(now: Date().timeIntervalSince1970)
    )
  }

  func testSemanticFingerprintUsesCanonicalNonPaddedEncoding() {
    let packet = IOSMeshPacket(
      type: IOSMeshProtocol.noiseEncrypted,
      ttl: 7,
      timestamp: 99,
      senderID: sender,
      payload: Data((0..<40).map(UInt8.init)),
      isRSR: true
    )
    var normalized = packet
    normalized.ttl = 0
    normalized.isRSR = false
    let expected = Data(
      SHA256.hash(data: IOSMeshProtocol.encode(normalized, padded: false)).prefix(12)
    ).hexString

    XCTAssertEqual(IOSMeshProtocol.fingerprint(packet), expected)
    XCTAssertEqual(
      IOSMeshProtocol.fingerprint(packet),
      IOSMeshProtocol.fingerprint(
        IOSMeshPacket(
          type: packet.type,
          ttl: 1,
          timestamp: packet.timestamp,
          senderID: packet.senderID,
          payload: packet.payload
        )
      )
    )
  }

  func testPeerPinCreatesFirstTOFUBinding() throws {
    let backend = TestSecurePinBackend()
    let store = backend.makeStore()
    let identity = makePeerPinMaterial()

    XCTAssertEqual(
      try store.validateAndPin(
        peerID: identity.peerID,
        noisePublicKey: identity.noise,
        signingPublicKey: identity.signing
      ),
      .firstBinding
    )
    XCTAssertEqual(store.pin(for: identity.peerID)?.noisePublicKey, identity.noise)
    XCTAssertNotNil(backend.data)
  }

  func testPeerPinAcceptsSameBoundKeys() throws {
    let backend = TestSecurePinBackend()
    let store = backend.makeStore()
    let identity = makePeerPinMaterial()
    _ = try store.validateAndPin(
      peerID: identity.peerID,
      noisePublicKey: identity.noise,
      signingPublicKey: identity.signing
    )

    XCTAssertEqual(
      try store.validateAndPin(
        peerID: identity.peerID,
        noisePublicKey: identity.noise,
        signingPublicKey: identity.signing
      ),
      .matched
    )
  }

  func testPeerPinRejectsSigningKeyChange() throws {
    let backend = TestSecurePinBackend()
    let store = backend.makeStore()
    let identity = makePeerPinMaterial()
    _ = try store.validateAndPin(
      peerID: identity.peerID,
      noisePublicKey: identity.noise,
      signingPublicKey: identity.signing
    )
    let replacement = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation

    XCTAssertEqual(
      try store.validateAndPin(
        peerID: identity.peerID,
        noisePublicKey: identity.noise,
        signingPublicKey: replacement
      ),
      .conflict(noiseChanged: false, signingChanged: true)
    )
    XCTAssertEqual(store.pin(for: identity.peerID)?.signingPublicKey, identity.signing)
  }

  func testPeerPinRejectsNoiseKeyChange() throws {
    let backend = TestSecurePinBackend()
    let store = backend.makeStore()
    let identity = makePeerPinMaterial()
    _ = try store.validateAndPin(
      peerID: identity.peerID,
      noisePublicKey: identity.noise,
      signingPublicKey: identity.signing
    )
    let replacement = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation

    XCTAssertEqual(
      try store.validateAndPin(
        peerID: identity.peerID,
        noisePublicKey: replacement,
        signingPublicKey: identity.signing
      ),
      .conflict(noiseChanged: true, signingChanged: false)
    )
    XCTAssertEqual(store.pin(for: identity.peerID)?.noisePublicKey, identity.noise)
  }

  func testPeerPinsRestoreFromSecurePersistence() throws {
    let backend = TestSecurePinBackend()
    let identity = makePeerPinMaterial()
    _ = try backend.makeStore().validateAndPin(
      peerID: identity.peerID,
      noisePublicKey: identity.noise,
      signingPublicKey: identity.signing
    )

    let restored = backend.makeStore()
    XCTAssertNil(restored.failure)
    XCTAssertEqual(restored.pin(for: identity.peerID)?.noisePublicKey, identity.noise)
    XCTAssertEqual(restored.pin(for: identity.peerID)?.signingPublicKey, identity.signing)
  }

  func testPeerPinsMigrateUnversionedSecurePayload() throws {
    let backend = TestSecurePinBackend()
    let identity = makePeerPinMaterial()
    backend.data = try JSONEncoder().encode([
      IOSPeerIdentityPin(
        peerID: identity.peerID,
        noisePublicKey: identity.noise,
        signingPublicKey: identity.signing
      ),
    ])
    let legacyPayload = backend.data

    let restored = backend.makeStore()

    XCTAssertNil(restored.failure)
    XCTAssertEqual(restored.pin(for: identity.peerID)?.noisePublicKey, identity.noise)
    XCTAssertNotEqual(backend.data, legacyPayload)
  }

  func testPeerPinWipeRemovesSecurePersistence() throws {
    let backend = TestSecurePinBackend()
    let identity = makePeerPinMaterial()
    let store = backend.makeStore()
    _ = try store.validateAndPin(
      peerID: identity.peerID,
      noisePublicKey: identity.noise,
      signingPublicKey: identity.signing
    )

    try store.clear()

    XCTAssertNil(backend.data)
    XCTAssertNil(store.pin(for: identity.peerID))
    XCTAssertNil(backend.makeStore().pin(for: identity.peerID))
  }

  func testNoiseSessionRequiresTemporalRekeyAtOneHourWithoutSleeping() throws {
    var clock = Date(timeIntervalSince1970: 10_000)
    let initiatorKey = Curve25519.KeyAgreement.PrivateKey()
    let responderKey = Curve25519.KeyAgreement.PrivateKey()
    let initiator = IOSNoiseSession(
      claimedPeerID: IOSMeshProtocol.peerID(responderKey.publicKey.rawRepresentation),
      initiator: true,
      localStatic: initiatorKey,
      now: { clock }
    )
    let responder = IOSNoiseSession(
      claimedPeerID: IOSMeshProtocol.peerID(initiatorKey.publicKey.rawRepresentation),
      initiator: false,
      localStatic: responderKey,
      now: { clock }
    )
    let messageOne = try initiator.start()
    let messageTwo = try XCTUnwrap(responder.process(messageOne))
    let messageThree = try XCTUnwrap(initiator.process(messageTwo))
    XCTAssertNil(try responder.process(messageThree))
    XCTAssertTrue(initiator.established)
    XCTAssertTrue(responder.established)

    clock = clock.addingTimeInterval(IOSNoiseSession.maximumSessionAge - 1)
    XCTAssertFalse(initiator.requiresRekey)
    XCTAssertFalse(responder.requiresRekey)
    clock = clock.addingTimeInterval(1)
    XCTAssertTrue(initiator.requiresRekey)
    XCTAssertTrue(responder.requiresRekey)
  }

  func testPrivateInteropPolicyHidesChatPreservesSOSAndGatesIdentity() {
    XCTAssertFalse(
      IOSMeshInteropPolicy.shouldProcessPublicMessage(
        privateMode: true,
        hearthbitVerified: false,
        emergency: false
      )
    )
    XCTAssertTrue(
      IOSMeshInteropPolicy.shouldProcessPublicMessage(
        privateMode: true,
        hearthbitVerified: false,
        emergency: true
      )
    )
    XCTAssertTrue(
      IOSMeshInteropPolicy.isExternalEmergency(
        privateMode: true,
        hearthbitVerified: false,
        emergency: true
      )
    )
    XCTAssertFalse(
      IOSMeshInteropPolicy.canSendIdentityToLink(
        privateMode: true,
        hearthbitProven: false,
        emergencyException: false
      )
    )
    XCTAssertTrue(
      IOSMeshInteropPolicy.canSendIdentityToLink(
        privateMode: true,
        hearthbitProven: false,
        emergencyException: true
      )
    )
    XCTAssertEqual(IOSMeshInteropPolicy.linkProof, Data("HB-LINK1".utf8))
  }

  private func makePeerPinMaterial() -> (peerID: String, noise: Data, signing: Data) {
    let noise = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    let signing = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    return (IOSMeshProtocol.peerID(noise).hexString, noise, signing)
  }
}

final class ConformanceFixtureTests: XCTestCase {
  private let fixtures = ConformanceFixtures.shared
  private let sender = Data([1, 2, 3, 4, 5, 6, 7, 8])

  func testPacketFramesV1V2CompressionAndMalformedInputs() throws {
    let v1 = try XCTUnwrap(IOSMeshProtocol.decode(fixtures.bytes("packet.v1.message")))
    XCTAssertEqual(v1.version, 1)
    XCTAssertEqual(v1.type, IOSMeshProtocol.message)
    XCTAssertEqual(v1.ttl, 7)
    XCTAssertEqual(v1.payload, Data("abc".utf8))

    let v2 = try XCTUnwrap(IOSMeshProtocol.decode(fixtures.bytes("packet.v2.route_signed")))
    XCTAssertEqual(v2.version, 2)
    XCTAssertEqual(v2.route.map(\.hexString), [
      "1011121314151617",
      "2021222324252627",
    ])
    XCTAssertEqual(v2.signature, Data(repeating: 0x55, count: 64))

    let expected = Data((0..<180).map { UInt8($0 % 6) })
    XCTAssertEqual(
      IOSMeshProtocol.decode(fixtures.bytes("packet.v1.raw_deflate"))?.payload,
      expected
    )
    XCTAssertEqual(
      IOSMeshProtocol.decode(fixtures.bytes("packet.v1.zlib_read"))?.payload,
      expected
    )
    for id in fixtures.ids(prefix: "packet.invalid.") {
      XCTAssertNil(IOSMeshProtocol.decode(fixtures.bytes(id)), id)
    }
  }

  func testCanonicalSignatureBytesUseSharedGolden() {
    var announcement = Data([0x01, 0x03])
    announcement.append(Data("bob".utf8))
    announcement.append(Data([0x02, 0x20]))
    announcement.append(Data(repeating: 0x11, count: 32))
    announcement.append(Data([0x03, 0x20]))
    announcement.append(Data(repeating: 0x22, count: 32))
    let packet = IOSMeshPacket(
      type: IOSMeshProtocol.announce,
      ttl: 7,
      timestamp: 0x0102030405060708,
      senderID: Data((0..<8).map { UInt8(0x10 + $0) }),
      payload: announcement,
      signature: Data(repeating: 0, count: 64)
    )
    let canonical = packet.canonical()

    XCTAssertEqual(canonical, fixtures.bytes("signature.canonical.v1_announce"))
    XCTAssertEqual(canonical[2], 0)
    XCTAssertEqual(
      Data(SHA256.hash(data: canonical)).hexString,
      "db232b00f54f6c161ab71e8756af799b2165d9f021cd4309aeb9ab203f2028af"
    )
  }

  func testRelayFingerprintMatchesV1AndV2WireVectors() throws {
    let vectors = [
      (
        id: "fingerprint.v1.message",
        relay16: "d2960f980cd5983d2feadf811d9109a2",
        firmware8: "d2960f980cd5983d"
      ),
      (
        id: "fingerprint.v2.route_signed",
        relay16: "988b3fd49212d7fea7a0494c68574c91",
        firmware8: "988b3fd49212d7fe"
      ),
    ]

    for vector in vectors {
      let wire = fixtures.bytes(vector.id)
      let fingerprint = try XCTUnwrap(IOSMeshProtocol.relayFingerprint(wire))
      XCTAssertEqual(fingerprint, String(vector.relay16.prefix(24)), vector.id)
      XCTAssertTrue(fingerprint.hasPrefix(vector.firmware8), vector.id)

      var normalizedVariant = wire
      normalizedVariant[2] = 1
      normalizedVariant[11] |= 0x10
      let paddingCount = 256 - normalizedVariant.count
      XCTAssertTrue((1...255).contains(paddingCount), vector.id)
      normalizedVariant.append(
        Data(repeating: UInt8(paddingCount), count: paddingCount)
      )
      XCTAssertEqual(
        IOSMeshProtocol.relayFingerprint(normalizedVariant),
        fingerprint,
        vector.id
      )
    }
  }

  func testRelayFingerprintRejectsInvalidPadding() {
    var malformed = fixtures.bytes("fingerprint.v1.message")
    malformed.append(contentsOf: [0x02, 0x01])
    XCTAssertNil(IOSMeshProtocol.relayFingerprint(malformed))
    XCTAssertNil(
      IOSMeshProtocol.relayFingerprint(fixtures.bytes("packet.invalid.padding"))
    )
  }

  func testRelayFingerprintPreservesCompressedWireRepresentation() throws {
    let rawDeflate = fixtures.bytes("packet.v1.raw_deflate")
    let zlibWrapped = fixtures.bytes("packet.v1.zlib_read")
    let rawPacket = try XCTUnwrap(IOSMeshProtocol.decode(rawDeflate))
    let zlibPacket = try XCTUnwrap(IOSMeshProtocol.decode(zlibWrapped))
    XCTAssertEqual(rawPacket.payload, zlibPacket.payload)
    XCTAssertEqual(
      IOSMeshProtocol.fingerprint(rawPacket),
      IOSMeshProtocol.fingerprint(zlibPacket)
    )

    let rawFingerprint = try XCTUnwrap(
      IOSMeshProtocol.relayFingerprint(rawDeflate)
    )
    let zlibFingerprint = try XCTUnwrap(
      IOSMeshProtocol.relayFingerprint(zlibWrapped)
    )
    XCTAssertNotEqual(rawFingerprint, zlibFingerprint)

    var expectedWire = rawDeflate
    expectedWire[2] = 0
    expectedWire[11] &= 0xef
    XCTAssertEqual(
      rawFingerprint,
      Data(SHA256.hash(data: expectedWire).prefix(12)).hexString
    )
  }

  func testFragmentsValidateLimitsAndReassembleOutOfOrder() throws {
    let valid = try XCTUnwrap(
      IOSMeshProtocol.decodeFragmentPayload(fixtures.bytes("fragment.payload.valid"))
    )
    XCTAssertEqual(valid.index, 0x0102)
    XCTAssertEqual(valid.total, 0x0304)
    XCTAssertEqual(valid.data, Data([0x55, 0x66]))
    XCTAssertNil(
      IOSMeshProtocol.decodeFragmentPayload(fixtures.bytes("fragment.invalid.total_zero"))
    )
    XCTAssertNil(
      IOSMeshProtocol.decodeFragmentPayload(
        fixtures.bytes("fragment.invalid.index_equal_total")
      )
    )

    let reassembler = IOSMeshFragmentReassembler()
    let second = try XCTUnwrap(
      IOSMeshProtocol.decode(fixtures.bytes("fragment.reassemble.out_of_order.1"))
    )
    let first = try XCTUnwrap(
      IOSMeshProtocol.decode(fixtures.bytes("fragment.reassemble.out_of_order.0"))
    )
    XCTAssertNil(reassembler.accept(second))
    let result = try XCTUnwrap(reassembler.accept(first))
    XCTAssertEqual(result.ttl, 0)
    XCTAssertEqual(result.payload, Data("abc".utf8))
  }

  func testGCSCourierAndExtensionsUseProductionParsers() throws {
    let request = try XCTUnwrap(
      IOSMeshProtocol.decodeSyncRequest(fixtures.bytes("gcs.request.two_packets"))
    )
    XCTAssertEqual(request.p, 7)
    XCTAssertEqual(request.m, 256)
    XCTAssertEqual(request.filter.hexString, "80a780")
    XCTAssertEqual(IOSMeshProtocol.decodeGCS(request), [130, 210])
    XCTAssertNil(IOSMeshProtocol.decodeSyncRequest(fixtures.bytes("gcs.invalid.p_zero")))

    let courier = try XCTUnwrap(
      IOSMeshProtocol.decodeCourierEnvelope(fixtures.bytes("courier.envelope.valid"))
    )
    XCTAssertEqual(courier.recipientTag.hexString, "81570f9c02cad65cc297a85facc44ff7")
    XCTAssertEqual(courier.expiry, 1_725_000_060_000)
    XCTAssertEqual(courier.ciphertext.count, 96)
    XCTAssertEqual(courier.copies, 4)
    XCTAssertNil(
      IOSMeshProtocol.decodeCourierEnvelope(fixtures.bytes("courier.invalid.truncated"))
    )

    XCTAssertEqual(fixtures.bytes("extension.hbt_capability.v1"), Data([0x01]))
    XCTAssertEqual(
      IOSMeshNodeRole.decodeCapability(
        fixtures.bytes("extension.node_capability.anchor")
      )?.role,
      .infraDataAnchor
    )
    let radar = try XCTUnwrap(
      IOSRadarConsentProtocol.decode(fixtures.bytes("extension.radar_grant"))
    )
    XCTAssertEqual(radar.action, IOSRadarConsentProtocol.grantAction)
    let beacon = try XCTUnwrap(
      IOSBeaconControlProtocol.decode(fixtures.bytes("extension.beacon_control.request"))
    )
    XCTAssertEqual(beacon.action, IOSBeaconControlProtocol.requestAction)
    XCTAssertEqual(beacon.flags, IOSBeaconControlProtocol.allowedFlags)
    let ranging = try XCTUnwrap(
      IOSRangingControlProtocol.decode(fixtures.bytes("extension.ranging_control.request"))
    )
    XCTAssertEqual(ranging.action, 2)
    XCTAssertEqual(ranging.technology, 4)
    XCTAssertEqual(ranging.sessionNonce, Data((0..<16).map(UInt8.init)))
    XCTAssertTrue(
      IOSMeshProtocol.supportsEmergencyAcknowledgements(
        fixtures.bytes("extension.emergency_capability.v1")
      )
    )
    XCTAssertEqual(
      IOSMeshProtocol.decodeEmergencyAcknowledgement(
        fixtures.bytes("extension.emergency_ack.v1")
      ),
      Data((0..<32).map(UInt8.init))
    )
    XCTAssertEqual(fixtures.bytes("extension.hbt_capability.canonical"), Data([1]))
    XCTAssertEqual(fixtures.bytes("extension.legacy_0x24.hbt_alias"), Data([1]))
    XCTAssertNotEqual(
      fixtures.bytes("extension.legacy_0x24.prekey_candidate"),
      Data([1])
    )
    let extensionEnvelope = try XCTUnwrap(
      IOSMeshProtocol.decodeExtensionEnvelope(fixtures.bytes("extension.envelope.hbit"))
    )
    XCTAssertEqual(extensionEnvelope.namespace, "HBIT")
    XCTAssertEqual(extensionEnvelope.subtype, 1)
    XCTAssertEqual(extensionEnvelope.payload, Data([1]))
    XCTAssertNil(
      IOSMeshProtocol.decodeExtensionEnvelope(fixtures.bytes("extension.envelope.truncated"))
    )
  }

  func testRadarConsentKeepsManualFifteenAndRenewsRescueForThirtyMinutes() {
    let firstPing: UInt64 = 1_000_000
    let secondPing = firstPing + 120_000
    let rescueConsent = IOSRadarConsentProtocol.Consent(
      action: IOSRadarConsentProtocol.grantAction,
      expiresAt: firstPing + IOSRadarConsentProtocol.sosDurationMilliseconds,
      nonce: Data(repeating: 1, count: IOSRadarConsentProtocol.nonceSize)
    )

    XCTAssertEqual(IOSRadarConsentProtocol.manualDurationMilliseconds, 15 * 60 * 1_000)
    XCTAssertEqual(IOSRadarConsentProtocol.sosDurationMilliseconds, 30 * 60 * 1_000)
    XCTAssertTrue(
      IOSRadarConsentProtocol.isValidGrant(
        rescueConsent,
        packetTimestamp: firstPing,
        now: firstPing
      )
    )
    XCTAssertEqual(
      IOSRadarConsentProtocol.sosConsentExpiresAt(
        packetTimestamp: firstPing,
        now: firstPing
      ),
      firstPing + 30 * 60 * 1_000
    )
    XCTAssertEqual(
      IOSRadarConsentProtocol.sosConsentExpiresAt(
        packetTimestamp: secondPing,
        now: secondPing
      ),
      secondPing + 30 * 60 * 1_000
    )
  }

  func testRadarRssiReportKeepsSignedValueTimestampAndFreshness() throws {
    let now: UInt64 = 10_000_000
    let payload = try XCTUnwrap(
      IOSRadarConsentProtocol.rssiReport(rssi: -67, measuredAt: now)
    )
    let report = try XCTUnwrap(IOSRadarConsentProtocol.decodeRssiReport(payload))

    XCTAssertEqual(payload.count, IOSRadarConsentProtocol.rssiReportPayloadSize)
    XCTAssertEqual(report.rssi, -67)
    XCTAssertEqual(report.measuredAt, now)
    XCTAssertEqual(report.nonce.count, IOSRadarConsentProtocol.nonceSize)
    XCTAssertTrue(
      IOSRadarConsentProtocol.isValidReport(
        report,
        packetTimestamp: now,
        now: now
      )
    )
    XCTAssertNil(
      IOSRadarConsentProtocol.decodeRssiReport(Data(payload.prefix(5)))
    )
    XCTAssertFalse(
      IOSRadarConsentProtocol.isValidReport(
        report,
        packetTimestamp: now - IOSRadarConsentProtocol.clockSkewMilliseconds - 1,
        now: now
      )
    )
  }

  func testRescueDefaultIntervalMatchesMethodChannelContract() {
    XCTAssertEqual(IOSRescueModeStore.defaultInterval, 300_000)
  }

  func testRadarConsentSOSExpirySaturatesTimestampOverflow() {
    let now: UInt64 = 10_000_000
    XCTAssertEqual(
      IOSRadarConsentProtocol.sosConsentExpiresAt(
        packetTimestamp: UInt64.max - IOSRadarConsentProtocol.sosDurationMilliseconds + 1,
        now: now
      ),
      now + IOSRadarConsentProtocol.sosDurationMilliseconds
    )
    XCTAssertEqual(
      IOSRadarConsentProtocol.sosConsentExpiresAt(
        packetTimestamp: UInt64.max,
        now: UInt64.max
      ),
      UInt64.max
    )
    XCTAssertTrue(IOSRadarConsentProtocol.hasValidTimestamp(UInt64.max, now: UInt64.max))
  }

  func testHBTUsesProductionCodecWithPositiveAndNegativeFixtures() throws {
    let offer = try XCTUnwrap(HBTransferFrame.decode(fixtures.bytes("hbt.offer.v1")))
    XCTAssertEqual(offer.type, HBTransferProtocol.typeOffer)
    XCTAssertEqual(offer.utf8(HBTransferProtocol.tagFileName), "foto.jpg")
    XCTAssertEqual(offer.u64(HBTransferProtocol.tagFileSize), 1_048_576)
    XCTAssertEqual(offer.signedBytes(), fixtures.bytes("hbt.offer.signed_bytes"))

    let chunk = try XCTUnwrap(HBTransferFrame.decode(fixtures.bytes("hbt.chunk.v1")))
    XCTAssertEqual(chunk.u32(HBTransferProtocol.tagChunkIndex), 3)
    XCTAssertEqual(chunk.tags[HBTransferProtocol.tagChunkData], Data([0xde, 0xad, 0xbe, 0xef]))
    XCTAssertNil(HBTransferFrame.decode(fixtures.bytes("hbt.invalid.version")))
    XCTAssertNil(HBTransferFrame.decode(fixtures.bytes("hbt.invalid.truncated")))
  }

  func testManifestPinsUpstreamCommit() {
    XCTAssertEqual(
      fixtures.upstreamCommit,
      "5156f7de89ec9f6a3429630d90f709b68f6fd7fd"
    )
  }

  func testNoiseReplayPolicyRejectsPreviousTransportEpoch() {
    XCTAssertTrue(
      IOSNoiseReplayPolicy.isCurrent(
        packetTimestamp: 100,
        latestAnnouncementTimestamp: nil
      )
    )
    XCTAssertFalse(
      IOSNoiseReplayPolicy.isCurrent(
        packetTimestamp: 99,
        latestAnnouncementTimestamp: 100
      )
    )
    XCTAssertTrue(
      IOSNoiseReplayPolicy.isCurrent(
        packetTimestamp: 100,
        latestAnnouncementTimestamp: 100
      )
    )
  }

  func testStoreForwardNeverPersistsNoiseState() {
    let handshake = IOSMeshPacket(
      type: IOSMeshProtocol.noiseHandshake,
      ttl: 7,
      timestamp: 100,
      senderID: sender,
      recipientID: Data(repeating: 0x22, count: 8),
      payload: Data(repeating: 0x33, count: 32)
    )
    let encrypted = IOSMeshPacket(
      type: IOSMeshProtocol.noiseEncrypted,
      ttl: 7,
      timestamp: 101,
      senderID: sender,
      recipientID: Data(repeating: 0x22, count: 8),
      payload: Data([0x44])
    )
    let message = IOSMeshPacket(
      type: IOSMeshProtocol.message,
      ttl: 7,
      timestamp: 102,
      senderID: sender,
      payload: Data("rescate".utf8)
    )

    XCTAssertFalse(IOSNoiseReplayPolicy.isStoreForwardSafe(handshake))
    XCTAssertFalse(IOSNoiseReplayPolicy.isStoreForwardSafe(encrypted))
    XCTAssertTrue(IOSNoiseReplayPolicy.isStoreForwardSafe(message))
  }

  func testRangingControlProtocolDecodesValidEnvelope() {
    var payload = Data(repeating: 0, count: IOSRangingControlProtocol.fixedSize)
    payload[0] = IOSRangingControlProtocol.version
    payload[1] = 7
    payload[2] = 4
    payload[3] = 2
    for index in 0..<IOSRangingControlProtocol.nonceSize {
      payload[4 + index] = UInt8(index)
    }

    let control = IOSRangingControlProtocol.decode(payload)

    XCTAssertEqual(control?.action, 7)
    XCTAssertEqual(control?.technology, 4)
    XCTAssertEqual(control?.sessionNonce, Data((0..<16).map(UInt8.init)))
    XCTAssertNil(IOSRangingControlProtocol.decode(payload.dropLast()))
    XCTAssertTrue(IOSRangingControlProtocol.hasValidTimestamp(1_000, now: 1_000))
    XCTAssertFalse(IOSRangingControlProtocol.hasValidTimestamp(1, now: 200_000))
  }
}

private final class ConformanceFixtures {
  struct Manifest: Decodable {
    let upstreamCommit: String
    let fixtures: [Entry]
  }

  struct Entry: Decodable {
    let id: String
    let blob: String
  }

  static let shared = ConformanceFixtures()

  let upstreamCommit: String
  private let root: URL
  private let entries: [String: Entry]

  private init() {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { repository.deleteLastPathComponent() }
    root = repository.appendingPathComponent("tests/conformance")
    let manifestData = try! Data(
      contentsOf: root.appendingPathComponent("fixtures.v1.json")
    )
    let manifest = try! JSONDecoder().decode(Manifest.self, from: manifestData)
    upstreamCommit = manifest.upstreamCommit
    entries = Dictionary(uniqueKeysWithValues: manifest.fixtures.map { ($0.id, $0) })
  }

  func bytes(_ id: String) -> Data {
    let entry = entries[id]!
    let text = try! String(
      contentsOf: root.appendingPathComponent(entry.blob),
      encoding: .ascii
    )
    let hex = text.filter { !$0.isWhitespace }
    precondition(hex.count.isMultiple(of: 2), "Hex impar en \(id)")
    var output = Data()
    output.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      output.append(UInt8(hex[index..<next], radix: 16)!)
      index = next
    }
    return output
  }

  func ids(prefix: String) -> [String] {
    entries.keys.filter { $0.hasPrefix(prefix) }.sorted()
  }
}

private extension Data {
  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}

private final class TestSecurePinBackend {
  var data: Data?
  private let suiteName: String
  private let defaults: UserDefaults

  init() {
    let name = "HearthBit.PeerPinTests.\(UUID().uuidString)"
    suiteName = name
    defaults = UserDefaults(suiteName: name)!
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func makeStore() -> IOSPeerIdentityPinStore {
    IOSPeerIdentityPinStore(
      defaults: defaults,
      read: { [weak self] in
        guard let data = self?.data else { return .missing }
        return .value(data)
      },
      upsert: { [weak self] data in
        self?.data = data
      },
      delete: { [weak self] in
        self?.data = nil
      }
    )
  }
}

/// Grabador thread-safe de eventos emitidos por el transporte Wi-Fi Aware.
private final class TransferEventRecorder {
  private let lock = NSLock()
  private var storage: [[String: Any]] = []

  func record(_ event: [String: Any]) {
    lock.lock()
    storage.append(event)
    lock.unlock()
  }

  var events: [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

final class WiFiAwareTransportTests: XCTestCase {
  // MARK: Gating de capacidades

  func testComputeSupportRequiresAllGates() {
    XCTAssertTrue(
      HearthBitWiFiAwareTransport.computeSupport(
        osAvailable: true,
        hardwareSupported: true,
        servicePublishable: true,
        serviceSubscribable: true,
        entitlementPresent: true
      )
    )
    for missingGate in 0..<5 {
      XCTAssertFalse(
        HearthBitWiFiAwareTransport.computeSupport(
          osAvailable: missingGate != 0,
          hardwareSupported: missingGate != 1,
          servicePublishable: missingGate != 2,
          serviceSubscribable: missingGate != 3,
          entitlementPresent: missingGate != 4
        ),
        "El gate \(missingGate) en false debe desactivar el soporte"
      )
    }
  }

  func testServiceNameMatchesAndroidService() {
    // Android publica `hearthbit-hbt`; en iOS el nombre RFC 6763 completo
    // lleva prefijo `_` y sufijo `._tcp`.
    XCTAssertEqual(HearthBitWiFiAwareTransport.serviceName, "_hearthbit-hbt._tcp")
  }

  func testSimulatorReportsUnsupported() throws {
    #if targetEnvironment(simulator)
      // La radio Wi-Fi Aware no existe en el simulador: el gating completo
      // debe reportar false y el canal Dart caer a LAN/BLE.
      XCTAssertFalse(HearthBitWiFiAwareTransport.isSupported)
    #else
      throw XCTSkip("Solo aplica al simulador")
    #endif
  }

  // MARK: Framing compatible con Android

  func testLengthHeaderIsBigEndianEightBytes() {
    let header = HearthBitWiFiAwareTransport.encodeLengthHeader(0x0102_0304_0506_0708)
    XCTAssertEqual([UInt8](header), [1, 2, 3, 4, 5, 6, 7, 8])
    XCTAssertEqual(
      [UInt8](HearthBitWiFiAwareTransport.encodeLengthHeader(0)),
      [0, 0, 0, 0, 0, 0, 0, 0]
    )
  }

  func testLengthHeaderRoundTrip() {
    for length: UInt64 in [0, 1, 255, 256, 65_535, 0xFFFF_FFFF, .max] {
      let encoded = HearthBitWiFiAwareTransport.encodeLengthHeader(length)
      XCTAssertEqual(encoded.count, 8)
      XCTAssertEqual(HearthBitWiFiAwareTransport.decodeLengthHeader(encoded), length)
    }
  }

  func testLengthHeaderRejectsWrongSizes() {
    XCTAssertNil(HearthBitWiFiAwareTransport.decodeLengthHeader(Data()))
    XCTAssertNil(HearthBitWiFiAwareTransport.decodeLengthHeader(Data(count: 7)))
    XCTAssertNil(HearthBitWiFiAwareTransport.decodeLengthHeader(Data(count: 9)))
  }

  // MARK: Contrato de eventos con Dart

  func testEventContractMatchesDartKeys() {
    let progress = HearthBitWiFiAwareTransport.progressEvent(
      transferId: "t1",
      bytes: 42
    )
    XCTAssertEqual(progress["type"] as? String, "wifiAwareProgress")
    XCTAssertEqual(progress["transferId"] as? String, "t1")
    XCTAssertEqual(progress["bytes"] as? Int, 42)
    XCTAssertEqual(progress.count, 3)

    let done = HearthBitWiFiAwareTransport.doneEvent(transferId: "t2")
    XCTAssertEqual(done["type"] as? String, "wifiAwareDone")
    XCTAssertEqual(done["transferId"] as? String, "t2")
    XCTAssertEqual(done.count, 2)

    let failure = HearthBitWiFiAwareTransport.errorEvent(
      transferId: "t3",
      message: "boom"
    )
    XCTAssertEqual(failure["type"] as? String, "wifiAwareError")
    XCTAssertEqual(failure["transferId"] as? String, "t3")
    XCTAssertEqual(failure["message"] as? String, "boom")
    XCTAssertEqual(failure.count, 3)
  }

  // MARK: Comportamiento sin soporte (simulador / iOS < 26)

  func testUnsupportedSendAndReceiveEmitErrorWithoutTasks() throws {
    guard !HearthBitWiFiAwareTransport.isSupported else {
      throw XCTSkip("El dispositivo soporta Wi-Fi Aware; este caso cubre el fallback")
    }
    let recorder = TransferEventRecorder()
    let transport = HearthBitWiFiAwareTransport(
      emit: recorder.record,
      observeBackground: false
    )
    transport.sendFile(transferId: "send-1", filePath: "/tmp/none.hbt")
    transport.receiveFile(transferId: "recv-1", destinationPath: "/tmp/out.hbt")

    let events = recorder.events
    XCTAssertEqual(events.count, 2)
    XCTAssertTrue(events.allSatisfy { ($0["type"] as? String) == "wifiAwareError" })
    XCTAssertEqual(events.first?["transferId"] as? String, "send-1")
    XCTAssertEqual(events.last?["transferId"] as? String, "recv-1")
    XCTAssertTrue(transport.activeTransferIds.isEmpty)
  }

  // MARK: Lifecycle y cancelación

  func testStopCancelsOperationWithoutFurtherEvents() {
    let recorder = TransferEventRecorder()
    let transport = HearthBitWiFiAwareTransport(
      emit: recorder.record,
      observeBackground: false
    )
    let started = expectation(description: "operación iniciada")
    let cancelled = expectation(description: "operación cancelada")
    transport.startTransferOperation(transferId: "t1") {
      started.fulfill()
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      cancelled.fulfill()
    }
    wait(for: [started], timeout: 5)
    XCTAssertEqual(transport.activeTransferIds, ["t1"])

    transport.stop(transferId: "t1")
    wait(for: [cancelled], timeout: 5)
    XCTAssertTrue(transport.activeTransferIds.isEmpty)
    // stop() no debe producir eventos posteriores hacia Dart.
    XCTAssertTrue(recorder.events.isEmpty)
  }

  func testStopUnknownTransferIsNoOp() {
    let recorder = TransferEventRecorder()
    let transport = HearthBitWiFiAwareTransport(
      emit: recorder.record,
      observeBackground: false
    )
    transport.stop(transferId: "missing")
    XCTAssertTrue(recorder.events.isEmpty)
    XCTAssertTrue(transport.activeTransferIds.isEmpty)
  }

  func testCancelAllTransfersEmitsOneErrorPerActiveTransfer() {
    let recorder = TransferEventRecorder()
    let transport = HearthBitWiFiAwareTransport(
      emit: recorder.record,
      observeBackground: false
    )
    let startedA = expectation(description: "A iniciada")
    let startedB = expectation(description: "B iniciada")
    transport.startTransferOperation(transferId: "a") {
      startedA.fulfill()
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
    }
    transport.startTransferOperation(transferId: "b") {
      startedB.fulfill()
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
    }
    wait(for: [startedA, startedB], timeout: 5)
    XCTAssertEqual(Set(transport.activeTransferIds), ["a", "b"])

    transport.cancelAllTransfers(reason: "wifi_aware_background")
    XCTAssertTrue(transport.activeTransferIds.isEmpty)

    let events = recorder.events
    XCTAssertEqual(events.count, 2)
    XCTAssertTrue(events.allSatisfy { ($0["type"] as? String) == "wifiAwareError" })
    XCTAssertTrue(
      events.allSatisfy { ($0["message"] as? String) == "wifi_aware_background" }
    )
    XCTAssertEqual(
      Set(events.compactMap { $0["transferId"] as? String }),
      ["a", "b"]
    )

    // Sin transferencias activas, cancelar de nuevo no emite nada.
    transport.cancelAllTransfers(reason: "wifi_aware_background")
    XCTAssertEqual(recorder.events.count, 2)
  }

  // MARK: Stream handler del canal de eventos

  func testTransferEventHandlerForwardsOnlyWhileListening() {
    let handler = HearthBitTransferEventHandler()
    var received: [Any?] = []

    // Sin listener: los eventos se descartan sin fallar.
    handler.emit(HearthBitTransferProtocolTestSupport.sampleEvent(id: "drop"))

    XCTAssertNil(
      handler.onListen(withArguments: nil) { event in
        received.append(event)
      }
    )
    handler.emit(HearthBitTransferProtocolTestSupport.sampleEvent(id: "live"))
    XCTAssertEqual(received.count, 1)
    let event = received.first as? [String: Any]
    XCTAssertEqual(event?["transferId"] as? String, "live")

    XCTAssertNil(handler.onCancel(withArguments: nil))
    handler.emit(HearthBitTransferProtocolTestSupport.sampleEvent(id: "late"))
    XCTAssertEqual(received.count, 1)
  }
}

/// Utilidades compartidas por las pruebas del canal de transferencias.
private enum HearthBitTransferProtocolTestSupport {
  static func sampleEvent(id: String) -> [String: Any] {
    HearthBitWiFiAwareTransport.doneEvent(transferId: id)
  }
}
