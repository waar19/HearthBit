import Foundation
import UIKit

#if canImport(WiFiAware) && canImport(DeviceDiscoveryUI)
  import DeviceDiscoveryUI
  import Network
  import WiFiAware
#endif

/// Transporte Wi-Fi Aware de iOS 26 para el contenedor HBT cifrado.
///
/// El archivo transferido es el contenedor HBT ya cifrado: este transporte lo
/// trata como bytes opacos y nunca lo descifra. El framing en el data path es
/// idéntico al de Android (`WifiAwareTransport.kt`): 8 bytes big-endian con la
/// longitud, seguidos de los bytes del contenedor.
///
/// Divergencia documentada con Android: el framework WiFiAware de Apple solo
/// permite conexiones entre dispositivos previamente emparejados
/// (`WAPairedDevice`, emparejamiento vía DeviceDiscoveryUI) y no expone un
/// data path por passphrase PSK como Android (`hbt-<transferId>`). Por eso la
/// interoperabilidad Wi-Fi Aware iOS<->Android queda bloqueada por Apple y este
/// transporte solo enlaza iOS<->iOS entre dispositivos emparejados. El selector
/// Dart mantiene LAN/BLE/QR como rutas multiplataforma.
///
/// Toda la superficie pública evita tipos de iOS 26 para poder compilarse con
/// deployment target iOS 16; el código específico vive tras
/// `#if canImport(WiFiAware) && canImport(DeviceDiscoveryUI)` y
/// `@available(iOS 26.0, *)`.
final class HearthBitWiFiAwareTransport {
  /// Alineado con el nombre de servicio Android `hearthbit-hbt` y el formato
  /// RFC 6763 que exige Apple para `WiFiAwareServices` (sufijo `._tcp`).
  static let serviceName = "_hearthbit-hbt._tcp"

  /// Tamaño de chunk para envío y cadencia de progreso.
  static let chunkSize = 64 * 1024

  typealias EventEmitter = ([String: Any]) -> Void

  private let emit: EventEmitter
  private let lock = NSLock()
  private var tasks: [String: Task<Void, Never>] = [:]
  private var backgroundObserver: NSObjectProtocol?

