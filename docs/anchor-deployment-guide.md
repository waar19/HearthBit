# Guía de despliegue del ancla Bitle

## Estado y alcance

Esta guía describe el firmware fijado en `firmware/anchor-node` y sus cambios
locales sin commit al momento de esta entrega. No es una guía genérica para
ESP32. La instalación y el flujo store-and-forward aquí definidos **no han sido
validados físicamente en esta entrega**: `P0-STORE-REBOOT` y los demás gates P0
que dependen de radios, teléfonos o aislamiento físico continúan `PENDING` o
`BLOCKED`.

No se garantiza cobertura ni alcance en metros. Antes de decidir cantidad,
altura o ubicación, ejecute la
[guía de densidad y ubicación](anchor-density-guide.md) como un *site survey*
con el hardware, caja, antena, potencia, interferencia y carga reales.

Fuentes de verdad complementarias:

- [README del firmware Bitle](../firmware/anchor-node/README.md).
- [procedimiento OTA del firmware](../firmware/anchor-node/docs/OTA.md).
- [gate físico `P0-STORE-REBOOT`](p0-execution-guide.md#p0-store-reboot).

## 1. Hardware e instalación

### Plataformas soportadas por este firmware

- **ESP32-C3:** Seeed XIAO ESP32C3 con antena de 2,4 GHz. Opera como relay BLE y,
  si `msgstore` está disponible, como buzón courier.
- **ESP32-S3:** Seeed XIAO ESP32S3 con el mismo firmware. Sin SX1262 opera solo
  por BLE.
- **LoRa opcional en S3:** el mapeo implementado corresponde al kit Seeed
  XIAO ESP32S3 + Wio-SX1262. El firmware sondea la radio al arrancar; solo
  anuncia `LONG_RANGE_TRUNK` después de que el troncal quedó operativo. C3 y S3
  sin radio detectada continúan por BLE.

LoRa es troncal entre anclas, no acceso directo para teléfonos. Antes de
transmitir, confirme frecuencia, potencia, antena, ciclo de trabajo y
homologación aplicables al país y al sitio. La ausencia de autorización deja la
prueba `BLOCKED_REGULATORY`.

### Energía y caja

El hardware de referencia documenta USB para banco y provisión, y batería
LiPo, cargador solar y panel para operación autónoma. No dimensione batería o
panel con una cifra teórica: mida el conjunto real, incluida la radio SX1262 si
existe, y deje margen por temperatura, envejecimiento, clima y días sin sol.

Use una caja resistente al ambiente previsto, con alivio de tensión, protección
eléctrica y gestión térmica compatibles con batería y cargador. Una caja
metálica o una antena encerrada detrás de metal puede degradar o bloquear la
radio.

### Ubicación como hipótesis de survey

Altura, orientación y separación son variables a ensayar, no recetas:

1. Pruebe varias alturas seguras y orientaciones de antena; más altura no
   garantiza mejor resultado dentro de edificios.
2. Separe la antena de metal, concreto armado, racks, vehículos, agua,
   vegetación húmeda y fuentes de interferencia de 2,4 GHz.
3. Mida con Wi-Fi, microondas, generadores, radios y ocupación en condiciones
   representativas.
4. Use controles negativos para demostrar que los extremos no tenían un enlace
   directo que evitara el ancla.
5. Evite que una ruta crítica dependa de una sola ancla, fuente, antena, caja o
   troncal. Valide la ruta alternativa retirando deliberadamente un elemento.

Registre ubicación con alias operativo y acceso restringido; no publique
direcciones personales, coordenadas sensibles, MAC, peer IDs ni claves.

## 2. Preparación, compilación y provisión

### Prerrequisitos

- ESP-IDF **v6.0**, que es la versión desarrollada y probada por el firmware.
- Submódulo inicializado y toolchain de ESP-IDF exportado en la terminal.
- Cable de datos, puerto COM identificado y alimentación estable.
- Flash de 4 MiB compatible con la tabla `partitions.csv`.

Desde PowerShell en Windows:

```powershell
cd C:\src\emergency-com
git submodule update --init --recursive
cd firmware\anchor-node
idf.py --version
```

El resultado debe identificar ESP-IDF v6.0. No trate como validada otra versión
solo porque compile.

### ESP32-C3

```powershell
idf.py set-target esp32c3
idf.py build
idf.py -p COM5 flash monitor
```

### ESP32-S3

```powershell
idf.py set-target esp32s3
idf.py build
idf.py -p COM6 flash monitor
```

Cambie `COM5`/`COM6` por el puerto real. El kit S3 + Wio-SX1262 documentado se
entrega con Meshtastic; para su **primera** provisión Bitle, el README del
firmware indica ejecutar `idf.py -p COM6 erase-flash` antes de `flash`. Es un
borrado destructivo de toda la flash, no un procedimiento de actualización.

### Particiones que deben quedar instaladas

La tabla de 4 MiB es parte del contrato OTA y de persistencia:

- `nvs`: `0x6000` (24 KiB), claves de identidad, nickname, reloj, manifiesto OTA
  persistido y `boot_count`.
- `phy_init`: `0x1000` (4 KiB).
- `otadata`: `0x2000` (8 KiB), selección A/B.
- `fw_manifest`: `0x1000` (4 KiB), manifiesto OTA firmado de 110 bytes.
- `ota_0` y `ota_1`: `0x1C0000` cada una (1792 KiB), slots A/B.
- `msgstore`: `0x60000` (384 KiB), anillo de sectores para courier.

La tabla A/B y `msgstore` deben flashearse por cable antes de sellar la caja. No
pueden añadirse remotamente a un nodo instalado con una tabla distinta.

### Identidad y nickname

En el primer arranque, el firmware genera y persiste en el namespace NVS
`noise`:

- clave privada estática Curve25519 para Noise XX (`static`);
- peer ID de 8 bytes derivado de SHA-256 de la clave pública Noise (`peer_id`);
- clave privada Ed25519 (`sign_sk`) y su pública (`sign_pk`).

La identidad se reutiliza mientras NVS sobreviva. El nickname de aplicación se
deriva como `Bitle-####` del peer ID y se guarda como `noise/nickname`. El
firmware acepta un nombre ASCII imprimible de 1 a 31 caracteres escrito
directamente en esa clave NVS, pero no existe un comando de runtime conectado
para establecerlo o regenerarlo. `Bitle Relay` es el nombre BLE fijo; no es el
nickname de la malla.

### OTA firmado y versión

`BITLE_FW_VERSION`, en `main/bitle_ota.h`, es el contador monotónico que compara
imágenes; en el árbol actual vale **5**. No es una versión comercial. Para cada
release:

1. incremente ese valor;
2. compile;
3. firme `build/bitle.bin` con el mismo número;
4. distribuya primero el manifiesto Ed25519 de 110 bytes y luego la imagen.

El procedimiento y los comandos canónicos están en
[`firmware/anchor-node/docs/OTA.md`](../firmware/anchor-node/docs/OTA.md). La
clave pública owner se compila en `main/ota_owner_pubkey.h`; la privada se
mantiene offline y fuera del repositorio. Una flota propia debe generar su owner
key antes de construir las imágenes que desplegará.

La imagen se escribe en el slot OTA inactivo y su SHA-256 se vuelve a comprobar
antes de cambiar el arranque. El nuevo slot inicia en prueba de rollback. Una
capacidad de radio y criptografía funcional queda demostrada cuando verifica
end-to-end el anuncio de un peer; entonces se marca válido. Si no aparece ningún
peer, el firmware actual aplica un fallback a los 30 minutos de uptime y también
lo marca válido para evitar un bucle de rollback en un sitio vacío. Un reset
antes de quedar válido permite al bootloader volver al slot anterior.

## 3. Contrato de red exacto

### Visibilidad, capacidad y buzón no son equivalentes

- **Firmware visible:** aparece el servicio BLE BitChat y puede recibirse su
  `ANNOUNCE`. Esto solo prueba descubrimiento.
- **Capacidad visible:** después de identidad/anuncio, el teléfono acepta un
  `NODE_CAPABILITY` tipo `0x25` de tres bytes únicamente si su firma Ed25519
  verifica contra la identidad anunciada.
- **Mailbox disponible:** `bitle_store_init()` encontró e inició `msgstore`.
  Solo entonces el firmware anuncia rol de data anchor y acepta depósitos.

El payload firmado `NODE_CAPABILITY` es exactamente:

- mailbox disponible, BLE: `[0x01, 0x04, 0x05]`;
- mailbox disponible, LoRa operativo: `[0x01, 0x04, 0x15]`;
- mailbox no disponible, BLE: `[0x01, 0x03, 0x01]`;
- mailbox no disponible, LoRa operativo: `[0x01, 0x03, 0x11]`.

Byte 0 es versión `0x01`; byte 1 es rol (`0x04`
`INFRA_DATA_ANCHOR`, `0x03` `INFRA_RELAY`); byte 2 son flags. `RELAY` es
`0x01`, `STORE` es `0x04` y `LONG_RANGE_TRUNK` es `0x10`. El nickname, el
nombre BLE, el TLV privado de firmware `0xB0` o el marcador cosmético de
infraestructura `0xB1` no sustituyen esa capacidad firmada.

### BLE y courier

El nodo ejecuta NimBLE simultáneamente como periférico GATT para teléfonos y
como central que busca otras anclas. El perfil actual configura **6 conexiones
totales**, limita a **2** los enlaces salientes entre anclas y solo inicia uno si
quedan al menos **2** plazas libres para conexiones entrantes. Es un presupuesto
de conexiones, no una cantidad garantizada de usuarios.

Courier usa el paquete BitChat tipo `0x04`. El paquete de depósito debe llegar
por el enlace Noise directo de su emisor, con identidad anunciada/verificada y
firma Ed25519 válida. El ancla almacena el sobre como bytes opacos; el
ciphertext privado Noise no se descifra en el ancla. Límites actuales:

- máximo **128** sobres courier globales;
- máximo **8** por depositor;
- expiración máxima **25 horas** desde la aceptación;
- `msgstore` de **384 KiB**, organizado como anillo de sectores flash.

Una repetición con el mismo ciphertext es idempotente. El índice usa una clave
de 16 bytes derivada de SHA-256 del ciphertext.

## 4. Arranque, reinicio y operación

### Secuencia observable

Con `idf.py -p COM5 monitor`, un arranque normal muestra, entre otros:

- `Starting Bitle firmware`;
- `Mailbox ready: ...` o
  `msgstore partition missing; mailbox disabled`;
- una línea `HBIT_METRICS`;
- `no SX1262 radio; running BLE-only` o `trunk up: ...`;
- inicio BLE y `Bitle task running`.

La mayoría de fallos de inicialización son fatales. El mailbox es la excepción:
si falla, el nodo registra `Courier mailbox unavailable; continuing without it`
y sigue como `INFRA_RELAY`.

Para un reinicio controlado, conserve la alimentación estable, marque UTC,
presione reset/EN o haga un ciclo de energía y vuelva a observar el arranque.
No borre flash ni NVS durante una prueba de persistencia.

### Reconstrucción y handoff

En cada boot, `bitle_store_init()` escanea los sectores de `msgstore`, valida
CRC, omite registros expirados, resuelve duplicados conservando la copia del
sector con secuencia más nueva y reconstruye el índice en RAM. Por eso
`packets_stored` vuelve a cero al reiniciar, pero `courier_store_used` debe
reflejar los registros vivos reconstruidos.

Cuando reaparece un peer verificado, el ancla calcula sus tags de destinatario
para día anterior, actual y siguiente:

- si el propietario está en enlace directo, envía el sobre y lo elimina del
  store después de un envío exitoso;
- si el propietario se oyó por la malla, reenvía una copia, conserva la local y
  aplica cooldown;
- si aparece otro carrier directo verificado y quedan varias copias, puede
  transferirle parte de ellas.

El estado auxiliar RAM que recuerda carriers ya usados y cooldown se pierde en
un reboot. El registro flash y su contador de copias permanecen; la única
consecuencia prevista en código es un reenvío redundante, que el receptor
deduplica por ciphertext.

### Métricas sin PII

El firmware emite `HBIT_METRICS` al arrancar y aproximadamente cada 10 minutos:

`uptime_ms`, `boot_count`, `packets_received`, `packets_forwarded`,
`packets_stored`, `packets_delivered`, `packets_deduplicated`,
`packets_expired`, `packets_rejected`, `courier_store_used`,
`courier_store_capacity`, `last_activity_uptime_ms`, `firmware_version`,
`protocol_version` y `mailbox_available`.

Los contadores son agregados y saturantes. Salvo `boot_count`, se reinician con
el proceso. `packets_delivered` cuenta handoffs courier salientes exitosos,
incluidos propietario directo, ruta hacia propietario y spray a carrier; no
prueba por sí solo recepción final. Si el mailbox no está disponible,
`mailbox_available=false` y ambos campos `courier_store_*` son cero.

La línea de métricas no incluye IDs, contenido, tags ni coordenadas, pero otros
logs serie sí pueden incluir MAC, nickname o identificadores. Capture solo esa
línea:

```powershell
idf.py -p COM5 monitor 2>&1 |
  Select-String -Pattern 'HBIT_METRICS' |
  Tee-Object -FilePath .\HBIT_METRICS-P0-STORE-REBOOT.txt
```

Use un archivo separado para cada corrida, UTC y alias no personales. No
publique el log serie completo sin sanearlo.

## 5. Seguridad y acceso físico

- Noise XX usa una identidad Curve25519 persistente y los anuncios/capacidades
  se vinculan con Ed25519.
- El perfil `sdkconfig.defaults` versionado **no habilita flash encryption ni
  Secure Boot**. Las claves privadas de identidad están en NVS sin protección
  de cifrado de flash aportada por este perfil.
- La owner key OTA autentica actualizaciones aceptadas por el firmware; no
  cifra NVS ni sustituye Secure Boot.
- Un atacante con acceso físico puede intentar leer, borrar o reemplazar flash.
  Proteja caja, puerto USB, reset, alimentación y cadena de custodia de cada
  ancla.
- No existe en la documentación del firmware un procedimiento operativo de
  factory reset o reprovisión de identidad. `erase-flash` solo está documentado
  para retirar Meshtastic antes de la primera provisión S3 y destruye la flash;
  no lo use como recuperación rutinaria ni durante un gate.
- Si NVS detecta páginas agotadas o una versión/layout incompatible, el arranque
  la borra y reinicializa. Eso puede regenerar identidad y rompe la continuidad
  esperada del peer; trátelo como incidente y vuelva a incorporar el nodo bajo
  el procedimiento de confianza del sitio.

## 6. Checklist ejecutable de validación

Use un marcador sintético único, dos teléfonos `A` y `B`, y un ancla. Mantenga
`B` fuera de línea y descarte un enlace directo `A↔B`. Cada punto exige su
observable; si falta, es `FAIL` o `BLOCKED` cuando la causa sea una precondición
externa documentada.

1. **Ancla visible.** Observable: `A` descubre el servicio BitChat y el
   `ANNOUNCE` del alias previsto. **FAIL:** no aparece, cambia de identidad sin
   explicación o solo se observa un nombre BLE sin anuncio utilizable.
2. **Rol/capacidad store correctos.** Observable: capacidad firmada
   `[01,04,05]` para BLE o `[01,04,15]` con troncal operativo, más
   `mailbox_available=true`. **FAIL:** rol `0x04` sin flag `0x04`, flag LoRa sin
   troncal operativo, firma inválida o contradicción con métricas.
3. **El teléfono reconoce data anchor.** Observable: snapshot/UI/diagnóstico de
   `A` clasifica el peer como `INFRA_DATA_ANCHOR` después de procesar
   `NODE_CAPABILITY` firmado. **FAIL:** se infiere por nickname, nombre BLE o
   marcador de infraestructura, o queda como relay.
4. **El teléfono deposita courier.** Con `B` offline, `A` establece Noise con el
   ancla y envía el paquete courier `0x04` firmado. Observable:
   `Envelope deposited (...)` y ausencia de rechazo de firma/identidad.
   **FAIL:** envío por peer no directo, sesión no establecida, firma no
   verificada o no aparece aceptación.
5. **`store used` incrementa.** Observable: una línea posterior muestra
   `courier_store_used` exactamente una unidad sobre el baseline y
   `packets_stored` incrementado. **FAIL:** no cambia, aumenta más de lo
   explicado por la corrida o solo cambia `packets_received`.
6. **Courier permanece antes del reboot.** Observable: una segunda lectura,
   antes del reinicio y con `B` aún offline, mantiene
   `courier_store_used > 0`. **FAIL:** cae a cero, expira durante una ventana que
   debía estar vigente o se entrega a un peer no previsto.
7. **Reboot ejecutado.** Observable: UTC de inicio/fin, nueva secuencia de boot y
   `uptime_ms` reiniciado. **FAIL:** se borró flash/NVS, se cambió firmware o no
   puede demostrarse el reinicio.
8. **`boot_count` aumenta y el store sigue.** Observable: `boot_count` es mayor
   que el previo y `courier_store_used` conserva el registro reconstruido;
   `Mailbox ready: 1 carried record(s)` es evidencia adicional. **FAIL:**
   `boot_count` no aumenta, `mailbox_available=false` o el registro vigente
   desaparece. No exija que `packets_stored` sobreviva: ese contador reinicia.
9. **Peer destino reaparece.** Ponga `B` online. Observable: anuncio de `B` con
   identidad y firma verificadas, mientras el control físico sigue descartando
   `A↔B`. **FAIL:** anuncio no verificado, identidad inesperada o topología
   permite entrega directa.
10. **Courier recuperado/reenviado.** Observable: `Handed ... envelope(s) toward
    peer`, aumento de `packets_delivered` y recepción única del marcador por
    `B`; en entrega directa, `courier_store_used` disminuye. **FAIL:** no hay
    handoff, contenido no llega, llega a otro peer o aparece más de una copia.
11. **ACK si aplica.** Observable: ACK propio del mensaje/SOS y del transporte
    bajo prueba, vinculado al marcador. Un courier que contiene ciphertext
    privado Noise **no es por sí mismo un SOS ACK** ni prueba que una persona lo
    recibió. Registre `ACK: unavailable` cuando ese flujo no lo defina.
    **FAIL:** se infiere ACK de depósito, `packets_delivered`, handoff o
    visibilidad del peer.
12. **Métricas y evidencia.** Observable: líneas `HBIT_METRICS` antes del
    depósito, antes del reboot, después del reboot y después del handoff; UTC,
    versiones, alias, resultado visual, control negativo, archivos saneados y
    SHA-256. **FAIL:** faltan baselines, hay PII/IDs/contenido real, TTL se usa
    como conteo de saltos o la evidencia no descarta una ruta directa.

Un build correcto, un test automatizado o un peer visible no convierte este
checklist en `PASS` físico. La decisión requiere revisar toda la evidencia del
gate.

## 7. Troubleshooting mínimo

- **`msgstore` ausente:** aparece `msgstore partition missing; mailbox
  disabled`, luego el nodo continúa relay-only. Debe emitir `[01,03,01]` o
  `[01,03,11]` y `mailbox_available=false`. Si anuncia data anchor, es `FAIL`.
  Corrija la tabla por cable; no intente crear la partición por OTA.
- **Firma inválida o peer no verificado:** espere
  `courier deposit signature invalid`, `courier deposit without verified
  identity` o `Rejected deposit from unverified peer`, con incremento de
  `packets_rejected`. Restablezca primero anuncio verificado y Noise directo; no
  omita la verificación.
- **Buzón lleno, cuota o expiry:** `Mailbox full` y `Depositor quota reached`
  incrementan `packets_rejected`; un sobre ya expirado incrementa
  `packets_expired`; una vida mayor de 25 h incrementa `packets_rejected`.
  No borre registros para hacer pasar el gate: use otro marcador/corrida y
  documente el límite observado.
- **No hay LoRa:** `no SX1262 radio; running BLE-only` es normal en C3 o S3 sin
  módulo y debe omitir `0x10`. En el kit S3, revise montaje, antena y
  alimentación antes de esperar `trunk up`; no anuncie cobertura por observar
  solo ese log.
- **Rollback OTA:** busque `Running unverified image ...`, después
  `marked healthy; rollback cancelled` o el fallback de 30 minutos. Si el nodo
  reinicia antes de validarse y vuelve a la versión anterior, preserve ambos
  boots, la versión y el motivo; no repita OTA hasta verificar owner key,
  manifiesto, SHA-256 y salud de radio/criptografía conforme a
  [OTA.md](../firmware/anchor-node/docs/OTA.md).

## 8. Gate de salida

Esta entrega deja lista la documentación, no el despliegue físico. Mantenga el
estado `PENDING` hasta ejecutar el checklist con hardware real, aislamiento
demostrable, capacidad firmada, persistencia a través de reboot, recepción única
y evidencia saneada. Cualquier dependencia regulatoria, de hardware o de
plataforma no satisfecha debe quedar `BLOCKED`, no asumida.
