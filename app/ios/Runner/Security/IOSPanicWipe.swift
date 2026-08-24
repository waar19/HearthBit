import Foundation

/// Encapsula el wipe nativo exhaustivo del panic-wipe spec
/// (`docs/superpowers/specs/2026-08-24-panic-wipe-sqlite-cipher-design.md`,
/// sección "Hueco 5"). Cubre los 4 stores persistentes del sistema:
///
/// 1. **Keychain** — `SecItemDelete` para `kSecClassGenericPassword`,
///    `kSecClassInternetPassword` y `kSecClassCertificate`. La clave
///    se va ANTES que los datos, por consistencia con el orden del
///    `MeshEngine.panicWipe` de Android (Task 3).
/// 2. **UserDefaults** del bundle id — claves nativas que Dart no
///    maneja (p. ej. `IOSRadarConsentProtocol.localConsentKey`).
/// 3. **Archivos** en Application Support, Documents, Caches y
///    `tmp/` — borrados y recreados vacíos para que la identidad
///    regenerada arriba (en el handler) tenga dónde escribir.
/// 4. **URLCache** compartido — respuestas HTTP cacheadas.
///
/// Se invoca desde `HearthBitMeshPlugin.case "panicWipe"` y desde
/// `RunnerTests/PanicWipeTests.swift`. La función es **idempotente**:
/// una segunda invocación sobre el mismo estado (ya vacío) no lanza
/// y deja el sistema en el mismo estado final.
///
/// Tests XCTest validan los 4 contratos de Hueco 5: Keychain vaciado,
/// archivos borrados, idempotencia, y orden Keychain → archivos.
struct IOSPanicWipe {
  /// Pasos ejecutados en orden canónico. `CaseIterable` permite al
  /// test de orden enumerar la secuencia esperada sin hardcodearla.
  enum Step: String, CaseIterable {
    case keychain
    case userDefaults
    case files
    case urlCache
  }

  /// Reporte de la operación. Permite a los tests verificar el
  /// contrato sin tener que inspeccionar el estado global del sistema.
  struct Report {
    /// Número de clases de Keychain que la wipe intentó vaciar
    /// (3 por defecto: GenericPassword, InternetPassword, Certificate).
    let keychainClassesDeleted: Int
    /// `true` si se intentó `removePersistentDomain` (bundle id presente).
    let userDefaultsRemoved: Bool
    /// Número de directorios de la lista `filesDirectories` que
    /// existían antes del wipe y fueron borrados.
    let filesRemoved: Int
    /// `true` siempre — `URLCache.removeAllCachedResponses` no lanza.
    let urlCacheCleared: Bool
    /// Orden observado de los pasos (en el orden canónico, pero el
    /// campo existe para que el test de ordering haga su assertion).
    let observedOrder: [Step]
  }

  /// Realiza el wipe nativo. Todos los parámetros tienen defaults
  /// razonables para uso desde el handler; los tests los inyectan
  /// para mantener el sistema en un estado controlado.
  ///
  /// - Parameters:
  ///   - fileManager: `FileManager` a usar (default `.default`).
  ///   - userDefaults: `UserDefaults` a usar (default `.standard`).
  ///   - urlCache: `URLCache` a usar (default `.shared`).
  ///   - bundleIdentifier: bundle id para
  ///     `UserDefaults.removePersistentDomain` (default
  ///     `Bundle.main.bundleIdentifier`).
  ///   - keychainClasses: clases de Keychain a vaciar (default las 3
  ///     del spec).
  ///   - filesDirectories: directorios a borrar. Si `nil`, usa los 4
  ///     del app data dir. Si se pasa una lista, se usa esa
  ///     exactamente (los tests pasan una lista de directorios
  ///     temporales).
  ///   - orderRecorder: closure opcional invocada con cada paso en
  ///     el orden en que se ejecuta. Los tests la usan para el
  ///     assertion de ordering.
  @discardableResult
  static func wipe(
    fileManager: FileManager = .default,
    userDefaults: UserDefaults = .standard,
    urlCache: URLCache = .shared,
    bundleIdentifier: String? = Bundle.main.bundleIdentifier,
    keychainClasses: [CFString] = [
      kSecClassGenericPassword,
      kSecClassInternetPassword,
      kSecClassCertificate,
    ],
    filesDirectories: [URL]? = nil,
    orderRecorder: ((Step) -> Void)? = nil
  ) -> Report {
    var order: [Step] = []
    let record: (Step) -> Void = { step in
      order.append(step)
      orderRecorder?(step)
    }

    // 1) Keychain — `SecItemDelete` con solo `kSecClass` borra todas
    // las entradas de esa clase en el keychain del bundle. Aceptamos
    // `errSecItemNotFound` (no había nada que borrar) como éxito
    // parcial: el contrato es "vaciar", no "borrar N items".
    var keychainCount = 0
    for cls in keychainClasses {
      let status = SecItemDelete([kSecClass: cls] as CFDictionary)
      if status == errSecSuccess || status == errSecItemNotFound {
        keychainCount += 1
      }
    }
    record(.keychain)

    // 2) UserDefaults — `removePersistentDomain` es no-op si el
    // dominio ya no existe, así que la segunda invocación no lanza.
    var userDefaultsRemoved = false
    if let bid = bundleIdentifier {
      userDefaults.removePersistentDomain(forName: bid)
      userDefaultsRemoved = true
    }
    record(.userDefaults)

    // 3) Archivos — borramos cada dir y lo recreamos vacío. Esto
    // garantiza que la identidad regenerada por el handler tenga
    // dónde escribir inmediatamente. `removeItem` puede fallar si
    // el dir ya no existe (segundo wipe): lo aceptamos vía `try?`.
    var filesRemoved = 0
    let dirs: [URL] = filesDirectories ?? [
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
      fileManager.temporaryDirectory,
    ].compactMap { $0 }
    for dir in dirs {
      if fileManager.fileExists(atPath: dir.path) {
        do {
          try fileManager.removeItem(at: dir)
          filesRemoved += 1
        } catch {
          // Best-effort: el wipe sigue. El reporte no incrementa el
          // contador para este dir.
        }
      }
      try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    record(.files)

    // 4) URLCache — `removeAllCachedResponses` no lanza nunca.
    urlCache.removeAllCachedResponses()
    record(.urlCache)

    return Report(
      keychainClassesDeleted: keychainCount,
      userDefaultsRemoved: userDefaultsRemoved,
      filesRemoved: filesRemoved,
      urlCacheCleared: true,
      observedOrder: order
    )
  }
}
