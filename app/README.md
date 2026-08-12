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
