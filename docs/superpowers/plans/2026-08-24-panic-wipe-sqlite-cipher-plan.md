# Panic wipe integral + SQLite cifrada — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cerrar los 8 huecos del panic wipe identificados en
`docs/superpowers/specs/2026-08-24-panic-wipe-sqlite-cipher-design.md` para
que la tesis de seguridad sea publicable.

**Architecture:** Implementación nativa por hueco. Tests TDD por task.
El panic wipe existente (`home_screen.dart:1153-1179` +
`MeshEngine.panicWipe()` + iOS `HearthBitMeshPlugin.swift:948`) se
extiende con nuevos helpers y se audita para cobertura. SQLCipher ya
está integrado; este plan no toca la lógica de cifrado, solo su
configuración nativa y su cobertura.

**Tech Stack:** Flutter/Dart (Dart side), Kotlin (Android), Swift (iOS),
SQLCipher (ya integrado), PowerShell + Git Bash (CI/scripts).

## Global Constraints

- Rama activa: `feature/anchor-p0`. No se cambia de rama.
- `git push` SOLO lo ejecuta el usuario. Los subagentes commitean pero
  no pushean.
- Política del repo: código fuente de claves privadas NUNCA entra al
  repo ni a assets, logs, o artefactos. `git ls-files` debe seguir
  sin claves privadas tras cada task.
- Cada task con código produce un commit. Tasks audit-only (sin
  cambios) producen solo el reporte.
- `flutter analyze`, `./gradlew :app:testDebugUnitTest`, y
  `xcodebuild test` deben terminar verdes al cerrar la fase.
- Conventional Commits: `feat:`, `fix:`, `chore:`, `test:`,
  `docs:`, `refactor:`.
- Tests nuevos deben verificar comportamiento real, no tautologías.
  Mocks solo donde sean necesarios (p. ej. Keychain).
- NO se introducen dependencias nuevas en `pubspec.yaml` salvo
  justificación explícita en el reporte (Hueco 1+2 no requiere deps;
  SQLCipher ya está).

## Archivos a tocar (resumen)

- Crear:
  - `app/ios/Runner/Security/IOSFileProtection.swift`
  - `app/ios/RunnerTests/PanicWipeTests.swift`
  - `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/PanicWipeTest.kt`
  - `app/lib/services/privacy_data_eraser_test.dart`
  - `app/test/panic_wipe_post_relaunch_test.dart`
  - `docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-audit.md`
- Modificar:
  - `app/ios/Runner/HearthBitMeshPlugin.swift` (Huecos 1+2+5)
  - `app/android/app/src/main/kotlin/com/hearthbit/app/mesh/MeshEngine.kt` (Hueco 4)
  - `app/lib/screens/home_screen.dart` (Hueco 6: comentario orden)
  - `app/lib/services/secure_database.dart` (Hueco 7: idempotencia)
  - `app/lib/services/app_preferences.dart` (Hueco 7: idempotencia)
  - `app/lib/services/privacy_data_eraser.dart` (Hueco 7: idempotencia)
  - `app/lib/l10n/app_en.arb` + `app_es.arb` (Hueco 8: i18n)
  - `app/test/secure_database_test.dart` (Hueco 7: idempotencia)
  - `app/test/app_preferences_drill_test.dart` (Hueco 7: panicWipe)

## SDD Setup

