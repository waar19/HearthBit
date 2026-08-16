import 'package:flutter/foundation.dart';

class NoopListenable implements Listenable {
  const NoopListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
