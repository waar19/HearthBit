import Flutter
import Foundation

final class IOSMeshPacketFragmenter {
  static let maximumGATTValueLength = 512
  static let maximumFragmentDataLength = 469
  static let maximumFragments = 256
  static let maximumReassembledBytes = 1_048_576

  private let fragmentIDGenerator: () -> Data

  init(fragmentIDGenerator: (() -> Data)? = nil) {
    self.fragmentIDGenerator = fragmentIDGenerator ?? Self.secureFragmentID
  }

  func prepare(
    packet: IOSMeshPacket,
    encoded: Data,
    maximumValueLength: Int
  ) -> [Data]? {
    let linkLimit = min(maximumValueLength, Self.maximumGATTValueLength)
    guard linkLimit > 0 else { return nil }
    guard packet.type != IOSMeshProtocol.fragment else { return nil }
    if encoded.count <= linkLimit { return [encoded] }

    let originalData = IOSMeshProtocol.removeBLETransportPadding(packet, encoded: encoded)
    guard originalData.count <= Self.maximumReassembledBytes else { return nil }
    let fragmentID = fragmentIDGenerator()
    guard fragmentID.count == IOSMeshProtocol.fragmentIDSize else { return nil }

    guard
      let emptyPacket = fragmentPacket(
        source: packet,
        fragmentID: fragmentID,
        index: 0,
        total: 1,
        data: Data()
      )
    else { return nil }
    let fixedSize = IOSMeshProtocol.encodeForBLE(emptyPacket).count
    var chunkSize = min(Self.maximumFragmentDataLength, linkLimit - fixedSize)
    guard chunkSize > 0 else { return nil }

    while chunkSize > 0 {
      let total = (originalData.count + chunkSize - 1) / chunkSize
      guard total <= Self.maximumFragments else { return nil }
      var frames: [Data] = []
      frames.reserveCapacity(total)
      var offset = 0
      var fits = true
      for index in 0..<total {
        let end = min(offset + chunkSize, originalData.count)
        guard
          let fragment = fragmentPacket(
            source: packet,
            fragmentID: fragmentID,
            index: index,
            total: total,
            data: originalData.subdata(in: offset..<end)
          )
        else { return nil }
        let frame = IOSMeshProtocol.encodeForBLE(fragment)
        if frame.count > linkLimit {
          fits = false
          break
        }
        frames.append(frame)
        offset = end
      }
      if fits { return frames }
      chunkSize -= 1
    }
    return nil
  }

  private func fragmentPacket(
    source: IOSMeshPacket,
    fragmentID: Data,
    index: Int,
    total: Int,
    data: Data
  ) -> IOSMeshPacket? {
    guard
      let payload = IOSMeshProtocol.encodeFragmentPayload(
        IOSMeshProtocol.FragmentPayload(
          fragmentID: fragmentID,
          index: index,
          total: total,
          originalType: source.type,
          data: data
        )
      )
    else { return nil }
    return IOSMeshPacket(
      version: source.version,
      type: IOSMeshProtocol.fragment,
      ttl: source.ttl,
      timestamp: source.timestamp,
      senderID: source.senderID,
      recipientID: source.recipientID,
      payload: payload,
      signature: nil,
      route: source.route,
      isRSR: false
    )
  }

  private static func secureFragmentID() -> Data {
    IOSSecureRandom.data(count: IOSMeshProtocol.fragmentIDSize) ?? Data()
  }
}

final class IOSMeshFragmentReassembler {
  private struct FragmentSet {
    let originalType: UInt8
    let total: Int
    let senderID: Data
    let recipientID: Data?
    var ttl: UInt8
    var updatedAt: Date
    var parts: [Int: Data] = [:]
    var bytes = 0
  }

  private static let maximumFragments = 256
  private static let maximumSetBytes = 1_048_576
  private static let maximumActiveSets = 64
  private static let maximumGlobalBytes = 4 * 1_048_576
  private static let timeout: TimeInterval = 30

  private var sets: [String: FragmentSet] = [:]
  private var bufferedBytes = 0

