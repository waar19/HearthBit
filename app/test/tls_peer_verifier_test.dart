import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/tls_peer_verifier.dart';

void main() {
  final certificate = Uint8List.fromList(List.generate(128, (i) => i));
  final fingerprint = TlsPeerVerifier.fingerprintDer(certificate);

  test('TOFU acepta primero y fija la misma huella durante la sesión', () {
    final verifier = TlsPeerVerifier(mode: TlsTrustMode.tofu);

    expect(verifier.verifyDer(certificate), isTrue);
    expect(verifier.observedFingerprint, fingerprint);
    expect(verifier.verifyDer(Uint8List.fromList([9, 9, 9])), isFalse);
  });

  test('TOFU restaurado rechaza un certificado diferente', () {
    final verifier = TlsPeerVerifier(
      mode: TlsTrustMode.tofu,
      storedFingerprint: fingerprint,
    );

    expect(verifier.verifyDer(certificate), isTrue);
    expect(verifier.verifyDer(Uint8List.fromList([1, 2, 3])), isFalse);
  });

  test('pinning normaliza separadores y compara SHA-256', () {
    final separated = fingerprint
        .replaceAllMapped(RegExp(r'..'), (match) => '${match.group(0)}:')
        .replaceFirst(RegExp(r':$'), '');
    final verifier = TlsPeerVerifier(
      mode: TlsTrustMode.pinned,
      configuredFingerprint: separated,
    );

    expect(verifier.verifyDer(certificate), isTrue);
    expect(verifier.verifyDer(Uint8List.fromList([0])), isFalse);
  });
}
