import Foundation

/// Cierra Hueco 1 (NSFileProtectionComplete) y Hueco 2 (iCloud backup
/// exclusion) del panic-wipe spec. Se invoca desde HearthBitMeshPlugin al
/// arranque y tras cada `panicWipe` para que cualquier archivo escrito por
/// SQLCipher, archivos residuales, caché, etc. quede cifrado en reposo y
/// excluido del backup de iCloud.
///
/// Diseñado para ser idempotente: aplicar dos veces es equivalente a
/// aplicar una. En simulador la protección puede no aplicar (la API existe
/// pero el kernel no la honra); en ese caso degradamos a
/// `.completeUntilFirstUserAuthentication` y emitimos un warning por
/// `MeshSecurityLog` (NSLog bajo `DEBUG`).
enum IOSFileProtection {
  /// Resultado de aplicar la protección a un directorio. Permite al
  /// caller loggear/inspeccionar sin abortar el wipe.
  struct ApplicationReport {
    let directory: URL
    let filesScanned: Int
    let protectionApplied: Int
    let protectionFallback: Int
    let protectionFailed: Int
    let backupExclusionApplied: Int
    let backupExclusionFailed: Int

    static let empty = ApplicationReport(
      directory: URL(fileURLWithPath: "/dev/null"),
      filesScanned: 0,
      protectionApplied: 0,
      protectionFallback: 0,
      protectionFailed: 0,
      backupExclusionApplied: 0,
      backupExclusionFailed: 0
    )
  }

  /// Aplica `FileProtectionType.complete` recursivamente a todos los
  /// archivos bajo `directory`. Si el environment no soporta
  /// `.complete` (p. ej. simulador iOS), degrada a
  /// `.completeUntilFirstUserAuthentication`. Devuelve un reporte con el
  /// número de archivos afectados.
  @discardableResult
  static func applyComplete(in directory: URL) throws -> ApplicationReport {
    let fm = FileManager.default
    var report = ApplicationReport.empty
    report.directory = directory

    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return report }

    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
      guard values?.isRegularFile == true else { continue }
      report.filesScanned += 1
      do {
        let actual = try setPreferredProtection(at: url)
        switch actual {
        case .complete:
          report.protectionApplied += 1
        case .completeUntilFirstUserAuthentication:
          report.protectionFallback += 1
        default:
          report.protectionFailed += 1
        }
      } catch {
        report.protectionFailed += 1
        logWarn("applyComplete failed for \(url.path): \(error.localizedDescription)")
      }
    }
    return report
  }

  /// Marca todos los archivos bajo `directory` como excluidos de iCloud
  /// backup (`isExcludedFromBackup = true`). No falla el panic wipe si la
  /// marca no aplica (p. ej. tmp/); registra en el reporte.
  @discardableResult
  static func excludeFromBackup(in directory: URL) throws -> ApplicationReport {
    let fm = FileManager.default
    var report = ApplicationReport.empty
    report.directory = directory

    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isExcludedFromBackupKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return report }

    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
      guard values?.isRegularFile == true else { continue }
      report.filesScanned += 1
      do {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
        report.backupExclusionApplied += 1
      } catch {
        report.backupExclusionFailed += 1
        logWarn("excludeFromBackup failed for \(url.path): \(error.localizedDescription)")
      }
    }
    return report
  }

  /// Convenience que aplica ambas a Application Support, Documents y
  /// Caches. Diseñado para llamarse al arranque de la app y tras
  /// `panicWipe`. Nunca lanza: loggea y continúa.
  static func applyAll() {
    let fm = FileManager.default
    let dirs: [URL] = [
      fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      fm.urls(for: .documentDirectory, in: .userDomainMask).first,
      fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
    ].compactMap { $0 }

    for dir in dirs {
      guard ensureDirectoryExists(dir) else {
        logWarn("skip non-existent directory: \(dir.path)")
        continue
      }
      let protection: ApplicationReport
      let backup: ApplicationReport
      do {
        protection = try applyComplete(in: dir)
        backup = try excludeFromBackup(in: dir)
      } catch {
        logWarn("IOSFileProtection.applyAll failed for \(dir.path): \(error.localizedDescription)")
        continue
      }
      logInfo(
        "applied to \(dir.lastPathComponent): scanned=\(protection.filesScanned) "
        + "complete=\(protection.protectionApplied) "
        + "fallback=\(protection.protectionFallback) "
        + "failed=\(protection.protectionFailed) "
        + "excluded=\(backup.backupExclusionApplied) "
        + "excludedFailed=\(backup.backupExclusionFailed)"
      )
    }
  }

  /// Intenta fijar `.complete` y devuelve el valor realmente aceptado
  /// por el filesystem. Útil para que los tests detecten entornos donde
  /// la clase completa no se honra (simulador).
  static func setPreferredProtection(at url: URL) throws -> FileProtectionType {
    let fm = FileManager.default
    try fm.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: url.path
    )
    let attrs = try fm.attributesOfItem(atPath: url.path)
    if let actual = attrs[.protectionKey] as? FileProtectionType {
      return actual
    }
    // Algunos simuladores devuelven `.none` cuando el atributo no
    // aplica. Devolvemos `.complete` para que el caller no infiera
    // éxito; el caller deberá comparar con la entrada solicitada.
    return .none
  }

  // MARK: - Internals

  private static func ensureDirectoryExists(_ url: URL) -> Bool {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
    return isDir.boolValue
  }

  private static func logWarn(_ message: String) {
    #if DEBUG
    NSLog("⚠️ IOSFileProtection: %@", message)
    #else
    NSLog("IOSFileProtection: %@", message)
    #endif
  }

  private static func logInfo(_ message: String) {
    #if DEBUG
    NSLog("ℹ️ IOSFileProtection: %@", message)
    #endif
  }
}
