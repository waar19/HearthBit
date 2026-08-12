# HearthBit

<img src="app/assets/icon/hearthbit.png" alt="Ícono de la app HearthBit" width="160">

[English](README.md) · **Español**

HearthBit («la red que sigue latiendo») es una aplicación móvil de
comunicación durante emergencias que
funciona sin internet. Los teléfonos crean una malla Bluetooth Low Energy (BLE)
y retransmiten mensajes entre dispositivos cercanos. Los nodos fijos ESP32 de
`firmware/anchor-node` amplían la cobertura y mantienen mensajes en tránsito.

Además del chat y las alertas SOS, HearthBit transfiere archivos sin internet
mediante una cadena de transportes con fallback automático:

- **Nearby Connections** (Android): rápido y sin configuración.
- **LAN / hotspot**: TCP directo cuando ambos comparten una red local.
- **Wi-Fi Aware** (Android 10+, progresivo): datos directos sin punto de acceso.
- **BLE inline**: archivos pequeños (≤ 256 KiB) por la propia malla.
- **QR óptico**: códigos fountain rateless entre pantalla y cámara, sin
  ninguna radio; ideal para dispositivos aislados o boletines.

Toda oferta se firma con Ed25519 y el contenido viaja cifrado de extremo a
extremo (X25519 + XChaCha20-Poly1305) con verificación SHA-256, sea cual sea
el transporte. En iOS, Nearby y Wi-Fi Aware aún no están disponibles: se usan
LAN, BLE u óptico.

Para los equipos de rescate incluye un **radar de proximidad** estilo AirTag:
desde cualquier alerta SOS se rastrea la señal Bluetooth de la víctima con
indicación de cercanía, tendencia («te estás acercando» / «la señal se está
debilitando»), vibración que acelera al acercarse y distancia GPS en línea
recta si la alerta traía coordenadas. El **modo rescate** de la víctima
reenvía su SOS con GPS fresco cada 5 minutos.

## Apoya el proyecto

HearthBit es de código abierto y se sostiene con la comunidad. Las donaciones
ayudan a financiar pruebas con dispositivos físicos, ensayos de campo y
hardware para los nodos repetidores.

[![Apoya HearthBit en Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_a_Coffee-apoya_HearthBit-FFDD00?logo=buymeacoffee&logoColor=000000)](https://buymeacoffee.com/wilmeralzal)

## Difunde el proyecto

Las mallas de emergencia son más útiles cuando más personas las instalan antes
de que ocurra un desastre. Comparte HearthBit con tu familia, vecinos, equipos
de rescate y comunidades locales:

**[Invita a alguien a usar HearthBit](https://github.com/waar19/HearthBit)**

La aplicación también incluye un botón nativo **Compartir HearthBit** en
«Acerca de» y en la pantalla «Cercanos».

## Idiomas

La app está localizada en inglés, español, alemán, francés, chino
(simplificado) y japonés, y sigue automáticamente el idioma del sistema.
Consulta [docs/localization.md](docs/localization.md) para añadir un idioma.

## Componentes

- `app/`: aplicación Flutter para Android e iOS.
- `firmware/anchor-node/`: firmware Bitle para ESP32-C3/ESP32-S3.
- `docs/`: protocolo, arquitectura, despliegue y pruebas de campo.
- `vendor/bitchat-android/`: referencia de protocolo y núcleo Noise usado por Android.

## Inicio rápido

```powershell
git submodule update --init --recursive
cd app
flutter pub get
flutter run
```

La malla necesita dispositivos físicos; los emuladores no reproducen los roles
BLE central y periférico. Para una prueba útil se requieren dos teléfonos
Android, o un Android y un iPhone, con Bluetooth habilitado.

## Seguridad y alcance

Los mensajes públicos son visibles para cualquier participante del canal y se
firman para detectar alteraciones. Los mensajes privados usan sesiones Noise XX
compatibles con BitChat. HearthBit no sustituye los canales oficiales de
emergencia ni garantiza la entrega: BLE y la ejecución en segundo plano están
limitados por cada sistema operativo.

## Licencias

El código propio se distribuye bajo MIT. BitChat está publicado bajo Unlicense.
El firmware Bitle se distribuye bajo MIT y conserva su atribución en el
submódulo correspondiente.

Dependencias directas de la app y sus licencias: `cryptography`,
`sqflite`, `geolocator`, `path_provider`, `file_selector`, `qr`,
`mobile_scanner`, `image` y `crypto` usan licencias MIT/BSD/Apache-2.0
compatibles. Google Play Services Nearby (solo Android) se usa bajo los
términos estándar de Google Play Services. Los códigos fountain LT del modo
óptico son implementación propia (MIT), sin dependencias RaptorQ de terceros.

## Antes de publicar

Lista de verificación administrativa (fuera del alcance del código):

1. Búsqueda de disponibilidad de la marca «HearthBit» en SIC Colombia
   (clases 9 y 42) y registro si procede.
2. Nombres en Google Play y App Store, y dominio(s) del proyecto.
3. Revisión de licencias de dependencias en cada actualización
   (`flutter pub deps`).
4. Ejecutar la matriz física completa de `docs/field-test.md`, incluida la
   prueba manual HearthBit↔BitChat, antes de declarar interoperabilidad.
