# EmergencyCom

EmergencyCom es una aplicación móvil de comunicación durante emergencias que
funciona sin internet. Los teléfonos crean una malla Bluetooth Low Energy (BLE)
y retransmiten mensajes entre dispositivos cercanos. Los nodos fijos ESP32 de
`firmware/anchor-node` amplían la cobertura y mantienen mensajes en tránsito.

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
compatibles con BitChat. EmergencyCom no sustituye los canales oficiales de
emergencia ni garantiza la entrega: BLE y la ejecución en segundo plano están
limitados por cada sistema operativo.

## Licencias

El código propio se distribuye bajo MIT. BitChat está publicado bajo Unlicense.
El firmware Bitle se distribuye bajo MIT y conserva su atribución en el
submódulo correspondiente.
