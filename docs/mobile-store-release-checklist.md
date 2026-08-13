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
- [ ] Revisar la política de privacidad y declarar con precisión Bluetooth,
  ubicación, dispositivos cercanos, notificaciones, cámara, micrófono, red
  local y almacenamiento según la plataforma.
- [ ] Confirmar que ningún flujo instala aplicaciones automáticamente.

## Google Play

- [ ] Crear un Android App Bundle de release firmado con la clave de carga.
- [ ] Configurar Play App Signing y documentar por separado la clave de carga,
  la firma de Play y la firma usada para APK distribuidos fuera de Play.
- [ ] Completar Data safety, política de privacidad, clasificación de contenido
  y justificación de permisos sensibles y de segundo plano.
- [ ] Probar en un track interno la instalación generada por Play, incluidos sus
  split APKs, en las arquitecturas y densidades admitidas.
- [ ] Verificar que HearthBit detecta una instalación split y no comparte solo
  `base.apk`, porque no sería un instalador completo.

## Apple App Store

- [ ] Crear un archive de release con el identificador, certificados y perfiles
  de distribución correctos.
- [ ] Completar App Privacy, textos de uso de permisos, capacidades Bluetooth y
  red local, y política de privacidad.
- [ ] Validar en TestFlight el comportamiento en primer plano y segundo plano,
  incluidos los límites reales de iOS.
- [ ] Confirmar que la opción de compartir APK no aparece en iOS y que el método
  nativo responde como no soportado si se invoca.

## F-Droid

- [ ] Confirmar que el proyecto y todas las dependencias cumplen los criterios
  de software libre y documentar cualquier antifeature aplicable.
- [ ] Preparar metadatos, licencia, changelog y receta de compilación
  reproducible sin descargar binarios no verificables durante el build.
- [ ] Producir o documentar un APK universal completo para distribución directa;
  no presentar un `base.apk` extraído de una instalación split como universal.
- [ ] Verificar la estrategia de firma y actualización de F-Droid frente a otros
  canales. Informar claramente cuando las firmas entre canales sean distintas.
- [ ] Probar el APK universal sin servicios de Google y con los transportes
  locales disponibles en ese entorno.
