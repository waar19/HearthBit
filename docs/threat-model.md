# Modelo de amenazas — Fase 6

## Estado, alcance y criterio de lectura

Este documento describe el modelo de amenazas de la implementación disponible
en la rama `feature/escala`. Distingue controles presentes de recomendaciones
operativas y riesgos residuales. No certifica el sistema, no sustituye pruebas
en hardware y no afirma seguridad, anonimato, disponibilidad ni entrega
absolutas.

HearthBit es un medio auxiliar de comunicación. Una malla BLE, un relay local o
un gateway opcional no sustituyen los canales oficiales de socorro, radio
especializada ni procedimientos de seguridad pública.

Quedan dentro del alcance:

- aplicaciones Android e iOS, su persistencia local y el puente Flutter↔nativo;
- BLE, LAN, Wi‑Fi Direct/Aware, QR, audio y enlaces opacos compatibles;
- relays de teléfono e infraestructura, anclas con almacenamiento y bridges
  opcionales;
- mensajes públicos, SOS/check-in abiertos, chats privados Noise, ACK y
  store-and-forward;
- límites impuestos por iOS, Android y fabricantes OEM.

Quedan fuera de una garantía técnica:

- un teléfono, relay, sistema operativo o clave ya comprometidos;
- coerción, engaño fuera de la app y veracidad humana de un SOS;
- disponibilidad frente a interferencia o bloqueo deliberado de radio;
- precisión clínica, cartográfica, de GPS, RSSI, radar o acústica;
- seguridad de servicios externos después de que un operador habilita un
  bridge.

## Objetivos de seguridad

1. Rechazar paquetes malformados, firmas inválidas, cambios de identidad no
   autorizados y tráfico privado fuera de una sesión segura.
2. Evitar que una copia repetida produzca entregas o retransmisiones ilimitadas.
3. Mantener acotados memoria, colas, conexiones, almacenamiento y fan-out.
4. Preservar confidencialidad e integridad de mensajes privados mientras los
   extremos y sus claves no estén comprometidos.
5. Mostrar la diferencia entre «emitido o preparado», «retransmitido» y
   «confirmado por otro peer».
6. Reducir la correlación pasiva y la retención innecesaria sin prometer
   anonimato por radio.
7. Degradar de forma visible y segura cuando la plataforma suspende radios,
   ubicación, sockets o procesos.

## Activos

- Claves privadas Curve25519/Ed25519 y claves de cifrado local.
- Pins TOFU, relaciones conocidas, secuencias de rotación y estado de confianza.
- Contenido de chats, SOS, check-ins, archivos, audio y coordenadas.
- Identificadores de peer, apodos, horarios, RSSI, topología y metadatos de
  proximidad.
- Outboxes, ACK, cachés de deduplicación, store-and-forward y bases de datos de
  relay.
- PSK LAN, certificados, tokens y credenciales de bridges opcionales.
- Disponibilidad de radio, batería, memoria, almacenamiento y atención de la
  persona rescatista.
- Integridad de la UI: origen, estado externo, simulacro, canal seguro, vigencia
  y estado de entrega.
- Evidencia de campo y diagnósticos saneados.

## Límites de confianza y flujo

### Radio y redes locales → ingreso nativo

BLE, Wi‑Fi, LAN, QR, audio y LoRa deben considerarse hostiles. Ver un anuncio,
una dirección, un UUID de servicio o un `gateway_id` no autentica a una persona
ni a un equipo. El ingreso nativo decodifica el frame, valida la identidad
autofirmada, consulta el trust store, exige firma para tipos públicos sensibles,
deduplica y aplica la política de relay.

Los adapters transportan frames opacos y no son autoridad criptográfica. Un
transporte puede entregar, omitir, retrasar, duplicar u observar bytes; no debe
alterar payload, firma ni ruta interna. El TTL se excluye de la firma para que
un relay pueda reducirlo, por lo que el TTL limita propagación pero no prueba
origen ni frescura.