- Workspace: `C:\src\emergency-com\.superpowers\sdd\2026-08-24-panic-wipe-sqlite-cipher\`
- BASE al arrancar: `b273d96` (HEAD del spec).
- Ledger en `<workspace>/progress.md`.
- Ejecución: subagent per task + review per task + final whole-branch review.

---

## Task 1: Audit de cobertura de DBs (Hueco 3)

**Files:**
- Create: `docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-audit.md`
- Modify (si hay migraciones): cualquier archivo que use `openDatabase(` directamente
- Modify (si hay docs): los archivos con DBs no sensibles que necesiten comentario explicativo

**Interfaces:**
- Consumes: estado actual del repo (HEAD = `b273d96`)
- Produces: `audit.md` con tabla de cada hit, decisión (cifrar / no cifrar / revisar), y código migrado si aplica

- [ ] **Step 1: Grep de llamadas directas a `openDatabase` en producción**

```powershell
Select-String -Path app/lib -Pattern "openDatabase\(" -Recurse
Select-String -Path app/lib -Pattern "getDatabasesPath\(" -Recurse
Select-String -Path app/lib -Pattern "databaseFactoryFfi|databaseFactoryFfiInit" -Recurse
Select-String -Path app/android/app/src/main -Pattern "openOrCreateDatabase|openDatabase" -Recurse
```

Resultado esperado: lista de archivos y líneas. Si vacío, documentar en audit como "todas las DBs usan SecureDatabase.open()".

- [ ] **Step 2: Clasificar cada hit como sensible / no sensible / revisar**

Para cada hit en Step 1:
- ¿Contiene datos sensibles? (mensajes, identidades, transferencias, rescate, etc.)
- Si SÍ → migrar a `SecureDatabase.open()`.
- Si NO (p. ej. cache de UI) → añadir comentario en código que apunte a la decisión.
- Si no se puede clasificar → marcar como REVISAR y bloquear merge.

- [ ] **Step 3: Aplicar migraciones o comentarios**

Si hay migraciones:
- Implementar siguiendo el patrón de `SecureDatabase.open()`.
- Test TDD: test que verifica que la DB se abre cifrada.

- [ ] **Step 4: Escribir el audit MD**

`docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-audit.md` con:

```markdown
# Audit de cobertura de DBs (Hueco 3)

## Greps ejecutados
[lista de comandos]

## Hits encontrados
| Path:Línea | DB | Clasificación | Acción |
|---|---|---|---|
| ... | ... | sensible / no sensible / revisar | migrar / documentar / bloquear |

## Conclusión
[PASS si todas las DBs sensibles están cifradas y las no sensibles documentadas]
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(audit): DB coverage audit; migrate any non-ciphered sensitive DBs"
```

Si no hubo cambios en código, status `DONE` con solo el audit MD.

---

## Task 2: iOS NSFileProtection + iCloud exclusion (Huecos 1+2)

**Files:**
- Create: `app/ios/Runner/Security/IOSFileProtection.swift`
- Create: `app/ios/RunnerTests/IOSFileProtectionTests.swift`
- Modify: `app/ios/Runner/HearthBitMeshPlugin.swift` (llamar al helper en `applicationDidFinishLaunching` y post-wipe)

**Interfaces:**
- `IOSFileProtection.applyComplete()` → aplica `FileProtectionType.complete` a todos los archivos en Application Support, Documents, Caches, tmp.
- `IOSFileProtection.excludeFromBackup()` → marca todos los URLs con `isExcludedFromBackup = true`.
- `IOSFileProtection.applyAll()` → convenience que llama ambas.

- [ ] **Step 1: Test XCTest del helper (TDD)**

```swift
// app/ios/RunnerTests/IOSFileProtectionTests.swift
import XCTest
@testable import Runner

final class IOSFileProtectionTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSFileProtectionTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testApplyCompleteSetsProtectionOnAllFiles() throws {
        let file1 = tempDir.appendingPathComponent("a.db")
        let file2 = tempDir.appendingPathComponent("b.db-wal")
        try "x".write(to: file1, atomically: true, encoding: .utf8)
        try "x".write(to: file2, atomically: true, encoding: .utf8)
        
        try IOSFileProtection.applyComplete(in: tempDir)
        
        let attrs1 = try FileManager.default.attributesOfItem(atPath: file1.path)
        let attrs2 = try FileManager.default.attributesOfItem(atPath: file2.path)
        XCTAssertEqual(attrs1[.protectionKey] as? FileProtectionType, .complete)
        XCTAssertEqual(attrs2[.protectionKey] as? FileProtectionType, .complete)
    }
    
    func testExcludeFromBackupMarksAllURLs() throws {
        let file = tempDir.appendingPathComponent("c.db")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        
        try IOSFileProtection.excludeFromBackup(in: tempDir)
        
        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(values.isExcludedFromBackup == true)
    }
}
```

- [ ] **Step 2: Implementar el helper**

```swift
// app/ios/Runner/Security/IOSFileProtection.swift
import Foundation

