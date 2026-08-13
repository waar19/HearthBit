# Aplicación HearthBit

UI Flutter con radios nativas Kotlin/CoreBluetooth.

## Desarrollo en Windows

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

La compilación local de iOS no está disponible en Windows. El workflow
`mobile-ci.yml` compila iOS sin firma en un runner macOS. Para distribución se
requiere configurar un equipo de Apple Developer y los certificados fuera del
repositorio.

## Permisos

- Android: Bluetooth scan/connect/advertise, notificaciones y ubicación para SOS.
- iOS: Bluetooth central/peripheral en segundo plano y ubicación mientras la app
  está visible para SOS.

No use un emulador para validar BLE. Consulte `../docs/field-test.md`.

## Mapas y uso sin conexión

Por defecto, la aplicación usa las teselas públicas de OpenStreetMap solo para
visualización interactiva. Las teselas que el usuario ve se conservan en una
caché pasiva respetando `Cache-Control`/`Expires` (o durante al menos siete días
si el servidor no envía esos encabezados). La
[política oficial de OSM](https://operations.osmfoundation.org/policies/tiles/)
prohíbe descargar o precargar regiones desde `tile.openstreetmap.org`.

Una fuente propia o autorizada puede configurarse durante la compilación:

```powershell
flutter run `
  --dart-define=MAP_TILE_URL_TEMPLATE=https://maps.example.org/{z}/{x}/{y}.png `
  --dart-define=MAP_TILE_ATTRIBUTION="© Example Maps" `
  --dart-define=MAP_TILE_ATTRIBUTION_URL=https://maps.example.org/terms `
  --dart-define=MAP_TILE_ALLOWS_BULK_DOWNLOAD=true
```

La descarga regional aparece únicamente cuando
`MAP_TILE_ALLOWS_BULK_DOWNLOAD=true`. Ese permiso siempre se ignora para
`tile.openstreetmap.org`, incluso ante una configuración incorrecta. Antes de
habilitarlo, confirme expresamente que los términos de la fuente permiten
prefetch y uso sin conexión.
