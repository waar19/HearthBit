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
