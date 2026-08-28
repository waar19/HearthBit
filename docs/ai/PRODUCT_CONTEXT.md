# Contexto de producto

## Qué es HearthBit

HearthBit es una aplicación móvil para comunicación de emergencia cuando no hay internet. Los teléfonos forman una malla Bluetooth Low Energy (BLE), retransmiten mensajes cercanos y pueden apoyarse en nodos ancla o relays. También permite SOS, radar de proximidad y transferencia de archivos mediante varias portadoras.

La utilidad central no es “tener muchas funciones”, sino que una persona pueda mantener comunicación local, comprender el estado de entrega y actuar con información honesta cuando las redes normales no están disponibles.

## Para quién y en qué momento

- **Personas cercanas sin conectividad:** necesitan descubrir la malla, enviar mensajes y distinguir entre envío local y confirmación remota.
- **Personas en una emergencia:** necesitan iniciar un SOS, conocer permisos, batería y restricciones del sistema, sin falsas garantías de entrega.
- **Equipos de rescate:** necesitan casos, roster, radar y datos de ubicación con consentimiento y lenguaje de aproximación, no de precisión certificada.
- **Operadores de infraestructura:** pueden desplegar anclas o relays, con límites de privacidad, configuración explícita y operación local.

## Promesas y límites del producto

- La aplicación funciona sin internet para los flujos de malla compatibles; no sustituye canales oficiales de emergencia ni garantiza entrega.
- Un estado de “enviado” o “preparado” no equivale a confirmación. Sólo el `EMERGENCY_ACK` demuestra que otro peer recibió y validó un SOS.
- El radar usa RSSI, GPS, brújula y, donde existe, ranging. Es una estimación para el último tramo; no es un instrumento certificado de rescate.
- Los mensajes privados y los archivos deben conservar sus límites de identidad, cifrado y permisos aunque se añada una nueva interfaz o transporte.
- La radio depende de sistema operativo, fabricante, permisos, batería y hardware. iOS y Android no ofrecen las mismas capacidades.

## Vocabulario que debe mantenerse consistente

- **Peer:** nodo de malla autenticado; no es una observación BLE genérica.
- **Presencia:** observación de bajo riesgo que no habilita chat ni crea una identidad persistente.
- **SOS:** mensaje de emergencia firmado y sujeto a política de reintentos y expiración.
- **ACK:** confirmación verificable de recepción; no se infiere de una UI o de una señal local.
- **Relay:** nodo que reenvía paquetes bajo reglas de TTL, rol y deduplicación.
- **Ancla:** firmware fijo que puede extender cobertura y, según su rol, conservar paquetes dirigidos.
- **Transferencia HBT:** oferta y contenido cifrado que usa una portadora seleccionada; la portadora no reemplaza la autenticación de la transferencia.

## Qué significa “terminado” para una feature

Una feature está terminada cuando el flujo pedido se entiende en la UI, respeta los límites anteriores, tiene validación automatizada proporcional y declara las pruebas físicas o de plataforma que siguen pendientes. No está terminada sólo porque compile o porque se vea bien en un emulador.

Para el detalle técnico, lea [`../architecture.md`](../architecture.md), [`../threat-model.md`](../threat-model.md) y [`../transparency.md`](../transparency.md).