### Identidad pública → confianza humana

Un `ANNOUNCE` válido demuestra control de las claves incluidas y liga el
`senderId` a la clave Noise. No demuestra nombre civil, función de rescatista,
pertenencia institucional ni veracidad del mensaje. El apodo es informativo y
puede ser imitado.

El primer anuncio válido se fija mediante TOFU. La confianza humana requiere una
verificación separada, por ejemplo una huella comparada presencialmente o un QR
de un contacto conocido. TOFU evita cambios posteriores silenciosos; no elimina
el riesgo del primer contacto.

### Público firmado → privado Noise

Los mensajes públicos y SOS son legibles por los participantes alcanzables y se
firman para integridad y atribución a una identidad criptográfica. Los chats
privados usan `Noise_XX_25519_ChaChaPoly_SHA256` y vinculan la clave estática
remota al peer anunciado. Una sesión segura protege el transporte, pero el
texto ya descifrado existe en ambos extremos y puede persistirse localmente.

### Proceso → almacenamiento de plataforma

Android protege claves, trust store, caché nativa de emergencia y
store-and-forward nativo con AES-GCM y una clave no exportable de Android
Keystore. iOS guarda identidad y pins en Keychain y cifra el store-and-forward
nativo con AES-GCM usando una clave de Keychain.

Las bases SQLite de Flutter usan SQLCipher con una clave aleatoria guardada en
el almacén seguro de la plataforma y migran las bases legadas en claro. Aun
así, la app y un extremo comprometido ven el contenido descifrado; exports,
notificaciones y archivos externos quedan fuera de esa protección. El cifrado
local no debe confundirse con confidencialidad extremo a extremo.

### Móvil → relay, gateway o bridge

Un relay amplía alcance y disponibilidad, no confianza. Puede descartar,
reordenar, retrasar, seleccionar o analizar tráfico y topología. Las firmas y
Noise siguen siendo la autoridad extremo a extremo.

El LAN seguro usa una PSK de al menos 32 bytes, HMAC/HKDF y AES-256-GCM. La PSK
es una credencial compartida del sitio: comprometer un miembro compromete el
perímetro LAN, aunque no permite firmar como una identidad ya fijada.

MQTT, Matrix, Reticulum/LXMF y servicios similares crean un límite nuevo. Deben
permanecer desactivados salvo decisión del operador. Las coordenadas se bloquean
por defecto en bridges que lo implementan, pero habilitarlas expone ubicación y
metadatos al operador y al proveedor externo.

### Aplicación → sistema operativo y fabricante

Permisos y declaraciones de background habilitan capacidades; no garantizan
tiempo de CPU, radio, GPS, sockets ni relanzamiento. El sistema operativo, la
política OEM, el usuario y el estado de batería permanecen fuera del control de
HearthBit.

## Actores y capacidades adversarias

- **Observador pasivo cercano:** captura UUID, tiempos, RSSI, volumen y patrones
  de movimiento; no necesita conectarse.
- **Peer activo no autenticado:** abre conexiones, envía frames malformados,
  fragmentos o anuncios y consume conexiones, CPU y batería.
- **Peer con identidad propia válida:** genera claves, firma mensajes y puede
  emitir SOS sintácticamente válidos. Puede crear muchas identidades.
- **Peer conocido malicioso o comprometido:** dispone de un pin previo y de un
  presupuesto de tasa mayor; puede enviar contenido falso con identidad válida.
- **Atacante LAN:** descubre mDNS, abre el puerto open-SOS, suplanta o rota
  `gateway_id` y fuerza reconexiones. Con la PSK puede entrar también al LAN
  seguro.
- **Relay o bridge comprometido:** observa metadatos, censura, demora, replica o
  conserva tráfico; además puede filtrar credenciales y registros bajo su
  control.
- **Atacante con acceso al dispositivo:** intenta extraer bases, notificaciones,
  exports, copias de seguridad o claves. Con ejecución privilegiada se considera
  comprometido el extremo.
