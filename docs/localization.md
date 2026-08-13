# Localización / Localization

HearthBit está disponible en seis idiomas: inglés (`en`, plantilla), español
(`es`), alemán (`de`), francés (`fr`), chino simplificado (`zh` en Flutter y
Android, `zh-Hans` en el bundle iOS) y japonés
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

- `HearthBitL10n` (al final de
  `app/ios/Runner/HearthBitMeshPlugin.swift`) contiene una tabla en código con
  los seis idiomas para los errores del plugin y elige según
  `Locale.preferredLanguages`.
- Los siete textos de permisos se localizan mediante
  `Runner/{en,es,de,fr,zh-Hans,ja}.lproj/InfoPlist.strings`. Xcode los muestra
  como un único variant group `InfoPlist.strings`, incluido en `Runner > Build
  Phases > Copy Bundle Resources`. `Runner/Info.plist` conserva inglés como
  fallback.
- `CFBundleLocalizations` y `knownRegions` usan `zh-Hans`, que es el
  identificador correcto del bundle para chino simplificado. La tabla Swift
  usa `zh` porque normaliza `Locale.languageCode` al idioma base.

Para un idioma nuevo: añadir el código a `supported` y una entrada a `table`
en `HearthBitL10n`; crear el `.lproj/InfoPlist.strings`, añadirlo al variant
group y actualizar `CFBundleLocalizations` y `knownRegions`.

### Validación de permisos en Xcode

1. Abra `app/ios/Runner.xcworkspace`, seleccione el proyecto `Runner` y
   compruebe que `InfoPlist.strings` tiene las seis localizaciones y pertenece
   al target `Runner`.
2. En `Product > Scheme > Edit Scheme > Run > Options`, establezca
   `Application Language` en cada idioma o en `System Language`. También puede
   cambiar el idioma del iPhone en `Ajustes > General > Idioma y región`.
3. Desinstale la app antes de cada variante (o restablezca sus permisos) para
   que iOS vuelva a mostrar los avisos. Active por separado Bluetooth, cámara,
   ubicación al usar la app, ubicación siempre, micrófono y red local.
4. Confirme que cada aviso usa únicamente el idioma elegido. Para un idioma no
   soportado, confirme el fallback monolingüe en inglés. Esta revisión requiere
   Xcode/iOS y no se considera ejecutada desde Windows.

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
3. **iOS native**: the in-code `HearthBitL10n` table localizes plugin errors.
   Permission prompts use the `InfoPlist.strings` variant group in
   `en`, `es`, `de`, `fr`, `zh-Hans` and `ja`; `Info.plist` retains the English
   fallback. Validate each language with the Xcode scheme or the device system
   language and reset permissions between checks.
4. **Internal diagnostics** stay in English by design; they only surface as
   detail inside an already-localized error message.

To add a language: copy `app_en.arb`, translate it, run `flutter gen-l10n`,
add a `values-<code>/strings.xml` on Android, and extend `HearthBitL10n`,
`InfoPlist.strings`, `CFBundleLocalizations` and Xcode `knownRegions` on iOS.
