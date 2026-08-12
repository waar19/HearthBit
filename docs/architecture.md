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

## Límites intencionales

- Los mensajes de texto se limitan a 240 caracteres en la interfaz para caber
  en un único intercambio GATT de 256 bytes con padding.
- No se envían archivos ni audio en esta primera versión.
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
