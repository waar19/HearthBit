# Checklist de distribución móvil

Este documento es una lista de preparación. No confirma que HearthBit se haya
publicado en ninguna tienda ni repositorio.

## Requisitos comunes

- [ ] Fijar una versión y un commit de release reproducible.
- [ ] Generar artefactos de release sin credenciales, tokens ni almacenes de
  claves dentro del repositorio o del APK.
- [ ] Firmar cada artefacto de release con la clave correspondiente y verificar
  su certificado y sus sumas SHA-256.
- [ ] Conservar de forma segura las claves y contraseñas fuera de CI; usar
  secretos protegidos si CI solo prepara artefactos sin publicar.
- [ ] Probar instalación limpia y actualización desde la versión anterior con
  la misma firma. Una firma distinta impide actualizar Android.
- [x] Publicar una política de privacidad formal en una URL estable antes del
  envío a tiendas. Está disponible en
  [`waar19.github.io/HearthBit/privacy-policy`](https://waar19.github.io/HearthBit/privacy-policy)
  y declara Bluetooth, ubicación, dispositivos cercanos, notificaciones,
  cámara, micrófono, red local y almacenamiento según la plataforma.
- [ ] Verificar que la licencia declarada en cada tienda coincide con
  [`LICENSE`](../LICENSE) y [`NOTICE.md`](../NOTICE.md); HearthBit es
  source-available (PolyForm Noncommercial 1.0.0), no open source OSI.
- [ ] Confirmar que ningún flujo instala aplicaciones automáticamente.

## Firma Android

El build local y el CI siguen pudiendo compilar sin secretos; si
`app/android/key.properties` no existe, Gradle usa la clave de depuración y
muestra una advertencia. Ese artefacto **no es publicable ni actualizable como
release oficial**.

1. Crear y custodiar un keystore fuera del repositorio, por ejemplo en Windows:

   ```powershell
   keytool -genkeypair -v -keystore C:\secure\hearthbit-upload.jks `
     -alias hearthbit-upload -keyalg RSA -keysize 4096 -validity 10000
   ```

2. Copiar `app/android/key.properties.example` como
   `app/android/key.properties`, usar rutas con `/` y completar sus cuatro
   valores. El archivo real y los formatos `*.jks`/`*.keystore` están ignorados
   por Git.
3. Generar el AAB con `flutter build appbundle --release`.
4. Verificar el certificado antes de subirlo:

   ```powershell
   jarsigner -verify -verbose -certs build\app\outputs\bundle\release\app-release.aab
   ```

   Si la versión instalada anteriormente usó otra firma, Android no permitirá
   actualizarla: será necesaria una desinstalación o conservar la firma previa.

El workflow `.github/workflows/release.yml` exige estos secretos protegidos y
falla de forma explícita si falta cualquiera:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Un tag `v*` ejecuta pruebas, genera AAB y APK universal firmados, SBOM
CycloneDX, `SHA256SUMS.txt` y un GitHub Release. Configure aprobación manual del
environment de publicación y no exponga estos secretos a pull requests de
forks.

El workflow manual `.github/workflows/store-publish.yml` publica únicamente en
canales de prueba. Configure los environments `play-internal` y `testflight`
con aprobación obligatoria antes de guardar sus secretos.

## Google Play

La opción `android` del workflow de tiendas compila con un `versionCode`
derivado de `github.run_number` y usa Fastlane para el track `internal`.
Además de los cuatro secretos de firma anteriores, exige:

- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64`: JSON de una cuenta de servicio con
  acceso limitado a la aplicación en Play Console, codificado en Base64.

La ficha de español latino usada por el pipeline está en
`app/android/fastlane/metadata/android/es-419/`. Las imágenes siguen siendo una
carga manual para que se revisen visualmente antes de publicarlas.

- [ ] Crear un Android App Bundle de release firmado con la clave de carga.
- [ ] Configurar Play App Signing y documentar por separado la clave de carga,
  la firma de Play y la firma usada para APK distribuidos fuera de Play.
- [ ] Completar Data safety, política de privacidad, clasificación de contenido
  y justificación de permisos sensibles y de segundo plano.
- [ ] Probar en un track interno la instalación generada por Play, incluidos sus
  split APKs, en las arquitecturas y densidades admitidas.
- [ ] Verificar que HearthBit detecta una instalación split y no comparte solo
  `base.apk`, porque no sería un instalador completo.
- [ ] Promover el mismo artefacto desde prueba interna a prueba cerrada, sin
  recompilarlo, e invitar el número y duración de testers que Play Console
  exija para el tipo de cuenta vigente.

## Apple App Store

La opción `ios` del workflow compila un archive firmado y lo sube a TestFlight.
El environment `testflight` exige:

- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_BASE64`

La variable opcional `APPLE_TEAM_ID` permite sustituir el Team ID del proyecto.
El certificado, perfil y llavero existen únicamente durante el job y se
eliminan al finalizar.

- [ ] Crear un archive de release con el identificador, certificados y perfiles
  de distribución correctos.
- [ ] Completar App Privacy, textos de uso de permisos, capacidades Bluetooth y
  red local, y política de privacidad.
- [ ] Validar en TestFlight el comportamiento en primer plano y segundo plano,
  incluidos los límites reales de iOS.
- [ ] Confirmar que la opción de compartir APK no aparece en iOS y que el método
  nativo responde como no soportado si se invoca.

## Distribución directa del APK

F-Droid exige licencias de software libre aprobadas; la licencia actual
(PolyForm Noncommercial 1.0.0) **no cumple** sus criterios de inclusión, así
que HearthBit no es elegible para el repositorio oficial de F-Droid mientras
mantenga este modelo. La alternativa es distribución directa (GitHub Releases
y compartir APK dentro de la app):

- [ ] Producir un APK universal completo firmado para distribución directa;
  no presentar un `base.apk` extraído de una instalación split como universal.
- [ ] Publicar sumas SHA-256 y la firma esperada junto al APK para que los
  usuarios puedan verificarlo.
- [ ] Verificar la estrategia de firma y actualización frente a otros canales.
  Informar claramente cuando las firmas entre canales sean distintas.
- [ ] Probar el APK universal sin servicios de Google y con los transportes
  locales disponibles en ese entorno.
- [ ] Si en el futuro se desea F-Droid, evaluar primero un cambio de licencia o
  un repositorio F-Droid propio (self-hosted), que sí admite estas licencias.
