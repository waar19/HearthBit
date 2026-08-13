# Nodo ancla ESP32

El firmware fijado en `firmware/anchor-node` es Bitle. Funciona en ESP32-C3 y
ESP32-S3 con ESP-IDF 6, anuncia el servicio BitChat, ejecuta Noise XX, retransmite
paquetes y mantiene correo cifrado store-and-forward.

## Hardware recomendado

- Seeed XIAO ESP32-C3 con antena de 2,4 GHz para una casa.
- Alimentación USB estable, o batería LiPo con cargador y panel solar.
- Caja ventilada para interior o caja IP65 con control térmico para exterior.
- ESP32-S3 + SX1262 solo si se necesita un troncal LoRa entre barrios.

En Colombia, verifique con la ANE la frecuencia y potencia permitidas antes de
activar LoRa. El perfil Bitle documenta 915 MHz; no asuma que una configuración
de otro país es legal localmente.

## D1-LORA-01 — dos islas BLE (guion no ejecutado)

Este caso es una especificación reproducible pendiente de hardware; no afirma
que el troncal haya sido probado. Requiere dos kits Seeed XIAO ESP32-S3 +
Wio-SX1262, cada uno con antena adecuada conectada antes de energizar, y dos
teléfonos HearthBit, `HB-A` y `HB-B`. Los nodos se denominan `LR-A` y `LR-B`.

La topología objetivo es
`HB-A ↔BLE↔ LR-A ↔LoRa↔ LR-B ↔BLE↔ HB-B`. Las dos islas BLE deben aislarse de
modo que los teléfonos no se descubran ni entreguen mensajes directamente. Con
ambos SX1262 deshabilitados o con uno de los nodos apagado, un marcador de
control no debe llegar. Sin cambiar distancias ni obstáculos, se habilita el
troncal, se comprueba en cada consola `trunk up`, y se envía un marcador único
de ida y otro de vuelta.

La app solo debe mostrar «troncal de largo alcance activo» después de recibir
un `NODE_CAPABILITY` autenticado con `LONG_RANGE_TRUNK` (`bit 4`, `0x10`). El
nombre Bitle, el rol `INFRA_RELAY`/`INFRA_DATA_ANCHOR` o el indicador histórico
de infraestructura no prueban que exista una radio operativa. Un firmware que
no emita ese bit puede transportar el experimento, pero la UI debe mostrar
únicamente el rol conocido y la evidencia queda incompleta para validar la
visibilidad de capacidad.

Conserve por separado los logs serie saneados de ambos nodos y los logs de app,
incluyendo horas UTC, marcadores, `trunk TX`, `trunk RX packet`, RSSI/SNR,
recepción visual y los dos controles negativos. `PASS` exige entrega exacta y
única en ambos sentidos solo con el troncal activo, además del flag `0x10`
visible. Entrega durante un control negativo, una dirección ausente,
duplicados, rol/capacidad inferidos o logs insuficientes es `FAIL` o `BLOCKED`
según corresponda. El procedimiento completo está en `docs/field-test.md`.

**Antes de cualquier transmisión**, valide con la ANE Colombia la frecuencia,
potencia, antena, ciclo de trabajo y demás condiciones aplicables al lugar y a
la fecha de la prueba. Si no existe confirmación normativa, mantenga las radios
sin transmitir y registre el caso como `BLOCKED`.

## Preparación

```powershell
git submodule update --init --recursive
cd firmware\anchor-node
idf.py set-target esp32c3
idf.py build
idf.py -p COM5 flash monitor
```

Cambie `COM5` por el puerto real. Para ESP32-S3 use `idf.py set-target esp32s3`.

## Claves OTA

Antes de sellar una flota propia, genere su clave de propietario:

```powershell
python tools\gen_owner_key.py
```

No confirme la clave privada en Git ni la copie a los nodos. Guárdela offline
con respaldo. Perderla impide futuras actualizaciones; filtrarla permite a un
atacante firmar firmware para toda la flota.

## Despliegue

1. Pruebe cada nodo durante 24 horas antes de instalarlo.
2. Colóquelo alto, alejado de metal, hornos microondas y routers saturados.
3. Mantenga línea de vista hacia calles o casas vecinas cuando sea posible.
4. Registre coordenadas y responsable, pero no publique claves ni direcciones
   personales.
