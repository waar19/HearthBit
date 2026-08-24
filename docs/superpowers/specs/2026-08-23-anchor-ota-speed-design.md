# OTA rápida del Anchor

Fecha: 2026-08-23  
Estado: aprobado por el usuario

## Contexto

La actualización OTA v8→v9 quedó validada físicamente, pero el transporte
stop-and-wait entrega cerca de diez bloques por segundo. Dos límites evitables
dominan el tiempo: Android conserva la prioridad BLE balanceada y cada bloque
transporta 384 bytes aunque el enlace y el firmware admiten más.

## Objetivo

Reducir una actualización de aproximadamente 740 KB desde tres o cuatro minutos
a cerca de un minuto, sin cambiar el protocolo OTA, la verificación Ed25519, el
formato del manifiesto ni la lógica de escritura del firmware.

## Decisiones

- Android solicita `CONNECTION_PRIORITY_HIGH` únicamente mientras hay una OTA
  activa por un enlace GATT cliente.
- Android restaura `CONNECTION_PRIORITY_BALANCED` al recibir aceptación para
  reinicio, confirmar la versión nueva, fallar o detener la malla.
- Si el teléfono no controla el enlace como cliente GATT, la operación continúa
  con prioridad normal; la optimización nunca es requisito funcional.
- El bloque predeterminado de los nuevos manifiestos será de 472 bytes. El
  firmware conserva el rango compatible de 64 a 480 bytes.
- iOS no cambia porque CoreBluetooth no expone una API equivalente para fijar la
  prioridad de conexión.

## Tamaño de bloque

El valor GATT máximo negociado es de 512 bytes. Una respuesta OTA dirigida suma
la cabecera del paquete mesh y ocho bytes de versión e índice. Un bloque de 472
bytes conserva margen para viajar como una sola escritura y evita activar la
fragmentación de malla. Los Anchors existentes aceptan el manifiesto sin cambio
de protocolo.

`tools/sign_fw.py` usará 472 como valor predeterminado. El parámetro explícito
`--chunk-size` seguirá disponible para compatibilidad y diagnóstico.

## Flujo Android

1. `startAnchorOta` valida el paquete, resuelve el enlace directo y crea la
   transferencia.
2. Si existe `clientGatts[sourceAddress]`, solicita prioridad alta antes de
   enviar `OTA_MANIFEST`.
3. Una reconexión que reanuda la transferencia vuelve a solicitar prioridad
   alta sobre el nuevo `BluetoothGatt`.
4. La recepción de `OTA_STATUS=0` restaura prioridad balanceada antes de esperar
   el reinicio.
5. Las rutas de éxito, error y detención también restauran prioridad balanceada
   de forma idempotente.

La solicitud de prioridad es una sugerencia al controlador Bluetooth. Un retorno
`false` o una excepción no abortan la OTA.

## Recuperación del Anchor

El Anchor `Bitle-5528` aparece protegido con una clave desconocida. Antes de la
validación se borrará la flash por USB y se instalará de nuevo v9. Esto elimina
la configuración administrativa y genera una identidad nueva. El usuario
reclamará el dispositivo desde la app con una clave definitiva que no se
registrará en código, terminales ni documentación.

La contraseña administrativa no autoriza firmware. La OTA sigue protegida por
el manifiesto Ed25519 y puede operar antes o después del reclamo.

## Release y validación

- Compilar firmware v10 con `BITLE_FW_VERSION=10`.
- Firmar `bitle.bin` con el manifiesto v10 y bloque de 472 bytes.
- Validar y copiar ambos artefactos a `app/assets/firmware/`.
- Instalar la app en Android y actualizar físicamente v9→v10.
- Medir duración total y confirmar versión v10 después del reinicio.
- Verificar que una falla o ausencia de enlace GATT cliente conserva el
  comportamiento funcional anterior.

## Pruebas

- Tests Android para solicitud y restauración de prioridad mediante una unidad
  aislada de política/coordinación, sin depender de hardware Bluetooth.
- Tests existentes del protocolo para límites y encuadre de bloques.
- `flutter analyze`, suite Flutter y suite Android.
- Build ESP-IDF para ESP32-S3 N16R8.
- Prueba física de borrado, flash v9, reclamo manual y OTA v9→v10.

## Implementation delta (cierre 2026-08-24)

- Android `CONNECTION_PRIORITY_HIGH` se solicita y restaura de forma
  idempotente en todas las rutas terminales dentro de `MeshEngine.kt`.
- `tools/sign_fw.py` usa 472 bytes como chunk default; `--chunk-size`
  sigue disponible para diagnóstico.
- iOS sin cambios (CoreBluetooth no expone equivalente).
- Pendiente (hardware): medición física de v9→v10 en ESP32-S3 N16R8
  con la app Android; ver `2026-08-24-anchor-p0-hardware-validation.md`.
- Pendiente (operación): borrado + flash + reclamo manual del
  `Bitle-5528` con clave no registrada en código.

## Criterios de éxito

1. La OTA v9→v10 termina inalámbricamente y el panel confirma v10.
2. El manifiesto empaquetado declara bloques de 472 bytes.
3. Android solicita prioridad alta durante la transferencia y la restaura en
   todas las rutas terminales.
4. La optimización no convierte la prioridad alta en requisito de actualización.
5. Ninguna clave administrativa o privada de firma entra al repositorio o a los
   logs.
