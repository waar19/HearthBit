import Foundation

final class HearthBitFileImportBridge {
  static let shared = HearthBitFileImportBridge()
  private let queue = DispatchQueue(label: "com.hearthbit.hbt-import")
  private var pendingPaths: [String] = []
  private var emit: (([String: Any]) -> Void)?
  private let maximumBytes: Int64 = 700 * 1024 * 1024

  private init() {}

  func setEmitter(_ emit: @escaping ([String: Any]) -> Void) {
    queue.async {
      self.emit = emit
    }
  }

  func accept(_ url: URL) -> Bool {
    let allowed = url.pathExtension.lowercased() == "hbt"
    guard allowed else { return false }
    queue.async {
      do {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
          if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        guard size > 0, size <= self.maximumBytes else { return }
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("hbt-imports", isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
        let destination = directory.appendingPathComponent(
          "import-\(UUID().uuidString).hbt"
        )
        try FileManager.default.copyItem(at: url, to: destination)
        self.pendingPaths.append(destination.path)
        if let emit = self.emit {
          DispatchQueue.main.async {
            emit(["type": "hbtImport", "path": destination.path])
          }
        }
      } catch {
        // Flutter valida el paquete; una importación ilegible se ignora.
      }
    }
    return true
  }

  func consumeInitial() -> String? {
    queue.sync {
      guard !pendingPaths.isEmpty else { return nil }
      return pendingPaths.removeFirst()
    }
  }
}
