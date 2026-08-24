# Panic wipe integral + SQLite cifrada (cierre de los 8 huecos)

Fecha: 2026-08-24
Estado: aprobado por el usuario (alcance confirmado)

## Contexto

HearthBit ya tiene un panic wipe end-to-end y SQLCipher en las bases
sensibles. La rama `feature/anchor-p0` (Phase 1 del plan maestro)
cerró la auditoría, las pruebas y la paridad iOS del Anchor, pero el
trabajo de seguridad transversal sigue marcado en el CHANGELOG
"Sin publicar" como obligatorio para release.

Este spec cierra los **8 huecos** identificados durante la auditoría
inicial del panic wipe: la implementación base existe, pero la
configuración nativa (iOS), la cobertura exhaustiva, la atomicidad, la
idempotencia, el comportamiento post-wipe y los tests iOS están
incompletos.

Trabajo previo relevante (no se modifica):

- `app/lib/services/secure_database.dart` (SQLCipher + migración atómica
  + `destroy`).
- `app/lib/services/privacy_data_eraser.dart` (limpieza de residuales).
- `app/lib/services/app_preferences.dart:166` (`panicWipe`).
- `app/lib/services/at_rest_file_cipher.dart` (cifrado de archivos).
- `app/lib/screens/home_screen.dart:1153-1179` (UI con confirmación
  tipeada y 8 sub-wipes en cadena).
- `app/android/.../mesh/MeshEngine.kt:1915` (`panicWipe` nativo).
- `app/ios/Runner/HearthBitMeshPlugin.swift:948` (handler MethodChannel).
- `app/android/app/src/main/res/xml/backup_rules.xml` +
  `data_extraction_rules.xml` (Android auto-backup excluido en todos los
  dominios).
- `sqflite_sqlcipher: ^3.4.1` en `pubspec.yaml`.
- `app/test/secure_database_test.dart`,
  `app/test/at_rest_file_cipher_test.dart`.

## Objetivo

Cerrar los 8 huecos para que la tesis de seguridad sea publicable:
cualquier dispositivo secuestrado, devuelto al fabricante o analizado
forensicamente no debe dejar al usuario expuesto.

## Fuera de alcance

- Cambios al protocolo de mesh o al handshake Noise.
- Cambios al flujo de onboarding existentes.
- Cambios al modelo de datos relacional (solo se añade configuración).
- iCloud / Drive: solo se excluye la app, no se ofrece migrar datos.
- Modo "wipe remoto" (alguien en la mesh pide wipe a otro nodo).
- Forensic scrubbing de bloques flash a nivel kernel (responsabilidad
  del SO; el wipe del app se apoya en la API de borrado del FS).

## Diseño

### Hueco 1 — iOS `NSFileProtectionComplete`

**Problema:** `Info.plist` no fija la clase de protección de archivos.
El default del sistema es
`NSFileProtectionCompleteUntilFirstUserAuthentication`, que descifra
después del primer unlock y mantiene el archivo legible mientras el
dispositivo esté encendido. Combinado con SQLCipher es aceptable, pero
para una app de emergencias es preferible
`NSFileProtectionComplete` (cifrado siempre, incluso con dispositivo
desbloqueado).

**Decisión:** aplicar `NSFileProtectionComplete` recursivamente al
directorio de datos de la app en iOS (`Library/Application Support/` y
`Documents/`) al inicio de la app y tras cada escritura. SQLCipher
suma una segunda capa. Sin cambios en Android (ya usa
EncryptedSharedPreferences para claves y se apoya en FBE del SO).

**Implementación:**

- Nuevo helper Swift `IOSFileProtection.apply(.complete)` que enumera
  los archivos del app data dir y aplica la clase via
  `NSFileManager.setAttributes(_:ofItemAtPath:)` con
  `[FileAttributeKey.protectionKey: FileProtectionType.complete]`.
- Llamado desde `HearthBitMeshPlugin.applicationDidFinishLaunching` y
  tras cada `panicWipe`.
- Si el dispositivo no soporta la clase (raro en iOS moderno, pero
  posible en simulador), degradar a
  `.completeUntilFirstUserAuthentication` y loggear
  `MeshSecurityLog` con severidad `warn`.

### Hueco 2 — Exclusión de iCloud backup

**Problema:** iOS respalda `Library/Application Support/` y
`Documents/` a iCloud Drive por defecto. La política de privacidad
del repo dice que los datos son locales, pero sin
`NSURLIsExcludedFromBackupKey` el backup ocurre igualmente.

**Decisión:** marcar todo el contenido del app data dir con
`NSURLIsExcludedFromBackupKey = true`. Se aplica junto con el helper
del Hueco 1 en cada ejecución.

**Implementación:**

- Mismo helper `IOSFileProtection.apply(.complete)` extendido: tras
  fijar la protección, recorrer los URLs y aplicar
  `var resourceValues = URLResourceValues(); resourceValues
  .isExcludedFromBackup = true; try url.setResourceValues(resourceValues)`.
