# Guía para agentes de IA

Este repositorio contiene HearthBit, una aplicación de comunicación de emergencia sin internet. Su UI es Flutter, mientras que la radio, la criptografía de plataforma y varios transportes viven en Kotlin (Android) y Swift (iOS). El proyecto también incluye un relay Linux en Python, un núcleo Rust experimental, vectores de conformidad y dos submódulos.

Esta guía es el punto de entrada para trabajar con ayuda de IA. Para contexto de producto y de funcionalidades, empiece por [`docs/ai/README.md`](docs/ai/README.md).

## Mapa rápido

- `app/lib/`: UI, controladores, modelos, persistencia y protocolos Dart.
- `app/android/`: radio BLE, malla, transportes y adaptadores nativos Android.
- `app/ios/Runner/`: equivalente nativo iOS.
- `relay/`: relay Linux/Raspberry Pi en Python; no descifra tráfico privado.
- `core/hearthbit-core/`: biblioteca Rust del frame; todavía no está conectada al runtime móvil.
- `tests/conformance/`: vectores binarios compartidos y su adaptador para firmware.
- `firmware/anchor-node/` y `vendor/bitchat-android/`: submódulos con sus propias reglas y licencias. No los trate como código copiado al repositorio principal.

## Reglas que no se negocian

- No debilite firmas Ed25519, Noise, verificación de identidad, límites de tamaño, rate limits, deduplicación, permisos ni cifrado para “hacer que funcione”. Ante una entrada inválida, falle de forma cerrada.
- Use sólo datos sintéticos. No ponga mensajes reales, ubicaciones, IDs de dispositivos, logs sin sanear, claves, tokens ni credenciales en código, pruebas, documentación o reportes.
- No presente una simulación, un emulador o una prueba unitaria como evidencia de radio, segundo plano, SOS o alcance físico. Si no se ejecutó con el hardware requerido, indique `PENDING`, `BLOCKED` o la limitación concreta.
- No edite manualmente `app/lib/l10n/generated/`; cambie los archivos ARB y regenere las localizaciones según [`docs/localization.md`](docs/localization.md).
- Manténgase en la rama activa. No cree un worktree ni cambie de rama salvo instrucción explícita de la persona usuaria.

## Flujo de trabajo para una solicitud de producto

1. Lea [`docs/ai/PRODUCT_CONTEXT.md`](docs/ai/PRODUCT_CONTEXT.md) y localice el flujo en [`docs/ai/WORKFLOWS.md`](docs/ai/WORKFLOWS.md).
2. Use [`docs/ai/FEATURE_MAP.md`](docs/ai/FEATURE_MAP.md) para encontrar las capas y archivos probables. Lea la especificación enlazada antes de tocar protocolo, seguridad, transferencias, SOS o firmware.
3. Haga el cambio más pequeño que cumpla el criterio de aceptación. Mantenga los contratos Dart↔nativo compatibles y no invente campos o códigos de paquete.
4. Añada o actualice las pruebas más cercanas al comportamiento modificado. Los cambios de protocolo deben considerar los fixtures de conformidad y todos los consumidores afectados.
5. Ejecute la validación proporcional y comunique exactamente qué pasó, qué no se pudo ejecutar y por qué. Consulte [`docs/ai/KNOWN_GAPS.md`](docs/ai/KNOWN_GAPS.md) para no confundir límites conocidos con regresiones nuevas.

## Validación rápida

Para documentación solamente, ejecute `git diff --check`.

Para cambios Flutter, desde `app/`:

```powershell
flutter analyze
flutter test
```

Para Android nativo, desde `app/android/`:

```powershell
.\gradlew.bat :app:testDebugUnitTest
```

Para el relay, desde `relay/` tras instalar las dependencias de prueba:

```powershell
python -m pytest
```

Para Rust, use comprobaciones que no reescriban archivos:

```powershell
cargo fmt --check --manifest-path core/hearthbit-core/Cargo.toml
cargo clippy --locked --manifest-path core/hearthbit-core/Cargo.toml --all-targets -- -D warnings
cargo test --locked --manifest-path core/hearthbit-core/Cargo.toml
```

La matriz binaria compartida está en [`tests/conformance/README.md`](tests/conformance/README.md). iOS requiere macOS; las validaciones BLE, SOS, batería, radar y firmware requieren el hardware y los gates definidos en [`docs/field-test.md`](docs/field-test.md).

## Fuentes de verdad

- Producto y solicitudes para IA: [`docs/ai/`](docs/ai/README.md).
- Arquitectura y límites: [`docs/architecture.md`](docs/architecture.md) y [`docs/threat-model.md`](docs/threat-model.md).
- Paquetes e interoperabilidad: [`docs/protocol.md`](docs/protocol.md), [`docs/bitchat-core-profile.md`](docs/bitchat-core-profile.md) y [`docs/extension-registry.md`](docs/extension-registry.md).
- Transferencias: [`docs/transfer-protocol.md`](docs/transfer-protocol.md).
- Decisiones vigentes que no deben reinterpretarse: [`docs/ai/DECISIONS.md`](docs/ai/DECISIONS.md).

Los planes y auditorías fechados en `docs/superpowers/` son contexto histórico. No los trate como una orden activa si contradicen una especificación, este archivo o una solicitud actual.
