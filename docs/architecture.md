# Arquitectura

## Flujo de datos

1. Cada teléfono mantiene una identidad Curve25519 para Noise y una clave
   Ed25519 para firmar anuncios y mensajes públicos.
2. Android anuncia y escanea el UUID BitChat desde un servicio en primer plano.
   iOS usa CoreBluetooth con restauración de estado y los modos
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