- **Plataforma/OEM no cooperativo:** suspende servicio, escaneo, advertising,
  ubicación, alarma, mDNS o socket y puede eliminar el proceso.
- **Operador mal configurado:** reutiliza PSK, expone puertos, activa bridges o
  logs sensibles, interpreta un ACK como rescate confirmado o declara PASS sin
  hardware.

## Canal open-SOS: abuso, Sybil y tradeoff explícito

El canal open-SOS permite recibir una emergencia de una víctima desconocida sin
PSK ni alta previa. En LAN acepta únicamente:

- `ANNOUNCE` con marcador de preemergencia;
- `MESSAGE` clasificado como SOS/check-in;
- `EMERGENCY_ACK`;
- nunca simulacros, mensajes normales, Noise privado ni transferencias.

Los frames pasan después por el ingreso normal. La firma impide modificar un
SOS sin invalidarlo y atribuye el paquete a sus claves. **No demuestra que la
emergencia sea real.** Cualquier persona puede generar una identidad nueva,
autofirmar un `ANNOUNCE` y emitir un SOS válido. Generar muchas identidades crea
un ataque Sybil; el pin TOFU no lo evita porque cada identidad llega como primer
contacto distinto.

El tradeoff es deliberado:

- exigir allowlist, PSK o verificación humana antes de mostrar/retransmitir
  reduciría falsas alertas, pero bloquearía a una víctima legítima desconocida;
- aceptar identidades nuevas preserva disponibilidad e interoperabilidad, pero
  permite spam, suplantación de apodos, Sybil y agotamiento de la atención;
- los límites globales preservan recursos, pero un atacante puede consumir la
  ventana de desconocidos y provocar que un SOS legítimo posterior sea
  descartado temporalmente.

Controles presentes:

- validación de estructura, binding `senderId`↔clave Noise y firma Ed25519;
- anuncio ordinario limitado a ±10 minutos; el preanuncio de emergencia admite
  hasta 24 horas hacia el pasado, pero no más de 10 minutos hacia el futuro;
- presupuesto móvil global separado: 600 frames/minuto para relaciones
  conocidas y 240/minuto para desconocidas, tanto en Android como en iOS;
- ingreso desconocido adicional: 30 paquetes por fuente cada 10 segundos, con
  hasta 256 fuentes rastreadas;
- socket LAN abierto: 30 frames/minuto por `gateway_id`, cierre al exceder;
- deduplicación canónica, límites de tamaño, TTL, colas acotadas y damping de
  relay;
- UI de emergencia externa cuando interoperabilidad está desactivada.

Límites de esos controles:

- `gateway_id`, dirección de enlace e identidad recién creada no son anclas
  resistentes a Sybil;
- los buckets del relay Python son por `senderId` (8/s, ráfaga 32 de forma
  predeterminada) y pueden repartirse entre identidades nuevas;
- el límite móvil open-SOS sí es global y contiene el volumen agregado, pero
  crea una posibilidad de inanición para desconocidos legítimos;
- el límite temporal explícito del ingreso móvil protege el `ANNOUNCE`; no debe
  interpretarse como prueba de que la necesidad humana siga vigente;
- la caché persistente de huellas SOS dura 24 horas y tiene 2048 entradas. Una
  copia posterior a su expiración o expulsión no tiene protección indefinida;
- una clave robada puede crear mensajes nuevos y correctamente firmados;
- ni firma ni ACK prueban que una autoridad haya aceptado o atendido el caso.

Decisión operativa: mostrar una alerta nueva como **no verificada** hasta que
exista contexto adicional. Priorizar coincidencia con una relación conocida,
múltiples observaciones independientes y contacto por otro canal, sin ocultar
automáticamente alertas desconocidas. Ante abuso LAN, desactivar el gateway
open-SOS o aislar el segmento es preferible a prometer una clasificación
automática fiable.

## Tormentas de broadcast y agotamiento

### Controles presentes