- Si la operación falla (sandbox), loggear warning sin abortar el wipe.

### Hueco 3 — Auditoría de cobertura de DBs

**Problema:** `SecureDatabase.open()` se usa en los repos, pero un grep
puede revelar llamadas directas a `openDatabase()`,
`getDatabasesPath()`, o uso de `DatabaseFactory` sin la envoltura.

**Decisión:** grep + audit + migración de cualquier DB sensible que
no esté cifrada.

**Implementación:**

- Grep en `app/lib/` y `app/android/.../mesh/` por
  `openDatabase(`, `getDatabasesPath(`,
  `databaseFactoryFfi`, `sqfliteFfiInit`.
- Para cada hit: si la DB contiene datos sensibles (mensajes, identidades,
  transferencias, rescate), migrar a `SecureDatabase.open()`.
- Si la DB es genuinamente no sensible (p. ej. cache de UI), documentar
  la excepción con un comentario que apunte a la decisión.
- Si la DB no se puede clasificar, marcarla como "revisar" y bloquear
  el merge hasta resolver.

### Hueco 4 — Auditoría de wipe nativo Android

**Problema:** `MeshEngine.panicWipe()` Android limpia el engine, los
beacon actuators, las sesiones Noise, etc. Pero el audit debe cubrir
todo el estado nativo persistente: NVS, Keystore entries (no-noise),
DataStore, SharedPreferences nativos, archivos restantes.

**Decisión:** enumerar y cubrir cada uno.

**Implementación:**

- Inventario de almacenes persistentes Android:
  - `EncryptedSharedPreferences` (`MeshSecurityStore`).
  - `KeystoreSecureStore` (claves de admin, OTA recipient, etc.).
  - `MeshIdentity` NVS o equivalente (claves Noise).
  - Cualquier `getSharedPreferences("...", ...)` directo.
  - Cualquier `getFilesDir()` o `getCacheDir()` residual.
- Para cada uno: llamada a su método `wipe()` o `clear()` desde
  `MeshEngine.panicWipe()`. Si no existe, añadirlo.
- Test: instrumentar un fake store, llamar `panicWipe`, verificar
  que cada store está vacío.

### Hueco 5 — Auditoría de wipe nativo iOS

**Problema:** el handler iOS en
`HearthBitMeshPlugin.swift:948` limpia `peerIdentityPins` y reinicia
el engine. Falta confirmar: Keychain completo, UserDefaults nativo,
archivos restantes.

**Implementación:**

- Inventario iOS:
  - `UserDefaults.standard` (claves no manejadas por Dart).
  - `SecItemDelete` para Keychain (clases `kSecClassGenericPassword`,
    `kSecClassInternetPassword`, `kSecClassCertificate`).
  - `FileManager.default.removeItem` para archivos en
    `Application Support`, `Documents`, `Caches`, `tmp`.
  - `URLCache.shared.removeAllCachedResponses()`.
- Cada uno: llamada desde el `case "panicWipe"` del handler.
- Test: `PanicWipeTest.swift` que mockea los stores y verifica.

### Hueco 6 — Atomicidad y orden de operaciones

**Problema:** si la app crashea mid-wipe, ¿quedan residuos accesibles?

**Decisión:** dos principios:

1. **El orden es "datos primero, clave al final".** El comentario en
   `secure_database.dart:46-48` ya documenta esto. La razón: si
   destruyes la clave y luego crasheas antes de borrar los archivos,
   el contenido es irrecuperable (correcto), pero la app queda en
   estado inconsistente. Si destruyes datos y luego crasheas antes de
   borrar la clave, los archivos pueden contener páginas de la DB
   anterior, pero están cifradas con la clave que aún existe (la
   clave se destruye al final). El wipe al reintentar encuentra la
   clave y termina.
2. **Cada sub-wipe es idempotente.** Si se llama dos veces, el segundo
   pase es no-op. Esto cubre el caso de reintento y el caso de wipe
   duplicado (UI presionada dos veces, MethodChannel llamado dos
   veces).

**Implementación:**

- Documentar el orden canónico en el comentario de
  `home_screen.dart:1153`. Si se reordena, el comentario debe
  actualizarse.
- Cada sub-wipe (`clearResidualFiles`, `destroy`, etc.) devuelve éxito
  incluso si ya estaba vacío.
- Test: invocar `panicWipe` dos veces seguidas, verificar que la
  segunda llamada no lanza y termina con el mismo estado final.

### Hueco 7 — Re-arranque post-wipe

**Problema:** tras un wipe, la app debe exigir re-onboarding. Si entra
en estado zombie (con UI pero sin estado), es peor que forzar cierre.

**Decisión:** al iniciar, `SecureDatabaseKeyStore.readOrCreate()`
crea clave nueva si no existe. Esto ya es el comportamiento actual
(`_readOrCreate` genera clave si falta). Lo que falta verificar: la
UI de onboarding se muestra y el usuario no ve datos viejos.

**Implementación:**

