import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum TlsTrustMode { system, tofu, pinned }

/// Verifica certificados por CA del sistema, TOFU o huella SHA-256 fija.
///
/// En TOFU/pinning se usa un contexto sin raíces para garantizar que Dart
/// invoque la validación para todos los certificados, incluso los de una CA
/// pública. La huella compara el DER completo y vincula efectivamente la sesión.
class TlsPeerVerifier {
  TlsPeerVerifier({
    required this.mode,
    String? configuredFingerprint,
    String? storedFingerprint,
  }) : configuredFingerprint = normalizeFingerprint(configuredFingerprint),
       storedFingerprint = normalizeFingerprint(storedFingerprint);

  final TlsTrustMode mode;
  final String? configuredFingerprint;
  final String? storedFingerprint;
  String? _observedFingerprint;

  String? get observedFingerprint => _observedFingerprint;

  SecurityContext createSecurityContext() =>
      SecurityContext(withTrustedRoots: mode == TlsTrustMode.system);

  bool verifyCertificate(X509Certificate certificate) =>
      verifyDer(certificate.der);

  @visibleForTesting
  bool verifyDer(Uint8List der) {
    if (mode == TlsTrustMode.system) return false;
    final actual = fingerprintDer(der);
    final expected = mode == TlsTrustMode.pinned
        ? configuredFingerprint
        : storedFingerprint ?? _observedFingerprint;
    if (expected == null && mode == TlsTrustMode.tofu) {
      _observedFingerprint = actual;
      return true;
    }
    return expected != null && _constantTimeEquals(actual, expected);
  }

  static String fingerprintDer(List<int> der) => sha256
      .convert(der)
      .bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  static String? normalizeFingerprint(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');
    return normalized.length == 64 ? normalized : null;
  }

  static bool isValidFingerprint(String? value) =>
      normalizeFingerprint(value) != null;

  static bool _constantTimeEquals(String first, String second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
    }
    return difference == 0;
  }
}
