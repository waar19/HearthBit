# Validación iOS de reconexión

Use este prompt en Cursor sobre la Mac cuando la versión final esté disponible
en `origin/master`:

> Trabaja como agente en el repositorio HearthBit, sobre macOS. No crees commits
> ni hagas push sin autorización explícita. Primero ejecuta `git status` y no
> descartes cambios locales. Actualiza `master` solo si el árbol está limpio,
> usando `git pull --ff-only origin master`.
>
> En `app/`, ejecuta `flutter pub get`, `flutter analyze` y `flutter test`.
> Después entra a `app/ios`, ejecuta `pod install` y vuelve a `app/` para correr
> `flutter build ios --debug --no-codesign`. Corrige únicamente errores reales
> de compilación o de disponibilidad de API en
> `ios/Runner/HearthBitMeshPlugin.swift`; no cambies el protocolo binario,
> firmas, tipos de paquete ni la política de privacidad.
>
> Abre `app/ios/Runner.xcworkspace`, selecciona el equipo de firma y compila
> Runner en un iPhone físico. Verifica permisos Bluetooth, ubicación y
> micrófono, además de los modos de segundo plano ya declarados.
>
> Con el Galaxy S25 y el iPhone a menos de cinco metros, prueba:
>
> 1. HearthBit Android ↔ HearthBit iOS: chat privado seguro en ambos sentidos.
> 2. HearthBit Android ↔ BitChat iOS: chat privado seguro en ambos sentidos.
> 3. En cada pareja, apaga Bluetooth 30 segundos con el chat abierto, escribe
>    desde HearthBit durante la desconexión y vuelve a activarlo.
> 4. Confirma que el chat se actualiza sin cerrarlo, Noise se renegocia solo y
>    el mensaje pendiente aparece exactamente una vez.
> 5. Repite cerrando y abriendo HearthBit y con ambas apps en segundo plano.
> 6. Repite una desconexión en perfil crítico y confirma que el burst de
>    recuperación evita esperar el ciclo de escaneo completo.
>
> Registra tiempos de reconexión y logs `HearthBitMesh` de Xcode. Actualiza
> `docs/field-test.md` solo con resultados observados; no declares aprobada una
> prueba que no se haya ejecutado. Al terminar, informa comandos, resultados,
> errores corregidos, archivos cambiados y riesgos pendientes.

