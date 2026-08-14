import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SensitiveScreen extends StatefulWidget {
  const SensitiveScreen({required this.child, super.key});

  final Widget child;

  @override
  State<SensitiveScreen> createState() => _SensitiveScreenState();
}

class _SensitiveScreenState extends State<SensitiveScreen> {
  @override
  void initState() {
    super.initState();
    SensitiveScreenGuard.acquire();
  }

  @override
  void dispose() {
    SensitiveScreenGuard.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SensitiveScreenGuard {
  SensitiveScreenGuard._();

  static const _methods = MethodChannel('com.hearthbit.mesh/methods');
  static int _holders = 0;

  static void acquire() {
    _holders += 1;
    if (_holders == 1) _setEnabled(true);
  }

  static void release() {
    _holders = (_holders - 1).clamp(0, 1 << 30);
    if (_holders == 0) _setEnabled(false);
  }

  static Future<void> _setEnabled(bool enabled) async {
    try {
      await _methods.invokeMethod<void>('setSecureScreen', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Widget tests and unsupported platforms.
    } on PlatformException {
      // Privacy hardening must not block emergency UI rendering.
    }
  }
}
