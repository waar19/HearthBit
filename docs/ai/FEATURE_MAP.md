# Mapa de funcionalidades

Use este mapa para iniciar una tarea. Los archivos son puntos de entrada, no una lista exhaustiva: siga sus llamadas antes de modificar una interfaz entre Dart y código nativo.

| Flujo de producto | Punto de entrada Flutter | Capas nativas o de apoyo | Fuente de verdad y pruebas |
| --- | --- | --- | --- |
| Onboarding, permisos y estado de malla | `app/lib/screens/onboarding_screen.dart`, `app/lib/main.dart`, `app/lib/controllers/mesh_controller.dart` | `app/android/app/src/main/kotlin/com/hearthbit/app/MainActivity.kt`, `app/ios/Runner/HearthBitMeshPlugin.swift` | [`../localization.md`](../localization.md), `app/test/mesh_controller_test.dart` |
| Chat público, chat privado y peers | `app/lib/screens/home_screen.dart`, `app/lib/controllers/mesh_controller.dart`, `app/lib/services/mesh_platform_service.dart` | `MeshEngine.kt`, `HearthBitMeshPlugin.swift`, `IOSMeshSecurity.swift` | [`../protocol.md`](../protocol.md), [`../bitchat-core-profile.md`](../bitchat-core-profile.md), pruebas Dart y nativas de malla |
| SOS, rescate, casos y roster | `app/lib/screens/emergency_screen.dart`, `app/lib/screens/rescue_operations_screen.dart`, `app/lib/controllers/rescue_case_controller.dart` | `MeshEngine.kt`, `MeshForegroundService.kt`, `HearthBitMeshPlugin.swift` | [`../field-test.md`](../field-test.md), [`../threat-model.md`](../threat-model.md), pruebas de emergencia y rescate |
| Radar, ranging y sonar | `app/lib/screens/radar_screen.dart`, `app/lib/services/radar_fusion.dart`, `app/lib/services/acoustic_sonar.dart` | `RadioRangingManager.kt`, `RadarConsentProtocol.kt`, `IOSMeshPolicies.swift` | [`../radar-ranging-validation.md`](../radar-ranging-validation.md), [`../protocol.md`](../protocol.md) |
| Archivos, HBT, QR óptico y voz | `app/lib/controllers/transfer_controller.dart`, `app/lib/screens/transfers_tab.dart`, `app/lib/screens/optical_*_screen.dart` | `app/android/app/src/main/kotlin/com/hearthbit/app/transfer/`, `HearthBitTransferProtocol.swift`, `HearthBitMultipeerFileTransport.swift` | [`../transfer-protocol.md`](../transfer-protocol.md), pruebas `transfer_*`, `optical_*` y `hbt_*` |
| Privacidad, borrado de pánico y almacenamiento | `app/lib/services/privacy_data_eraser.dart`, `app/lib/services/secure_database.dart`, `app/lib/services/at_rest_file_cipher.dart` | `MeshEnginePanicWipe.kt`, `Security/IOSPanicWipe.swift`, `Security/IOSFileProtection.swift` | [`../threat-model.md`](../threat-model.md), diseño de privacidad, pruebas `panic_wipe_*` y `secure_database_test.dart` |
| Familias, contactos de confianza y anuncios de autoridad | `family_screen.dart`, `authority_announcements_screen.dart`, sus controladores y modelos | almacenamiento/plataforma de malla cuando aplica | `app/test/family_*`, `app/test/authority_announcement_*`, documentos de privacidad |
| Gateway LAN y relay Linux | `app/lib/services/lan_mesh_gateway.dart`, `lan_gateway_controller.dart` | `relay/src/hearthbit_relay/` | [`../lan-mesh-gateway.md`](../lan-mesh-gateway.md), [`../../relay/README.md`](../../relay/README.md), `relay/tests/` |
| Anclas y OTA | `anchor_admin_screen.dart`, `anchor_admin_models.dart`, `anchor_ota_manifest.dart` | `AnchorAdminProtocol.kt`, `AnchorOtaProtocol.kt`, submódulo `firmware/anchor-node/` | [`../anchor-admin-protocol.md`](../anchor-admin-protocol.md), [`../anchor-deployment-guide.md`](../anchor-deployment-guide.md) |
| Protocolo y conformidad binaria | codecs Dart/nativos que consume el flujo | `relay`, `core/hearthbit-core`, firmware y submódulo BitChat | [`../../tests/conformance/README.md`](../../tests/conformance/README.md), perfil BitChat y registro de extensiones |
| Idiomas y texto visible | `app/lib/l10n/app_*.arb` | Android `strings.xml`; iOS `InfoPlist.strings` y `HearthBitL10n` | [`../localization.md`](../localization.md) |

## Regla para cambios transversales

Si una solicitud toca más de una fila, enumere esas filas en el plan antes de editar. Ejemplos: un nuevo estado de transferencia puede requerir UI Flutter, eventos nativos, localización, protocolo, pruebas y documentación; una nueva capacidad de paquete puede requerir fixtures y los clientes que los consumen.