- TTL inicial 7 y decremento único por relay; TTL ≤1 no se retransmite.
- Huella canónica que ignora TTL, deduplicación antes del relay y exclusión del
  enlace de ingreso durante el fan-out.
- Caché móvil en memoria de hasta 8192 huellas y caché SOS persistente de 2048
  huellas durante 24 horas.
- Damping con jitter: 80–160 ms para emergencia y 180–420 ms para tráfico
  normal. Una emergencia se suprime después de observar tres copias
  adicionales; hay como máximo 1024 relays pendientes.
- Store-and-forward móvil de hasta 100 paquetes, conservando emergencia hasta
  24 horas y tráfico dirigido normal hasta 12 horas.
- Colas y conexiones acotadas; prioridad y reserva para emergencia; máximo de
  ocho conexiones BLE en los perfiles que permiten conexiones.
- En relay de infraestructura: dedupe persistente, cuotas de paquetes/bytes,
  buckets por emisor y bridge, y replay por lotes.
- `REQUEST_SYNC` es link-local, con máximo 40 reenvíos de respuesta y ocho
  respuestas por enlace cada 30 segundos.

### Riesgo residual

Un adversario puede emitir continuamente paquetes únicos y firmados. La
deduplicación elimina copias, no mensajes nuevos. Esto puede:

- ocupar radio, CPU y batería antes de que actúe el límite;
- expulsar huellas, pins o paquetes legítimos de estructuras acotadas;
- llenar el store de emergencia, cuya prioridad puede desplazar tráfico normal;
- saturar la atención con alertas distintas;
- aprovechar múltiples portadoras para aumentar el costo de ingreso;
- provocar que damping suprima una retransmisión útil al observar suficientes
  copias, aunque el destino final todavía no la haya recibido.

No hay defensa de aplicación frente a jamming RF. En una tormenta real o
maliciosa se debe conservar un canal alternativo y reducir físicamente el
dominio de broadcast.

## Trust store e identidad

Controles presentes:

- TOFU persistente con binding del peer ID a la clave Noise.
- Rechazo fail-closed de entrada corrupta y de un `ANNOUNCE` que cambie claves.
- Rotación dedicada con firma exterior, autorización firmada por la clave
  anterior, secuencia monotónica y reemplazo persistente.
- Rechazo de replay de rotación y de colisión con claves de otro peer.
- Android cifra pins con Keystore y admite hasta 4096; iOS los guarda en
  Keychain y admite hasta 4096; el relay Linux mantiene hasta 4096 en un JSON
  atómico con permisos `0600`.
- Peers con relaciones, sesiones, radar o entregas pendientes se protegen de
  expulsión en móvil cuando aplica la política de retención.

Riesgos residuales:

- primer contacto malicioso, apodos imitados y verificación humana ausente;
- llenado Sybil. Móvil puede expulsar un pin no protegido de forma determinista;
  el relay deja de aceptar pins al llegar a capacidad;
- pérdida o borrado del trust store convierte contactos anteriores en primeros
  contactos;
- restaurar datos sin la clave Keystore puede volverlos indescifrables y obliga
  a descartar estado legado;
- el trust store del relay contiene claves públicas, no secretos, pero revela
  relaciones e identificadores;
- una rotación legítima no corrige una clave antigua ya comprometida antes de
  que los peers reciban y acepten la rotación.

Acción: comparar huellas fuera de banda para relaciones críticas, proteger el
archivo del relay, monitorizar capacidad y tratar un conflicto de pin como
incidente, no como error que deba resolverse borrando confianza sin verificar.

## Relay, store-and-forward y bridges

En los motores móviles, los roles aplican mínimo privilegio funcional:

- `PHONE_RELAY` origina, retransmite y conserva;
- `PHONE_BEACON` no chatea, retransmite ni conserva;
- `INFRA_RELAY` retransmite sin conservar;
- `INFRA_DATA_ANCHOR` puede conservar tráfico dirigido.

