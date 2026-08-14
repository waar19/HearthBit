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

Tras conectar por GATT, el `ANNOUNCE` firmado vincula la conexión con la
identidad criptográfica. El token rotatorio nunca se escribe en el trust store.
Los contactos confiables se reconocen por sus claves firmadas después de la
conexión, no por el anuncio BLE.

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

## Límites

- Un adversario activo que se conecte puede recibir la identidad necesaria para
  autenticar el enlace.
- El UUID de servicio revela que hay un dispositivo HearthBit cercano.
- Un SOS abierto no puede ser anónimo y a la vez verificable y enrutable con el
  protocolo actual.
- La rotación reduce correlación; no oculta patrones de tiempo, RSSI o lugar.
