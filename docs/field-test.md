# Prueba de campo

La radio BLE no se valida con emuladores. Use teléfonos físicos y desactive
Wi-Fi y datos móviles durante la prueba.

## Matriz mínima

1. Instale HearthBit en dos Android.
2. Instale BitChat oficial en un tercer Android o iPhone.
3. Con los tres a menos de cinco metros, active la malla y confirme que aparecen
   los nombres cercanos.
4. Envíe mensajes públicos desde cada app y confirme recepción cruzada.
5. Abra un chat privado, espere que el candado indique canal seguro y pruebe en
   ambos sentidos.
6. Aleje el tercer equipo fuera del alcance directo del primero, dejando el
   segundo a mitad de camino; confirme el relé de dos saltos.
7. Apague el destinatario, envíe un mensaje dirigido, vuelva a encenderlo antes
   de 12 horas y confirme el reintento store-and-forward.
8. Inserte un ESP32 Bitle entre dos equipos fuera de alcance directo y repita.

La interoperabilidad HearthBit↔BitChat con hardware real (pasos 2-5) es una
prueba manual obligatoria antes de declarar compatibilidad física; los tests
binarios automatizados no la sustituyen.

## Matriz de transferencia de archivos

Pruebe cada celda con un archivo pequeño (~100 KB) y una foto (~3 MB):

| Transporte | Android↔Android | Android↔iPhone | iPhone↔iPhone |
| ---------- | --------------- | -------------- | ------------- |
| Nearby Connections | ✔ requerido | n/a (iOS pendiente) | n/a |
| LAN / hotspot | ✔ requerido | ✔ requerido | ✔ requerido |
| Wi-Fi Aware | ✔ si ambos API 29+ | n/a | n/a |
| BLE inline (≤ 256 KiB) | ✔ requerido | ✔ requerido | ✔ requerido |
| QR óptico | ✔ requerido | ✔ requerido | ✔ requerido |

Escenarios adversos a cubrir en al menos un transporte:

- Pérdida de frames en el modo QR (tape parcialmente la pantalla): la
  transferencia debe alargarse, nunca corromperse.
- Cancelación a mitad desde ambos extremos; verificar que el estado queda
  `cancelada` en ambos y que los archivos parciales se eliminan.
- Fallo de transporte forzado (apagar Wi-Fi durante LAN): debe caer al
  siguiente transporte sin intervención.
- Aplicación en segundo plano durante la transferencia.
- Batería < 15 % y almacenamiento casi lleno en el receptor.
- SOS enviado durante una transferencia grande: los mensajes deben llegar
  sin demora perceptible.

## Radar de proximidad

Con dos teléfonos y la malla activa:

1. Desde una alerta SOS toque «RASTREAR» (o el icono de radar en Cercanos) y
   confirme que aparecen lecturas en menos de 5 s.
2. Camine acercándose y alejándose en línea recta (10-30 m): la tendencia
   debe cambiar a «te estás acercando» / «la señal se está debilitando» en
   pocos segundos, sin parpadear con usted quieto.
3. Verifique la vibración: más rápida e intensa al acercarse.
4. Apague el Bluetooth del objetivo: en ~5 s debe aparecer «señal perdida».
5. Repita con el teléfono objetivo en un bolsillo o bajo una caja (atenúa la
   señal): las bandas de distancia deben degradarse, nunca congelar la UI.
6. Combinaciones requeridas: Android→Android, Android→iPhone (objetivo iOS en
   primer plano y en segundo plano), iPhone→Android.

## Evidencia a registrar

- Modelos y versiones de Android/iOS.
- Distancia aproximada y obstáculos.
- Hora de envío y recepción.
- Estado foreground/background de cada app.
- Porcentaje de batería antes y después de una hora.

## Prueba automatizada

`MeshProtocolTest` congela la cabecera binaria v1 y la carga de mensajes usada
por BitChat. Ejecútela con:

```powershell
cd app\android
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
.\gradlew.bat :app:testDebugUnitTest
```

Esta prueba detecta cambios incompatibles en bytes, pero no reemplaza la matriz
de tres dispositivos.