Noise crudo, handshakes, control de baliza, ranging y rotación no entran al
store-and-forward móvil. La entrega privada diferida usa el outbox del emisor o
un `CourierEnvelope` cifrado.

El relay Python anuncia el rol configurado, pero en la implementación actual
`node_role=INFRA_RELAY` no deshabilita por sí mismo `_store_if_eligible`. La
configuración predeterminada todavía permite persistir `MESSAGE`,
`CourierEnvelope` y `EMERGENCY_ACK`. Para operar realmente sin conservación se
debe establecer `store.message_types: []` y verificar `relay.db`; hasta que el
rol gobierne también la escritura, la capacidad anunciada no basta como prueba
de conducta. Para tipos habilitados, el relay exige firma por defecto.

Riesgos residuales:

- un relay puede negar servicio o hacer análisis de tiempos, tamaños, enlaces y
  sender IDs aunque no descifre Noise;
- los mensajes públicos y SOS almacenados son contenido público firmado, no
  ciphertext privado;
- `relay.db` no tiene cifrado de aplicación: contiene frames y metadatos hasta
  siete días por defecto, con máximo 20 000 paquetes o 64 MiB;
- un relay configurado como `INFRA_RELAY` puede conservar datos si el operador
  no vacía `store.message_types`; es una brecha entre rol anunciado y política
  efectiva;
- un `INFRA_DATA_ANCHOR` comprometido puede retener sobres y observar etiquetas,
  aunque no deba poder abrir el ciphertext;
- una PSK LAN compartida no identifica individualmente a operadores y su
  rotación corta a todos los miembros;
- un bridge externo puede conservar copias fuera del alcance del borrado local;
- reglas, TLS, allowlists y bloqueo de coordenadas dependen de la configuración
  efectiva del operador.

Acción: usar `INFRA_RELAY` con `store.message_types: []` cuando no se necesite
persistencia, limitar permisos y retención de `relay.db`, separar redes, rotar
PSK por sitio, mantener bridges desactivados por defecto y revisar configuración
y conducta real antes de cada despliegue.

## Persistencia y privacidad

Controles presentes:

- modo privado por defecto; token Android HMAC rotatorio cada 15 minutos e iOS
  sin identidad en advertising;
- `ANNOUNCE` ordinario con TTL 1 en modo privado;
- identidad revelada a varios saltos solo como excepción necesaria antes de un
  SOS abierto;
- presencias BLE genéricas sin nombre ni MAC, HMAC efímero, expiración a 45
  segundos y sin SQLite;
- diagnósticos locales con máximo 500 entradas/256 KiB, claves sensibles
  filtradas y sin carga automática;
- borrado de emergencia de identidades, confianza, mensajes, colas, gateways,
  cachés y diagnósticos controlados por la app;
- ubicación exacta, aproximada o ausente seleccionable para SOS.

Exposición y límites:

- un SOS abierto revela deliberadamente identidad criptográfica, contenido,
  tiempo y la precisión de ubicación seleccionada;
- UUID, RSSI, tiempos, movimiento y conexiones permiten correlación aun con
  tokens rotatorios;
- interoperabilidad BitChat publica más identidad y aumenta correlación;
- mensajes y outboxes SQLCipher se descifran durante el uso; notificaciones
  pueden aparecer en pantalla bloqueada e historial;
- exports, archivos compartidos, backups del sistema y copias en receptores o
  bridges no pueden borrarse remotamente;
- logs nativos de desarrollo pueden contener prefijos, direcciones o IDs si se
  exportan sin el saneamiento de campo;
- el borrado lógico no demuestra borrado físico de bloques flash.

Acción: usar datos sintéticos en pruebas, revisar notificaciones, no exportar
consolas completas, cifrar y limitar backups del relay, y ejecutar el borrado de
emergencia antes de reasignar un dispositivo.

## Límites de segundo plano

### iOS

La app declara `bluetooth-central`, `bluetooth-peripheral` y `location`, y
configura restauración de estado para CoreBluetooth. Esto permite oportunidades
de restauración, no ejecución continua.

