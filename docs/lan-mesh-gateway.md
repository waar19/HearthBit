# Gateway de malla Wi‑Fi/LAN

## Alcance

E2 añade un enlace local TCP entre relays y teléfonos, y entre teléfonos.
Transporta cada frame
BitChat v1/v2 completo como bytes opacos; no está limitado a HBT y no
implementa MQTT, Matrix ni servicios cloud.

El enlace está desactivado por defecto. Requiere una clave precompartida
aleatoria de al menos 32 bytes y solo debe habilitarse en redes locales de
confianza.

## Descubrimiento y conexión

- Servicio mDNS: `_hearthbit._tcp.local`.
- Puerto predeterminado del relay: `45893/TCP`.
- Cada proceso deriva o genera un `gateway_id` de 16 bytes. La app lo conserva
  durante la vida del servicio y ahora anuncia también su servidor.
- El relay anuncia PTR, SRV, TXT (`gid=<hex>`) y A. También navega el mismo
  servicio, por lo que puede actuar como servidor y cliente LAN.
- Si dos relays abren conexiones simultáneas, el ID menor conserva el socket
  saliente y el mayor el entrante. Solo queda un enlace lógico por par.
- La app aplica la misma regla. El servidor autenticado usa `45893/TCP`; el
  canal público de emergencia usa `45894/TCP`. Ambos puertos se anuncian en
  TXT (`gid`, `secure`, `eport`).

Android mantiene un `MulticastLock` únicamente mientras el discovery opt-in
está activo. iOS declara `_hearthbit._tcp` en `NSBonjourServices` y explica el
uso en `NSLocalNetworkUsageDescription`.

## Autenticación y cifrado

No se usa una contraseña humana directamente. Genere 32 bytes aleatorios:

```powershell
$key = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($key)
[Convert]::ToBase64String($key)
```

Cada lado envía un `HELLO` fijo:

```text
magic "HBLN" | version u8 | role u8 | gateway_id[16] |
nonce[32] | max_frame u32 | HMAC-SHA256[32]
```

El HMAC cubre `hello:` y todos los campos anteriores. Servidor y cliente
validan posesión de la PSK, intercambian un `FINISH` HMAC que liga ambos HELLO
y derivan 64 bytes con HKDF-SHA256. Las mitades forman claves direccionales
AES-256-GCM. Los nonces son `00000000 || sequence_u64`; la secuencia debe ser
exacta y nunca se reutiliza.

La PSK no se anuncia, no se guarda en el protocolo y no atraviesa Flutter
channels. En móvil permanece en el cliente Dart que posee el socket.

### Canal público de emergencia

Durante un SOS puede habilitarse un segundo socket sin PSK. No es una malla
general abierta: solo admite `ANNOUNCE` con marcador de preemergencia,
`MESSAGE` SOS/check-in y `EMERGENCY_ACK`. Android e iOS decodifican y clasifican
el frame antes de exponerlo a este socket, y vuelven a aplicar en el ingreso
normal identidad autofirmada, Ed25519, reloj, deduplicación y flood control.
Flutter limita cada peer a 30 frames por minuto y cierra la conexión al
excederlo. Mensajes normales, tramas privadas y transferencias nunca cruzan el
canal abierto.

## Framing

Después del handshake, cada registro usa:

```text
record_length u32 |
version u8 | sequence u64 |
AES-GCM(
  record_type u8 |
  message_id[16] |
  path_count u8 | gateway_id[path_count] |
  frame_length u32 | frame BitChat opaco
) | tag[16]
```

`record_length` es big-endian y está limitado antes de reservar memoria. El
valor predeterminado de `max_frame_size` es 2048 bytes y el límite absoluto es
65535. El máximo predeterminado de path es 8 gateways (límite absoluto 32).
Handshake/conexión vence a los 10 segundos; una lectura inactiva vence a los
90 segundos. Un PING autenticado se envía cada tercio de ese intervalo.

## TTL, ruta y anti-loop

El envelope LAN no modifica la trama BitChat:

