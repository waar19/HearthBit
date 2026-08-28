# Decisiones de producto y arquitectura que siguen vigentes

Estas decisiones reducen ambigüedad en tareas de IA. Cambiarlas requiere una solicitud explícita, una especificación proporcional y pruebas que demuestren la compatibilidad o la migración necesarias.

## Seguridad y privacidad

- Las identidades, firmas, sesiones Noise y pins de confianza no se eluden para mejorar UX ni para simplificar una integración. Las entradas malformadas o no autenticadas se rechazan de forma cerrada.
- La presencia BLE genérica no equivale a un peer. No puede habilitar chat, persistencia ni una identidad reutilizable.
- Las ubicaciones, mensajes, archivos, contactos, identificadores y logs son sensibles. Las pruebas y ejemplos usan datos sintéticos y los reportes se sanean.
- Los bridges externos sólo transportan lo que su documentación permite; tráfico privado no se exporta a MQTT, Matrix o Reticulum.

## Interoperabilidad y transporte

- HearthBit conserva el frame BitChat cuando cambia de portadora. TTL, deduplicación y los bytes firmados obedecen la forma canónica definida por el perfil, no una interpretación de la UI.
- Las extensiones se asignan y admiten según el registro. Una extensión nueva no se introduce sólo añadiendo una constante en un cliente.
- Los archivos usan el contrato HBT y verifican cifrado e integridad de extremo a extremo. El orden de fallback de portadoras y la prioridad del SOS son decisiones de protocolo.

## Experiencia de emergencia

- La UI distingue preparación/envío local de confirmación. Sólo un ACK válido prueba recepción del SOS.
- RSSI, GPS, ranging y sonar se presentan como estimaciones y con consentimiento donde corresponde. Nunca se anuncian como instrumentos certificados.
- Los límites de segundo plano y batería del sistema operativo se comunican, no se esconden tras una promesa de disponibilidad continua.

## Mantenibilidad

- Flutter concentra UI, estado y persistencia; la radio queda nativa para respetar capacidades de Android e iOS. Todo contrato entre ambas capas debe cambiar de forma coordinada.
- Todo texto visible cubre inglés, español, alemán, francés, chino simplificado y japonés siguiendo las cinco capas de localización. El código generado no se edita a mano.
- Las pruebas automáticas y las pruebas físicas son señales distintas. Un cambio puede estar verde en CI y seguir pendiente de validación RF.

Las referencias normativas están en [`../threat-model.md`](../threat-model.md), [`../protocol.md`](../protocol.md), [`../extension-registry.md`](../extension-registry.md), [`../transfer-protocol.md`](../transfer-protocol.md) y [`../localization.md`](../localization.md).
