# Flujos de producto y criterios de aceptación

Estas descripciones sirven para convertir una idea de vibecoding en una tarea con límites observables. Consulte [`FEATURE_MAP.md`](FEATURE_MAP.md) para encontrar las capas de cada flujo.

## 1. Entrar a la malla

**Historia:** como persona usuaria, quiero entender qué permisos faltan y el estado de la malla antes de depender de ella.

**Debe ocurrir:** la UI explica permisos y estado sin exponer identificadores sensibles; Android e iOS conservan sus diferencias; un peer autenticado se distingue de una presencia genérica.

**No asumir:** que Bluetooth habilitado significa que la malla está lista, que un emulador valida BLE o que todos los permisos se conceden de una vez.

## 2. Conversar y reenviar mensajes

**Historia:** como persona cercana, quiero enviar mensajes públicos o privados y saber si una conversación privada está disponible.

**Debe ocurrir:** los mensajes públicos van firmados; los privados usan una sesión Noise autenticada; TTL, deduplicación y rol conservan las reglas de relay; la UI no presenta una entrega como confirmada sin evidencia.

**Antes de cambiarlo:** lea `docs/protocol.md`, el perfil BitChat y la threat model. Si cambia bytes, firma, extensión o compatibilidad, añada o actualice fixtures de conformidad.

## 3. Activar y seguir un SOS

**Historia:** como persona en emergencia, quiero iniciar un SOS y conocer sus limitaciones operativas. Como rescatista, quiero ver una confirmación real y usar herramientas de aproximación con consentimiento.

**Debe ocurrir:** el SOS se firma, sigue la política de expiración/reintentos, indica sus portadoras y diferencia estado local de `EMERGENCY_ACK`. Rescate, ubicación, batería y segundo plano se presentan con límites claros.

**Criterio adicional:** cualquier cambio en este flujo debe identificar el gate relevante de `docs/field-test.md`. Si no hubo dispositivos físicos, el reporte debe marcarlo pendiente en vez de afirmar éxito.

## 4. Transferir un archivo

**Historia:** como persona usuaria, quiero ofrecer o recibir un archivo sin internet, conservando autenticación, privacidad e integridad aunque cambie la portadora.

**Debe ocurrir:** la oferta va dentro de la sesión apropiada, el contenido se cifra, el hash final se verifica y el selector puede pasar a la siguiente portadora. El modo óptico no autentica por sí mismo una fuente no verificada; la interfaz comunica ese estado.

**No cambiar silenciosamente:** límites de tamaño, política de prioridad ante SOS, tipos HBT, semántica de aceptación o el orden de fallback. El contrato está en [`../transfer-protocol.md`](../transfer-protocol.md).

## 5. Usar radar, ranging o sonar

**Historia:** como rescatista, quiero una guía de proximidad útil sin que la app prometa una distancia, dirección o seguridad que el hardware no puede demostrar.

**Debe ocurrir:** se obtiene consentimiento donde aplica, se muestran señales como estimaciones y se degradan de forma explícita cuando falta RSSI, GPS, brújula, UWB o condiciones acústicas.

**Criterio adicional:** una mejora visual no valida precisión física. Mantenga la validación de campo y las advertencias de `docs/radar-ranging-validation.md`.

## 6. Proteger o borrar información local

**Historia:** como persona usuaria, quiero que mis mensajes, archivos, llaves y configuración sensible estén protegidos y que el borrado de pánico no deje restos recuperables por las capas conocidas.

**Debe ocurrir:** cada almacenamiento nuevo entra al inventario y política de protección; los errores no registran secretos; el borrado cubre las rutas y claves correspondientes en Flutter y en la plataforma afectada.

**Antes de cambiarlo:** lea la threat model y los tests de borrado de pánico. Una migración de datos o almacenamiento requiere pruebas de creación, actualización, reinicio y borrado.

## 7. Operar infraestructura opcional

**Historia:** como operador, quiero usar un relay, gateway o ancla sin ampliar silenciosamente la exposición de datos ni las capacidades de forwarding.

**Debe ocurrir:** los bridges y el gateway se habilitan de forma explícita, las claves viven fuera del repositorio, las políticas de confianza se conservan y el relay no descifra tráfico privado.

**No asumir:** que una prueba Python valida BlueZ, una placa ESP32 o una red real. Use los documentos de despliegue y las matrices físicas pertinentes.