  func accept(_ packet: IOSMeshPacket, now: Date = Date()) -> IOSMeshPacket? {
    guard
      packet.type == IOSMeshProtocol.fragment,
      let fragment = IOSMeshProtocol.decodeFragmentPayload(packet.payload),
      fragment.total <= Self.maximumFragments,
      fragment.originalType != IOSMeshProtocol.fragment,
      !fragment.data.isEmpty
    else { return nil }

    pruneExpired(now: now)
    let key = "\(packet.senderID.hex):\(fragment.fragmentID.hex)"
    var set: FragmentSet
    if let existing = sets[key] {
      set = existing
    } else {
      guard sets.count < Self.maximumActiveSets else { return nil }
      set = FragmentSet(
        originalType: fragment.originalType,
        total: fragment.total,
        senderID: packet.senderID,
        recipientID: packet.recipientID,
        ttl: packet.ttl,
        updatedAt: now
      )
    }
    guard
      set.originalType == fragment.originalType,
      set.total == fragment.total,
      set.senderID == packet.senderID,
      set.recipientID == packet.recipientID
    else {
      remove(key)
      return nil
    }
    set.ttl = min(set.ttl, packet.ttl)
    if let existing = set.parts[fragment.index] {
      if existing != fragment.data { remove(key) }
      return nil
    }
    guard
      set.bytes + fragment.data.count <= Self.maximumSetBytes,
      bufferedBytes + fragment.data.count <= Self.maximumGlobalBytes
    else {
      remove(key)
      return nil
    }

    set.parts[fragment.index] = fragment.data
    set.bytes += fragment.data.count
    set.updatedAt = now
    bufferedBytes += fragment.data.count
    sets[key] = set
    guard set.parts.count == set.total else { return nil }

    var reassembled = Data()
    reassembled.reserveCapacity(set.bytes)
    for index in 0..<set.total {
      guard let part = set.parts[index] else { return nil }
      reassembled.append(part)
    }
    let decoded = IOSMeshProtocol.decode(reassembled)
    remove(key)
    guard
      var original = decoded,
      original.type == set.originalType,
      original.senderID == packet.senderID,
      original.recipientID == packet.recipientID
    else { return nil }
    switch original.type {
    case IOSMeshProtocol.beaconControl:
      guard
        original.ttl == IOSBeaconControlProtocol.initialTTL,
        IOSBeaconControlProtocol.isValidTTL(set.ttl)
      else { return nil }
      original.ttl = set.ttl
    case IOSMeshProtocol.rangingControl:
      guard original.ttl == 1, set.ttl == 1 else { return nil }
      original.ttl = 1
    default:
      original.ttl = 0
    }
    return original
  }

  func clear() {
    sets.removeAll()
    bufferedBytes = 0
  }

  private func pruneExpired(now: Date) {
    for key in sets.compactMap({
      now.timeIntervalSince($0.value.updatedAt) > Self.timeout ? $0.key : nil
    }) {
      remove(key)
    }
  }

