# Modo privado y descubrimiento BLE

## Objetivo

El modo privado es el valor predeterminado. Reduce la correlación pasiva por
radio sin prometer anonimato frente a un nodo que se conecta activamente a la
malla. La interoperabilidad BitChat queda como opción explícita.

## Identificador de anuncio

Android no publica el `peerId` estable cuando el modo privado está activo.
Publica nueve octetos de service data:

1. marcador `0xA5`;
2. ocho octetos de
   `HMAC-SHA256(noisePrivateKey, floor(unixMillis / 15 minutos))`.

El token:

- rota cada 15 minutos;
- no permite calcular el `peerId`;
- no permite correlacionar dos ventanas sin conocer la clave privada;
- solo es una pista de conexión y nunca autentica una identidad.

iOS conserva su postura más estricta: anuncia únicamente el UUID de servicio.
CoreBluetooth suministra identificadores efímeros de periférico; añadir service
data no mejoraría el descubrimiento y sí ampliaría la superficie de huella.

## Reidentificación y confianza

Tras conectar por GATT, dos HearthBit intercambian primero la prueba anónima de
enlace `HB-LINK1`. No contiene `peerId`, nickname ni claves; solo evita el
deadlock en plataformas que no pueden anunciar service data. Un enlace queda
habilitado para recibir nuestra identidad si anunció el token rotatorio, envió
esa prueba o entregó directamente un `ANNOUNCE` con TLV `0xF0`/un
`HBT_CAPABILITY` válido. BitChat no responde a la prueba y no recibe nuestros
paquetes locales de identidad con interoperabilidad desactivada.

Después, el `ANNOUNCE` firmado vincula la conexión con la identidad
criptográfica. El token rotatorio y la prueba anónima nunca se escriben en el
trust store. Los contactos confiables se reconocen por sus claves firmadas
después de la conexión, no por el anuncio BLE.

En modo privado, los `ANNOUNCE` ordinarios tienen TTL 1 para que no se propaguen
más allá del vecino directo. Esto limita el chat autenticado ordinario a peers
cuya identidad se observó directamente.

Un SOS público es una excepción deliberada: antes de emitirlo, la app publica
un `ANNOUNCE` con el TTL completo. Sin esa excepción, los saltos posteriores no
podrían verificar la firma del emisor y descartarían el SOS. La UI debe dejar
claro que un SOS abierto revela identidad y, según la granularidad elegida,
ubicación.

## Interoperabilidad BitChat

Con interoperabilidad activa:

- Android vuelve a publicar el `peerId` de ocho octetos en el scan response;
- `ANNOUNCE` usa el TTL completo;
- se conserva la semántica del perfil BitChat.

La opción permanece desactivada por defecto y advierte del riesgo de
correlación pasiva.

Con interoperabilidad desactivada:

- los mensajes públicos de un peer sin prueba HearthBit se descartan solo en la
  presentación local; el relay del paquete no se altera;
- sus SOS públicos sí se muestran, con la etiqueta «red externa»;
- el dispositivo sigue visible como presencia externa sin acciones de chat;
- `ANNOUNCE`, `HBT_CAPABILITY` y capacidades locales solo salen por enlaces
  probados HearthBit. El `ANNOUNCE` de alcance completo previo a un SOS sigue
  siendo la excepción deliberada.

## Límites

- Un adversario activo puede imitar la prueba pública `HB-LINK1` o el protocolo
  HearthBit y recibir la identidad necesaria para autenticar el enlace. La
  prueba separa clientes BitChat normales; no es autenticación ni defensa ante
  un cliente malicioso compatible.
- El UUID de servicio revela que hay un dispositivo HearthBit cercano.
- Un SOS abierto no puede ser anónimo y a la vez verificable y enrutable con el
  protocolo actual.
- La rotación reduce correlación; no oculta patrones de tiempo, RSSI o lugar.
