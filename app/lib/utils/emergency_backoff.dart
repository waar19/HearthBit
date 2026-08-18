import 'dart:math';

Duration emergencyRetryBackoff({
  required int attempts,
  required Duration maximumBackoff,
}) {
  final exponent = min(max(attempts - 1, 0), 5);
  final seconds = min(15 * (1 << exponent), maximumBackoff.inSeconds);
  return Duration(seconds: seconds);
}
