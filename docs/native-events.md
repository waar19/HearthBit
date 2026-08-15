# Contrato de eventos nativos

Android e iOS publican mapas por `com.hearthbit.mesh/events`. Dart debe
convertirlos exclusivamente mediante `MeshNativeEvent.parse`; las pantallas y
controladores no deben interpretar directamente el discriminador `type`.

## Reglas comunes

- `type` es obligatorio para eventos conocidos y usa `String`.
- Campos numéricos aceptan cualquier `num` del `StandardMessageCodec`.
- Bytes se aceptan como `Uint8List` o `List<int>`.
- Un campo ausente o con tipo incorrecto se convierte en `null`; el consumidor
  debe ignorar el evento incompleto sin cambiar estado crítico.
- Tipos desconocidos producen `MeshUnknownEvent` para mantener compatibilidad
  hacia delante.

## Eventos consumidos por `MeshController`

- `snapshot`, `status`: estado, identidad local, enlaces, métricas y permisos.
- `power`: `batteryLevel`, `powerProfile`, `adaptivePowerSaving`.
- `peers`, `presences`: listas completas de topología.
- `radarConsent`: vigencia del consentimiento y peers actualizados.
- `beaconRequest`, `beaconRequestResolved`, `beaconState`.
- `message`: mapa compatible con `MeshMessage`.
- `error`, `wiped`, `emergencyAck`, `rescuePing`.

## Eventos consumidos por `RadarScreen`

- `rssi`: `peerId`, `rssi`, `at`, `remote`, `tentative`.
- `radarExpired`, `radarDiagnostic`.
- `rangingMeasurement`: `peerId`, `meters`, `errorMeters`, `confidence`.
- `radioRangingState`: `state`.
- `rangingControl`: `peerId`, `payload`.
- `beaconState` remoto y `message` para ubicación compartida.

Los nombres y tipos nuevos deben añadirse primero al parser sellado y a sus
pruebas de contrato antes de ser consumidos por UI o controladores.
