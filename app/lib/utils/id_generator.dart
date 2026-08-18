import 'dart:math';

String newEmergencyLocalId(Random random) {
  final randomPart = List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'EMG-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
}

String newPrivateMessageLocalId(Random random) {
  final randomPart = random.nextInt(0x7fffffff).toRadixString(16);
  return 'dm-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
}
