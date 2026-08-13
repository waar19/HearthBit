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
}

private extension Data {
  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
