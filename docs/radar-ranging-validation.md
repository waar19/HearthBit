# Validación del radar y medición de distancia

[English](radar-ranging-validation.en.md) · **Español** ·
[Deutsch](radar-ranging-validation.de.md) ·
[Français](radar-ranging-validation.fr.md) ·
[简体中文](radar-ranging-validation.zh.md) ·
[日本語](radar-ranging-validation.ja.md)

## Alcance y seguridad

HearthBit combina varias fuentes, pero ninguna sustituye el criterio del equipo
de rescate:

- GPS: orientación de largo alcance cuando el error combinado es pequeño.
- BLE RSSI: proximidad y tendencia; no mide una dirección física.
- Barrido BLE: sector experimental que debe repetirse al caminar 15 m o después
  de 90 segundos.
- Android Ranging: distancia por Channel Sounding, Wi-Fi NAN RTT o BLE RSSI en
  Android 16 o posterior, según el hardware de ambos teléfonos.
- Sonar acústico: distancia corta entre Android y iPhone usando tres rondas de
  chirridos y el método de dos vías tipo BeepBeep.

El sonar acústico funciona mejor entre 1 y 25 metros, con ambos teléfonos
descubiertos y sin obstáculos. No debe usarse junto al oído; las frecuencias
altas pueden ser audibles para niños y animales.

## Consentimiento y Modo Rescate

1. Conceder radar desde el botón manual y confirmar una vigencia de 15 minutos.
2. Activar Modo Rescate y comprobar que el primer SOS concede 30 minutos.
3. Esperar al siguiente ping y confirmar que la expiración vuelve a quedar 30
   minutos por delante del nuevo ping, también con Flutter suspendido.
4. Desactivar Modo Rescate antes del siguiente ping nativo y confirmar que no
   vuelve a habilitarse el radar.
5. En el receptor, confirmar que cada SOS renueva la ventana remota durante 30
   minutos y que timestamps cercanos al máximo representable no desbordan.

## Prueba de layout

1. Abrir el radar en una pantalla estrecha.
2. Provocar una calibración deficiente acercando el teléfono a metal.
3. Confirmar que solo aparece un banner y que el círculo no cambia de posición.
4. Alejarlo del metal, moverlo en forma de ocho y comprobar que el banner
   desaparece sin desplazar el radar.
5. Iniciar un barrido y verificar que la guía aparece sobre el círculo.
6. Esperar 90 segundos o caminar más de 15 m y confirmar que pide repetirlo.

## Prueba de Android Ranging

Requiere dos dispositivos con Android 16 o posterior y permiso `RANGING`.

1. Activar la malla y el consentimiento de radar en el objetivo.
2. Abrir el radar desde el segundo teléfono.
3. Pulsar el botón de medición por radio.
4. Verificar que la UI cambia de distancia aproximada a distancia medida,
   mostrando margen de error.
5. Repetir a 1, 3, 5 y 10 m con línea de vista y con una pared.

La tecnología elegida depende de las capacidades reportadas por
`RangingManager`: Bluetooth Channel Sounding, Wi-Fi NAN RTT o BLE RSSI.

## Prueba de sonar acústico Android–iPhone

La app debe estar abierta en ambos teléfonos y el objetivo debe haber concedido
el consentimiento del radar.

1. Conceder permiso de micrófono en ambos teléfonos.
2. Desconectar audífonos Bluetooth y dejar libres altavoz y micrófono.
3. Colocar los teléfonos a 1–3 m, sin cubrirlos.
4. Pulsar el botón de onda acústica.
5. Permanecer quietos durante las tres rondas.
6. Comparar la distancia medida con una cinta métrica.
7. Repetir a 5, 10 y 20 m y en presencia de ruido.

Si no se detectan dos chirridos por ronda, HearthBit descarta la medición en vez
de mostrar una distancia engañosa.

## Notificación persistente Android

1. Activar la malla.
2. Deslizar la notificación fuera de la bandeja en Android 14 o posterior.
3. Confirmar que se publica nuevamente mientras la malla continúa activa.
4. Detener la malla desde la app.
5. Confirmar que la notificación desaparece y no vuelve a publicarse.
