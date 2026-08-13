# Entrega de validación para Mac

Este trabajo queda **pendiente de compilación Swift/Xcode y pruebas físicas**.
No use los pasos siguientes para declarar PASS sin observar todos los criterios.

## 1. Sincronizar sin perder cambios

```bash
cd ~/src/emergency-com
git status --short
```

Si aparece cualquier cambio, deténgase: no ejecute `stash`, `reset`, `checkout`
ni `clean`. Con el árbol limpio y la rama correcta:

```bash
git pull --ff-only
git status --short
```

## 2. Dependencias y validación Flutter

```bash
cd ~/src/emergency-com/app
flutter doctor -v
flutter pub get
flutter analyze
flutter test
```

## 3. CocoaPods, recursos y build sin firma

El repositorio contiene `ios/Podfile` y `ios/Podfile.lock`; por tanto, instale
los pods después de `flutter pub get`:

```bash
cd ~/src/emergency-com/app/ios
pod install
plutil -lint Runner/Info.plist
plutil -lint Runner/*.lproj/InfoPlist.strings
cd ..
flutter build ios --debug --no-codesign
```

Abra el workspace, no el `.xcodeproj`:

```bash
open ios/Runner.xcworkspace
```

En Xcode confirme:

1. `InfoPlist.strings` es un variant group con `en`, `es`, `de`, `fr`,
   `zh-Hans` y `ja`, y está en `Runner > Build Phases > Copy Bundle Resources`.
2. `AppDelegate.swift`, `SceneDelegate.swift`, `HearthBitMeshPlugin.swift`,
   `HearthBitTransferProtocol.swift` e `IOSBeaconActuator.swift` pertenecen a
   `Runner`; `RunnerTests.swift` pertenece únicamente a `RunnerTests`.
3. No hay advertencias por recursos duplicados ni por localización `zh`.

## 4. Tests Swift en simulador

Liste los destinos y copie exactamente el nombre de un iPhone disponible:

```bash
cd ~/src/emergency-com/app
xcrun simctl list devices available
export SIMULATOR_NAME="iPhone 16 Pro"
mkdir -p ../artifacts
set -o pipefail
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME,OS=latest" \
  CODE_SIGNING_ALLOWED=NO \
  | tee ../artifacts/xcodebuild-simulator.log
```

Cambie solo `SIMULATOR_NAME` si ese modelo no existe en la Mac. `PASS` requiere
`** TEST SUCCEEDED **`, cero tests fallidos y ejecución de `RunnerTests`.
Build fallido, target ausente, crash o test omitido es `FAIL`.

## 5. Firma, instalación física y permisos

En Xcode seleccione `Runner > Signing & Capabilities`, el equipo autorizado y
el iPhone físico. Ejecute una vez `Product > Run`. Después puede repetir por
CLI:

```bash
cd ~/src/emergency-com/app
flutter build ios --debug
xcrun devicectl list devices
export DEVICE_ID="<identificador-devicectl>"
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  build/ios/iphoneos/Runner.app
```

No publique `DEVICE_ID`. En el iPhone conceda Bluetooth, cámara, ubicación,
micrófono y red local solo durante el caso que los necesita.

Para validar idiomas, en `Product > Scheme > Edit Scheme > Run > Options`
seleccione cada `Application Language`; desinstale la app o restablezca permisos
antes de volver a provocar cada aviso. Criterio PASS: las siete descripciones
son monolingües en el idioma elegido y un idioma no soportado cae a inglés.
Cualquier mezcla, clave visible, idioma incorrecto o permiso sin descripción es
FAIL.

## 6. Guion físico

Lea completo `docs/ios-reconnection-validation.md`. Ejecute capturas separadas
para:

- `D1-NOISE-01`: privado seguro HearthBit ↔ HearthBit.
- Reconexión HearthBit ↔ BitChat en ambos sentidos.
- Segundo plano y bloqueo durante 10 y 25 minutos.
- Outbox privado persistente con tres IDs y conteo once-only.
- Baliza: rechazo, aceptación, parada, expiración y salida a segundo plano.
- Mapa: caché sin internet, SOS/check-in, consentimiento y revocación.

Ejemplo de captura:

```bash
cd ~/src/emergency-com
export RUN_ID="RUN-$(date -u +%Y%m%dT%H%M%SZ)"
bash scripts/field-test/collect-ios-field-log.sh \
  --case-id D1-NOISE-01 \
  --run-id "$RUN_ID" \
  --node-alias IOS-A \
  --device-id "$DEVICE_ID" \
  --duration 300
```

El script requiere iOS 17 o posterior, reinicia HearthBit, escribe únicamente
salida saneada y marca `result=PENDING`. Para iOS 16, siga la alternativa
manual de Xcode descrita en la guía. PASS/FAIL se decide después con la UI de
ambos teléfonos y todos los criterios. Si iOS termina la app, faltan permisos,
hardware, BitChat o señal GPS, use `BLOCKED` cuando la guía así lo indique.

## 7. Devolver resultados

Cree un resumen sin datos sensibles:

```bash
cd ~/src/emergency-com
mkdir -p artifacts/mac-validation
cat > artifacts/mac-validation/results.md <<'EOF'
# Validación Mac/iOS

- Commit validado:
- macOS / Xcode / Flutter:
- iPhone / iOS (sin serial):
- flutter analyze: PASS|FAIL
- flutter test: PASS|FAIL
- build iOS sin firma: PASS|FAIL
- RunnerTests simulador: PASS|FAIL
- Localización de permisos: PASS|FAIL|BLOCKED
- D1-NOISE-01: PASS|FAIL|BLOCKED
- Reconexión BitChat: PASS|FAIL|BLOCKED
- Segundo plano: PASS|FAIL|BLOCKED
- Outbox once-only: PASS|FAIL|BLOCKED
- Baliza: PASS|FAIL|BLOCKED
- Mapa: PASS|FAIL|BLOCKED
- Primer criterio incumplido o bloqueo:
- Rutas de evidencia saneada:
EOF

shasum -a 256 artifacts/field-test/*/ios-hearthbit-sanitized.log \
  > artifacts/mac-validation/field-log-sha256.txt
tar -czf artifacts/mac-validation/ios-validation-sanitized.tar.gz \
  artifacts/mac-validation/results.md \
  artifacts/mac-validation/field-log-sha256.txt \
  artifacts/field-test/*/capture.json \
  artifacts/field-test/*/ios-hearthbit-sanitized.log
```

Revise el archivo antes de compartirlo. Devuelva `results.md`, el log de
simulador y el `.tar.gz` saneado; no devuelva Device Console completa,
coordenadas, capturas de mapas, MAC, UUID, seriales, claves ni mensajes reales.
