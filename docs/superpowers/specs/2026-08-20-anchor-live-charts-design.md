# Gráficas en vivo en el panel de administración del Anchor

Fecha: 2026-08-20
Estado: aprobado por el usuario (diseño validado en conversación)

## Contexto

El panel de administración del Anchor (`app/lib/screens/anchor_admin_screen.dart`) muestra hoy un
estado instantáneo obtenido con el comando `STATUS_GET` del protocolo admin (v1, firmware v6):
contadores acumulados de paquetes, uso del buzón, reloj, uptime y nombre. No hay visualización
de tendencia: el operador no puede ver si el Anchor está activo "ahora" ni cómo evoluciona el buzón.

## Objetivo

Agregar al panel una sección "Actividad" con cuatro mini-gráficas en vivo que se alimentan
sondeando `STATUS_GET` periódicamente mientras el panel está abierto:

1. **Actividad**: paquetes recibidos y reenviados por intervalo (dos series).
2. **Buzón**: porcentaje de uso del almacén de mensajes (0–100 %).
3. **Memoria**: memoria libre del equipo en KB (requiere campo nuevo en firmware).
4. **Seguridad**: paquetes rechazados y duplicados por intervalo (dos series).

## Fuera de alcance (decidido explícitamente)

- Historial persistente en el firmware (ver horas pasadas sin haber estado conectado).
- Configuración de radio LoRa desde el panel.
- Indicador RSSI/calidad del enlace BLE.
- Librerías de gráficas de terceros (p. ej. `fl_chart`): las gráficas se dibujan con
  `CustomPainter`, como ya hacen `mesh_health_card.dart`, `voice_waveform.dart` y `radar_screen.dart`.

## Diseño

### Flujo de datos

- Mientras `AnchorAdminScreen` está visible, un temporizador consulta `STATUS_GET` cada 4 s por el
  canal admin cifrado existente (payload Noise `0x31`). `STATUS_GET` no requiere autenticación, así
  que no consume challenges ni afecta el anti-fuerza-bruta.
- La pantalla mantiene un buffer circular en memoria con las últimas 60 muestras (~4 minutos).
  El buffer vive en el estado de la pantalla y se descarta al salir.
- Las gráficas "por intervalo" (actividad, seguridad) se calculan como delta entre muestras
  consecutivas de los contadores acumulados (u64). Si un delta es negativo (reinicio del Anchor,
  contadores vuelven a cero), se registra 0 para ese intervalo.
- Buzón y memoria son medidas directas (gauge), sin delta.
- El cálculo de deltas y el buffer se implementan como lógica pura testeable en Dart
  (p. ej. `app/lib/models/anchor_admin_models.dart` o un archivo hermano), separada del widget.

### Cambio de firmware (v6 → v7)

Archivo: `firmware/anchor-node/main/bitle_admin.c`, función `build_status`.

- Se agregan dos campos `u32` big-endian **después del nickname** (al final del payload):
  1. `free_heap`: `esp_get_free_heap_size()`.
  2. `min_free_heap`: `esp_get_minimum_free_heap_size()`.
- `BITLE_ADMIN_PROTOCOL_VERSION` no cambia (sigue en 1); el formato se distingue por longitud.
- `BITLE_FW_VERSION` en `firmware/anchor-node/main/bitle_ota.h` sube de 6 a 7.
- El self-test de admin (`bitle_admin_self_test`) sigue pasando; se ajusta si valida longitudes.
- Nada más cambia en firmware: ni radio, ni protocolo mesh, ni criptografía, ni NVS.

### Decodificadores nativos (Android e iOS)

- `app/android/app/src/main/kotlin/com/hearthbit/app/mesh/AnchorAdminProtocol.kt` (`parseStatus`)
  y su equivalente en `app/ios/Runner/IOSMeshProtocol.swift`:
  - Hoy rechazan bytes sobrantes tras el nickname. Nueva regla: tras leer el nickname deben quedar
    **exactamente 0 bytes** (firmware v6, campos de memoria ausentes) **o exactamente 8 bytes**
    (firmware v7, se leen `free_heap` y `min_free_heap`). Cualquier otro sobrante → payload inválido.
  - Los dos campos se exponen como opcionales (null cuando el firmware no los reporta).
- Los mapas enviados por `MethodChannel` desde `MeshEngine.kt` y `HearthBitMeshPlugin.swift`
  incluyen `freeHeap` y `minFreeHeap` solo cuando están presentes.

Compatibilidad: app nueva + firmware v6 funciona (gráfica de memoria oculta). App vieja +
firmware v7 rechazaría el status por el byte sobrante; se acepta porque app y firmware se
actualizan juntos en el piloto y el resto del panel no depende de versiones cruzadas.

### Interfaz (Flutter)

Archivo: `app/lib/screens/anchor_admin_screen.dart` (+ widget de gráfica reutilizable, p. ej.
`app/lib/widgets/anchor_sparkline.dart`).

- Nueva sección "Actividad" bajo el bloque de estado actual, con las cuatro mini-gráficas en
  tarjetas apiladas. Cada tarjeta muestra: título localizado, la gráfica y el valor más reciente
  como número. Tipo de gráfica por serie: actividad y seguridad como barras por intervalo;
  buzón y memoria como línea con área rellena.
- La gráfica de memoria solo se muestra si el firmware reporta el campo (v7+). Con firmware v6
  la tarjeta no aparece (sin mensaje de error).
- Textos nuevos en `app/lib/l10n/app_en.arb` y `app/lib/l10n/app_es.arb` + regeneración de
  localizaciones (el resto de idiomas hereda el fallback inglés como en el resto del panel).

### Manejo de errores

- Si una consulta de sondeo falla o expira (Anchor fuera de alcance, reinicio, sesión Noise caída),
  el panel conserva las gráficas con los datos ya recibidos y muestra una insignia "sin conexión"
  en la sección Actividad. El temporizador sigue intentando; al recibir respuesta la insignia
  desaparece y las series continúan (el hueco no se interpola: el delta tras reconectar se
  calcula contra la última muestra válida y se satura a 0 si es negativo).
- El sondeo se pausa cuando la pantalla pierde visibilidad (navegación, app en segundo plano)
  y se reanuda al volver.
- Las operaciones admin existentes (clave, renombrar, reiniciar, factory reset) no cambian; el
  sondeo no debe interferir con ellas (las peticiones se serializan por la cola admin existente).

### Pruebas

- **Kotlin** (`AnchorAdminProtocolTest.kt`): `parseStatus` con payload v6 (sin memoria), payload v7
  (con memoria) y payload con sobrante inválido (p. ej. 4 bytes extra) → rechazo.
- **Dart**: test unitario de la lógica de deltas y buffer (delta normal, reinicio de contadores
  con saturación a 0, buffer circular que descarta muestras viejas).
- **Firmware**: build limpio para esp32s3; `bitle_admin_self_test` pasa con el nuevo formato.
- **Hardware**: validación en la placa ESP32-S3 N16R8 real: abrir el panel, verificar que las
  cuatro gráficas se mueven al generar tráfico, apagar el Anchor y verificar la insignia
  "sin conexión", volver a encender y verificar la reanudación.

## Criterios de éxito

1. El panel muestra las cuatro gráficas actualizándose cada ~4 s con el Anchor real.
2. Con firmware v6 (sin actualizar) el panel sigue funcionando y omite la gráfica de memoria.
3. Un reinicio del Anchor durante el sondeo no produce picos falsos ni errores en pantalla.
4. Los tests de Kotlin y Dart nuevos pasan; los existentes no se rompen.
