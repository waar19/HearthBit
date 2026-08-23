# OTA inalámbrico del Anchor desde HearthBit

Fecha: 2026-08-22  
Estado: aprobado por el usuario

## Contexto

El firmware del Anchor ya implementa actualizaciones OTA con particiones duales,
manifiestos Ed25519, verificación SHA-256, protección contra downgrade, rollback y
propagación nodo a nodo. La aplicación todavía no puede sembrar una actualización.
Además, no existe en esta estación la clave privada correspondiente a la clave pública
compilada en firmware v7. Por eso, la primera versión utilizable por la app requiere una
última instalación por cable con una clave nueva bajo control del propietario.

## Objetivo

Permitir que un operador actualice un Anchor desde su panel administrativo por BLE,
sin internet ni cable, usando una imagen y un manifiesto firmado incluidos en HearthBit.
La interfaz debe mostrar disponibilidad, progreso, errores y confirmación de la versión
nueva después del reinicio.

## Decisiones

- La app incluye `bitle.bin` y `bitle.bin.bota`; no descarga firmware.
- Kotlin y Swift sirven los fragmentos desde el motor mesh nativo. Flutter inicia la
  operación y presenta su estado.
- La firma Ed25519 autoriza la imagen. La contraseña administrativa no firma ni autoriza
  firmware.
- La clave privada vive fuera del repositorio. Solo la clave pública se compila.
- La primera versión es v8 y se instala por cable. Una v9 valida el flujo inalámbrico.

## Ceremonia de claves y confianza

`tools/gen_owner_key.py` genera:

- `~/bitle-keys/bitle_owner_key.hex`: clave privada. Debe respaldarse cifrada y fuera del
  equipo. Nunca se incluye en Git, assets, logs ni artefactos de CI.
- `main/ota_owner_pubkey.h`: clave pública que sí se versiona y compila.

Perder la privada impide publicar actualizaciones para esos Anchors. Su filtración
permite firmar firmware aceptado por la flota. La rotación futura exige una versión
firmada por la clave vigente que instale una clave pública nueva.

## Artefactos de lanzamiento

`tools/sign_fw.py` firma el binario y produce un manifiesto fijo de 110 bytes:

```text
"BOTA":4 | version:u32 | size:u32 | sha256:32 | chunk:u16 | signature:64
```

Los enteros son big-endian. La firma cubre
`"bitle-fw-v1" || version || size || sha256 || chunk`. La app valida estructura,
tamaño declarado y versión para presentar la actualización; el Anchor realiza la
validación criptográfica autoritativa.

Los dos archivos se empaquetan en `app/assets/firmware/`. Cada release debe compilar,
firmar y copiar ambos artefactos juntos. La versión del manifiesto debe coincidir con
`BITLE_FW_VERSION`.

## Arquitectura y flujo

1. Flutter lee el manifiesto empaquetado y compara su versión con `STATUS_GET`.
2. Si la versión empaquetada es mayor, el panel ofrece actualizar.
3. El código nativo recibe los bytes del manifiesto y del binario y envía
   `OTA_MANIFEST` (`0xA0`) dentro de la sesión Noise actual.
4. El Anchor verifica firma, versión, tamaño y disponibilidad de partición.
5. El Anchor dirige stop-and-wait mediante `OTA_REQ` (`0xA1`), con versión e índice.
6. El teléfono valida cada petición y responde `OTA_CHUNK` (`0xA2`) con versión,
   índice y el intervalo exacto del binario. Reporta progreso a Flutter.
7. El Anchor reintenta la petición si no recibe respuesta en cuatro segundos.
8. Al completar, verifica SHA-256, informa `OTA_STATUS` (`0xA3`) y reinicia.
9. HearthBit se reconecta y consulta `STATUS_GET`. Ver la versión objetivo confirma
   éxito en la UI y aporta la actividad de red necesaria para marcar la imagen sana.

Solo puede existir una transferencia OTA activa. Las operaciones administrativas
mutables se bloquean mientras dure y el sondeo de gráficas se pausa para no competir
por el enlace.

## Contrato nativo con Flutter

La API del plugin expone una operación de inicio con peer, manifiesto e imagen, y emite
eventos asociados al peer:

- `preparing`: validación local.
- `transferring`: bytes enviados, bytes totales y porcentaje.
- `rebooting`: el Anchor aceptó la imagen y se espera desconexión.
- `completed`: la reconexión confirmó la versión objetivo.
- `failed`: código estable y detalle presentable.

Kotlin y Swift mantienen la misma máquina de estados y rechazan solicitudes con versión,
índice o longitud fuera del manifiesto. Cancelación, desconexión o cambio de peer limpian
el estado en memoria sin enviar datos a otro Anchor.

## Interfaz

En `AnchorAdminScreen` se muestra:

- tarjeta de disponibilidad con versión actual y versión empaquetada;
- confirmación que advierte duración estimada y pide mantener el teléfono cerca;
- progreso determinado durante la transferencia;
- espera de reinicio y reconexión;
- éxito únicamente tras observar la versión objetivo;
- error accionable para firmware no válido, versión no superior, rechazo del Anchor,
  desconexión o tiempo agotado.

La UI no promete reanudación desde flash después de cerrar la app. Una pérdida breve
del enlace se tolera mientras la sesión nativa siga activa y el Anchor continúe
solicitando. Si la operación termina, reintentar puede reiniciar la escritura según el
estado conservado por el firmware.

## Compatibilidad y errores

- App nueva con Anchor v7: ofrece v8.
- App nueva con Anchor v8 o superior: no ofrece una versión igual o anterior.
- App anterior con Anchor v8: sigue operando; desconoce la función OTA del teléfono.
- Firma o hash inválidos: el Anchor conserva la versión anterior.
- Reinicio o fallo de salud: el bootloader revierte al slot anterior.
- Binario ausente o inconsistente en assets: la app no inicia la transferencia.
- Fondo de la app: Android mantiene la operación en el motor activo; iOS informa que
  debe permanecer abierta por las restricciones de ejecución BLE.

## Pruebas

- Dart: parseo del manifiesto válido y rechazo de magic, longitud, tamaño y chunk
  inválidos.
- Kotlin: framing de manifiesto, respuesta de chunk, límites, progreso, estado remoto,
  desconexión y limpieza.
- Swift: pruebas equivalentes donde la infraestructura actual lo permita; como mínimo,
  funciones puras verificables y compilación.
- Flutter: tarjeta oculta/visible según versión, diálogo, progreso y errores.
- Firmware: build ESP32-S3, manifiesto v8 firmado y validación de particiones.
- Hardware: instalar v8 por cable y sembrar su manifiesto; crear v9, empaquetarla,
  instalarla desde Android por BLE, comprobar reinicio, reconexión, versión v9 y ausencia
  de rollback.

## Criterios de éxito

1. Una placa con v8 y la clave pública nueva acepta v9 desde HearthBit sin cable ni
   internet.
2. La app nunca transfiere una imagen igual, anterior, corrupta o incoherente con su
   manifiesto.
3. El operador ve progreso y un resultado inequívoco.
4. Una interrupción o imagen fallida deja el Anchor arrancable en la versión anterior.
5. La clave privada no aparece en Git, assets, logs ni binarios de la aplicación.
