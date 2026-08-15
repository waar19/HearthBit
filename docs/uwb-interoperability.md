# UWB entre Android y iPhone

Estado revisado: 2026-08-15.

## Decisión para S25 e iPhone 11

No se habilita UWB para la pareja de prueba actual. El Samsung conectado
(`SM-S931B`) no declara la feature Android `android.hardware.uwb`, comprobada
con `adb shell pm list features`. El iPhone 11 incorpora U1, pero una sesión
UWB necesita soporte en ambos extremos.

Para esta pareja HearthBit mantiene:

1. sonar acústico para distancia precisa con ambas apps visibles;
2. RSSI BLE para tendencia de proximidad;
3. GPS consentido cuando existe una alerta SOS con ubicación.

La ausencia de UWB no debe presentarse como error ni ocultar esas alternativas.

## Interoperabilidad futura

Android 16 introdujo `RangingManager` para UWB, Bluetooth Channel Sounding,
Wi-Fi NAN RTT y RSSI BLE. La documentación de Android describe
interoperabilidad UWB con iOS mediante un canal OOB propio y parámetros que
coincidan con el protocolo de accesorios Nearby Interaction de Apple.

Esto hace técnicamente posible una fase futura, pero no convierte la sesión
genérica OOB que HearthBit usa actualmente en una sesión UWB compatible con
iOS. Antes de exponerla en producto se necesita:

- detectar `android.hardware.uwb` y capacidades UWB reales, no solo la versión
  del sistema;
- intercambiar configuración UWB dentro del canal Noise autenticado existente;
- implementar `NearbyInteraction` en iOS y la configuración raw UWB compatible
  en Android;
- enlazar cada sesión al nonce y consentimiento de `RANGING_CONTROL`;
- rechazar configuración reutilizada, fuera de ventana o de un peer distinto;
- validar dirección, distancia, background y recuperación en hardware físico;
- conservar sonar y BLE como fallback inmediato.

No se reservará un nuevo valor wire ni se anunciará capacidad UWB hasta que
exista implementación en ambos extremos y fixtures de conformidad. Esto evita
que versiones actuales intenten negociar una tecnología incompleta.

## Fuentes primarias

- Android Developers, Range between devices:
  https://developer.android.com/develop/connectivity/ranging
- Android Developers, UWB communication:
  https://developer.android.com/develop/connectivity/uwb
- Apple Developer, Nearby Interaction with UWB:
  https://developer.apple.com/nearby-interaction/
