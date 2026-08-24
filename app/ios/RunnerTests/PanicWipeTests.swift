import Foundation
import Security
import XCTest
@testable import Runner

/// Cobertura de `IOSPanicWipe` (Hueco 5 del panic-wipe spec, sección
/// "Hueco 8 — Tests iOS dedicados" del spec
/// `2026-08-24-panic-wipe-sqlite-cipher-design.md`).
///
/// 4 tests como pide el spec:
/// 1. `testKeychainCleared` — N items en Keychain → `panicWipe` →
///    `SecItemCopyMatching` devuelve `errSecItemNotFound` por cuenta.
/// 2. `testFilesRemoved` — archivos en 4 dirs (App Support / Documents
///    / Caches / tmp) → `panicWipe` → cada dir queda vacío.
/// 3. `testIdempotent` — dos invocaciones seguidas, la segunda no
///    lanza y deja el mismo estado final.
/// 4. `testOrderingKeychainBeforeFiles` — `SecItemDelete` ocurre
///    antes de `FileManager.removeItem` (consistencia con el orden
///    de `MeshEngine.panicWipe` en Android).
///
/// Notas de portabilidad:
/// - Los tests del Keychain usan `kSecAttrService` único por test
///   (`com.hearthbit.tests.panic-wipe.<UUID>`) para evitar colisiones
///   entre runs y para que el `SecItemDelete` global del helper no
///   afecte a items legítimos del runner.
/// - Los tests de `UserDefaults` no verifican contenido del bundle
///   real del Runner; usan un `UserDefaults(suiteName:)` inyectado
///   para mantener el sistema en estado controlado.
/// - En simulador, `removeAllCachedResponses` se ejecuta pero no
///   podemos inspeccionar el cache limpiado; el test verifica que
///   la operación no lanza y aparece en el orden canónico.
final class PanicWipeTests: XCTestCase {
  /// Servicio único por test para no contaminar el Keychain global
  /// del RunnerTests target ni depender de items preexistentes.
  private var keychainService: String!
  private var tempRoot: URL!
  /// UserDefaults de suite aislada — no tocamos `.standard` para no
  /// interferir con el resto del test bundle.
  private var isolatedDefaults: UserDefaults!
  private var isolatedDefaultsSuiteName: String!

  override func setUp() {
    super.setUp()
    keychainService = "com.hearthbit.tests.panic-wipe.\(UUID().uuidString)"
    tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("PanicWipeTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(
      at: tempRoot,
      withIntermediateDirectories: true
    )
    isolatedDefaultsSuiteName = "com.hearthbit.tests.panic-wipe.\(UUID().uuidString)"
    isolatedDefaults = UserDefaults(suiteName: isolatedDefaultsSuiteName)
  }

