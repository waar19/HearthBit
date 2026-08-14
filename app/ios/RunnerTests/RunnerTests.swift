import CoreBluetooth
import Flutter
import Foundation
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  private let sender = Data([1, 2, 3, 4, 5, 6, 7, 8])
  private let fragmentID = Data([9, 8, 7, 6, 5, 4, 3, 2])

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
      ttl: 1,
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
    XCTAssertEqual(decoded.ttl, 1)
    XCTAssertNotNil(decoded.recipientID)
    XCTAssertNotNil(decoded.signature)
    XCTAssertFalse(IOSNoiseReplayPolicy.isStoreForwardSafe(decoded))
    XCTAssertFalse(
      IOSBeaconControlProtocol.shouldAutoAccept(localRadarConsentUntil: now, now: now)
    )
    XCTAssertTrue(
      IOSBeaconControlProtocol.shouldAutoAccept(localRadarConsentUntil: now + 1, now: now)
    )
  }
}

final class ConformanceFixtureTests: XCTestCase {
  private let fixtures = ConformanceFixtures.shared

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