1. `gateway_path` vive fuera del frame y cada gateway añade su ID al salir.
2. Un gateway rechaza un path que ya contiene su ID, no termina en el ID del
   peer autenticado o supera el límite.
3. `message_id` es SHA-256 truncado a 16 bytes sobre una copia con TTL
   normalizado a cero y RSR despejado. Sirve para deduplicación de transporte.
4. El motor de malla conserva la deduplicación canónica definitiva y reduce
   TTL exactamente una vez antes del fan-out al siguiente salto lógico.
5. Los adapters LAN, BLE y el bridge raw nunca reducen TTL ni alteran payload,
   firma, ruta BitChat o padding.

Un frame entrante desde LAN se inyecta en el motor nativo. Android lo trata
como un `LinkAdapter` LAN y excluye ese mismo enlace durante el fan-out. iOS
suprime el bridge LAN durante la llamada de inyección. Así no hay eco al mismo
socket y sí puede continuar hacia BLE.

## Configuración del relay

Copie `relay/config.example.json`, genere la PSK y habilite:

```json
{
  "lan": {
    "enabled": true,
    "listen_host": "0.0.0.0",
    "port": 45893,
    "psk_base64": "REEMPLAZAR_POR_32_BYTES_EN_BASE64",
    "discovery": true,
    "service_name": "Refugio Norte",
    "max_frame_size": 2048,
    "max_connections": 8,
    "connect_timeout_seconds": 10,
    "idle_timeout_seconds": 90,
    "max_gateway_hops": 8
  }
}
```

Todos los relays y móviles de la misma malla LAN deben usar la misma PSK.
Cambiarla corta la interoperabilidad inmediatamente; planifique rotación por
sitio físico. Restrinja `45893/TCP` y `5353/UDP` a la LAN en el firewall.

## Activación móvil

No existe una pantalla general de ajustes de red en la app actual. Por eso E2
expone un servicio deliberadamente explícito y no persistente:

```dart
final gateway = LanMeshGatewayService();
await gateway.start(
  LanMeshGatewayConfig(
    enabled: true,
    psk: base64Decode(pskFromSecureProvisioning),
  ),
);
```

El integrador debe obtener `pskFromSecureProvisioning` de almacenamiento
seguro o aprovisionamiento presencial. No la incruste en el repositorio ni la
registre en logs. `stop()` cierra discovery/socket, deshabilita los channels
raw y libera el multicast lock. Ningún código inicia este servicio por defecto.

`LanGatewayController.setEmergencyMode(true)` activa temporalmente el canal
abierto y el servidor entre teléfonos aunque no exista una PSK. Al desactivar
el SOS restaura el modo PSK configurado o detiene LAN por completo.

## Pruebas

```powershell
cd C:\src\emergency-com\relay
python -m pytest

cd C:\src\emergency-com\app
flutter test
cd android
.\gradlew.bat testDebugUnitTest
```

La integración Python abre dos servidores en loopback, autentica ambos lados,
envía un frame BitChat completo, verifica deduplicación y comprueba un
decremento TTL por cada relay.

## Limitaciones

- iOS puede suspender sockets y mDNS al pasar a segundo plano; los modos BLE
  existentes no conceden ejecución LAN continua. E2 es fiable en primer plano
  y durante la ventana que iOS mantenga activa la app.
- iOS mostrará el consentimiento de red local la primera vez. Si se deniega,
  discovery no encuentra gateways hasta cambiarlo en Ajustes.
- El móvil mantiene una conexión autenticada y una conexión pública de
  emergencia simultáneas. El relay admite varias y enlaza redes LAN/BLE.
- El relay Python se ejecuta en Windows para pruebas de loopback, pero el
  transporte BlueZ real requiere Linux. Windows Firewall puede solicitar
  autorización para mDNS/TCP y varias apps no siempre pueden compartir 5353;
  no se garantiza operación de relay BLE+LAN en Windows.
- mDNS no cruza routers/VLAN por diseño. No hay fallback a internet, DNS
  unicast, MQTT ni Matrix.
