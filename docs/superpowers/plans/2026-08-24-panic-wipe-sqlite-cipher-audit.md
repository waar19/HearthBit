# Audit de cobertura de DBs (Hueco 3)

> **Task:** `docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-plan.md` § Task 1.
> **Estado al ejecutar:** `b273d96` (HEAD de `feature/anchor-p0`).
> **Alcance:** inventario de aperturas de SQLite en `app/lib/**` y
> `app/android/app/src/main/**`; clasificación sensible / no sensible /
> revisar; migración de hits no cifrados a `SecureDatabase.open()`.

## Greps ejecutados

```bash
# A. Llamadas directas a openDatabase en Dart de producción
Select-String -Path app/lib -Pattern "openDatabase\(" -Recurse
Select-String -Path app/lib -Pattern "getDatabasesPath\(" -Recurse
Select-String -Path app/lib -Pattern "databaseFactoryFfi|databaseFactoryFfiInit" -Recurse
Select-String -Path app/lib -Pattern "deleteDatabase\(" -Recurse
Select-String -Path app/lib -Pattern "sqflite|sqlcipher" -Recurse

# B. Llamadas nativas a SQLite / stores cifrados en Android
Select-String -Path app/android/app/src/main -Pattern "openOrCreateDatabase|openDatabase|SQLiteDatabase" -Recurse
Select-String -Path app/android/app/src/main -Pattern "EncryptedSharedPreferences|getSharedPreferences|KeyStore|getFilesDir|getCacheDir" -Recurse

# C. Stores nativos iOS (Hueco 5, fuera de alcance directo de este audit, registrados)
Select-String -Path app/ios/Runner -Pattern "UserDefaults|SecItemAdd|SecItemDelete|FileManager|URLCache" -Recurse
```

Equivalentes ejecutados con `rg` (lookaround no soportado por `Select-String`
en PowerShell 5.1 sin `ConvertTo-Json`). Resultados abajo.

## Hits encontrados

### `app/lib/services/secure_database.dart` (wrapper cifrado)

| Path:Línea | DB | Clasificación | Acción |
|---|---|---|---|
| `app/lib/services/secure_database.dart:68` | `testFactory.openDatabase` (rama test) | no sensible (rama de tests inyectada) | mantener — solo se usa cuando el caller pasa `testFactory` |
| `app/lib/services/secure_database.dart:81` | `sqlcipher.openDatabase(..., password: ...)` — producción | sensible (camino cifrado real) | mantener — única ruta productiva del wrapper |
| `app/lib/services/secure_database.dart:119` | `sqlcipher.openDatabase(..., password: ..., readOnly: true)` — sonda de migración | sensible (lectura de BD cifrada) | mantener — comprobación atómica de cifrado pre-existente |
| `app/lib/services/secure_database.dart:153` | `sqlcipher.openDatabase(..., singleInstance: false)` — lectura en claro para re-cifrar | sensible (solo abre la copia en claro como paso intermedio de `sqlcipher_export`) | mantener — migración atómica a cifrado, va seguida de borrado de la copia en claro y verificación de integridad |
| `app/lib/services/secure_database.dart:258` | `sqlcipher.openDatabase(..., password: ..., readOnly: true)` — `PRAGMA cipher_integrity_check` | sensible (verificación de cifrado) | mantener — la verificación exige abrir con la clave maestra |

### Repositorios Dart (callers de `SecureDatabase.open()`)

| Path:Línea | DB | Clasificación | Acción |
|---|---|---|---|
| `app/lib/services/family_repository.dart:22-34,39` | `hearth_bit_family.db` (grupos, miembros, signing_public_key, fingerprint, owner_signing_key) | sensible | **OK** — invoca `SecureDatabase.open(...)` |
| `app/lib/services/message_repository.dart:102-161,166` | `hearth_bit.db` (messages, known_peers, private_message_outbox, emergency_outbox/ack/attempt_hash) | sensible (contenido de chat y outbox de emergencia) | **OK** — invoca `SecureDatabase.open(...)` |
| `app/lib/services/transfer_repository.dart:21-71,76` | `hearth_bit_transfers.db` (transfers + claves de sesión X3DH) | sensible (claves de sesión y metadatos de archivos) | **OK** — invoca `SecureDatabase.open(...)` |
| `app/lib/services/rescue_case_repository.dart:45-66,44` | `hearth_bit_rescue.db` (rescue_cases, SOS) | sensible (casos de rescate) | **OK** — invoca `SecureDatabase.open(...)` |
| `app/lib/services/rescue_roster_repository.dart:26-47,25` | `hearth_bit_rescue.db` (rescue_teams, rescue_members con signing keys) | sensible (claves de firma de equipo de rescate) | **OK** — invoca `SecureDatabase.open(...)` |
| `app/lib/services/swept_zone_repository.dart:31-52,30` | `hearth_bit_rescue.db` (swept_zones) | sensible (zonas rastrilladas con peer_id y timestamps) | **OK** — invoca `SecureDatabase.open(...)` |