- iOS agrupa o reduce advertising, suspende timers, mDNS, LAN y sockets, y puede
  terminar el proceso.
- MultipeerConnectivity de SOS/radar funciona solo con la app visible.
- Modo de bajo consumo reduce BLE en background.
- La ubicación «Siempre» puede mantener actividad mientras haya actualizaciones,
  pero el sistema conserva la decisión final.
- Cerrar la app desde el selector impide una restauración BLE fiable hasta que
  se vuelva a abrir. Ese escenario es `BLOCKED_PLATFORM`, nunca un PASS de
  continuidad.
- Si iOS termina el proceso, la existencia de `UIBackgroundModes` no demuestra
  que se hayan emitido pings o recibido mensajes.

### Android y OEM

La app usa servicio en primer plano `connectedDevice|location`, notificación
persistente, `START_STICKY`, estado de rescate persistido y
`AlarmManager.setAndAllowWhileIdle`.

- Doze y ahorro de batería pueden suspender BLE/GPS si no existe exclusión.
- Algunos OEM matan servicios pese a la notificación o requieren una excepción
  manual adicional.
- «Forzar detención» impide el reinicio hasta una acción explícita del usuario;
  no es equivalente a una muerte recuperable del proceso.
- Permisos de ubicación en background, dispositivos cercanos y notificaciones
  pueden revocarse.
- Bluetooth apagado, límites de alarmas exactas, temperatura y batería crítica
  degradan la cadencia.

Acción: mostrar el estado real, no ocultar restricciones, registrar fabricante y
perfil de batería, y validar cada modelo físico. Una promesa genérica de
background basada en emulador o manifiesto es inválida.

## Riesgos priorizados y aceptación

### Críticos

- **TM-01 — SOS Sybil/falso:** alerta válida criptográficamente pero no
  verificada humanamente. Mitigación actual parcial; riesgo aceptado solo con
  etiqueta no verificada, límites y procedimiento de triage.
- **TM-02 — inanición del canal de desconocidos:** un flood consume el bucket
  global. No hay garantía de recepción durante ataque; requiere canal alterno.
- **TM-03 — suspensión en background:** pérdida silenciosa si la UI u operación
  promete continuidad. Debe ser visible y quedar bloqueada la declaración de
  «lista para emergencias» mientras los P0 físicos estén pendientes.

### Altos

- **TM-04 — compromiso de extremo o relay:** exposición de contenido local,
  ubicación y claves. No mitigable por E2E en el extremo comprometido.
- **TM-05 — tormenta multitransporte:** agotamiento de radio/batería con frames
  únicos. Controles acotados, sin defensa contra jamming ni Sybil distribuido.
- **TM-06 — primer contacto TOFU mal atribuido:** identidad criptográfica válida
  asociada a la persona equivocada. Requiere verificación fuera de banda.
- **TM-07 — retención externa:** copias en relay, receptor, bridge, backup o
  notificación sobreviven al borrado local.
- **TM-08 — rol de relay no aplicado al almacenamiento:** el relay Python puede
  anunciar `INFRA_RELAY` y conservar tipos habilitados. Requiere
  `store.message_types: []`, verificación operativa y corrección de código antes
  de usar el rol anunciado como garantía.

### Medios

- **TM-09 — correlación pasiva:** modo privado reduce, pero no elimina, la
  observación por UUID/RSSI/tiempo.
- **TM-10 — llenado de trust store/cachés:** límites evitan memoria ilimitada,
  pero pueden expulsar estado útil o bloquear pins nuevos.
- **TM-11 — reloj incorrecto:** puede rechazar una alerta futura o ampliar la
  aceptación de un preanuncio antiguo dentro de 24 horas.

Aceptar un riesgo significa documentar responsable, entorno, controles y fecha
de revisión; no significa declarar que dejó de existir.

## Señales operativas y respuesta

Señales disponibles hoy:

- estado `starting/active/degraded/error/stopped` y notificación persistente;
- advertising, escaneo mesh/genérico, conexiones, cercanos y presencias;
- batería, perfil de energía, duty-cycle BLE, escaneos iniciados y entradas de
  store-and-forward;
- portadoras que aceptaron el frame;
- outbox `pending/relayed/acknowledged/expired`, intentos y siguiente reintento;
- pings de rescate esperados/ejecutados y `lastPingAt`;
- logs de relay para paquete inválido, conflicto de identidad, fallo de
  persistencia, fan-out y replay;
- diagnósticos locales saneados y exportables por decisión del usuario.

Interpretación:

- «emitido», una ruta listada o `relayed` no prueba recepción final;
- solo un `EMERGENCY_ACK` válido prueba que otro peer compatible recibió y
  validó ese SOS; no prueba que una persona lo leyó ni que el rescate comenzó;
- `scanActive=false`, estado `error`, restricciones de batería, ausencia de
  pings debidos o outbox vencido son degradación operativa;
- crecimiento rápido de identidades nuevas, huellas, conexiones, rechazos,
  store o batería es compatible con abuso o con una emergencia masiva y exige
  revisión humana.

Brecha de observabilidad: el móvil no expone actualmente contadores durables de
frames descartados por bucket open-SOS, expulsiones de pins/huellas, supresión
por damping ni saturación por identidad. No se debe inferir «sin ataque» de la
ausencia de un evento. Para una operación administrada se recomiendan, sin
contenido ni IDs estables:

- descartes por razón y portadora por ventana;
- identidades nuevas por minuto y ocupación de trust store/cachés;
- ocupación/evicción de colas y store;
- fan-out, duplicados y TTL observados;
- latencia y tasa de ACK;
- continuidad de scan/advertising/ping frente a batería y background.

Respuesta mínima ante anomalía:

1. Mantener un canal oficial o alternativo y no asumir entrega.
2. Registrar hora UTC, build, plataforma, estado foreground/background, batería
   y primer síntoma, sin contenido ni identificadores reales.
3. Aislar el segmento o desactivar el gateway/bridge abierto si el origen es LAN;
   no borrar trust store como primera reacción.
4. Rotar PSK o credenciales si hubo exposición, y tratar el relay como
   comprometido hasta revisar host, permisos, DB y logs.
5. Preservar solo evidencia saneada con SHA-256 y reportar vulnerabilidades por
   el [canal privado de seguridad](../SECURITY.md).

## Supuestos

- Los generadores aleatorios, CryptoKit, Android Keystore, Keychain, Ed25519,
  Curve25519, ChaCha20-Poly1305 y AES-GCM se comportan según sus contratos.
- Los builds y dependencias corresponden a revisiones revisadas y no fueron
  sustituidos.
- Los relojes están razonablemente sincronizados; la excepción de 24 horas para
  preanuncio solo tolera una víctima atrasada, no valida el contenido.
- Los relays tienen control de acceso del host, almacenamiento y configuración
  adecuados.
- Las personas entienden que «identidad válida» no equivale a «persona
  verificada».
- La regulación, frecuencia, potencia y hardware de LoRa/Meshtastic fueron
  autorizados antes de transmitir.
- Existe al menos una ruta física operativa; la criptografía no crea cobertura.

Si un supuesto no se cumple, el resultado debe degradarse a `FAIL`, `BLOCKED` o
riesgo explícitamente aceptado, no a una afirmación más fuerte.

## Validación de campo

La fuente operativa es [Prueba de campo](field-test.md), complementada por la
[matriz de pruebas de campo](field-test-matrix.md) y, para iPhone, la
[guía de validación física de iOS](ios-reconnection-validation.md).

Proceso obligatorio:

1. Usar hardware físico, build y commit identificados, alias no personales y
   reloj UTC.
2. Ejecutar una corrida nueva `RUN-<UTC>-<CASE_ID>` con controles negativos y
   topología físicamente demostrada.
