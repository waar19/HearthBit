# Prueba de campo

La radio BLE no se valida con emuladores. Use teléfonos físicos y desactive
Wi-Fi y datos móviles durante la prueba.

## Matriz mínima

1. Instale HearthBit en dos Android.
2. Instale BitChat oficial en un tercer Android o iPhone.
3. Con los tres a menos de cinco metros, active la malla y confirme que aparecen
   los nombres cercanos.
4. Envíe mensajes públicos desde cada app y confirme recepción cruzada.
5. Abra un chat privado, espere que el candado indique canal seguro y pruebe en
   ambos sentidos.
6. Aleje el tercer equipo fuera del alcance directo del primero, dejando el
   segundo a mitad de camino; confirme el relé de dos saltos.
7. Apague el destinatario, envíe un mensaje dirigido, vuelva a encenderlo antes
   de 12 horas y confirme el reintento store-and-forward.
8. Inserte un ESP32 Bitle entre dos equipos fuera de alcance directo y repita.

La interoperabilidad HearthBit↔BitChat con hardware real (pasos 2-5) es una
prueba manual obligatoria antes de declarar compatibilidad física; los tests
binarios automatizados no la sustituyen.

## Matriz ampliada de mega-red

Ejecute estos casos además de la matriz móvil:

1. **Modo presencia:** con dos HearthBit ya identificados, cambie uno a
   `PHONE_BEACON`. Confirme que se deshabilitan los compositores y el relay. En
   Android, compruebe por log que se cierran GATT y los escáneres y que el
   anuncio se reinicia como no conectable; al volver a `PHONE_RELAY`, chat y
   GATT deben recuperarse sin borrar identidad ni historial.
2. **Balizas genéricas:** acerque un TV, asistente o radio BLE no compatible.
   Debe aparecer como «Presencia detectada, sin chat», desaparecer en unos
   45 s al apagarlo y cambiar de identificador después de 15 min. Confirme que
   eventos, SQLite y logs no contienen nombre Bluetooth ni MAC.
3. **Raspberry Pi/Home Assistant:** coloque el daemon BlueZ entre dos teléfonos
   sin alcance directo. Verifique un solo reenvío por paquete, decremento TTL,
   deduplicación tras reiniciar el servicio y entrega store-and-forward dentro
   de la cuota configurada.
4. **Android TV:** pruebe primero un equipo con advertising múltiple y luego
   uno sin soporte. La UI debe distinguir relay dual de modo central degradado;
   en ambos casos confirme el comportamiento real con tres nodos.
5. **Android Automotive:** inicie el relay estacionado, salga de la actividad
   y apague la pantalla. Servicio y advertising deben detenerse. Una unidad OEM
   solo puede mantenerlo con una señal de ignición autorizada y debe fallar
   cerrado cuando esa señal sea desconocida.
6. **Courier:** use un `INFRA_DATA_ANCHOR` directo y repita depósito, expiración,
   destinatario incorrecto y entrega después de reconexión.

Linux/BlueZ, TV y Automotive requieren hardware real; compilar sus paquetes o
usar un emulador no demuestra radio dual, alcance ni ejecución prolongada.

## Reconexión y sincronización GCS

Use dos teléfonos HearthBit y un BitChat oficial:

1. Conecte los tres, espere los `ANNOUNCE` firmados y envíe tres mensajes
   públicos desde cada cliente.
2. Apague Bluetooth en un HearthBit y envíe otros tres mensajes desde BitChat.
3. Reactive Bluetooth antes de seis horas. Al recibir el nuevo `ANNOUNCE`,
   HearthBit debe enviar `REQUEST_SYNC` (`0x21`) con TTL 0 y un filtro GCS
   MSB-first; BitChat debe devolver únicamente los paquetes ausentes.
4. Repita desconectando BitChat. HearthBit debe responder su `REQUEST_SYNC`
   firmado con un máximo de 40 reenvíos, TTL 0 y flag RSR (`0x10`), sin duplicar
   mensajes ya presentes.
5. Capture los bytes de una petición y compruebe los TLV de 16 bits: P `0x01`,
   M big-endian `0x02`, filtro `0x03` y tipos little-endian `0x04`.
6. Mantenga los equipos conectados dos minutos y confirme que el control de
   tasa evita tormentas: no más de ocho respuestas por enlace cada 30 s.

Registre el número de mensajes antes y después. El resultado correcto es
convergencia exacta, sin duplicados y sin propagar `REQUEST_SYNC` más allá del
vecino directo.

## Paquetes v2 con ruta

Con un cliente BitChat que emita versión 2:

1. Envíe un paquete con flag route `0x08`, dos IDs de salto y payload conocido.
2. Confirme que HearthBit conserva los dos IDs al decodificar y volver a
   codificar; el largo del payload no debe incluir el byte de conteo ni la ruta.
3. Repita con recipient, compresión y firma activados.
4. Inyecte una ruta truncada. El paquete debe rechazarse sin cerrar la conexión.
5. Verifique también un paquete v1 normal: sus bytes deben seguir coincidiendo
   con el vector BitChat existente.

## Courier cifrado con ancla Bitle

1. Establezca una sesión Noise entre dos teléfonos y conecte el emisor
   directamente a un ancla con `0xB1 bit0`.
2. Envíe un mensaje privado. El emisor debe completar Noise con el ancla y
   depositar un `CourierEnvelope` `0x04` firmado, dirigido al ID del ancla.
