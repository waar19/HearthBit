import Foundation

/// Contadores agregados, sin PII y con vida igual a la del proceso.
///
/// - received: frame de paquete entregado al ingress, incluso si no decodifica.
/// - accepted: paquete decodificado, autenticado/admitido y único.
/// - rejected: fallo permanente de decode, autenticación o política; los
///   duplicados no vuelven a contarse como rechazo.
/// - deduplicated: fingerprint visto o relay todavía pendiente.
/// - expired: no existe una expiración temporal observable en este engine y
///   permanece en cero.
/// - droppedRateLimit: límites observables de ingress desconocido y emergencia
///   abierta.
/// - droppedTtl: candidato a relay no reenviado por ttl <= 1, aunque se procese
///   localmente.
/// - forwarded: decisión de relay que alcanza broadcast, una vez por paquete.
/// - failedTransport: enqueue rechazado por cola central/periférica llena o
///   escritura central finalmente fallida; cuenta intentos, no paquetes únicos.
final class IOSMeshPacketCounters {
  private let lock = NSLock()
  private var values: [String: UInt64] = [
    "packetsReceived": 0,
    "packetsAccepted": 0,
    "packetsRejected": 0,
    "packetsForwarded": 0,
    "packetsDeduplicated": 0,
    "packetsExpired": 0,
    "packetsDroppedRateLimit": 0,
    "packetsDroppedTtl": 0,
    "packetsFailedTransport": 0,
  ]

  func recordReceived() { increment("packetsReceived") }
  func recordAccepted() { increment("packetsAccepted") }
  func recordRejected() { increment("packetsRejected") }
  func recordForwarded() { increment("packetsForwarded") }
  func recordDeduplicated() { increment("packetsDeduplicated") }
  func recordDroppedRateLimit() { increment("packetsDroppedRateLimit") }
  func recordDroppedTtl() { increment("packetsDroppedTtl") }
  func recordFailedTransport() { increment("packetsFailedTransport") }

  /// Queue rejection and final async write failure are emitted at disjoint
  /// points, so each failed attempt is counted once.
  func recordTransportFailure(code: String) {
    switch code {
    case "central_queue_full", "peripheral_queue_full", "central_write_failed":
      recordFailedTransport()
    default:
      break
    }
  }

  func snapshot() -> [String: UInt64] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }

  private func increment(_ key: String) {
    lock.lock()
    values[key, default: 0] &+= 1
    lock.unlock()
  }
}