enum IOSFileProtection {
    static func applyComplete(in directory: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            try? fm.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        }
    }
    
    static func excludeFromBackup(in directory: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isExcludedFromBackupKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }
    
    static func applyAll() {
        let fm = FileManager.default
        let dirs = [
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
        for dir in dirs {
            try? applyComplete(in: dir)
            try? excludeFromBackup(in: dir)
        }
    }
}
```

- [ ] **Step 3: Compilar y correr tests iOS**

```bash
cd app/ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:RunnerTests/IOSFileProtectionTests
```

Resultado esperado: 2/2 PASS. En simulador la protección puede no aplicar;
skip con `XCTSkip` si el environment no soporta `FileProtectionType.complete`.

- [ ] **Step 4: Llamar al helper desde HearthBitMeshPlugin**

En `applicationDidFinishLaunching` (o equivalente en el plugin), tras
la inicialización existente, llamar `IOSFileProtection.applyAll()`.
También tras el `case "panicWipe"`.

```swift
// En HearthBitMeshPlugin.swift, después de la inicialización existente:
IOSFileProtection.applyAll()
```

Y al final del `case "panicWipe"` (antes del `emit(wipedState)`):

```swift
IOSFileProtection.applyAll()
```

- [ ] **Step 5: Verificar compilación**

```bash
cd app/ios
xcodebuild build -workspace Runner.xcworkspace -scheme Runner
```

- [ ] **Step 6: Commit**

```bash
git add app/ios/Runner/Security/IOSFileProtection.swift
git add app/ios/RunnerTests/IOSFileProtectionTests.swift
git add app/ios/Runner/HearthBitMeshPlugin.swift
git commit -m "feat(ios): NSFileProtection Complete + iCloud backup exclusion (panic wipe spec)"
```

---

## Task 3: Audit wipe Android (Hueco 4)

**Files:**
- Create: `app/android/app/src/test/kotlin/com/hearthbit/app/mesh/PanicWipeTest.kt`
- Modify: `app/android/app/src/main/kotlin/com/hearthbit/app/mesh/MeshEngine.kt` (extender `panicWipe` para limpiar stores nativos adicionales)

**Interfaces:**
- Test: instrumenta `MeshSecurityStore`, `KeystoreSecureStore`, `MeshIdentity` con fakes; llama `panicWipe`; verifica que cada store quedó vacío.
- Producción: `MeshEngine.panicWipe()` debe llamar a `wipe()` en cada store nativo.

- [ ] **Step 1: Inventario de stores Android**

```powershell
Select-String -Path app/android/app/src/main -Pattern "EncryptedSharedPreferences|getSharedPreferences|KeyStore|getFilesDir|getCacheDir" -Recurse
```

Resultado: lista de cada store persistente.

- [ ] **Step 2: Test TDD — instrumentar stores**

```kotlin
// app/android/app/src/test/kotlin/com/hearthbit/app/mesh/PanicWipeTest.kt
package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Test

