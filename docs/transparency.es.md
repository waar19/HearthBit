# Transparencia y privacidad de HearthBit

Consulta los términos formales dirigidos a usuarios en la
[Política de Privacidad de HearthBit](https://waar19.github.io/HearthBit/privacy-policy.es)
([English](https://waar19.github.io/HearthBit/privacy-policy)).

HearthBit publica su implementación para que cualquier persona pueda verificar
qué hace la aplicación durante una emergencia. La visibilidad del código es un
mecanismo de privacidad y rendición de cuentas; no convierte el proyecto en
open source aprobado por la OSI. El modelo legal se explica en
[`NOTICE.md`](../NOTICE.md).

## Modelo de datos

La comunicación local por malla no requiere una cuenta central. La identidad y
las claves criptográficas se generan en el dispositivo. Los mensajes, la
bandeja de salida, las transferencias y la configuración familiar confiable
pueden guardarse localmente para seguir funcionando sin internet.

La app principal no necesita analítica. Aun así, puede acceder a la red cuando
el usuario carga mapas, habilita gateways MQTT/Matrix/LAN, abre enlaces externos
o usa transportes de terceros como Google Play Services Nearby. Esos servicios
tienen operadores, registros, políticas de privacidad y licencias propios.

## Qué pueden observar los dispositivos cercanos

BLE necesita anuncios e identificadores de radio descubribles. Un observador
cercano puede inferir que existe un dispositivo compatible, medir intensidad y
correlacionar horarios. HearthBit reduce exposición innecesaria, pero no puede
ofrecer anonimato por radio.

Los mensajes públicos no son confidenciales: están destinados a participantes
del canal y se firman para detectar alteraciones. Los mensajes privados usan
sesiones Noise XX autenticadas, pero la presencia de radio, el horario y parte
de los metadatos de enrutamiento pueden seguir siendo observables.

## Ubicación y radar de rescate

La ubicación se comparte cuando el usuario ejecuta una acción que la necesita,
como SOS, modo rescate o consentimiento temporal del radar. El sistema operativo
puede conservar registros de permisos y accesos independientemente de
HearthBit.

- GPS entrega posición y precisión estimada, no dirección fiable en interiores.
- BLE RSSI estima proximidad y tendencia; paredes, cuerpos y reflejos lo alteran.
- El barrido BLE infiere un sector amplio y vence a los 90 segundos o tras 15 m.
- Android Ranging depende de Android 16 y del hardware de ambos dispositivos.
- El sonar graba ventanas PCM cortas en memoria y emite chirridos de alta
  frecuencia. No guarda esas capturas intencionalmente como notas de voz, pero
  personas, animales u otros micrófonos cercanos pueden percibirlas.

Los controles de medición son dirigidos y firmados por identidad. Esto detecta
modificaciones, pero no oculta todos los metadatos de radio. Las mediciones son
ayudas, no evidencia certificada de ubicación.

## Archivos, voz y almacenamiento local

Las ofertas de archivos están firmadas y el contenido aceptado se verifica. Los
archivos y notas de voz recibidos permanecen en el dispositivo hasta que el
usuario o el sistema los elimine.

Las bases y cachés locales permiten trabajar sin conexión. El protocolo no
protege contra un dispositivo comprometido, copias de seguridad desbloqueadas,
capturas de pantalla ni archivos exportados. El borrado de pánico elimina el
estado controlado por HearthBit, pero no garantiza borrar backups, historial de
notificaciones ni copias en otro dispositivo.

## Gateways opcionales

MQTT, Matrix y LAN trasladan mensajes fuera de la malla BLE local. Al activarlos
cambia el límite de confianza: operadores y servidores pueden procesar
identificadores, contenido y marcas de tiempo. Los administradores deben
informarlo y proteger credenciales, registros y acceso al servidor.

## Segundo plano y batería

Android usa un servicio en primer plano y una notificación visible persistente
mientras la malla está activa. iOS controla el BLE en segundo plano y no permite
garantizar su continuidad. Los perfiles de energía reducen escaneo y GPS, lo
que puede retrasar el descubrimiento. El modo supervivencia intercambia alcance
por autonomía de forma explícita.

## Límites de seguridad

HearthBit busca ofrecer identidades autenticadas, sesiones privadas, protección
contra repetición y controles de emergencia firmados. No garantiza entrega,
resistencia a interferencias, anonimato, protección de un dispositivo
comprometido, identidad civil a partir de un apodo ni operación médica o de
seguridad pública certificada.

Los reportes de vulnerabilidades no deben publicar identificadores, ubicaciones,
grabaciones ni mensajes reales de emergencia.

## Verificación y licencias

Las especificaciones, vectores y guías de validación están en `docs/` y
`tests/`. Los cambios nativos de iOS deben compilarse y probarse también en
macOS. Las afirmaciones dependientes de hardware permanecen pendientes hasta
superar la matriz física.

El código propio está disponible bajo PolyForm Noncommercial 1.0.0 y puede
licenciarse comercialmente por separado. Las versiones ya publicadas bajo MIT
siguen bajo MIT; terceros y submódulos conservan sus términos. Consulta
[`LICENSE`](../LICENSE), [`NOTICE.md`](../NOTICE.md) y
[`COMMERCIAL-LICENSE.md`](../COMMERCIAL-LICENSE.md).
