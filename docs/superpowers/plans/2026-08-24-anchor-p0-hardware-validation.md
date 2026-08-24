# Procedimiento de validación física — Anchor P0 close-out

**Propósito:** gate manual que el usuario (Wilmer) ejecuta con su
hardware antes de mergear `feature/anchor-p0` a `master`.

**Hardware requerido:**
- 1× ESP32-S3 N16R8 (Anchor de pruebas, p. ej. `Bitle-5528`).
- 1× teléfono Android físico con HearthBit compilado desde
  `feature/anchor-p0`.
- 1× PC con `idf.py` (ESP-IDF) y ADB.
- 1× cable USB-C para flasheo directo cuando aplique.

## Pre-flight

1. Confirmar que la rama local es `feature/anchor-p0` y el working
   tree está limpio.
2. Build del firmware:
   ```powershell
   cd firmware/anchor-node
   idf.py build
   ```
3. Build de la app Android:
   ```powershell
   cd app
   flutter build apk --debug
   ```
4. Instalar el APK en el teléfono.

## Gate 1 — Live charts

1. Abrir el panel del Anchor (`AnchorAdminScreen`).
2. Verificar las 4 gráficas (Actividad, Buzón, Memoria, Seguridad)
   actualizándose cada ~4 s.
3. Apagar el Anchor. Verificar insignia "sin conexión" en menos de
   8 s.
4. Encender el Anchor. Verificar reanudación sin picos falsos.
5. Generar tráfico (otro nodo enviando mensajes) y observar que la
   serie "Actividad" y "Seguridad" reflejan los deltas.

**PASS si:** los 5 pasos se cumplen sin error.

## Gate 2 — OTA inalámbrica

1. Con el Anchor en v9 (o la versión base que se decida), abrir el
   panel admin.
2. Verificar que la tarjeta OTA muestra "v9 → v10 disponible".
3. Confirmar la instalación. Esperar el ciclo completo:
   `preparing → transferring → rebooting → completed`.
4. Verificar versión v10 tras la reconexión.

**PASS si:** la actualización termina con v10 visible en el panel
y `anchor_admin_models` no muestra picos espurios.

## Gate 3 — OTA rápida (472-byte chunk + priority)

1. Medir tiempo total del Gate 2.
2. Repetir la actualización v9→v10 y medir.
3. Comparar con el target del spec (~1 min para 740 KB).
4. Verificar con `adb logcat` que `CONNECTION_PRIORITY_HIGH` se
   solicitó y se restauró a `BALANCED` al terminar.

**PASS si:** tiempo total ≤ 1 min ± 10% y la prioridad se restauró.

## Gate 4 — Reclamo del Bitle-5528

1. Borrar flash por USB: `idf.py -p COMx erase-flash`.
2. Flash v9 por USB.
3. En la app, abrir el panel del Anchor, "Reclamar dispositivo",
   introducir la clave de admin (que el usuario elige, no se registra
   en código ni en docs).
4. Confirmar que el Anchor queda operativo y visible en la app.

**PASS si:** el Anchor arranca en v9, aparece en la app, y la OTA
inalámbrica funciona sobre él.

## Reporte

Al terminar, completar `docs/templates/rescue-pilot-report.template.md`
(mismo template que usa `p0-execution-guide.md`) con los IDs de gate
de este archivo, y commitear en la rama. No elevar a `PASS` global:
el revisor independiente externo es el único que puede hacerlo.

**Mapeo de gates (estos 4 gates no son P0 formales; usar estos IDs
locales en el campo "IDs de gate" del template):**
- Gate 1 (Live charts) → `ANCHOR-CHARTS-01`
- Gate 2 (OTA inalámbrica) → `ANCHOR-OTA-01`
- Gate 3 (OTA rápida, 472-byte chunk + priority) → `ANCHOR-OTA-SPEED-01`
- Gate 4 (Reclamo del Bitle-5528) → `ANCHOR-RECLAIM-01`