class PanicWipeTest {
    @Test
    fun `panicWipe clears all native stores`() {
        val securityStore = FakeMeshSecurityStore().apply {
            write("k1", "v1"); write("k2", "v2")
        }
        val keystore = FakeKeystore().apply { putAlias("anchor-admin") }
        val identity = FakeMeshIdentity().apply { markPersisted() }
        val engine = TestMeshEngine(securityStore, keystore, identity)
        
        engine.panicWipe()
        
        assertEquals(0, securityStore.size())
        assertEquals(0, keystore.size())
        assertEquals(false, identity.isPersisted())
    }
}
```

(Los `Fake*` son doubles locales en el mismo archivo de test; no
introducir un framework de mocking solo para este test.)

- [ ] **Step 3: Implementar la instrumentación**

Si `MeshEngine.panicWipe()` no llama a cada store, añadir las llamadas.
Si un store no tiene método `wipe()` o `clear()`, añadirlo.

- [ ] **Step 4: Correr test Android**

```bash
cd app/android
./gradlew :app:testDebugUnitTest --tests "com.hearthbit.app.mesh.PanicWipeTest"
```

- [ ] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/com/hearthbit/app/mesh/MeshEngine.kt
git add app/android/app/src/test/kotlin/com/hearthbit/app/mesh/PanicWipeTest.kt
git commit -m "feat(android): panic wipe clears all native stores"
```

---

## Task 4: Audit wipe iOS (Hueco 5)

**Files:**
- Modify: `app/ios/Runner/HearthBitMeshPlugin.swift` (extender el `case "panicWipe"`)
- Tests: añadidos a `app/ios/RunnerTests/PanicWipeTests.swift` (crear en Task 7)

**Interfaces:**
- El handler debe borrar:
  - `UserDefaults.standard` (claves no manejadas por Dart).
  - Keychain completo (`SecItemDelete` con clases
    `kSecClassGenericPassword`, `kSecClassInternetPassword`,
    `kSecClassCertificate`).
  - `FileManager.default.removeItem` para Application Support, Documents, Caches, tmp.
  - `URLCache.shared.removeAllCachedResponses()`.

- [ ] **Step 1: Inventario iOS**

```powershell
Select-String -Path app/ios/Runner -Pattern "UserDefaults|SecItemAdd|SecItemDelete|FileManager|URLCache" -Recurse
```

- [ ] **Step 2: Extender el handler panicWipe**

```swift
// En HearthBitMeshPlugin.swift, dentro de case "panicWipe":
// (antes del emit(wipedState))

// Keychain
let secClasses: [CFString] = [
    kSecClassGenericPassword,
    kSecClassInternetPassword,
    kSecClassCertificate,
]
for cls in secClasses {
    SecItemDelete([kSecClass: cls] as CFDictionary)
}

// UserDefaults
if let bundleId = Bundle.main.bundleIdentifier {
    UserDefaults.standard.removePersistentDomain(forName: bundleId)
}

// Files
let fm = FileManager.default
let dirs = [
    fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
    fm.urls(for: .documentDirectory, in: .userDomainMask).first,
    fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
].compactMap { $0 }
for dir in dirs {
    try? fm.removeItem(at: dir)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
}
try? fm.removeItem(at: fm.temporaryDirectory)

// URL cache
URLCache.shared.removeAllCachedResponses()
```

- [ ] **Step 3: Compilar**

```bash
cd app/ios
xcodebuild build -workspace Runner.xcworkspace -scheme Runner
```

- [ ] **Step 4: Commit**

```bash
git add app/ios/Runner/HearthBitMeshPlugin.swift
git commit -m "feat(ios): panic wipe clears Keychain, UserDefaults, files, URL cache"
```

---

## Task 5: Atomicidad + idempotencia (Huecos 6+7)

**Files:**
- Modify: `app/lib/screens/home_screen.dart` (documentar el orden canónico)
- Modify: `app/lib/services/secure_database.dart` (idempotency en `destroy()`)
- Modify: `app/lib/services/privacy_data_eraser.dart` (idempotency en `clearResidualFiles()`)
- Modify: `app/lib/services/app_preferences.dart` (idempotency en `panicWipe()`)
- Modify: `app/test/secure_database_test.dart` (test idempotency)
- Modify: `app/test/app_preferences_drill_test.dart` (test panicWipe + idempotency)

- [ ] **Step 1: Documentar el orden en home_screen.dart**

Justo encima de la cadena de wipes en `home_screen.dart:1153-1164`,
añadir comentario:

```dart
// Orden canónico del panic wipe (ver
// docs/superpowers/specs/2026-08-24-panic-wipe-sqlite-cipher-design.md,
// sección "Hueco 6"):
// 1. sub-wipes por dominio (transfers, family, rescue, gateway, lan, controller)
// 2. logs (diagnostics)
// 3. archivos residuales (PrivacyDataEraser)
// 4. clave maestra (SecureDatabaseKeyStore) — al final para que
//    cualquier crash durante los pasos 1-3 deje los datos cifrados
//    con la clave aún existente, recuperables en el siguiente intento.
// 5. preferencias (app_preferences) — borra los flags de UI.
```

- [ ] **Step 2: Test idempotency en `secure_database_test.dart`**

```dart
test('destroy is idempotent', () async {
  final dbPath = p.join(testDir, 'idem.db');
  // abrir y cerrar una vez
  await SecureDatabase.open(databasePath: dbPath, version: 1, onCreate: (_, __) async {});
  await SecureDatabase.destroy(databasePath: dbPath);
  // segundo destroy: no debe lanzar
  await SecureDatabase.destroy(databasePath: dbPath);
  // base inexistente: no debe lanzar
  await SecureDatabase.destroy(databasePath: p.join(testDir, 'nope.db'));
});
```

- [ ] **Step 3: Test idempotency en `app_preferences_drill_test.dart`**

```dart
test('panicWipe is idempotent', () async {
  final prefs = await AppPreferences.create(...);
  await prefs.panicWipe();
  await prefs.panicWipe(); // no debe lanzar
});
```

- [ ] **Step 4: Si SecureDatabase.destroy no es idempotente, hacerlo idempotente**

El método actual ya usa `await sqlcipher.deleteDatabase(...)` que es
no-op si el archivo no existe. Pero verificar que el manejo de WAL/SHM
también lo es.

- [ ] **Step 5: Si app_preferences.panicWipe no es idempotente, hacerlo idempotente**

`_preferences.remove(...)` ya es idempotente (no-op si la key no existe).
Pero verificar el `Future.wait([...])`.

- [ ] **Step 6: Correr tests Dart**

```bash
cd app
flutter test test/secure_database_test.dart test/app_preferences_drill_test.dart
```

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/home_screen.dart
git add app/lib/services/secure_database.dart
git add app/lib/services/privacy_data_eraser.dart
git add app/lib/services/app_preferences.dart
git add app/test/secure_database_test.dart
git add app/test/app_preferences_drill_test.dart
git commit -m "test: panic wipe atomicity + idempotency"
```

---

## Task 6: Re-arranque post-wipe (Hueco 8)

**Files:**
- Create: `app/test/panic_wipe_post_relaunch_test.dart`
- Modify: bootstrap/router si es necesario (verificar primero)

- [ ] **Step 1: Verificar el comportamiento actual de bootstrap**

Buscar el código de inicialización de la app (probablemente
`main.dart` o un widget raíz). ¿Qué pasa si
`SecureDatabaseKeyStore.readOrCreate()` genera una clave nueva?

- [ ] **Step 2: Si el routing no distingue, añadir check**

Si el router enruta a `/home` por defecto, añadir:

```dart
// En el bootstrap, antes de decidir ruta inicial:
final hasKey = await SecureDatabaseKeyStore.exists();
initialRoute = hasKey ? '/home' : '/onboarding';
```

(Ajustar al patrón real del proyecto; puede ser un `GoRouter` redirect,
un `Navigator.initialRoute`, etc.)

- [ ] **Step 3: Test integration**

```dart
// app/test/panic_wipe_post_relaunch_test.dart
testWidgets('post-wipe relaunch routes to onboarding', (tester) async {
  // Setup: app with data
  await tester.pumpWidget(MyApp());
  await tester.pumpAndSettle();
  // Wipe
  await panicWipeAll();
  // Relaunch (recreate the app)
  await tester.pumpWidget(MyApp());
  await tester.pumpAndSettle();
  // Verify
  expect(find.text('onboarding_title'), findsOneWidget);
});
```

- [ ] **Step 4: Correr test**

```bash
cd app
flutter test test/panic_wipe_post_relaunch_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add app/test/panic_wipe_post_relaunch_test.dart
git add [cualquier archivo de bootstrap modificado]
git commit -m "fix: post-wipe relaunch routes to onboarding"
```

---

## Task 7: Tests iOS PanicWipeTests.swift (Hueco 8)

**Files:**
- Create: `app/ios/RunnerTests/PanicWipeTests.swift`

- [ ] **Step 1: Crear archivo de tests con 4 tests**

```swift
import XCTest
@testable import Runner

