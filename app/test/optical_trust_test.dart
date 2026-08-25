import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/optical_protocol.dart';
import 'package:hearth_bit/services/optical_trust.dart';

/// Cubre los huecos del spec Hueco 2 para `classifyOpticalTrust` y la
/// sensibilidad del [OpticalProtocol.signingPayload] ante modificaciones.
void main() {
  OpticalHeader validSignedHeader({
    String senderPeerId = '0011223344556677',
  }) {
    return OpticalHeader(
      transferId: Uint8List.fromList(List.generate(16, (i) => i * 7)),
      seed: 0x12345678,
      fileSize: 1024,
      chunkSize: 256,
      chunkCount: 4,
      sha256: Uint8List.fromList(List.generate(32, (i) => i * 3)),
      fileName: 'reporte.pdf',
      senderPeerId: senderPeerId,
      protocolVersion: OpticalProtocol.version,
      signature: Uint8List.fromList(List.generate(64, (i) => i * 5)),
    );
  }

  // Escenario 2: peer conocido + firma válida → verified.
  test('v2 firmado por peer conocido con firma válida devuelve verified', () async {
    final header = validSignedHeader();
    final classification = await classifyOpticalTrust(
      header: header,
      isPeerKnown: (_) => true,
      verifySignature: (_, _, _) async => true,
    );
    expect(classification, isNotNull);
    expect(classification!.trust, OpticalTrust.verified);
    expect(classification.requiresUserConfirmation, isFalse);
  });

  // Escenario 1: peer conocido + firma inválida → null (descartar header).
  test('v2 con firma inválida por peer conocido devuelve null', () async {
    final header = validSignedHeader();
    final classification = await classifyOpticalTrust(
      header: header,
      isPeerKnown: (_) => true,
      verifySignature: (_, _, _) async => false,
    );
    expect(classification, isNull);
  });

  // Escenario 1 (variante): excepción del verificador se trata como inválida.
  test('v2 con firma que lanza excepción se trata como inválida', () async {
    final header = validSignedHeader();
    final classification = await classifyOpticalTrust(
      header: header,
      isPeerKnown: (_) => true,
      verifySignature: (_, _, _) async {
        throw StateError('crypto backend down');
      },
    );
    expect(classification, isNull);
  });

  // Escenario 3: peer desconocido → unverified, requiere confirmación.
  test('v2 firmado por peer desconocido devuelve unverified + confirmación', () async {
    final header = validSignedHeader(senderPeerId: 'aabbccddeeff');
    final classification = await classifyOpticalTrust(
      header: header,
      isPeerKnown: (_) => false,
      verifySignature: (_, _, _) async {
        throw StateError('no debe invocarse si el peer es desconocido');
      },
    );
    expect(classification, isNotNull);
    expect(classification!.trust, OpticalTrust.unverified);
    expect(classification.requiresUserConfirmation, isTrue);
  });

  // Escenario 4: v1 (legacy) nunca autentica, ni siquiera si el peer es conocido.
  test('v1 legacy devuelve legacy con confirmación obligatoria', () async {
    final header = OpticalHeader(
      transferId: Uint8List.fromList(List.generate(16, (i) => i * 7)),
      seed: 0x12345678,
      fileSize: 1024,
      chunkSize: 256,
      chunkCount: 4,
      sha256: Uint8List.fromList(List.generate(32, (i) => i * 3)),
      fileName: 'reporte.pdf',
      protocolVersion: OpticalProtocol.legacyVersion,
    );
    final classification = await classifyOpticalTrust(
      header: header,
      isPeerKnown: (_) => true,
      verifySignature: (_, _, _) async {
        throw StateError('legacy nunca debe invocar al verificador');
      },
    );
    expect(classification, isNotNull);
    expect(classification!.trust, OpticalTrust.legacy);
    expect(classification.requiresUserConfirmation, isTrue);
  });

  // Escenario 6: modificar un byte del signingPayload cambia el digest,
  // por lo que la verificación Ed25519 falla aunque la firma siga presente.
  test(
      'modificar un byte del signingPayload provoca fallo de verificación Ed25519',
      () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    final original = validSignedHeader();
    final originalPayload = OpticalProtocol.signingPayload(original);
    final signature = await algorithm.sign(originalPayload, keyPair: keyPair);
    final signed = OpticalHeader(
      transferId: original.transferId,
      seed: original.seed,
      fileSize: original.fileSize,
      chunkSize: original.chunkSize,
      chunkCount: original.chunkCount,
      sha256: original.sha256,
      fileName: original.fileName,
      senderPeerId: original.senderPeerId,
      protocolVersion: original.protocolVersion,
      signature: Uint8List.fromList(signature.bytes),
    );
    final encoded = base64Decode(OpticalProtocol.encodeHeader(signed));

    // El primer byte del nombre 'reporte.pdf' vive en:
    // magic(4) + type(1) + transferId(16) + seed(4) + fileSize(8)
    // + chunkSize(2) + chunkCount(4) + sha256(32) + nameLen(1) = 72
    final firstNameByteOffset = 4 + 1 + 16 + 4 + 8 + 2 + 4 + 32 + 1;
    expect(String.fromCharCode(encoded[firstNameByteOffset]), 'r');
    final tampered = Uint8List.fromList(encoded)
      ..[firstNameByteOffset] = 'Z'.codeUnitAt(0);
    final decoded = OpticalProtocol.decode(base64Encode(tampered));
    expect(decoded, isA<OpticalHeader>());
    final tamperedHeader = decoded! as OpticalHeader;

    final tamperedPayload = OpticalProtocol.signingPayload(tamperedHeader);
    expect(tamperedPayload, isNot(equals(originalPayload)));

    // Verificación sobre el payload original: pasa.
    final okSignature = await algorithm.verify(
      originalPayload,
      signature: Signature(signed.signature!, publicKey: publicKey),
    );
    expect(okSignature, isTrue);

    // Verificación sobre el payload mutado: falla.
    final badSignature = await algorithm.verify(
      tamperedPayload,
      signature: Signature(signed.signature!, publicKey: publicKey),
    );
    expect(badSignature, isFalse);

    // classifyOpticalTrust con peer conocido y firma inválida → null.
    final classification = await classifyOpticalTrust(
      header: tamperedHeader,
      isPeerKnown: (_) => true,
      verifySignature: (_, data, sig) async {
        return algorithm.verify(data,
            signature: Signature(sig, publicKey: publicKey));
      },
    );
    expect(classification, isNull);
  });
}