5. Revalide cobertura y batería cada tres meses.

El firmware y sus instrucciones completas conservan la licencia MIT y
atribución del proyecto Bitle dentro del submódulo.

## Límites del ESP32 para transferencias de archivos

El ancla ESP32 es un relay de **mensajes**, no un nodo de datos. Sus límites
medidos y estructurales son:

- **Reensamblado ~2 KB:** el buffer de fragmentación del firmware Bitle
  reconstruye paquetes BitChat de hasta ~2 KB. Sirve para texto, anuncios,
  SOS y tramas de control HBT (ofertas, ACCEPT, progreso), pero no para
  chunks de datos sostenidos.
- **RAM total 320–512 KB** (C3/S3), compartida con las pilas BLE y Wi-Fi.
  No hay espacio para bitmaps de chunks ni colas de archivos.
- **Flash de 4–8 MB** ya ocupada por firmware, OTA A/B y el correo
  store-and-forward cifrado. Un solo archivo de cámara la agotaría.
- **Contención 2,4 GHz:** BLE y Wi-Fi comparten la misma radio; saturarla
  con datos degrada el relay de mensajes, que es su función crítica.

Por eso el plano de datos HBT (Nearby, LAN, Wi-Fi Aware, óptico) nunca pasa
por el ancla: el ESP32 solo transporta el plano de control cifrado por Noise
y los archivos «inline» BLE pequeños entre teléfonos directamente conectados.

## HearthBit Data Anchor (diseño)

Para guardar y reenviar **archivos grandes** en un barrio sin internet se
define un nodo separado, el *Data Anchor*, basado en hardware con almacenamiento
real. No sustituye al ancla ESP32: la complementa.

### Hardware objetivo

| Opción | Base | Ventaja |
| ------ | ---- | ------- |
| A (recomendada) | Raspberry Pi Zero 2 W / Pi 4 + microSD ≥ 64 GB | Linux completo, Wi-Fi AP + BLE simultáneos, bajo consumo (~1–3 W) |
| B | Router OpenWrt con USB (p. ej. GL.iNet) | AP robusto de fábrica, PoE posible, carcasa lista |
| C (experimento posterior) | ESP32-S3 + microSD | Coste mínimo, pero limitado por RAM y contención 2,4 GHz; solo para colas pequeñas |

Alimentación: batería LiFePO4 + panel solar dimensionados para ≥ 72 h de
autonomía; el AP Wi-Fi se enciende bajo demanda (anuncio BLE) para ahorrar.

### Funciones

1. **Relay BitChat completo** (igual que el ESP32) por BLE.
2. **Caché cifrada de archivos:** recibe contenedores HBT cifrados de
   extremo a extremo y los reenvía cuando aparece el destinatario. El ancla
   **nunca** posee claves de descifrado: almacena bytes opacos con el
   `transferId`, el destinatario y la expiración como únicos metadatos.
3. **AP Wi-Fi local:** publica una red `HearthBit-Anchor-XXXX`; los teléfonos
   usan el transporte LAN existente (TCP + contenedor cifrado) contra el
   ancla, sin código nuevo en la app.
4. **Cuotas y expiración:** por defecto 100 MB por remitente, 1 GB total,
   expiración de 7 días y borrado seguro al expirar. Anti-DoS: rechaza
   ofertas sin firma Ed25519 válida de un peer conocido.
5. **Boletines públicos:** puede reemitir boletines firmados (modo óptico
   público) en una página local sencilla.

### Confianza

- El teléfono trata al Data Anchor como un peer más de la malla: las ofertas
  se firman y el contenido va cifrado con la clave efímera del destinatario.
- Comprometer físicamente un ancla expone solo bytes cifrados y metadatos
  mínimos; el panic wipe del teléfono no depende del ancla.
- La administración del ancla (cuotas, purga) se hace por consola local, no
  por la malla, para que ningún paquete remoto pueda reconfigurarla.

### Estado

Diseño aprobado; implementación fuera del alcance de esta fase. El
experimento ESP32-S3 + microSD queda pospuesto hasta medir la contención
BLE/Wi-Fi con tráfico real de malla.