### Tests (`app/test/**`) — fuera de producción

| Path:Línea | DB | Clasificación | Acción |
|---|---|---|---|
| `app/test/family_repository_test.dart:81` | `databaseFactoryFfi.openDatabase` | tests (FFI SQLCipher en tmp) | no aplica — código de test |
| `app/test/message_repository_test.dart:149,406,453` | `databaseFactoryFfi.openDatabase` | tests | no aplica — código de test |
| `app/test/rescue_case_repository_test.dart:40,60,168,184,211` | `databaseFactoryFfi.openDatabase` | tests | no aplica — código de test |
| `app/test/transfer_retention_test.dart:112` | `databaseFactoryFfi.openDatabase` | tests | no aplica — código de test |
| `app/test/swept_zone_repository_test.dart:40,54` | `databaseFactoryFfi.openDatabase` | tests | no aplica — código de test |
| `app/test/{family,message,rescue_case,rescue_roster,swept_zone}_repository_test.dart`, `rescue_case_controller_test.dart:627` | `databaseFactoryFfi.deleteDatabase` | tests | no aplica — código de test |

### Android nativo (sin `openDatabase` directo)

- `EncryptedSharedPreferences` / `getSharedPreferences` en
  `KeystoreSecureStore.kt` y `MeshEngine.kt:56` operan sobre archivos de
  preferencias cifrados por Keystore (AndroidKeyStore). **No son SQLite**;
  el audit de "cobertura de DBs" no aplica. La cobertura del wipe la cierra
  Task 3 (Hueco 4).
- Cero hits para `openOrCreateDatabase`, `SQLiteDatabase`, `openDatabase`
  en `app/android/app/src/main`.

### iOS nativo

- No hay llamadas a SQLite desde Swift (`HearthBitMeshPlugin.swift`,
  `HearthBitFileImportBridge.swift`, `IOSMeshPersistence.swift`,
  `IOSMeshSecurity.swift`, etc.). Toda persistencia pasa por Keychain
  (`SecItemAdd` / `SecItemDelete`) y `UserDefaults`. La cobertura del wipe
  la cierra Task 4 (Hueco 5).

## Comentarios en código

No se requieren comentarios `// NOT CIPHERED:`: este audit no encontró
ningún archivo SQLite de producción abierto sin cifrar. Cada repositorio
pasa por `SecureDatabase.open()` con la clave maestra derivada de
`SecureDatabaseKeyStore.readOrCreate()` (almacenada en
`flutter_secure_storage` con backend Keychain/Keystore).

## Cambios aplicados

- `app/lib/**` — sin cambios (todas las DBs sensibles ya usan
  `SecureDatabase.open()`).
- `app/android/app/src/main/**` — sin cambios.
- `app/ios/Runner/**` — sin cambios (no hay SQLite directo).

## Conclusión

**PASS.** Las 6 bases SQLite de producción
(`hearth_bit.db`, `hearth_bit_family.db`, `hearth_bit_transfers.db`,
`hearth_bit_rescue.db`) se abren exclusivamente a través de
`SecureDatabase.open()`, que invoca `sqlcipher.openDatabase(..., password: <clave maestra>)`.
La única ruta `openDatabase` no cifrada está en
`secure_database.dart:153` y es una apertura efímera de la copia en
claro durante la migración atómica a cifrado, seguida de borrado de
la copia en claro y verificación de integridad; no queda archivo en
claro en reposo.

## Concerns

1. **Apertura temporal en claro durante migración** (`secure_database.dart:153`).
   Por diseño la migración debe abrir la base legacy en claro para ejecutar
   `sqlcipher_export`. La ventana es corta (atómica con rename) y termina
   con `_verify()` + borrado de la copia en claro, pero si un proceso
   muere entre `rename(databasePath)` y `_verify()`, podría quedar una
   copia `.plaintext.backup` brevemente. La rama de recuperación
   (`_recoverInterruptedMigration`, líneas 201-229) ya la maneja.
   Recomendación: documentar en el spec que la única ruta no cifrada
   transitoria es esta. (Fuera del scope de este task.)

2. **Tests FFI usan `databaseFactoryFfi`** (no `databaseFactoryFfiInit`
   explícito). Verificar que el suite de tests inicializa el factory
   global antes de correr; en `flutter test` el setup está en los
   `setUp` de cada archivo de test. Sin acción aquí, pero Task 7
   (idempotencia) podría beneficiarse de un helper común.

3. **Persistencia no-SQLite** (Keychain iOS, EncryptedSharedPreferences
   Android, `UserDefaults`, `flutter_secure_storage`): fuera del scope
   de este audit (Hueco 3). Su cobertura de wipe se cierra en Task 3
   (Hueco 4) y Task 4 (Hueco 5).
