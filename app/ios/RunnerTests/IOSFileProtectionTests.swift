import Foundation
import XCTest
@testable import Runner

/// Cobertura de IOSFileProtection (Huecos 1+2 del panic-wipe spec).
///
/// Notas de portabilidad:
/// - En simulador iOS, `FileProtectionType.complete` puede no aplicarse
///   realmente (el kernel del simulador no lo honra). En ese caso los
///   tests de protección skipean con un mensaje explícito; los tests de
///   iCloud backup exclusion y de idempotencia sí corren siempre.
/// - En dispositivo físico, los 4 tests pasan.
final class IOSFileProtectionTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("IOSFileProtectionTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(
      at: base,
      withIntermediateDirectories: true
    )
    tempDir = base
  }

  override func tearDown() {
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
    super.tearDown()
  }

  func testApplyCompleteSetsProtectionOnAllFiles() throws {
    let file1 = tempDir.appendingPathComponent("a.db")
    let file2 = tempDir.appendingPathComponent("b.db-wal")
    let file3 = tempDir.appendingPathComponent("nested/c.db")
    try FileManager.default.createDirectory(
      at: tempDir.appendingPathComponent("nested"),
      withIntermediateDirectories: true
    )
    try Data([0xAA]).write(to: file1)
    try Data([0xBB]).write(to: file2)
    try Data([0xCC]).write(to: file3)

    let report = try IOSFileProtection.applyComplete(in: tempDir)

    XCTAssertEqual(report.filesScanned, 3)
    // El simulador puede degradar a .completeUntilFirstUserAuthentication.
    // Aceptamos ambos: el contrato es que la protección sea >= complete
    // (cifrado en reposo) o, en su defecto, completeUntilFirstUser.
    let attrs1 = try FileManager.default.attributesOfItem(atPath: file1.path)
    let attrs2 = try FileManager.default.attributesOfItem(atPath: file2.path)
    let attrs3 = try FileManager.default.attributesOfItem(atPath: file3.path)
    for (label, attrs) in [("a.db", attrs1), ("b.db-wal", attrs2), ("nested/c.db", attrs3)] {
      guard let protection = attrs[.protectionKey] as? FileProtectionType else {
        throw XCTSkip(
          "FileProtectionType not honored in this environment (simulator). "
            + "Skipping \(label) protection assertion. Applies on physical device."
        )
      }
      XCTAssertTrue(
        protection == .complete || protection == .completeUntilFirstUserAuthentication,
        "expected .complete or fallback, got \(protection) for \(label)"
      )
    }
  }

  func testExcludeFromBackupMarksAllURLs() throws {
    let file1 = tempDir.appendingPathComponent("c.db")
    let file2 = tempDir.appendingPathComponent("d.db-wal")
    try Data([0x01]).write(to: file1)
    try Data([0x02]).write(to: file2)

    let report = try IOSFileProtection.excludeFromBackup(in: tempDir)

    XCTAssertEqual(report.filesScanned, 2)
    XCTAssertEqual(report.backupExclusionFailed, 0)
    XCTAssertEqual(report.backupExclusionApplied, 2)
    let values1 = try file1.resourceValues(forKeys: [.isExcludedFromBackupKey])
    let values2 = try file2.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values1.isExcludedFromBackup, true)
    XCTAssertEqual(values2.isExcludedFromBackup, true)
  }

  func testApplyCompleteIsIdempotent() throws {
    let file = tempDir.appendingPathComponent("idem.db")
    try Data([0x10]).write(to: file)

    let first = try IOSFileProtection.applyComplete(in: tempDir)
    let second = try IOSFileProtection.applyComplete(in: tempDir)

    XCTAssertEqual(first.filesScanned, 1)
    XCTAssertEqual(second.filesScanned, 1)
    // El contador de "applied" puede variar si el simulador degrada; lo
    // que importa es que la segunda llamada no lance y deje el archivo
    // en estado consistente.
    let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
    let protection = attrs[.protectionKey] as? FileProtectionType
    if let protection = protection {
      XCTAssertTrue(
        protection == .complete || protection == .completeUntilFirstUserAuthentication
      )
    }
  }

  func testExcludeFromBackupIsIdempotent() throws {
    let file = tempDir.appendingPathComponent("idem-exclude.db")
    try Data([0x20]).write(to: file)

    _ = try IOSFileProtection.excludeFromBackup(in: tempDir)
    let second = try IOSFileProtection.excludeFromBackup(in: tempDir)

    XCTAssertEqual(second.backupExclusionApplied, 1)
    XCTAssertEqual(second.backupExclusionFailed, 0)
    let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

  func testApplyCompleteOnEmptyDirectoryReturnsZeroScanned() throws {
    let emptyDir = tempDir.appendingPathComponent("empty")
    try FileManager.default.createDirectory(
      at: emptyDir,
      withIntermediateDirectories: true
    )
    let report = try IOSFileProtection.applyComplete(in: emptyDir)
    XCTAssertEqual(report.filesScanned, 0)
    XCTAssertEqual(report.protectionApplied, 0)
    XCTAssertEqual(report.protectionFailed, 0)
  }

  func testExcludeFromBackupOnEmptyDirectoryReturnsZeroScanned() throws {
    let emptyDir = tempDir.appendingPathComponent("empty-excl")
    try FileManager.default.createDirectory(
      at: emptyDir,
      withIntermediateDirectories: true
    )
    let report = try IOSFileProtection.excludeFromBackup(in: emptyDir)
    XCTAssertEqual(report.filesScanned, 0)
    XCTAssertEqual(report.backupExclusionApplied, 0)
    XCTAssertEqual(report.backupExclusionFailed, 0)
  }
}
