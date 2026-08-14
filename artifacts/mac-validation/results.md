# Validación Mac/iOS — fase 7

- Commit validado: `7fca01f` en `feature/helpful_links` (`f1087eb` es ancestro)
- Entorno: macOS 26.6.1; Xcode 26.6 (17F113); Flutter 3.47.0; Dart 3.13.0; CocoaPods 1.17.0
- iPhone / iOS: iPhone físico conectado con iOS 26.6; nombre, modelo e identificadores omitidos
- `dart format`: PASS — 110 archivos, 0 cambios
- `flutter analyze`: PASS — sin incidencias después de la corrección
- `flutter test`: PASS — 198 pruebas
- CocoaPods: PASS
- `Info.plist` e `InfoPlist.strings`: PASS
- Build iOS release sin firma: PASS
- RunnerTests simulador: PASS — 23/23; aparece `** TEST SUCCEEDED **` y se ejecutaron `RunnerTests` y `ConformanceFixtureTests`

## Validación física

- Instalación y primer arranque: BLOCKED — falta observación manual en Xcode y en el iPhone
- Permisos Bluetooth, ubicación siempre, notificaciones, red local y micrófono: BLOCKED — falta provocar y observar cada permiso en el iPhone
- Malla y notificación/estado coherentes: BLOCKED — falta un segundo nodo físico y observación de la UI
- Segundo plano con pantalla bloqueada durante 10 y 25 minutos: BLOCKED — falta ejecución física cronometrada
- Reconexión HearthBit ↔ BitChat en ambos sentidos: BLOCKED — falta BitChat y ejecución física en ambos sentidos
- Outbox privado sin duplicados: BLOCKED — falta evidencia física de entrega once-only
- Modo rescate tras cierre/reapertura: BLOCKED — falta prueba física aislada con el texto `PRUEBA`
- Radar durante 10 minutos: BLOCKED — falta ejecución física cronometrada
- Textos al 200 % sin desbordes: BLOCKED — falta inspección física; las pruebas Flutter de layout sí aprobaron
- Primer criterio incumplido o bloqueo: no se observó instalación y primer arranque desde Xcode en el iPhone

## Correcciones aplicadas

- Se esperó correctamente el resultado asíncrono del decodificador de teselas.
- Se hizo explícito el tipo de datos persistidos por Swift para evitar ambigüedad de compilación.
- Se rechazaron datos sobrantes después de una carga comprimida y fragmentos anidados.
- Se reparó la compilación de los tests Swift y se conservaron sus casos de conformidad.

## Resumen de comandos

- Git: estado, fetch, cambio a la rama requerida, pull fast-forward y actualización recursiva de submódulos.
- Flutter: doctor, dependencias, formato, análisis, pruebas y build iOS release sin firma.
- iOS: instalación de Pods y validación de todos los plist localizados.
- Swift: selección dinámica de simulador y `xcodebuild test` sin firma.
- Dispositivo: se confirmó de forma saneada un iPhone iOS conectado; no se publicaron identificadores.

## Evidencia saneada

- `artifacts/mac-validation/results.md`
- `artifacts/mac-validation/xcodebuild-simulator.log`
- `artifacts/mac-validation/simulator-log-sha256.txt`
- `artifacts/mac-validation/ios-validation-sanitized.tar.gz`

## Gate de release

HearthBit no queda declarada lista para emergencias reales: permanecen gates P0 físicos en estado BLOCKED.