  private func remove(_ key: String) {
    guard let removed = sets.removeValue(forKey: key) else { return }
    bufferedBytes = max(0, bufferedBytes - removed.bytes)
  }
}
/// Stream handler del canal de eventos de transferencia: conserva el sink de
/// Flutter y reenvía los eventos del transporte Wi-Fi Aware
/// (`wifiAwareProgress`/`wifiAwareDone`/`wifiAwareError`). Debe usarse desde el
/// hilo principal.
final class HearthBitTransferEventHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  /// Reenvía un evento a Dart; se descarta si nadie escucha el canal.
  func emit(_ event: [String: Any]) {
    eventSink?(event)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
/// Localización nativa mínima sin tocar el proyecto de Xcode: elige el idioma
/// preferido del sistema entre los seis que soporta la app y cae a inglés si
/// no hay coincidencia. Las traducciones espejan los ARB de Flutter.
enum HearthBitL10n {
  private static let supported = ["en", "es", "de", "fr", "zh", "ja"]

  static var language: String {
    for preferred in Locale.preferredLanguages {
      let code = String(preferred.prefix(2)).lowercased()
      if supported.contains(code) { return code }
    }
    return "en"
  }

  static func string(_ key: String) -> String {
    table[language]?[key] ?? table["en"]?[key] ?? key
  }

  private static let table: [String: [String: String]] = [
    "en": [
      "sos_default": "I need help",
      "nearby_unavailable": "Nearby Connections is not available on iOS",
      "wifi_aware_unavailable": "Wi-Fi Aware is not available on this iOS version",
      "identity_rejected": "A private channel was rejected due to an invalid identity",
      "no_advertising": "This device cannot advertise over BLE; receive-only mode",
      "advertise_failed": "Could not advertise the BLE mesh: %@",
      "not_running": "The mesh is not active",
      "peer_unavailable": "The device is no longer available",
      "invalid_peer_id": "The device identity is not valid",
      "identity_mismatch": "The Noise identity does not match",
      "identity_unavailable": "The secure device identity is unavailable",
      "noise_failed": "The Noise encrypted channel failed",
      "noise_rekey_required": "The private channel must be renewed",
      "storage_unavailable": "Secure emergency storage is unavailable",
      "secure_random_unavailable": "Secure randomness is unavailable; the operation was cancelled",
      "invalid_payload": "The transfer payload is not valid",
      "radar_consent_required": "This person has not allowed radar location",
      "role_cannot_chat": "Presence-only mode cannot send messages",
      "family_notification_title": "HearthBit family alert",
      "family_status_sos": "SOS",
      "family_status_ok": "I am safe",
      "family_status_help": "Needs help",
      "family_status_injured": "Injured",
      "family_status_check_in": "Check-in",
    ],
    "es": [
      "sos_default": "Necesito ayuda",
      "nearby_unavailable": "Nearby Connections no está disponible en iOS",
      "wifi_aware_unavailable": "Wi-Fi Aware no está disponible en esta versión de iOS",
      "identity_rejected": "Un canal privado fue rechazado por identidad inválida",
      "no_advertising": "Este dispositivo no puede anunciarse por BLE; modo solo recepción",
      "advertise_failed": "No se pudo anunciar la malla BLE: %@",
      "not_running": "La malla no está activa",
      "peer_unavailable": "El dispositivo ya no está disponible",
      "invalid_peer_id": "La identidad del dispositivo no es válida",
      "identity_mismatch": "La identidad Noise no coincide",
      "identity_unavailable": "La identidad segura del dispositivo no está disponible",
      "noise_failed": "Falló el canal cifrado Noise",
      "noise_rekey_required": "El canal privado debe renovarse",
      "storage_unavailable": "El almacenamiento seguro de emergencia no está disponible",
      "secure_random_unavailable": "La aleatoriedad segura no está disponible; se canceló la operación",
      "invalid_payload": "La carga de la transferencia no es válida",
      "radar_consent_required": "Esta persona no ha permitido la ubicación por radar",
      "role_cannot_chat": "El modo de solo presencia no puede enviar mensajes",
      "family_notification_title": "Alerta familiar de HearthBit",
      "family_status_sos": "SOS",
      "family_status_ok": "Estoy bien",
      "family_status_help": "Necesita ayuda",
      "family_status_injured": "Herido",
      "family_status_check_in": "Estado familiar",
    ],
    "de": [
      "sos_default": "Ich brauche Hilfe",
      "nearby_unavailable": "Nearby Connections ist auf iOS nicht verfügbar",
      "wifi_aware_unavailable": "Wi-Fi Aware ist in dieser iOS-Version nicht verfügbar",
      "identity_rejected": "Ein privater Kanal wurde wegen ungültiger Identität abgelehnt",
      "no_advertising": "Dieses Gerät kann sich nicht über BLE ankündigen; Nur-Empfangsmodus",
      "advertise_failed": "Das BLE-Mesh konnte nicht angekündigt werden: %@",
      "not_running": "Das Mesh ist nicht aktiv",
      "peer_unavailable": "Das Gerät ist nicht mehr verfügbar",
      "invalid_peer_id": "Die Geräteidentität ist ungültig",
      "identity_mismatch": "Die Noise-Identität stimmt nicht überein",
      "noise_failed": "Der verschlüsselte Noise-Kanal ist fehlgeschlagen",
      "invalid_payload": "Die Übertragungsdaten sind ungültig",
      "radar_consent_required": "Diese Person hat die Ortung per Radar nicht erlaubt",
      "role_cannot_chat": "Im reinen Anwesenheitsmodus können keine Nachrichten gesendet werden",
      "family_notification_title": "HearthBit-Familienmeldung",
      "family_status_sos": "SOS",
      "family_status_ok": "Mir geht es gut",
      "family_status_help": "Benötigt Hilfe",
      "family_status_injured": "Verletzt",
      "family_status_check_in": "Statusmeldung",
    ],
    "fr": [
      "sos_default": "J'ai besoin d'aide",
      "nearby_unavailable": "Nearby Connections n'est pas disponible sur iOS",
      "wifi_aware_unavailable": "Wi-Fi Aware n'est pas disponible sur cette version d'iOS",
      "identity_rejected": "Un canal privé a été rejeté pour identité invalide",
      "no_advertising": "Cet appareil ne peut pas s'annoncer en BLE ; mode réception seule",
      "advertise_failed": "Impossible d'annoncer le maillage BLE : %@",
      "not_running": "Le maillage n'est pas actif",
      "peer_unavailable": "L'appareil n'est plus disponible",
      "invalid_peer_id": "L'identité de l'appareil n'est pas valide",
      "identity_mismatch": "L'identité Noise ne correspond pas",
      "noise_failed": "Le canal chiffré Noise a échoué",
      "invalid_payload": "La charge du transfert n'est pas valide",
      "radar_consent_required": "Cette personne n'a pas autorisé la localisation par radar",
      "role_cannot_chat": "Le mode présence seule ne peut pas envoyer de messages",
      "family_notification_title": "Alerte familiale HearthBit",
      "family_status_sos": "SOS",
      "family_status_ok": "Je vais bien",
      "family_status_help": "A besoin d'aide",
      "family_status_injured": "Blessé",
      "family_status_check_in": "État familial",
    ],
    "zh": [
      "sos_default": "我需要帮助",
      "nearby_unavailable": "Nearby Connections 在 iOS 上不可用",
      "wifi_aware_unavailable": "此 iOS 版本不支持 Wi-Fi Aware",
      "identity_rejected": "一个私密通道因身份无效被拒绝",
      "no_advertising": "此设备无法进行 BLE 广播；仅接收模式",
      "advertise_failed": "无法广播 BLE 网状网络：%@",
      "not_running": "网状网络未激活",
      "peer_unavailable": "该设备已不可用",
      "invalid_peer_id": "设备身份无效",
      "identity_mismatch": "Noise 身份不匹配",
      "noise_failed": "Noise 加密通道失败",
      "invalid_payload": "传输数据无效",
      "radar_consent_required": "对方尚未允许通过雷达定位",
      "role_cannot_chat": "仅在线状态模式无法发送消息",
      "family_notification_title": "HearthBit 家庭警报",
      "family_status_sos": "SOS",
      "family_status_ok": "我很安全",
      "family_status_help": "需要帮助",
      "family_status_injured": "受伤",
      "family_status_check_in": "家庭状态",
    ],
    "ja": [
      "sos_default": "助けが必要です",
      "nearby_unavailable": "Nearby Connections は iOS では利用できません",
      "wifi_aware_unavailable": "このバージョンの iOS では Wi-Fi Aware を利用できません",
      "identity_rejected": "無効な ID のためプライベートチャネルが拒否されました",
      "no_advertising": "この端末は BLE アドバタイズができません。受信専用モードです",
      "advertise_failed": "BLE メッシュをアドバタイズできませんでした：%@",
      "not_running": "メッシュが有効ではありません",
      "peer_unavailable": "端末が利用できなくなりました",
      "invalid_peer_id": "端末の ID が無効です",
      "identity_mismatch": "Noise の ID が一致しません",
      "noise_failed": "Noise 暗号化チャネルに失敗しました",
      "invalid_payload": "転送ペイロードが無効です",
      "radar_consent_required": "相手はレーダーによる位置確認を許可していません",
      "role_cannot_chat": "プレゼンス専用モードではメッセージを送信できません",
      "family_notification_title": "HearthBit 家族通知",
      "family_status_sos": "SOS",
      "family_status_ok": "無事です",
      "family_status_help": "助けが必要です",
      "family_status_injured": "負傷しています",
      "family_status_check_in": "家族の安否情報",
    ],
  ]
}
