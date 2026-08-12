# Arquitectura

## Flujo de datos

1. Cada teléfono mantiene una identidad Curve25519 para Noise y una clave
   Ed25519 para firmar anuncios y mensajes públicos.
2. Android anuncia y escanea el UUID BitChat desde un servicio en primer plano
   y mantiene un segundo escaneo, solo de presencia, para balizas BLE
   genéricas. iOS usa CoreBluetooth con restauración de estado y los modos
   `bluetooth-central` y `bluetooth-peripheral`.
3. Los peers intercambian anuncios TLV firmados. El identificador de 8 bytes es
   `SHA-256(clave pública Noise)[0:8]`.
4. Los mensajes públicos se firman y se retransmiten con TTL 7. Cada nodo
   deduplica por el hash del paquete excluyendo el TTL.
5. Un chat privado ejecuta Noise XX
   (`25519_ChaChaPoly_SHA256`). Solo después de comprobar que la clave estática
   remota produce el peer ID anunciado se aceptan mensajes cifrados.
6. Los paquetes dirigidos se conservan hasta 12 horas en Android para
   reintentar su entrega cuando reaparece el destinatario.

## Transferencia de archivos (HBT)

1. Las ofertas de archivo viajan como tramas HBT firmadas con Ed25519 dentro
   de la sesión Noise de la malla (plano de control). Ver
   [`transfer-protocol.md`](transfer-protocol.md).
2. Aceptada la oferta, ambos lados derivan una clave X25519 efímera y cifran
   cada chunk con XChaCha20-Poly1305; el receptor verifica el SHA-256 final.
3. El selector de transporte prueba en orden: **LAN/hotspot** (TCP + cifrado
   de aplicación), **Nearby Connections** (Android), **Wi-Fi Aware**
   (Android 10+, feature flag), y **BLE inline** para archivos ≤ 256 KiB.
   Cada fallo cae automáticamente al siguiente transporte.
4. El **modo óptico** (QR + códigos fountain LT) funciona sin ninguna radio:
   el emisor muestra símbolos rateless y el receptor filma hasta reconstruir
   y verificar el archivo. Si además hay sesión de malla, una trama HBT
   `COMPLETE` detiene al emisor al instante.
5. En iOS, Nearby y Wi-Fi Aware aún no están disponibles: el selector usa
   LAN, BLE u óptico. Las fotos grandes pueden comprimirse con el perfil de
   emergencia (1600 px, JPEG 70) antes de ofrecerse.
6. Un SOS en la malla frena los transportes de datos durante unos segundos:
   el chat de emergencia siempre tiene prioridad sobre los archivos.

## Modo rescate y energía

1. El **modo rescate** reenvía la alerta SOS con coordenadas GPS frescas cada
   5 minutos para que los rescatistas sigan la posición. Requiere ubicación
   «todo el tiempo» (Android) o «siempre» (iOS); la app la solicita en dos
   pasos como exige cada sistema.
2. En Android, el servicio en primer plano declara los tipos
   `connectedDevice|location`, lo que permite leer GPS con la pantalla
   apagada. La app ofrece el diálogo del sistema para excluirse de la
   optimización de batería (Doze); sin esa exclusión, Android suspende BLE y
   GPS.
3. En iOS no existe exclusión de Doze: la guía integrada recomienda no forzar
   el cierre de la app y evitar el Modo de bajo consumo, que reduce el BLE en
   segundo plano. El modo de fondo `location` mantiene viva la app mientras
   siga la actualización de posición.
4. La pestaña SOS muestra una lista de verificación (optimización de batería,
   ubicación permanente, modo de ahorro activo) con acciones directas y
   consejos de ahorro para prolongar la autonomía durante la emergencia.

## Radar de proximidad (rescatistas)

1. El radar mide la intensidad de señal BLE (RSSI) del dispositivo objetivo,
   igual que la búsqueda de un AirTag sin banda ultra ancha. Se activa desde
   una alerta SOS («RASTREAR») o desde la lista de cercanos.
