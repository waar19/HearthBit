import 'dart:math';
import 'dart:typed_data';

Uint8List randomBytes(Random random, int length) =>
    Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexToBytes(String hex) {
  final output = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < output.length; i++) {
    output[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return output;
}
