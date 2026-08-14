# HearthBit application

[Español](README.es.md)

Flutter UI with native Kotlin/CoreBluetooth radios.

## Development on Windows

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

Local iOS builds are not available on Windows. The `mobile-ci.yml` workflow
builds iOS without signing on a macOS runner. Distribution requires an Apple
Developer team and certificates configured outside the repository.

## Permissions

- Android: Bluetooth scan/connect/advertise, notifications, and location for SOS.
- iOS: background Bluetooth central/peripheral and location while the app is
  visible for SOS.

Do not use an emulator to validate BLE. See
[`../docs/field-test.md`](../docs/field-test.md).

## Maps and offline use

By default, the application uses public OpenStreetMap tiles only for
interactive viewing. Tiles that the user sees are kept in a passive cache that
honors `Cache-Control`/`Expires` (or for at least seven days if the server sends
neither header). The
[official OSM tile policy](https://operations.osmfoundation.org/policies/tiles/)
prohibits downloading or preloading regions from `tile.openstreetmap.org`.

A self-hosted or authorized source can be configured at build time:

```powershell
flutter run `
  --dart-define=MAP_TILE_URL_TEMPLATE=https://maps.example.org/{z}/{x}/{y}.png `
  --dart-define=MAP_TILE_ATTRIBUTION="© Example Maps" `
  --dart-define=MAP_TILE_ATTRIBUTION_URL=https://maps.example.org/terms `
  --dart-define=MAP_TILE_ALLOWS_BULK_DOWNLOAD=true
```

Regional download appears only when
`MAP_TILE_ALLOWS_BULK_DOWNLOAD=true`. This permission is always ignored for
`tile.openstreetmap.org`, even if configured incorrectly. Before enabling it,
explicitly confirm that the source terms permit prefetching and offline use.

## Offline emergency directory

Country-specific emergency numbers and official links live in
`assets/emergency_contacts/`. Every translation is strictly validated and a
broken translation falls back to the complete English directory. When updating
the data, review every source and the `reviewedAt` date; an administrative line
must never be presented as emergency dispatch.