3. En el log del ancla confirme `Envelope deposited`; el TLV `0x03` debe ser el
   paquete Noise cifrado opaco, nunca texto en claro.
4. Desconecte el emisor, conecte el destinatario y anuncie su clave. El ancla
   debe entregar el sobre por la etiqueta HMAC del día y eliminar su copia.
5. Confirme que el destinatario valida la firma del portador, la etiqueta y la
   expiración antes de abrir el paquete Noise, y que copias repetidas no generan
   mensajes duplicados.
6. Repita con etiqueta de otra clave, sobre vencido y ciphertext alterado:
   todos deben descartarse. Pruebe además el cruce de medianoche; se aceptan
   día anterior, actual y siguiente para tolerar desfase de reloj.

El depósito requiere enlace directo, identidad anunciada y sesión Noise con el
ancla. Un relay no verificado o alcanzado solo por varios saltos no debe aceptar
correo.

## Registro de interoperabilidad

### 2026-08-12 — Galaxy S25 ↔ BitChat en iPhone

- Android: Samsung SM-S931B, Android 16 (API 36), HearthBit debug.
- Distancia: teléfonos cercanos, BitChat en primer plano.
- Resultado confirmado por log: conexión GATT, decodificación y validación
  Ed25519 de anuncios BitChat actuales; peers directos y retransmitidos
  aceptados (`ANNOUNCE accepted`, TTL 7 y TTL 6).
- Correcciones necesarias para lograrlo: firma canónica con TTL=0 y padding,
  compresión raw-deflate compatible, TLV de capacidades y serialización de
  escrituras GATT.
- Confirmación visual manual del build actual: `HB_MEGA_1723` llegó de
  HearthBit a BitChat y `BITCHAT_MEGA_1725` llegó de BitChat a HearthBit.
- Tras apagar y reactivar Bluetooth en el iPhone, `HB_RECONNECT_1731` y
  `BITCHAT_RECONNECT_1732` llegaron en ambos sentidos. El log confirmó
  `REQUEST_SYNC` con TTL 0, solicitudes salientes y respuestas que reprodujeron
  uno y dos paquetes ausentes.
- Pendiente con hardware adicional: Noise DM deliberado en ambos sentidos y
  relay físico de dos saltos.

## Matriz de transferencia de archivos

Pruebe cada celda con un archivo pequeño (~100 KB) y una foto (~3 MB):

| Transporte | Android↔Android | Android↔iPhone | iPhone↔iPhone |
| ---------- | --------------- | -------------- | ------------- |
| Nearby Connections | ✔ requerido | n/a (iOS pendiente) | n/a |
| LAN / hotspot | ✔ requerido | ✔ requerido | ✔ requerido |
| Wi-Fi Aware | ✔ si ambos API 29+ | n/a | n/a |
| BLE inline (≤ 256 KiB) | ✔ requerido | ✔ requerido | ✔ requerido |
| QR óptico | ✔ requerido | ✔ requerido | ✔ requerido |

Escenarios adversos a cubrir en al menos un transporte:

- Pérdida de frames en el modo QR (tape parcialmente la pantalla): la
  transferencia debe alargarse, nunca corromperse.
- Cancelación a mitad desde ambos extremos; verificar que el estado queda
  `cancelada` en ambos y que los archivos parciales se eliminan.
- Fallo de transporte forzado (apagar Wi-Fi durante LAN): debe caer al
  siguiente transporte sin intervención.
- Aplicación en segundo plano durante la transferencia.
- Batería < 15 % y almacenamiento casi lleno en el receptor.
- SOS enviado durante una transferencia grande: los mensajes deben llegar
  sin demora perceptible.

## Radar de proximidad

Con dos teléfonos y la malla activa:

1. Desde una alerta SOS toque «RASTREAR» (o el icono de radar en Cercanos) y
   confirme que aparecen lecturas en menos de 5 s.
2. Camine acercándose y alejándose en línea recta (10-30 m): la tendencia
   debe cambiar a «te estás acercando» / «la señal se está debilitando» en
   pocos segundos, sin parpadear con usted quieto.
3. Verifique la vibración: más rápida e intensa al acercarse.
4. Apague el Bluetooth del objetivo: en ~5 s debe aparecer «señal perdida».
5. Repita con el teléfono objetivo en un bolsillo o bajo una caja (atenúa la
   señal): las bandas de distancia deben degradarse, nunca congelar la UI.
6. Combinaciones requeridas: Android→Android, Android→iPhone (objetivo iOS en
   primer plano y en segundo plano), iPhone→Android.

## Evidencia a registrar

- Modelos y versiones de Android/iOS.
- Distancia aproximada y obstáculos.
- Hora de envío y recepción.
- Estado foreground/background de cada app.
- Porcentaje de batería antes y después de una hora.

## Prueba automatizada

`MeshProtocolTest` congela las cabeceras binarias v1/v2, rutas, compresión, la
forma canónica de firma, GCS y Courier, además del parseo tolerante de anuncios
usados por BitChat. La prueba de ANNOUNCE también garantiza que HearthBit no
vuelva a emitir el TLV privado `0xF0`.
Ejecútela con:

```powershell
cd app\android
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
.\gradlew.bat :app:testDebugUnitTest
```

Esta prueba detecta cambios incompatibles en bytes, pero no reemplaza la matriz
de tres dispositivos.