  override func tearDown() {
    // Limpieza best-effort: borrar todos los items del Keychain que
    // hayamos podido dejar por errores de assertion intermedios.
    if let service = keychainService {
      let cleanup: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
      ]
      SecItemDelete(cleanup as CFDictionary)
    }
    if let root = tempRoot {
      try? FileManager.default.removeItem(at: root)
    }
    if let suiteName = isolatedDefaultsSuiteName {
      UserDefaults().removePersistentDomain(forName: suiteName)
    }
    super.tearDown()
  }

  // MARK: - Test 1: Keychain wipe

  /// Inserta 3 items en el Keychain, invoca el wipe, y verifica que
  /// `SecItemCopyMatching` devuelve `errSecItemNotFound` para cada uno.
  /// El helper hace `SecItemDelete` con solo `kSecClass`, así que la
  /// aserción es que TODA la clase queda vacía (cualquier service).
  func testKeychainCleared() throws {
    // Setup: insertar 3 items en el Keychain con un service único.
    let accounts = ["alpha", "bravo", "charlie"]
    for account in accounts {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: account,
        kSecValueData as String: Data("v-\(account)".utf8),
      ]
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      XCTAssertEqual(
        addStatus, errSecSuccess,
        "Setup failed: could not insert Keychain item \(account) (OSStatus \(addStatus))"
      )
    }
    // Sanity check: cada item debe existir antes del wipe.
    for account in accounts {
      let lookup: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: AnyObject?
      let preStatus = SecItemCopyMatching(lookup as CFDictionary, &result)
      XCTAssertEqual(preStatus, errSecSuccess, "Pre-wipe lookup failed for \(account)")
    }

    // Action: invocar el wipe nativo. Inyectamos `filesDirectories`
    // para que el helper NO toque los directorios reales del app
    // data dir (aislamiento). El bundle id para UserDefaults
    // también es el suite aislado.
    var observedOrder: [IOSPanicWipe.Step] = []
    let report = IOSPanicWipe.wipe(
      fileManager: FileManager.default,
      userDefaults: isolatedDefaults,
      urlCache: URLCache.shared,
      bundleIdentifier: "com.hearthbit.tests.panic-wipe.ignored",
      keychainClasses: [kSecClassGenericPassword],
      filesDirectories: [tempRoot],
      orderRecorder: { step in observedOrder.append(step) }
    )

    // Assert: el helper tocó 1 clase de Keychain.
    XCTAssertEqual(report.keychainClassesDeleted, 1)
    XCTAssertTrue(report.userDefaultsRemoved)
    XCTAssertGreaterThanOrEqual(report.filesRemoved, 0)
    XCTAssertTrue(report.urlCacheCleared)
    XCTAssertEqual(observedOrder.count, 4)

    // Assert: cada item del Keychain debe haber sido borrado. Como
    // el helper hace `SecItemDelete([kSecClass: kSecClassGenericPassword])`
    // (sin service), también borraría items con otros services del
    // test bundle. Lo que nos importa contractualmente es que NUESTROS
    // items desaparezcan.
    for account in accounts {
      let lookup: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: AnyObject?
      let postStatus = SecItemCopyMatching(lookup as CFDictionary, &result)
      XCTAssertEqual(
        postStatus, errSecItemNotFound,
        "Post-wipe Keychain item \(account) should be gone, got OSStatus \(postStatus)"
      )
    }
  }

  // MARK: - Test 2: Files wipe

  /// Crea archivos en 4 directorios (análogos a Application Support,
  /// Documents, Caches, tmp), invoca el wipe, y verifica que cada
  /// directorio queda vacío.
  func testFilesRemoved() throws {
    let fm = FileManager.default
    let dirNames = ["appSupport", "documents", "caches", "tmp"]
    var dirs: [URL] = []
    for name in dirNames {
      let dir = tempRoot.appendingPathComponent(name)
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      // Crear 2 archivos por directorio (total 8 archivos wipeados).
      for i in 0..<2 {
        let file = dir.appendingPathComponent("file-\(i).db")
        try Data([UInt8(i)]).write(to: file)
      }
      // Crear un subdirectorio anidado (también debe ser wipeado por
      // removeItem del dir padre).
      let nested = dir.appendingPathComponent("nested")
      try fm.createDirectory(at: nested, withIntermediateDirectories: true)
      try Data([0xAA]).write(to: nested.appendingPathComponent("nested.db"))
      dirs.append(dir)
    }

    // Sanity: cada dir tiene contenido antes del wipe.
    for dir in dirs {
      let contents = try fm.contentsOfDirectory(atPath: dir.path)
      XCTAssertFalse(contents.isEmpty, "Setup failed: \(dir.lastPathComponent) is empty")
    }

    // Action: wipe con los 4 dirs inyectados.
    let report = IOSPanicWipe.wipe(
      fileManager: fm,
      userDefaults: isolatedDefaults,
      urlCache: URLCache.shared,
      bundleIdentifier: nil,  // No tocamos UserDefaults en este test.
      keychainClasses: [],    // No tocamos Keychain en este test.
      filesDirectories: dirs
    )

    // Assert: los 4 dirs fueron borrados y recreados vacíos.
    XCTAssertEqual(report.filesRemoved, dirs.count)
    for dir in dirs {
      let contents = try fm.contentsOfDirectory(atPath: dir.path)
      XCTAssertTrue(
        contents.isEmpty,
        "Directory \(dir.lastPathComponent) should be empty post-wipe, has: \(contents)"
      )
    }
    // Como no pasamos bundle id ni keychain classes, esos contadores
    // reflejan la no-acción.
    XCTAssertEqual(report.keychainClassesDeleted, 0)
    XCTAssertFalse(report.userDefaultsRemoved)
    XCTAssertTrue(report.urlCacheCleared)
  }

  // MARK: - Test 3: Idempotency

  /// Invoca el wipe dos veces seguidas. La segunda invocación no
  /// debe lanzar y debe dejar el sistema en el mismo estado final
  /// (directorios vacíos, sin items en Keychain).
  func testIdempotent() throws {
    let fm = FileManager.default
    let dir = tempRoot.appendingPathComponent("idem-dir")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data([0x01, 0x02]).write(to: dir.appendingPathComponent("first.db"))

    // Primer wipe.
    let firstReport = IOSPanicWipe.wipe(
      fileManager: fm,
      userDefaults: isolatedDefaults,
      urlCache: URLCache.shared,
      bundleIdentifier: nil,
      keychainClasses: [kSecClassGenericPassword],
      filesDirectories: [dir]
    )
    XCTAssertEqual(firstReport.filesRemoved, 1)
    XCTAssertTrue(
      (try fm.contentsOfDirectory(atPath: dir.path)).isEmpty,
      "First wipe should leave the dir empty"
    )

    // Segundo wipe sobre el mismo dir (ya vacío y recreado).
    let secondReport = IOSPanicWipe.wipe(
      fileManager: fm,
      userDefaults: isolatedDefaults,
      urlCache: URLCache.shared,
      bundleIdentifier: nil,
      keychainClasses: [kSecClassGenericPassword],
      filesDirectories: [dir]
    )
    // El dir ya estaba vacío antes de la segunda invocación: el
    // helper lo borra igual (existe) y lo recrea. Como existe, el
    // contador sube a 1. Lo importante es que no lance.
    XCTAssertEqual(secondReport.filesRemoved, 1)
    XCTAssertEqual(secondReport.keychainClassesDeleted, 1)
    XCTAssertTrue(
      (try fm.contentsOfDirectory(atPath: dir.path)).isEmpty,
      "Second wipe should leave the dir empty"
    )
    // UserDefaults: como no pasamos bundleIdentifier, no se intenta
    // removePersistentDomain. El test 1 y 2 ya cubren ese path.
    XCTAssertFalse(secondReport.userDefaultsRemoved)
  }

  // MARK: - Test 4: Ordering (Keychain antes de Files)

  /// Verifica que el orden canónico se cumple: Keychain → UserDefaults
  /// → Files → URLCache. El contrato crítico (consistencia con
  /// Android) es Keychain ANTES de Files, para que un crash mid-wipe
  /// deje los datos viejos sin acceso vía Keychain antes de tocar el
  /// filesystem.
  func testOrderingKeychainBeforeFiles() throws {
    // Setup: insertar un item en el Keychain + un archivo en el dir.
    let keychainQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: "ordering-test",
      kSecValueData as String: Data("ordering".utf8),
    ]
    let addStatus = SecItemAdd(keychainQuery as CFDictionary, nil)
    XCTAssertEqual(addStatus, errSecSuccess, "Setup: Keychain insert failed")

    let dir = tempRoot.appendingPathComponent("ordering-dir")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data([0x99]).write(to: dir.appendingPathComponent("ordering.db"))

    // Action: wipe con recorder.
    var observedOrder: [IOSPanicWipe.Step] = []
    _ = IOSPanicWipe.wipe(
      fileManager: FileManager.default,
      userDefaults: isolatedDefaults,
      urlCache: URLCache.shared,
      bundleIdentifier: "com.hearthbit.tests.panic-wipe.ignored",
      keychainClasses: [kSecClassGenericPassword],
      filesDirectories: [dir],
      orderRecorder: { step in observedOrder.append(step) }
    )

    // Assert: orden canónico.
    XCTAssertEqual(
      observedOrder,
      [.keychain, .userDefaults, .files, .urlCache],
      "Wipe order must be Keychain → UserDefaults → Files → URLCache"
    )
    // Assert específico de Hueco 5: Keychain antes de Files.
    let keychainIndex = observedOrder.firstIndex(of: .keychain)
    let filesIndex = observedOrder.firstIndex(of: .files)
    XCTAssertNotNil(keychainIndex, "Keychain step not recorded")
    XCTAssertNotNil(filesIndex, "Files step not recorded")
    XCTAssertLessThan(
      keychainIndex!, filesIndex!,
      "Keychain wipe must happen before file wipe (consistency with Android)"
    )
  }
}
