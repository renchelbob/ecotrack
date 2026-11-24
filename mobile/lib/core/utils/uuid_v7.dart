import 'dart:math';

/// Pure Dart RFC 9562 compliant UUIDv7 generator.
/// Format: 48-bit unix timestamp in ms + 4-bit version (7) + 12-bit random + 2-bit variant (10) + 62-bit random.
final class UuidV7 {
  const UuidV7._();

  static final Random _random = Random.secure();

  static String generate() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 48-bit timestamp
    final timeHex = nowMs.toRadixString(16).padLeft(12, '0');
    final timeHigh = timeHex.substring(0, 8);
    final timeMid = timeHex.substring(8, 12);

    // 12-bit random for version field (version 7)
    final randA = _random.nextInt(0xFFF);
    final verAndRand = (0x7000 | randA).toRadixString(16).padLeft(4, '0');

    // Variant 1 (0b10xxxxxx) + 14-bit random
    final randB = _random.nextInt(0x3FFF);
    final varAndRand = (0x8000 | randB).toRadixString(16).padLeft(4, '0');

    // 48-bit random
    final randNode1 = _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    final randNode2 = _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    final randNode3 = _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');

    return '$timeHigh-$timeMid-$verAndRand-$varAndRand-$randNode1$randNode2$randNode3';
  }
}