2. Fuentes de RSSI: en Android, cada anuncio captado por el escaneo más
   lecturas `readRemoteRssi()` cada segundo sobre la conexión GATT; en iOS,
   `didDiscover` (con duplicados activados en primer plano) más `readRSSI()`
   sobre periféricos conectados.
3. Para asociar dirección/periférico con el peer, Android usa el peerId del
   scan response; para objetivos iOS (que no anuncian su peerId) ambos lados
   aprovechan que un anuncio de malla con TTL intacto solo puede venir del
   vecino directo.
4. El RSSI crudo es ruidoso: una media móvil exponencial lo suaviza y la
   tendencia («te estás acercando» / «la señal se está debilitando») compara
   contra la señal de hace 4 s con histéresis de 2 dB. La distancia se estima
   con el modelo log-distancia y se muestra siempre como aproximación.
5. La vibración tipo contador Geiger acelera al acercarse; si no llegan
   muestras en 5 s el radar declara «señal perdida» y pide volver sobre los
   pasos. Si el SOS traía GPS, se muestra además la distancia en línea recta
   desde la posición del rescatista.
6. Alcance realista: decenas de metros a cielo abierto, mucho menos entre
   escombros. El radar guía el último tramo; la aproximación inicial es GPS.

## Dos niveles, roles e infraestructura

1. El nivel de **presencia** acepta anuncios BLE genéricos, pero no intenta
   GATT, no crea peers y nunca habilita chat. Android elimina toda observación
   tras 45 s; Flutter solo presenta «Presencia detectada, sin chat».
2. El nivel de **malla** exige `ANNOUNCE` firmado y claves vinculadas. Los
   peers autenticados anuncian su rol en el paquete firmado dedicado `0x25`;
   no se añade un TLV HearthBit a `ANNOUNCE` por compatibilidad con builds
   BitChat afectados por la regresión de TLV desconocidos.
3. `PHONE_RELAY` conserva el comportamiento de teléfono actual:
   comunicación, relay y store-and-forward. `PHONE_BEACON` es presencia sin
   chat ni relay. `INFRA_RELAY` retransmite sin conservar datos y
   `INFRA_DATA_ANCHOR` retransmite y conserva paquetes dirigidos.
4. La decisión de relay está centralizada y depende del rol, TTL y destino.
   Noise dirigido al propio nodo se consume; Noise para otro destinatario y
   paquetes públicos solo avanzan cuando el rol permite relay.
5. El escáner genérico jamás entrega a Flutter nombre o MAC. Normaliza solo
   datos de servicio/fabricante y genera un HMAC con secreto de proceso; el ID
   cambia cada 15 min y también con cada reinicio. Estas presencias no se
   persisten ni se mezclan con la identidad Curve25519.

## Límites intencionales

- Los mensajes de texto se limitan a 240 caracteres en la interfaz para caber
  en un único intercambio GATT de 256 bytes con padding.
- Los archivos se limitan a 512 MiB, con ofertas que caducan a los 10
  minutos; los blobs nunca entran al store-and-forward de mensajes ni se
  retransmiten por la malla.
- iOS suspende arbitrariamente apps en segundo plano y no relanza una app que
  el usuario cerró a la fuerza. La malla es más fiable con la app visible.
- En Android, el servicio muestra una notificación permanente. Algunos
  fabricantes requieren excluir manualmente la app del ahorro de batería.
- Una malla BLE no sustituye radio VHF, LoRa ni canales oficiales de socorro.

## Dependencias externas

- El submódulo `vendor/bitchat-android` fija la implementación pública que
  aporta las primitivas Noise Java y los vectores de referencia.
- El submódulo `firmware/anchor-node` fija Bitle, firmware MIT compatible con el
  protocolo BitChat.
- Flutter comparte la UI y la persistencia SQLite; la radio permanece nativa.