  init(emit: @escaping EventEmitter, observeBackground: Bool = true) {
    self.emit = emit
    if observeBackground {
      backgroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.cancelAllTransfers(reason: "wifi_aware_background")
      }
    }
  }

  deinit {
    if let observer = backgroundObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    let pending = drainTasks()
    for task in pending.values {
      task.cancel()
    }
  }

  // MARK: - Capacidades

  /// `true` solo si el SO, el hardware, el servicio declarado en Info.plist y
  /// el entitlement del binario están presentes.
  static var isSupported: Bool {
    #if canImport(WiFiAware) && canImport(DeviceDiscoveryUI)
      guard #available(iOS 26.0, *) else { return false }
      return computeSupport(
        osAvailable: true,
        hardwareSupported: WACapabilities.supportedFeatures.contains(.wifiAware),
        servicePublishable: WAPublishableService.allServices[serviceName] != nil,
        serviceSubscribable: WASubscribableService.allServices[serviceName] != nil,
        entitlementPresent: hasWiFiAwareEntitlement
      )
    #else
      return false
    #endif
  }

  /// Lógica de gating pura, separada para poder probarse sin hardware iOS 26.
  static func computeSupport(
    osAvailable: Bool,
    hardwareSupported: Bool,
    servicePublishable: Bool,
    serviceSubscribable: Bool,
    entitlementPresent: Bool
  ) -> Bool {
    osAvailable && hardwareSupported && servicePublishable &&
      serviceSubscribable && entitlementPresent
  }

  /// Detecta `com.apple.developer.wifi-aware` en el blob de entitlements
  /// embebido en el ejecutable. La clave se construye por partes para que el
  /// literal contiguo no aparezca en la sección de constantes del binario y
  /// produzca un falso positivo.
  static let hasWiFiAwareEntitlement: Bool = {
    let key = ["com.apple", "developer", "wifi-aware"].joined(separator: ".")
    guard
      let executable = Bundle.main.executableURL,
      let binary = try? Data(contentsOf: executable, options: .mappedIfSafe)
    else { return false }
    return binary.range(of: Data(key.utf8)) != nil
  }()

  // MARK: - Framing (compatible con Android)

  /// Cabecera de 8 bytes big-endian con la longitud del contenedor.
  static func encodeLengthHeader(_ length: UInt64) -> Data {
    var header = Data(count: 8)
    for index in 0..<8 {
      header[index] = UInt8(truncatingIfNeeded: length >> (8 * UInt64(7 - index)))
    }
    return header
  }

  static func decodeLengthHeader(_ data: Data) -> UInt64? {
    guard data.count == 8 else { return nil }
    var length: UInt64 = 0
    for byte in data {
      length = (length << 8) | UInt64(byte)
    }
    return length
  }

  // MARK: - Eventos con el contrato exacto de Dart

  static func progressEvent(transferId: String, bytes: Int) -> [String: Any] {
    ["type": "wifiAwareProgress", "transferId": transferId, "bytes": bytes]
  }

  static func doneEvent(transferId: String) -> [String: Any] {
    ["type": "wifiAwareDone", "transferId": transferId]
  }

  static func errorEvent(transferId: String, message: String) -> [String: Any] {
    ["type": "wifiAwareError", "transferId": transferId, "message": message]
  }

  // MARK: - API consumida por el plugin

  /// Publica el servicio y sirve el archivo al primer suscriptor emparejado.
  func sendFile(transferId: String, filePath: String) {
    #if canImport(WiFiAware) && canImport(DeviceDiscoveryUI)
      guard #available(iOS 26.0, *), Self.isSupported else {
        emit(Self.errorEvent(
          transferId: transferId,
          message: HearthBitL10n.string("wifi_aware_unavailable")
        ))
        return
      }
      startTransferOperation(transferId: transferId) { [emit] in
        await Self.runSend(transferId: transferId, filePath: filePath, emit: emit)
      }
    #else
      emit(Self.errorEvent(
        transferId: transferId,
        message: HearthBitL10n.string("wifi_aware_unavailable")
      ))
    #endif
  }

  /// Descubre al publicador emparejado, conecta y descarga el archivo.
  func receiveFile(transferId: String, destinationPath: String) {
    #if canImport(WiFiAware) && canImport(DeviceDiscoveryUI)
      guard #available(iOS 26.0, *), Self.isSupported else {
        emit(Self.errorEvent(
          transferId: transferId,
          message: HearthBitL10n.string("wifi_aware_unavailable")
        ))
        return
      }
      startTransferOperation(transferId: transferId) { [emit] in
        await Self.runReceive(
          transferId: transferId,
          destinationPath: destinationPath,
          emit: emit
        )
      }
    #else
      emit(Self.errorEvent(
        transferId: transferId,
        message: HearthBitL10n.string("wifi_aware_unavailable")
      ))
    #endif
  }

  /// Cancela listener, browser y conexiones de la transferencia sin emitir
  /// eventos posteriores.
  func stop(transferId: String) {
    lock.lock()
    let task = tasks.removeValue(forKey: transferId)
    lock.unlock()
    task?.cancel()
  }

  /// Cancela todas las transferencias activas (background o desalojo) y avisa
  /// a Dart para que caiga a LAN/BLE.
  func cancelAllTransfers(reason: String) {
    let pending = drainTasks()
    guard !pending.isEmpty else { return }
    for (transferId, task) in pending {
      task.cancel()
      emit(Self.errorEvent(transferId: transferId, message: reason))
    }
  }

  /// Ids de transferencias activas; expuesto para pruebas de lifecycle.
  var activeTransferIds: [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(tasks.keys)
  }

  // MARK: - Gestión de tareas

  /// Registra y lanza la tarea de una transferencia. Interno (no privado)
  /// para poder probar lifecycle y cancelación sin radio Wi-Fi Aware.
  func startTransferOperation(
    transferId: String,
    operation: @escaping () async -> Void
  ) {
    stop(transferId: transferId)
    let task = Task { [weak self] in
      await operation()
      self?.clearTask(transferId: transferId)
    }
    lock.lock()
    tasks[transferId] = task
    lock.unlock()
  }

  private func clearTask(transferId: String) {
    lock.lock()
    tasks.removeValue(forKey: transferId)
    lock.unlock()
  }

  private func drainTasks() -> [String: Task<Void, Never>] {
    lock.lock()
    defer { lock.unlock() }
    let pending = tasks
    tasks.removeAll()
    return pending
  }

  #if canImport(WiFiAware) && canImport(DeviceDiscoveryUI)

    /// Error centinela para terminar `NetworkListener.run` tras servir el
    /// archivo una vez.
    private struct TransferFinished: Error {}

    /// El servicio no está declarado en `WiFiAwareServices` del Info.plist.
    private struct ServiceUnavailable: Error {}

    @available(iOS 26.0, *)
    private static func runSend(
      transferId: String,
      filePath: String,
      emit: @escaping EventEmitter
    ) async {
      do {
        let payload = try Data(
          contentsOf: URL(fileURLWithPath: filePath),
          options: .mappedIfSafe
        )
        guard let service = WAPublishableService.allServices[serviceName] else {
          throw ServiceUnavailable()
        }
        let listener = try NetworkListener(
          for: .wifiAware(
            .connecting(to: service, from: .allPairedDevices, datapath: .defaults)
          )
        ) {
          TCP()
        }
        do {
          try await listener.run { connection in
            try await serve(
              payload: payload,
              transferId: transferId,
              over: connection,
              emit: emit
            )
            throw TransferFinished()
          }
        } catch is TransferFinished {
          // Transferencia completada; el done ya se emitió.
        }
      } catch is CancellationError {
        // stop()/background: sin eventos posteriores.
      } catch is ServiceUnavailable {
        emit(errorEvent(
          transferId: transferId,
          message: HearthBitL10n.string("wifi_aware_unavailable")
        ))
      } catch {
        emit(errorEvent(
          transferId: transferId,
          message: error.localizedDescription
        ))
      }
    }

    @available(iOS 26.0, *)
    private static func serve(
      payload: Data,
      transferId: String,
      over connection: NetworkConnection<TCP>,
      emit: @escaping EventEmitter
    ) async throws {
      try await connection.send(encodeLengthHeader(UInt64(payload.count)))
      var sent = 0
      while sent < payload.count {
        try Task.checkCancellation()
        let end = min(sent + chunkSize, payload.count)
        try await connection.send(payload.subdata(in: sent..<end))
        sent = end
        emit(progressEvent(transferId: transferId, bytes: sent))
      }
      emit(doneEvent(transferId: transferId))
    }

    @available(iOS 26.0, *)
    private static func runReceive(
      transferId: String,
      destinationPath: String,
      emit: @escaping EventEmitter
    ) async {
      do {
        guard let service = WASubscribableService.allServices[serviceName] else {
          throw ServiceUnavailable()
        }
        let browser = NetworkBrowser(
          for: .wifiAware(.connecting(to: .allPairedDevices, from: service))
        )
        let endpoint = try await browser.run { endpoints in
          if let first = endpoints.first {
            return .finish(first)
          }
          return .continue
        }
        let connection = NetworkConnection(to: endpoint) { TCP() }
        try await download(
          transferId: transferId,
          destinationPath: destinationPath,
          over: connection,
          emit: emit
        )
      } catch is CancellationError {
        // stop()/background: sin eventos posteriores.
      } catch is ServiceUnavailable {
        emit(errorEvent(
          transferId: transferId,
          message: HearthBitL10n.string("wifi_aware_unavailable")
        ))
      } catch {
        emit(errorEvent(
          transferId: transferId,
          message: error.localizedDescription
        ))
      }
    }

    @available(iOS 26.0, *)
    private static func download(
      transferId: String,
      destinationPath: String,
      over connection: NetworkConnection<TCP>,
      emit: @escaping EventEmitter
    ) async throws {
      let header = try await connection.receive(exactly: 8).content
      guard let expected = decodeLengthHeader(header) else {
        throw POSIXError(.EBADMSG)
      }
      FileManager.default.createFile(atPath: destinationPath, contents: nil)
      let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: destinationPath))
      defer { try? handle.close() }
      var received: UInt64 = 0
      while received < expected {
        try Task.checkCancellation()
        let remaining = expected - received
        let batch = Int(min(remaining, UInt64(chunkSize)))
        let message = try await connection.receive(atLeast: 1, atMost: batch)
        let content = message.content
        guard !content.isEmpty else {
          throw POSIXError(.ECONNRESET)
        }
        try handle.write(contentsOf: content)
        received += UInt64(content.count)
        emit(progressEvent(transferId: transferId, bytes: Int(received)))
      }
      try handle.close()
      emit(doneEvent(transferId: transferId))
    }

  #endif
}
