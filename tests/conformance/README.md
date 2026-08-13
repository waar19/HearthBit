# Suite de conformidad binaria

Esta suite fija el perfil de `docs/bitchat-core-profile.md` contra
`vendor/bitchat-android@5156f7de89ec9f6a3429630d90f709b68f6fd7fd`.
`fixtures.v1.json` contiene metadatos neutrales y `blobs/*.hex` contiene los
bytes exactos. Los runners ignoran espacios en los blobs, pero no bytes
sobrantes.

Los vectores no son ejemplos inventados:

- v1, firma canónica, GCS, Courier y HBT provienen de los golden tests y codecs
  de producción existentes.
- v2/ruta se obtuvo con el encoder de producción usando campos deterministas.
- DEFLATE crudo y zlib representan el mismo payload determinista y siguen la
  política de escritura/lectura del perfil.
- los casos truncados o malformed son mutaciones mínimas de esos frames
  positivos: versión, longitud, firma, ruta, padding, stream o límite.
- los payloads de extensiones reproducen literalmente
  `docs/extension-registry.md`.

## Ejecución

Desde PowerShell en la raíz:

```powershell
.\tests\conformance\run-conformance.ps1
```

Se puede limitar con `-Target kotlin`, `dart`, `python`, `swift` o `firmware`.
Swift se ejecuta solo en macOS. Firmware requiere ESP-IDF para compilar; el
self-test C corre durante el arranque y aborta si un vector discrepa. En
Windows sin ESP-IDF, el script valida que el header C generado siga siendo
idéntico a los blobs neutrales.

Para regenerar el adaptador C después de cambiar fixtures:

```powershell
python .\tests\conformance\generate_firmware_header.py
python .\tests\conformance\generate_firmware_header.py --check
```

Comandos directos:

- Kotlin: `cd app/android; .\gradlew.bat :app:testDebugUnitTest --tests com.hearthbit.app.mesh.ConformanceFixtureTest`
- Dart: `cd app; flutter test test/conformance_fixtures_test.dart`
- Python: `cd relay; python -m pytest tests/test_conformance_fixtures.py`
- Swift: `cd app/ios; xcodebuild test -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination "platform=iOS Simulator,OS=latest,name=iPhone 16" CODE_SIGNING_ALLOWED=NO`
- Firmware: `cd firmware/anchor-node; idf.py build`; después `idf.py flash monitor`

## Matriz exacta por runner

Kotlin JUnit y Swift XCTest cubren:

- `packet.v1.message`, `packet.v2.route_signed`
- `packet.v1.raw_deflate`, `packet.v1.zlib_read`
- todos los `packet.invalid.*`
- `signature.canonical.v1_announce`
- `fragment.payload.valid`, todos los `fragment.invalid.*` y ambos
  `fragment.reassemble.out_of_order.*`
- ambos `gcs.*` y ambos `courier.*`
- `extension.hbt_capability.v1`, `extension.node_capability.anchor`,
  `extension.radar_grant` y ambos `extension.envelope.*`
- todos los `hbt.*`

Python pytest cubre:

- `packet.v1.message`, `packet.v2.route_signed`
- `packet.v1.raw_deflate`, `packet.v1.zlib_read`
- todos los `packet.invalid.*`
- `signature.canonical.v1_announce`
- `fragment.payload.valid`, todos los `fragment.invalid.*` y ambos
  `fragment.reassemble.out_of_order.*`
- ambos `gcs.*`, ambos `courier.*` y ambos `extension.envelope.*`

Dart `flutter_test` cubre todos los `hbt.*` mediante `TransferFrame` de
producción. No duplica el codec de malla nativo de Android/iOS.

El self-test C de firmware cubre:

- `packet.v1.message`
- `packet.v1.raw_deflate`, `packet.v1.zlib_read`
- `packet.invalid.version`, `packet.invalid.header_truncated`,
  `packet.invalid.payload_truncated`, `packet.invalid.signature_truncated`,
  `packet.invalid.padding`, `packet.invalid.deflate_truncated`,
  `packet.invalid.deflate_trailing` y `packet.invalid.expanded_size`

El firmware no declara v2/rutas porque su estructura de paquete de producción
es v1. La cobertura v2 queda en Kotlin, Swift y Python; la matriz evita
presentar una prueba de otro lenguaje como capacidad del firmware.

## Integración continua

El workflow móvil ya ejecuta todos los tests Dart y Kotlin. El job
`conformance` añadido ejecuta pytest. La comprobación del header C permanece en
el script local porque firmware es un submódulo y su cambio debe publicarse con
su propio commit antes de actualizar el puntero del repositorio principal.
XCTest queda listo para macOS, pero no se añadió al workflow de compilación iOS
para no introducir una dependencia frágil de un modelo concreto de simulador.
