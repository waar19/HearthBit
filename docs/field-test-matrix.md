# Matriz de pruebas de campo

Esta matriz valida el camino crítico de HearthBit con teléfonos reales. Cada
ejecución debe registrar fecha, versión, modelos, versiones de sistema,
porcentaje de batería inicial/final, entorno y resultado.

La secuencia ejecutable de los gates P0 prioritarios está en la
[guía de ejecución P0](p0-execution-guide.md).

## Criterios comunes

- Repetir cada escenario cinco veces después de reiniciar ambas aplicaciones.
- Probar primero a 0,5 m y después a 10 m con línea de vista.
- Registrar mediana y peor tiempo, no solo el mejor resultado.
- Un resultado es correcto únicamente si el receptor valida la firma y muestra
  el contenido íntegro.
- Anotar permisos rechazados, cambios de Wi-Fi/Bluetooth y si la pantalla estaba
  encendida, bloqueada o la aplicación terminada.

## Descubrimiento y recuperación BLE

| Escenario | Equipos mínimos | Criterio de éxito |
| --- | --- | --- |
| Android a iOS en primer plano | Galaxy S25 e iPhone 11 | Descubrimiento mutuo en menos de 10 s en 4 de 5 intentos |
| Reconexión tras apagar Bluetooth | Galaxy S25 e iPhone 11 | Recuperación en menos de 20 s, sin tormenta de conexiones |
| iOS con pantalla bloqueada | Galaxy S25 e iPhone 11 | Android detecta el anuncio de overflow y documenta la latencia |
| Android de gama baja | Android con 3–4 GB RAM y uno de referencia | Descubrimiento y recepción sin cierre del proceso |

## SOS y malla

| Escenario | Preparación | Criterio de éxito |
| --- | --- | --- |
| SOS directo | Dos teléfonos sin internet | Recepción autenticada y ACK visible |
| SOS de dos saltos | A y C fuera de alcance; B como relé | C recibe una sola copia válida y conserva al emisor original |
| Store-and-forward | Receptor ausente al emitir | Entrega al reaparecer dentro de la vigencia |
| Congestión | Mensajes normales mientras se emite SOS | El SOS se prioriza y no queda bloqueado |
| Reinicio durante rescate | Reiniciar el relé intermedio | La malla se recupera sin duplicados persistentes |

## Segundo plano y energía

| Plataforma | Estado | Duración | Criterio de éxito |
| --- | --- | --- | --- |
| Android | Malla activa, pantalla bloqueada | 8 h | Sigue recibiendo SOS; registrar consumo |
| Android | Doze y ahorro de batería | 2 h | Recupera el enlace y recibe el siguiente SOS |
| iOS | Malla activa, pantalla bloqueada | 2 h | Registrar límite real de descubrimiento y recepción |
| iOS | Aplicación terminada por el sistema | 30 min | Confirmar y comunicar la degradación esperada |

## Transportes de archivos

Probar un archivo pequeño (100 KiB), uno mediano (10 MiB) y el máximo permitido.
Verificar hash y nombre después de cada recepción.

| Transporte | Combinación | Casos adicionales |
| --- | --- | --- |
| BLE inline | Android–iOS | Interrumpir y reintentar |
| LAN | Android–Android y Android–iOS | Cambiar de red durante el envío |
| Wi-Fi Direct | Android–Android | Compartir grupo con el canal SOS |
| Wi-Fi Aware | Android compatible–Android compatible | Desactivar disponibilidad durante el envío |
| MultipeerConnectivity | iOS–iOS | Bloquear una pantalla durante el envío |
| HBTX por hoja de compartir | Android e iOS | Importar antes y después de aceptar la sesión |
| HBTS sellado | Android–iOS | Destinatario correcto, incorrecto y paquete alterado |
| QR | Android–iOS | Luz baja y fragmento repetido |

## Resultado de una ejecución

Copiar este bloque por ejecución:

```text
Fecha y versión:
Equipos y sistemas:
Escenario:
Resultados de los cinco intentos:
Mediana / peor tiempo:
Batería inicial / final:
Canales reportados:
Errores o permisos:
Diagnóstico exportado:
Conclusión: APROBADO / FALLIDO
```
