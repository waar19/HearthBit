import 'dart:typed_data';

import 'optical_protocol.dart';

/// Resultado de evaluar la firma de un [OpticalHeader] óptico contra el
/// estado local (peer conocido, clave pública, etc.).
enum OpticalTrust { verified, unverified, legacy }

/// Clasificación de confianza para un [OpticalHeader] recibido por QR.
///
/// `requiresUserConfirmation` indica que el caller debe mostrar el diálogo de
/// `_confirmUnverified` antes de aceptar el header. `trust` es el valor final
/// (después de la confirmación del usuario) o, en el caso de v2 firmado por
/// peer conocido, el valor verificado criptográficamente.
class TrustClassification {
  const TrustClassification({
    required this.trust,
    required this.requiresUserConfirmation,
  });

  final OpticalTrust trust;
  final bool requiresUserConfirmation;
}

/// Clasifica un [OpticalHeader] óptico en uno de los tres valores de
/// [OpticalTrust] y decide si el usuario debe confirmarlo manualmente.
///
/// Devuelve `null` si la firma v2 no verifica contra la clave pública del
/// peer (escenario: firma inválida). En ese caso el caller debe mostrar
/// `opticalSignatureInvalid` y descartar el header.
///
/// Esta función es pura desde el punto de vista de side-effects: delega la
/// consulta de "peer conocido" y la verificación Ed25519 en callbacks
/// inyectados. Se extrae de [OpticalReceiveScreen] para ser directamente
/// testeable.
Future<TrustClassification?> classifyOpticalTrust({
  required OpticalHeader header,
  required bool Function(String peerId) isPeerKnown,
  required Future<bool> Function(
    String peerId,
    Uint8List data,
    Uint8List signature,
  ) verifySignature,
}) async {
  // v1 (legacy) nunca autentica: siempre pide confirmación.
  if (header.isLegacy) {
    return const TrustClassification(
      trust: OpticalTrust.legacy,
      requiresUserConfirmation: true,
    );
  }
  // v2 con firma. Si el peer es conocido, intentamos verificar criptográficamente.
  final hasPeer = header.senderPeerId.isNotEmpty &&
      isPeerKnown(header.senderPeerId);
  if (hasPeer) {
    var verified = false;
    try {
      verified = await verifySignature(
        header.senderPeerId,
        OpticalProtocol.signingPayload(header),
        header.signature!,
      );
    } catch (_) {
      verified = false;
    }
    if (!verified) return null;
    return const TrustClassification(
      trust: OpticalTrust.verified,
      requiresUserConfirmation: false,
    );
  }
  // v2 firmado por peer desconocido: warning + fingerprint, sin aceptación
  // silenciosa.
  return const TrustClassification(
    trust: OpticalTrust.unverified,
    requiresUserConfirmation: true,
  );
}
