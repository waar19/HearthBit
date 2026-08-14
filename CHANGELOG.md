# Historial de cambios

Los cambios se documentan para que auditorías, pruebas de campo y publicaciones
puedan relacionarse con una versión concreta. Una función implementada no se
considera validada para emergencias reales hasta superar los gates físicos
indicados en `docs/field-test.md`.

## [Sin publicar]

### Añadido

- Entrega persistente de SOS y check-ins con reintentos, expiración y
  confirmaciones opcionales entre nodos HearthBit.
- Continuidad nativa del modo rescate y cola privada recuperable.
- Manifiestos firmados para transferencia óptica, advertencia de origen no
  verificado y lectura explícita del formato anterior.
- Gateway LAN voluntario, autenticado y cifrado para relays Raspberry Pi.
- Diagnósticos locales acotados de batería, BLE, GPS, mapas, colas y sonar.

### Mejorado

- Consumo de batería y memoria en radar, escaneo BLE, mapas y sonar.
- Accesibilidad del SOS, simulacro, estados de entrega y texto al 200 %.
- Gateways Matrix/MQTT con TLS obligatorio, confirmación del servidor, cola
  cifrada y reintento progresivo.

### Seguridad

- Borrado de pánico integral, bases SQLite cifradas y backups sensibles
  desactivados.
- Logs nativos con identificadores desactivados en builds de producción.
- CI con pruebas Swift, Android, Flutter, relay, conformidad, SBOM y escaneo de
  dependencias.

[Sin publicar]: https://github.com/waar19/HearthBit/compare/v1.0.0...HEAD