- Test de integración: tras panic wipe, relanzar la app, verificar
  que la ruta de navegación es `/onboarding` y no `/home`.
- Si el enrutador no distingue, añadir un check
  `await SecureDatabaseKeyStore.exists()` en el bootstrap y forzar
  el reset del `GoRouter` o equivalente.

### Hueco 8 — Tests iOS dedicados

**Problema:** la lógica iOS de panic wipe vive en
`HearthBitMeshPlugin.swift` pero no tiene suite dedicada en
`RunnerTests/`. El coverage depende de que el binario se compile
(CI `xcodebuild test`), no de aserciones.

**Decisión:** añadir `RunnerTests/PanicWipeTests.swift` con cobertura
mínima.

**Implementación:**

- Test 1: dado un `KeychainStore` mockeado con N entradas, llamar
  `panicWipe`, verificar `deleteAll` invocado.
- Test 2: dado un `FileManager` mockeado, verificar que se borran
  `Application Support`, `Documents`, `Caches`, `tmp`.
- Test 3: idempotencia — llamar dos veces, sin crash.
- Test 4: ordering — `SecItemDelete` ocurre antes de
  `FileManager.removeItem` (la clave se va antes que los datos, por
  consistencia con Android).

## Criterios de éxito

1. iOS: tras `apply(.complete)`, cualquier archivo bajo
   `Application Support/` y `Documents/` tiene `FileAttributeKey
   .protectionKey == .complete` y `isExcludedFromBackup == true`.
   Verificable con `ls -l@` o un test XCTest.
2. iOS: un backup de iCloud sobre un dispositivo con la app no
   incluye los archivos de la app. Verificable manualmente con un
   dispositivo real + Xcode Devices.
3. Android + iOS: ningún grep de `openDatabase(` o equivalente en
   código de producción apunta a una DB no cifrada con datos
   sensibles. Cualquier excepción está documentada en un comentario
   en el código que apunte a la decisión.
4. Android: tras `MeshEngine.panicWipe()`, los siguientes almacenes
   están vacíos: EncryptedSharedPreferences, Keystore (excepto claves
   de sistema), NVS, archivos restantes. Verificable con un test
   instrumentado.
5. iOS: tras el handler `panicWipe`, Keychain, UserDefaults nativos y
   archivos de datos están vacíos. Verificable con `PanicWipeTests`.
6. Crash mid-wipe no deja datos accesibles. El reintento del wipe
   termina con el mismo estado final que un wipe sin crash.
7. `panicWipe` es idempotente. Segunda llamada no lanza.
8. Tras wipe + relaunch, la app muestra onboarding y no tiene
   referencia a estado previo.
9. CI verde en `mobile-ci.yml` (flutter analyze, flutter test, gradle
   test, xcodebuild test).

## Tests nuevos (resumen)

- `app/lib/services/secure_database_test.dart` (ya existe, ampliar
  idempotencia).
- `app/lib/services/privacy_data_eraser_test.dart` (nuevo).
- `app/lib/services/app_preferences_test.dart` (verificar
  `panicWipe` borra todas las keys).
- `app/test/panic_wipe_post_relaunch_test.dart` (nuevo, integración).
- `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/PanicWipeTest.kt`
  (nuevo, instrumenta stores).
- `app/ios/RunnerTests/PanicWipeTests.swift` (nuevo, 4 tests como
  arriba).

## Riesgos y puntos abiertos

- **Performance:** aplicar `NSFileProtectionComplete` recursivamente
  puede ser lento si hay miles de archivos. Mitigación: aplicar solo
  al primer nivel y dejar que el sistema propague.
- **Backward compatibility:** usuarios con DBs existentes en plaintext
  (instalaciones pre-SQLCipher) deben pasar por la migración. La
  lógica en `_migratePlaintextIfNeeded` ya cubre esto, pero un test
  E2E de "instalar versión vieja, actualizar, wipe" es deseable
  (Task 9 del plan maestro cubre hardware E2E, no es bloqueante aquí).
- **Forensic scrubbing:** aunque la clave se destruya, los bloques
  flash pueden contener páginas antiguas. Android FBE y APFS en iOS
  ofrecen "secure erase" via TRIM/overwrite, pero no es invocable
  desde el app. El wipe se apoya en la promesa del SO; el spec lo
  declara como fuera de alcance.
- **Versión mínima de iOS:** `NSFileProtectionComplete` requiere
  iOS 4+. No es un bloqueo pero el test debe skipear en simuladores
  donde no aplica la protección.
- **Naming:** el spec usa "panic wipe" pero la UI dice "Wipe data".
  Mantener consistencia en strings (EN/ES). El cambio es trivial
  (3 strings) pero debe coordinarse con el spec de localization.

## Próximo paso

Tras aprobación:

1. Crear `docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-plan.md`
   con tasks bite-sized, cada uno con su TDD cycle.
2. Ejecutar con subagent per task (modo `subagent`).
3. Cierre con final review whole-branch y merge.