3. Conservar `capture.json`, logs saneados por nodo, evidencia visual redactada
   cuando aplique, primer criterio incumplido y SHA-256.
4. Registrar `PENDING`, `PASS`, `FAIL`, `BLOCKED`, `BLOCKED_PLATFORM`,
   `BLOCKED_HARDWARE` o `BLOCKED_REGULATORY` según el caso; un test unitario,
   build, log aislado o peer visible no constituye PASS físico.
5. No incluir coordenadas, contenido real, MAC, seriales, peer IDs, claves,
   nombres Bluetooth ni notificaciones personales.

Cobertura sintética automatizada de esta fase:

- `MeshSosSimulationTest` modela 12 nodos y 100 SOS con fan-out máximo de ocho,
  copias redundantes, deduplicación, damping, presupuestos conocidos/desconocidos
  y colas acotadas.
- `relay/tests/test_load.py` comprueba que una ráfaga de identidades firmantes
  desconocidas no se reenvía ni crea estado de confianza, y que una ráfaga SOS
  de un emisor fijado se limita al presupuesto configurado.

Estas pruebas detectan regresiones deterministas de política; no modelan
interferencia RF, temporización real, suspensión del sistema ni diversidad OEM.

Casos existentes que validan este modelo:

- `P0-SOS-NO-AUDIENCE`, `P0-SOS-ACK` y `P0-SOS-CLOCK-01`;
- `P0-STORE-REBOOT`, `P0-FOUR-NODE-TWO-HOP` y `D1-RELAY-01`;
- `P0-RESCUE-KILL-DOZE`, `P0-RESCUE-RESTART-01`,
  `P0-BT-RECOVERY-01` y `P0-IOS-FORCEQUIT-01`;
- `P0-LAN-PI`, `P0-PANIC-WIPE`, `P0-PRIVATE-NOISE` y
  `P0-OPTICAL-TRUST`;
- `P0-BATTERY-24H`, la reconexión GCS y el descubrimiento iOS en segundo plano.

Pruebas adversarias adicionales para cerrar Fase 6:

- **TM-SYBIL-OPEN:** emitir `ANNOUNCE+SOS` válidos desde identidades nuevas hasta
  superar 240 frames/minuto. Confirmar estabilidad, memoria acotada y que el
  bucket conocido sigue separado. Documentar que un desconocido legítimo puede
  quedar bloqueado durante la ventana; eso es riesgo residual, no PASS de
  disponibilidad.
- **TM-LAN-RATE:** enviar 31 frames en un minuto desde el mismo `gateway_id` y
  comprobar cierre; repetir rotando ID para demostrar que el límite LAN no es
  defensa Sybil.
- **TM-BROADCAST-STORM:** cuatro nodos con rutas redundantes, paquetes únicos y
  duplicados. Verificar decremento único de TTL, dedupe, damping, límites de
  cola/store, ausencia de loops y entrega de un SOS legítimo conocido.
- **TM-TRUST-FILL:** alcanzar la capacidad configurada con identidades de prueba,
  comprobar protección/expulsión o rechazo, conflicto de claves y rotación
  autenticada sin borrar el store.
- **TM-REPLAY-24H:** reinyectar la misma huella antes y después de la ventana
  persistente para documentar exactamente el límite, sin afirmar protección
  indefinida.
- **TM-RELAY-COMPROMISE:** interrumpir, retrasar y duplicar en un relay de
  laboratorio; confirmar que no puede modificar un mensaje firmado ni abrir
  Noise, y que la UI no presenta entrega sin ACK.
- **TM-PRIVACY-AT-REST:** inspeccionar, con datos sintéticos, SQLite móvil,
  Keychain/Keystore, `relay.db`, notificaciones, exports y borrado de emergencia.
  Registrar qué queda fuera del control de la app.

La declaración «lista para emergencias reales» permanece bloqueada mientras un
gate P0 aplicable esté `PENDING`, `FAIL` o sin evidencia física saneada.
