# Localización / Localization

HearthBit está disponible en seis idiomas: inglés (`en`, plantilla), español
(`es`), alemán (`de`), francés (`fr`), chino simplificado (`zh`) y japonés
(`ja`). La app sigue el idioma del sistema y cae a inglés cuando el idioma no
está soportado.

Las cadenas visibles viven en cuatro capas; para añadir o corregir un idioma
hay que tocar las cuatro:

## 1. UI Flutter (la mayoría de las cadenas)

- Archivos ARB en `app/lib/l10n/app_<código>.arb`. La plantilla con las
  descripciones (`@clave`) es `app_en.arb`.
- `app/l10n.yaml` configura `flutter gen-l10n`; el código generado queda en
  `app/lib/l10n/generated/` (no se edita a mano).
- En widgets se accede con `context.l10n.clave`; fuera del árbol de widgets
  (controladores, servicios) con `currentL10n` de `app/lib/l10n/l10n.dart`.

Para añadir un idioma nuevo: copiar `app_en.arb` a `app_<código>.arb`,
traducir los valores (sin tocar las claves ni los placeholders `{asi}`) y
ejecutar `flutter gen-l10n`. `AppLocalizations.supportedLocales` se actualiza
solo.

## 2. Android nativo (notificación del servicio y errores BLE)

- Recursos en `app/android/app/src/main/res/values/strings.xml` (inglés,
  base) y `values-es/`, `values-de/`, `values-fr/`, `values-zh/`,
  `values-ja/`.
- Los usan `MeshEngine`, `MeshForegroundService`, `MainActivity`,
  `NearbyTransport` y `WifiAwareTransport` vía `context.getString(...)`.

Para un idioma nuevo: crear `values-<código>/strings.xml` con las mismas
claves. Android resuelve el idioma automáticamente.

## 3. iOS nativo (errores del plugin de malla)

- No hay archivos `.lproj`: agregar archivos al proyecto exige editar
  `project.pbxproj` desde Xcode. En su lugar, `HearthBitL10n` (al final de
  `app/ios/Runner/HearthBitMeshPlugin.swift`) contiene una tabla en código
  con los seis idiomas y elige según `Locale.preferredLanguages`.
- Los textos de permisos de `Info.plist` están en español e inglés en una
  sola cadena. Para localizarlos por idioma hace falta crear
  `InfoPlist.strings` por cada `.lproj` **desde Xcode** (pendiente; requiere
  macOS).

Para un idioma nuevo: añadir el código a `supported` y una entrada a `table`
en `HearthBitL10n`.

## 4. Cadenas internas (no traducibles)

Los mensajes de diagnóstico de protocolo (p. ej. `"Repeated Noise nonce"`,
`"TLV ... exceeds 65535 bytes"`, errores de socket LAN) están en inglés a
propósito: son para desarrolladores y llegan al usuario solo como detalle
dentro de un error ya localizado.

## Convenciones

- El apodo por defecto es `SOS-XXXX` en todas las plataformas: neutro y
  comprensible en cualquier idioma.
- Los términos técnicos con nombre propio (Noise, BLE, Wi-Fi Aware, Nearby
  Connections, SHA-256) no se traducen.
- Mantener las traducciones de las cuatro capas coherentes entre sí; la
  fuente de verdad del tono y el vocabulario es `app_en.arb`.

---

# English summary

HearthBit ships in English (template), Spanish, German, French, Simplified
Chinese and Japanese. Strings live in four layers:

1. **Flutter UI**: ARB files in `app/lib/l10n/`, generated via
   `flutter gen-l10n`, accessed with `context.l10n` (widgets) or
   `currentL10n` (controllers/services).
2. **Android native**: `strings.xml` per locale, used by the foreground
   service notification and BLE/transport errors.
3. **iOS native**: in-code `HearthBitL10n` table at the end of
   `HearthBitMeshPlugin.swift` (adding `.lproj` files requires Xcode).
   `Info.plist` permission texts are bilingual ES/EN; per-language
   `InfoPlist.strings` is pending and needs macOS/Xcode.
4. **Internal diagnostics** stay in English by design; they only surface as
   detail inside an already-localized error message.

To add a language: copy `app_en.arb`, translate it, run `flutter gen-l10n`,
add a `values-<code>/strings.xml` on Android, and extend `HearthBitL10n` on
iOS.
