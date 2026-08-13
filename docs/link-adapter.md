# Contrato común de enlace

## Alcance

Un enlace transporta una trama BitChat completa como bytes opacos. La frontera
común es conceptualmente la misma en Android/Kotlin, relay/Python y firmware/C:

```text
capabilities
send(frame)
```

E1 definió este contrato. E2 añade el adapter LAN descrito en
`docs/lan-mesh-gateway.md`; MQTT y Matrix siguen fuera de alcance.

## Capacidades

Cada adapter publica una estructura inmutable con estos campos:

- `id`: identificador único durante la vida del proceso o nodo.
- `kind`: familia de transporte (`ble`, `lan`, `lora` o `in-memory`).
- `mtu`: tamaño máximo, en bytes, aceptado por una llamada a `send`.
- `broadcast` y `unicast`: modos de destino disponibles. Al menos uno debe ser
  verdadero.
- `reliability`: `best-effort` o `acknowledged`; describe la confirmación del
  enlace, no una garantía de entrega de extremo a extremo.
- `background`: indica si el enlace puede seguir operando sin UI en primer
  plano.
- `maxConnections`: concurrencia máxima declarada por el adapter
  (`max_connections` en Python y `max_connections` en C).
- `cost`: coste relativo no negativo. Un valor menor es preferible cuando dos
  enlaces pueden alcanzar el mismo destino.

El MTU pertenece a la frontera del adapter, no necesariamente al PDU de radio.
Android publica el límite GATT efectivo y `MeshEngine` fragmenta antes de
invocar `send`. BlueZ publica el límite de trama que acepta su adapter actual.
El firmware conserva el límite lógico de sus adapters legados; transportes
nuevos deben declarar su límite real.

## Responsabilidades

El motor de malla:

1. selecciona enlaces usando capacidades;
2. fragmenta cuando la trama supera el MTU, si la plataforma lo soporta;
3. reduce TTL exactamente una vez al cruzar un salto lógico;
4. entrega la misma copia ya reducida a todos los enlaces seleccionados;
5. registra telemetría por envío.

El adapter:

1. acepta o rechaza `send(frame)` según su estado y MTU;
2. copia o consume el frame sin interpretarlo;
3. no modifica TTL, flags, firma ni payload;
4. no realiza deduplicación de malla.

Un fan-out hacia varios enlaces sigue siendo un solo salto lógico desde el
nodo actual. Por eso el TTL se reduce antes del fan-out y no dentro de cada
adapter. La fragmentación conserva el TTL ya decidido y no crea saltos.

## Deduplicación canónica

La identidad de relay se calcula sobre los bytes de la trama lógica:

- sin padding de transporte;
- con TTL normalizado a cero;
- con el flag de replay `RSR` despejado;
- conservando el resto de cabecera, ruta, payload y firma.

Así, una copia viva, una copia con otro TTL y un replay RSR representan el mismo
paquete para deduplicación. El algoritmo de digest puede variar por plataforma;
el material canónico no.

## Implementaciones

- Android: `LinkAdapter`, `LinkCapabilities`, adapters BLE por callback e
  `InMemoryLinkAdapter`. `MeshEngine` usa el MTU del contrato para fragmentar y
  emite eventos `linkTelemetry`.
- Python: `RelayLink` es un ABC, BlueZ implementa adapters central/periférico e
  `InMemoryRelayLink` sirve para pruebas de contrato. `LanConnection` extiende
  el envío con un gateway path fuera del frame.
- C: `bitle_link_t` combina capabilities, vtable y contexto. La función
  `bitle_link_register` sigue disponible y adapta callbacks BLE/LoRa existentes
  al registro nuevo. El adapter en memoria ejecuta un self-test al iniciar.

Los IDs solo son únicos dentro de su plataforma. Kotlin y Python usan texto; C
mantiene el `uint16_t` histórico para no romper handles NimBLE ni el trunk LoRa.
