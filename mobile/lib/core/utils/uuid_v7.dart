import 'dart:math';

final class const UuidV7() {
  static final Random _random = Random.secure();
  static int _lastMs = -1;
  static int _lastCounter = 0;

  String next() => generate();

  static String generate() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final int timestampMs;
    if (nowMs > _lastMs) {
      _lastMs = nowMs;
      _lastCounter = _random.nextInt(0x1000);
      timestampMs = nowMs;
    } else {
      _lastCounter++;
      if (_lastCounter > 0xFFF) {
        _lastMs++;
        _lastCounter = 0;
      }
      timestampMs = _lastMs;
    }

    final timeHex = timestampMs.toRadixString(16).padLeft(12, '0');
    final timeHigh = timeHex.substring(0, 8);
    final timeMid = timeHex.substring(8, 12);

    final verAndRand = (0x7000 | (_lastCounter & 0x0FFF))
        .toRadixString(16)
        .padLeft(4, '0');

    final randB = _random.nextInt(0x4000);
    final varAndRand = (0x8000 | randB).toRadixString(16).padLeft(4, '0');

    final randNode1 = _random
        .nextInt(0x10000)
        .toRadixString(16)
        .padLeft(4, '0');
    final randNode2 = _random
        .nextInt(0x10000)
        .toRadixString(16)
        .padLeft(4, '0');
    final randNode3 = _random
        .nextInt(0x10000)
        .toRadixString(16)
        .padLeft(4, '0');

    return '$timeHigh-$timeMid-$verAndRand-$varAndRand-$randNode1$randNode2$randNode3';
  }
}
