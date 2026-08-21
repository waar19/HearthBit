# Riesgo de licencias y procedencia

## Estado verificado de Fase 6

**CRITICAL BUSINESS RISK:** antes de distribución comercial, piloto con
terceros o incorporación de más código, una revisión legal y de procedencia
debe confirmar compatibilidad, obligaciones de distribución, avisos y alcance
de cada licencia.

Este registro no es asesoría legal y no modifica ninguna licencia:

- la raíz usa [PolyForm Noncommercial 1.0.0](../LICENSE);
- el archivo de licencia de `vendor/bitchat-android` contiene
  [GNU GPL v3](../vendor/bitchat-android/LICENSE.md), pero su README afirma
  «public domain»; la contradicción queda abierta para revisión y este registro
  no intenta reinterpretarla;
- `firmware/anchor-node` conserva su [licencia MIT](../firmware/anchor-node/LICENSE);
- [`relay/pyproject.toml`](../relay/pyproject.toml) declara `MIT`, pero
  `relay/` no contiene un archivo `LICENSE` propio;
- el firmware describe `components/noise_ref` como Noise-C vendorizado con
  referencias y licencias por archivo: encabezados de estilo MIT de Southern
  Storm Software y primitivas declaradas de dominio público. En esta fase no
  se copió código de Noise ni se modificó `vendor/`, `components/noise_ref` o
  los textos de licencia.

La verificación no atribuye cobertura de archivos *untracked* a
`git diff --name-only`. Se revisó `git status --short --untracked-files=all`
tanto en la raíz como en el submódulo de firmware; después se inspeccionaron los
manifiestos y lockfiles existentes (`pubspec.yaml`, `pubspec.lock`,
`pyproject.toml`, `Cargo.toml`, `Cargo.lock` e `idf_component.yml`) y los nuevos
archivos `.c`/`.h`. Ningún manifiesto o lockfile está modificado. Los únicos
`.c`/`.h` nuevos son `bitle_metrics.c` y `bitle_metrics.h`, código interno
registrado por `main/CMakeLists.txt` sin añadir una dependencia externa.
**no new third-party dependencies in Phase 6**. Esta conclusión sobre el árbol
de trabajo actual no sustituye un inventario de dependencias, copyrights o
procedencia del contenido ya existente.

## Fuente Noise Java propia de HearthBit para Android

Este registro técnico documenta procedencia e integración; no concluye
compatibilidad jurídica ni sustituye la revisión legal pendiente:

- origen: `https://github.com/rweather/noise-java`;
- commit fijado:
  `49377b6dfc6a1e75740bce2318118291a57c0d6e` (2 de agosto de 2022);
- licencia incorporada: `app/android/noise/LICENSE.txt`, texto MIT con
  copyright `Copyright (C) 2016 Southern Storm Software, Pty Ltd.`;
- SHA-256 de `LICENSE.txt`:
  `712219e049cc901aa00140df9845baf0fa14b2f66f488701b3a4e6cedc903032`;
- SHA-256 reproducible de los 29 `.java` upstream más `LICENSE.txt`:
  `9fba618331d7a6404d18dd92fa3b1068a84490e8f7d1099f572b38337d020ef1`.
  El cálculo concatena, en orden por ruta relativa, ruta UTF-8, byte NUL,
  bytes originales y byte NUL; finalmente concatena `LICENSE.txt`, NUL, sus
  bytes originales y NUL.

Se incorporaron sin omitir clases los 29 archivos de
`src/main/java/com/southernstorm/noise`: en `crypto/`,
`Blake2bMessageDigest`, `Blake2sMessageDigest`, `ChaChaCore`, `Curve25519`,
`Curve448`, `GHASH`, `NewHope`, `NewHopeTor`, `Poly1305`, `RijndaelAES`,
`SHA256MessageDigest`, `SHA512MessageDigest` y `package-info`; en `protocol/`,
`AESGCMFallbackCipherState`, `AESGCMOnCtrCipherState`,
`ChaChaPolyCipherState`, `CipherState`, `CipherStatePair`,
`Curve25519DHState`, `Curve448DHState`, `DHState`, `DHStateHybrid`,
`Destroyable`, `HandshakeState`, `NewHopeDHState`, `Noise`, `Pattern`,
`SymmetricState` y `package-info`.

La única modificación sobre esos archivos upstream es el cambio mecánico de
namespace:

```text
com.southernstorm.noise
com.hearthbit.noise.southernstorm
```

Los avisos originales por archivo se conservaron. Además del texto MIT general,
`NewHope.java` y `NewHopeTor.java` conservan sus avisos de dominio público y
atribuciones; `RijndaelAES.java` conserva la declaración de dominio público de
los autores originales.

Una comparación normalizada verificó cero diferencias entre las 29 fuentes
incorporadas y el commit upstream, ignorando exclusivamente el namespace,
finales de línea y whitespace final. La misma comparación dio cero diferencias
entre ese upstream y las fuentes Southern Storm que compilaba BitChat.

Los `sourceSets` de `app/android/app` y `app/android/relay` apuntan ahora
exclusivamente a `app/android/noise/src/main/java`. El repositorio
`vendor/bitchat-android` permanece como referencia, pero su árbol
`app/src/main/java/com/bitchat/android/noise` no participa como fuente Noise en
los APK Android de HearthBit. Esta afirmación describe el build verificado; no
reinterpreta la licencia ni la procedencia del resto de BitChat.