final class PanicWipeTests: XCTestCase {
    func testKeychainCleared() throws {
        // Setup: insertar 3 items de Keychain
        for i in 0..<3 {
            let q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "test-\(i)",
                kSecValueData as String: "v\(i)".data(using: .utf8)!,
            ]
            SecItemAdd(q as CFDictionary, nil)
        }
        // Action: invocar panic wipe (vía MethodChannel mock o helper interno)
        // ...
        // Assert: SecItemCopyMatching devuelve errSecItemNotFound para cada cuenta
    }
    
    func testFilesRemoved() throws { ... }
    func testIdempotent() throws { ... }
    func testOrderingKeychainBeforeFiles() throws { ... }
}
```

(Estructura exacta depende de cómo se pueda testear el handler
MethodChannel; ajustar a los helpers disponibles.)

- [ ] **Step 2: Correr tests iOS**

```bash
cd app/ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:RunnerTests/PanicWipeTests
```

- [ ] **Step 3: Commit**

```bash
git add app/ios/RunnerTests/PanicWipeTests.swift
git commit -m "test(ios): PanicWipeTests covering Keychain, files, idempotency, ordering"
```

---

## Task 8: Tests Dart nuevos (privacy_data_eraser)

**Files:**
- Create: `app/lib/services/privacy_data_eraser_test.dart`

- [ ] **Step 1: Test del clearResidualFiles**

```dart
// app/lib/services/privacy_data_eraser_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthbit/services/privacy_data_eraser.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ... mocks para path_provider

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.createTempSync('hb_test').path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProvider();
  
  test('clearResidualFiles removes only known prefixes', () async {
    final tempDir = Directory.systemTemp.createTempSync('hb_test_eraser');
    final kept = File('${tempDir.path}/hearthbit_voice_a.aac')..writeAsStringSync('x');
    final alsoKept = File('${tempDir.path}/random.txt')..writeAsStringSync('x');
    
    await PrivacyDataEraser.clearResidualFiles();
    
    expect(kept.existsSync(), isFalse);
    expect(alsoKept.existsSync(), isTrue); // no match
    tempDir.deleteSync(recursive: true);
  });
}
```

- [ ] **Step 2: Correr test**

```bash
cd app
flutter test test/services/privacy_data_eraser_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/privacy_data_eraser_test.dart
git commit -m "test: PrivacyDataEraser.clearResidualFiles covers prefix filter"
```

---

## Task 9: i18n strings consistency

**Files:**
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_es.arb`,
  `app/lib/l10n/app_de.arb`, `app/lib/l10n/app_fr.arb`,
  `app/lib/l10n/app_zh.arb`, `app/lib/l10n/app_ja.arb`
- Run: `flutter gen-l10n`

- [ ] **Step 1: Buscar strings de "panic" / "wipe" en los ARB**

```powershell
Select-String -Path app/lib/l10n/app_en.arb -Pattern "wipe|panic|erase" -CaseSensitive:$false
```

- [ ] **Step 2: Decidir si renombrar o mantener**

El spec dice "mantener consistencia" — los strings actuales pueden
ser "Wipe data" / "Borrar datos" / etc. Decisión:
- Si los strings son claros → dejar como están.
- Si hay inconsistencias (p. ej. "wipe" en un idioma, "delete" en otro) → unificar.
- Política del proyecto: EN/ES completas, DE/FR/ZH/JA heredan fallback (Phase 1 decisión confirmada).

