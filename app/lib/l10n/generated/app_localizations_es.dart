// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'HearthBit';

  @override
  String storageOpenError(String error) {
    return 'No se pudo abrir el almacenamiento local:\n$error';
  }

  @override
  String statusActiveLabel(String nickname, int count) {
    return '$nickname · $count cercanos';
  }

  @override
  String statusDegradedLabel(String nickname) {
    return '$nickname · solo recepción (sin anuncio BLE)';
  }

  @override
  String get statusStarting => 'Iniciando malla…';

  @override
  String get statusError => 'Error en la malla';

  @override
  String get statusStopped => 'Malla detenida';

  @override
  String get actionStop => 'DETENER';

  @override
  String get actionRestart => 'REINICIAR';

  @override
  String get actionActivate => 'ACTIVAR';

  @override
  String get actionRetry => 'REINTENTAR';

  @override
  String get tooltipChangeName => 'Cambiar nombre';

  @override
  String get tooltipPanicWipe => 'Borrado de emergencia';

  @override
  String get tabChannel => 'Canal';

  @override
  String get tabNearby => 'Cercanos';

  @override
  String get tabFiles => 'Archivos';

  @override
  String get tabSos => 'SOS';

  @override
  String get emptyChatTitle => 'Aún no hay mensajes';

  @override
  String get emptyChatBody =>
      'Activa la malla. Los mensajes saltarán entre teléfonos cercanos sin usar internet.';

  @override
  String get composerPublicHint => 'Mensaje para todos los cercanos';

  @override
  String get composerPrivateHint => 'Mensaje cifrado';

  @override
  String get privateChatIntro =>
      'El primer mensaje iniciará un handshake Noise XX.';

  @override
  String get emptyPeersTitle => 'No hay dispositivos cercanos';

  @override
  String get emptyPeersBody =>
      'Mantén Bluetooth activo y acerca otro teléfono con HearthBit o BitChat.';

  @override
  String get peerSecure => 'canal cifrado listo';

  @override
  String get peerTapToEncrypt => 'toca para cifrar';

  @override
  String get tooltipRadar => 'Radar de proximidad';

  @override
  String get tooltipSendFile => 'Enviar archivo';

  @override
  String get sosCardTitle => 'Enviar alerta prioritaria';

  @override
  String get sosCardBody =>
      'Se intentará incluir tu ubicación GPS. La alerta será pública y se retransmitirá por la malla.';

  @override
  String get sosMedical => 'Necesito ayuda médica';

  @override
  String get sosTrapped => 'Estoy atrapado';

  @override
  String get sosImOk => 'Estoy bien';

  @override
  String get sosDefaultMessage => 'Necesito ayuda';

  @override
  String get sosReceivedTitle => 'Alertas recibidas';

  @override
  String get sosNoneReceived => 'No se han recibido alertas SOS.';

  @override
  String get actionTrack => 'RASTREAR';

  @override
  String get rescueModeTitle => 'Modo rescate';

  @override
  String rescueModeActive(int minutes) {
    return 'Reenviando tu SOS con ubicación cada $minutes min.';
  }

  @override
  String rescueModeLastPing(String time) {
    return 'Último envío: $time.';
  }

  @override
  String rescueModeInactive(int minutes) {
    return 'Reenvía tu SOS con GPS actualizado cada $minutes minutos, incluso con la pantalla apagada.';
  }

  @override
  String get rescueModeNoBackgroundLocation =>
      'Sin ubicación permanente, el GPS solo se actualiza con la app abierta.';

  @override
  String get actionAllow => 'PERMITIR';

  @override
  String get powerCardTitle => 'Batería y ubicación';

  @override
  String get powerCardSubtitle =>
      'Ajustes para que la malla siga latiendo y los rescatistas puedan ubicarte.';

  @override
  String get powerBatteryOptimization =>
      'Optimización de batería desactivada para HearthBit';

  @override
  String get actionDisable => 'DESACTIVAR';

  @override
  String get powerLocationAndroid => 'Ubicación permitida «todo el tiempo»';

  @override
  String get powerLocationIos => 'Ubicación permitida «siempre»';

  @override
  String get powerSaverAndroid =>
      'El ahorro de batería del sistema está activo y puede apagar la malla';

  @override
  String get powerSaverIos =>
      'El Modo de bajo consumo está activo y reduce el Bluetooth en segundo plano';

  @override
  String get powerTipsTitle => 'Consejos para ahorrar batería';

  @override
  String get actionAdjust => 'AJUSTAR';

  @override
  String get powerTipBrightness =>
      'Baja el brillo de la pantalla al mínimo y reduce el tiempo de bloqueo.';

  @override
  String get powerTipMobileData =>
      'Si no hay internet, desactiva los datos móviles y el 5G: la malla no los usa y la búsqueda de señal gasta mucha batería.';

  @override
  String get powerTipCloseApps =>
      'Cierra las apps que no necesites; deja Bluetooth y ubicación activos.';

  @override
  String get powerTipAndroidRecents =>
      'No cierres HearthBit desde «recientes»: el sistema mataría la malla.';

  @override
  String get powerTipAndroidVendor =>
      'Algunos fabricantes (Xiaomi, Huawei, Samsung) tienen su propio ahorro de energía: excluye a HearthBit también allí.';

  @override
  String get powerTipAndroidSync =>
      'Desactiva la sincronización automática de cuentas mientras dure la emergencia.';

  @override
  String get powerTipIosForceClose =>
      'No fuerces el cierre de HearthBit: iOS no la relanza sola.';

  @override
  String get powerTipIosBackgroundRefresh =>
      'Desactiva «Actualización en segundo plano» de otras apps en Ajustes.';

  @override
  String get powerTipIosLowPower =>
      'Evita el Modo de bajo consumo salvo que HearthBit esté en pantalla: reduce el Bluetooth en segundo plano.';

  @override
  String get powerTipShareBattery =>
      'Comparte batería externa entre vecinos: un solo teléfono encendido mantiene el enlace de toda la manzana.';

  @override
  String get nicknameDialogTitle => 'Nombre visible';

  @override
  String get nicknameDialogHint => 'Ej. Casa 12 o Ana';

  @override
  String get actionCancel => 'CANCELAR';

  @override
  String get actionSave => 'GUARDAR';

  @override
  String get wipeDialogTitle => '¿Borrar toda la identidad?';

  @override
  String get wipeDialogBody =>
      'Se eliminarán claves, historial y mensajes pendientes. Esta acción no se puede deshacer.';

  @override
  String get actionWipe => 'BORRAR TODO';

  @override
  String get photoProfileTitle => 'Perfil de emergencia';

  @override
  String photoProfileBody(String size) {
    return 'La foto pesa $size MiB. Comprimirla acelera el envío y ahorra batería en la malla.';
  }

  @override
  String get actionSendOriginal => 'ENVIAR ORIGINAL';

  @override
  String get actionCompress => 'COMPRIMIR';

  @override
  String offerFileError(String error) {
    return 'No se pudo ofrecer el archivo: $error';
  }

  @override
  String get sendByQr => 'Enviar por QR';

  @override
  String get receiveByQr => 'Recibir por QR';

  @override
  String get emptyTransfersTitle => 'Sin transferencias';

  @override
  String get emptyTransfersBody =>
      'Toca el clip junto a un dispositivo cercano para ofrecerle un archivo. La oferta viaja cifrada por la malla y el contenido usa el transporte más rápido disponible. El modo QR funciona incluso sin ninguna radio.';

  @override
  String transferFrom(String nickname) {
    return 'De $nickname';
  }

  @override
  String transferTo(String nickname) {
    return 'Para $nickname';
  }

  @override
  String transferProgress(String done, String total) {
    return '$done de $total';
  }

  @override
  String transferSavedAt(String path) {
    return 'Guardado en $path';
  }

  @override
  String get stateOffered => 'Oferta';

  @override
  String get stateConnecting => 'Conectando';

  @override
  String get stateTransferring => 'Enviando';

  @override
  String get stateCompleted => 'Completa';

  @override
  String get stateRejected => 'Rechazada';

  @override
  String get stateCancelled => 'Cancelada';

  @override
  String get stateFailed => 'Falló';

  @override
  String get transportBle => 'Bluetooth';

  @override
  String get transportLan => 'Wi-Fi local';

  @override
  String get transportNearby => 'Nearby';

  @override
  String get transportWifiAware => 'Wi-Fi Aware';

  @override
  String get transportOptical => 'QR óptico';

  @override
  String get actionReject => 'RECHAZAR';

  @override
  String get actionAccept => 'ACEPTAR';

  @override
  String get actionDelete => 'ELIMINAR';

  @override
  String get opticalFileEmpty => 'El archivo está vacío';

  @override
  String opticalSendStats(String fileName, int chunks, int symbol) {
    return '$fileName · $chunks chunks · símbolo $symbol';
  }

  @override
  String get opticalConfirmed => 'El receptor confirmó la recepción por BLE';

  @override
  String get opticalSpeedLabel => 'Velocidad';

  @override
  String opticalFps(int fps) {
    return '$fps QR/s';
  }

  @override
  String get densityCompact => 'Compacta';

  @override
  String get densityMedium => 'Media';

  @override
  String get densityHigh => 'Alta';

  @override
  String get opticalSendHint =>
      'Si la cámara receptora pierde muchos frames, baja la velocidad o la densidad. El código es rateless: repetir símbolos nunca corrompe la transferencia.';

  @override
  String get opticalShaFailed =>
      'La verificación SHA-256 falló; reinicia el envío';

  @override
  String opticalSavedTitle(String fileName) {
    return '$fileName verificado y guardado';
  }

  @override
  String get genericFile => 'Archivo';

  @override
  String get actionDone => 'LISTO';

  @override
  String get opticalScanHint =>
      'Apunta la cámara al QR del emisor. La cabecera se repite cada pocos frames.';

  @override
  String opticalReceiveStats(
    String fileName,
    int decoded,
    int total,
    int symbols,
  ) {
    return '$fileName · $decoded de $total chunks · $symbols símbolos';
  }

  @override
  String radarTitle(String nickname) {
    return 'Radar · $nickname';
  }

  @override
  String get radarSignalLost => 'SEÑAL PERDIDA';

  @override
  String get radarSignalLostHint =>
      'Vuelve despacio sobre tus pasos hasta recuperar la señal.';

  @override
  String get radarSearching => 'Buscando señal…';

  @override
  String get radarSearchingHint =>
      'Camina despacio describiendo un círculo amplio. El radar detecta la señal Bluetooth directa (decenas de metros).';

  @override
  String get proximityVeryClose => 'MUY CERCA';

  @override
  String get proximityClose => 'CERCA';

  @override
  String get proximityInRange => 'EN RANGO';

  @override
  String get proximityFar => 'LEJOS';

  @override
  String get trendApproaching => 'Te estás acercando';

  @override
  String get trendReceding => 'La señal se está debilitando';

  @override
  String get trendSteady => 'Señal estable';

  @override
  String get trendUnknown => 'Midiendo señal…';

  @override
  String get distanceVeryNear => 'a menos de 2 m';

  @override
  String distanceApprox(int meters) {
    return '≈ $meters m';
  }

  @override
  String get distanceFar => 'a más de 15 m';

  @override
  String radarDbm(int dbm) {
    return 'Señal $dbm dBm';
  }

  @override
  String radarGpsDistance(String distance) {
    return 'Último GPS reportado: a $distance en línea recta';
  }

  @override
  String get errorPermissions =>
      'Se necesitan permisos de Bluetooth y notificaciones para crear la malla.';

  @override
  String get errorLocationOff =>
      'Activa la ubicación del sistema para el modo rescate';

  @override
  String get errorUnknown => 'Error desconocido';

  @override
  String get tooltipSupport => 'Apoyar HearthBit';

  @override
  String get aboutTitle => 'Acerca de HearthBit';

  @override
  String get aboutBody =>
      'HearthBit es un proyecto de comunicación de emergencia de código abierto. Tu apoyo ayuda a financiar pruebas con dispositivos y hardware repetidor resistente.';

  @override
  String aboutVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get aboutSourceCode => 'Código fuente';

  @override
  String get supportButton => 'Invítame a un café';

  @override
  String get openLinkError => 'No se pudo abrir el enlace';

  @override
  String get actionClose => 'Cerrar';

  @override
  String get terrInterrupted => 'Interrumpida al cerrar la aplicación';

  @override
  String get terrFileSize => 'El archivo debe pesar entre 1 byte y 512 MiB';

  @override
  String get terrOfferExpired => 'La oferta caducó sin respuesta';

  @override
  String get terrNoTransport => 'Sin transporte compatible con el emisor';

  @override
  String get terrInvalidSignature =>
      'Se descartó una oferta con firma inválida';

  @override
  String get terrUnsupportedTransport =>
      'Transporte no soportado en esta versión';

  @override
  String get terrLanIncomplete => 'La conexión LAN terminó incompleta';

  @override
  String terrLanFailed(String error) {
    return 'LAN falló: $error';
  }

  @override
  String terrBleChunk(String error) {
    return 'Chunk BLE inválido: $error';
  }

  @override
  String get terrTransport => 'Error de transporte';

  @override
  String terrNearbyStart(String error) {
    return 'No se pudo iniciar Nearby: $error';
  }

  @override
  String terrWifiAwareStart(String error) {
    return 'No se pudo iniciar Wi-Fi Aware: $error';
  }

  @override
  String terrBleInterrupted(String error) {
    return 'Envío BLE interrumpido: $error';
  }

  @override
  String get terrReceiverSilent => 'El receptor dejó de confirmar chunks';

  @override
  String terrNearbyUnavailable(String error) {
    return 'Nearby no disponible: $error';
  }

  @override
  String terrWifiAwareUnavailable(String error) {
    return 'Wi-Fi Aware no disponible: $error';
  }

  @override
  String get terrContainerIncomplete => 'El contenedor llegó incompleto';

  @override
  String terrContainerDecrypt(String error) {
    return 'No se pudo descifrar el contenedor: $error';
  }

  @override
  String get terrShaMismatch =>
      'La verificación SHA-256 falló; archivo descartado';

  @override
  String terrNoMeshSession(String error) {
    return 'Sin conexión de malla con el peer: $error';
  }

  @override
  String get terrTransportTimeout => 'El transporte no respondió';

  @override
  String get recentChatsTitle => 'Conversaciones recientes';

  @override
  String get nearbyPeopleTitle => 'Personas cercanas';

  @override
  String get peerOnline => 'En línea';

  @override
  String get peerOffline => 'Desconectado';

  @override
  String get offlineChatHint =>
      'Esta persona está desconectada. Puedes leer el historial y enviar cuando vuelva a conectarse.';

  @override
  String get radarConsentTitle => 'Privacidad del radar';

  @override
  String get radarConsentOff =>
      'La ubicación por radar está bloqueada por defecto';

  @override
  String radarConsentActive(int minutes) {
    return 'Otros pueden usar el radar durante $minutes min más';
  }

  @override
  String get radarConsentAllow => 'Permitir radar durante 15 minutos';

  @override
  String get radarConsentRevoke => 'Revocar ahora';

  @override
  String get radarPrivacyWarning =>
      'Esto limita únicamente HearthBit. Otro software aún puede medir las señales Bluetooth que emite tu teléfono.';

  @override
  String get rescueRadarWarning =>
      'El modo rescate comparte ubicaciones SOS actualizadas y permite que rescatistas HearthBit cercanos midan tu señal mientras el SOS siga activo.';

  @override
  String get radarConsentRequired =>
      'Requiere el consentimiento de esta persona';

  @override
  String get radarConsentSos => 'Disponible por un SOS reciente';

  @override
  String get radarConsentTemporary =>
      'Autorizado temporalmente por esta persona';

  @override
  String radarConsentExpires(String time) {
    return 'El permiso vence a las $time';
  }

  @override
  String get radarNotDirection =>
      'El punto muestra proximidad, no dirección. Muévete despacio y compara si la señal se fortalece.';

  @override
  String get radarPermissionExpired =>
      'El permiso del radar venció o fue revocado.';

  @override
  String get dateToday => 'Hoy';

  @override
  String get dateYesterday => 'Ayer';
}