- [ ] **Step 3: Aplicar cambios si los hay**

- [ ] **Step 4: Regenerar localizaciones**

```bash
cd app
flutter gen-l10n
```

- [ ] **Step 5: Commit (si hubo cambios)**

```bash
git add app/lib/l10n
git commit -m "i18n: align panic wipe / data wipe strings across locales"
```

---

## Task 10: Security re-audit + CI verification

**Files:**
- Create: `docs/superpowers/plans/2026-08-24-panic-wipe-security-review.md` (audit findings)

- [ ] **Step 1: Re-correr security checks**

```powershell
git ls-files | Select-String -Pattern "private_key|BEGIN PRIVATE" -CaseSensitive:$false
git log --all -p -S "BEGIN PRIVATE KEY" --diff-filter=A --name-only
```

Resultado esperado: 0 matches.

- [ ] **Step 2: Verificar logs nativos**

```powershell
Select-String -Path app/lib app/android/app/src/main -Pattern "Log\.[dvwie]\(.*(peerId|peerAddress|macAddress)" -Recurse
```

Cualquier hit nuevo → revisar y parchear si filtra PII.

- [ ] **Step 3: Correr CI gates localmente**

```bash
cd app
flutter analyze
flutter test
```

```bash
cd app/android
./gradlew :app:testDebugUnitTest
```

```bash
cd app/ios
xcodebuild test -workspace Runner.xcworkspace -scheme Runner
```

Resultado esperado: todo verde.

- [ ] **Step 4: Escribir security review MD**

`docs/superpowers/plans/2026-08-24-panic-wipe-security-review.md` con:
- Comandos ejecutados + output.
- Verdict: PASS / FAIL.

- [ ] **Step 5: Commit (si hubo fixes de seguridad)**

Solo si se parchó algo.

---

## Task 11: Final whole-branch review + handoff

**Files:** ninguno (es review + handoff).

- [ ] **Step 1: Generar review package para el diff completo**

```bash
bash scripts/sdd-workspace docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-plan.md
bash scripts/review-package docs/superpowers/plans/2026-08-24-panic-wipe-sqlite-cipher-plan.md <BASE> <HEAD>
```

Donde BASE = `b273d96` (HEAD al arrancar este plan) y HEAD = commit final.

- [ ] **Step 2: Dispatch final code-reviewer**

Subagent `worker` con el path del diff, el brief, y los 8 huecos como
checklist. Modelo: el más capaz disponible (per writing-plans guidance).

- [ ] **Step 3: Si hay findings, dispatch ONE fix subagent + scoped re-review**

Por el global constraint de "ONE fix dispatch, one scoped re-review, adjudicate residuals".

- [ ] **Step 4: Hand off al usuario**

Mensaje al usuario con:
- Resumen de los commits de la fase (cuántos, qué cubren).
- Comando `git push` listo (no ejecutado).
- Comando de merge + tag (no ejecutado, usuario decide).
- Recordatorio: hardware validation gates anteriores siguen aplicando si los cambios afectan la app móvil.

- [ ] **Step 5: Cleanup workspace**

```bash
# Bloqueado por safety policy; documentar al usuario.
# rm -rf C:\src\emergency-com\.superpowers\sdd\2026-08-24-panic-wipe-sqlite-cipher
```

---

## Criterios de salida de la fase 2.1

- [ ] Los 8 huecos cerrados (tasks 1-7).
- [ ] i18n consistente (task 9).
- [ ] Security re-audit verde (task 10).
- [ ] CI local verde: `flutter analyze`, `flutter test`, `./gradlew :app:testDebugUnitTest`, `xcodebuild test`.
- [ ] Final whole-branch review sin findings bloqueantes.
- [ ] Push, merge y tag ejecutados por el usuario (gated).

Cuando estos 6 ítems estén en verde, fase 2.1 cerrada. Sigue 2.2
(manifiestos firmados ópticos), 2.3 (gateway LAN), 2.4 (Matrix/MQTT).
