import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hybrid CO2 Domain Math & Eco-Equivalents Parity Tests', () {
    test('Numerical Example Section 4.4 parity: 6000 steps, 74cm stride', () {
      const steps = 6000;
      const strideCm = 74;

      // Distance calculation
      // D_steps = ROUND(6000 * 74 / 100.0, 2) = 4440.00 m
      final totalStepDistM = (steps * strideCm / 100.0).roundToDouble();
      expect(totalStepDistM, equals(4440.0));

      // Auto-calculated CO2 before GPS allocation:
      // C_auto = ROUND_HALF_UP(4440.00 * 0.80 * 0.08200 * 0.70) = ROUND_HALF_UP(203.8848) = 204 g CO2
      final autoCo2Before = (totalStepDistM * 0.80 * 0.08200 * 0.70).round();
      expect(autoCo2Before, equals(204));

      // Points awarded for day = floor(6000 / 100) = 60
      const points = steps ~/ 100;
      expect(points, equals(60));

      // After allocating 1500m at 0.19805 g/m (Personal car):
      // C_alloc = ROUND_HALF_UP(1500.00 * 0.19805 * 1.00) = ROUND_HALF_UP(297.075) = 297 g
      const allocatedDistM = 1500.0;
      final allocatedCo2 = (allocatedDistM * 0.19805).round();
      expect(allocatedCo2, equals(297));

      // Unallocated distance = 4440 - 1500 = 2940 m
      final unallocatedDistM = totalStepDistM - allocatedDistM;
      expect(unallocatedDistM, equals(2940.0));

      // C_auto remaining = ROUND_HALF_UP(2940.00 * 0.04592) = ROUND_HALF_UP(135.0048) = 135 g
      final remainingAutoCo2 = (unallocatedDistM * 0.04592).round();
      expect(remainingAutoCo2, equals(135));

      // Total CO2 saved = 297 + 135 = 432 g
      final totalCo2New = allocatedCo2 + remainingAutoCo2;
      expect(totalCo2New, equals(432));

      // Net delta = 432 - 204 = +228 g
      expect(totalCo2New - autoCo2Before, equals(228));
    });

    test('Eco-Equivalents Metric formulas Section 5.1 parity', () {
      // For 43200 g CO2 saved
      const gCo2 = 43200;

      // trees_planted = ROUND(G / 20000.0, 2)
      final treesPlanted = (gCo2 / 20000.0 * 100).round() / 100;
      expect(treesPlanted, equals(2.16));

      // car_km_avoided = ROUND(G / 192.0, 1)
      final carKm = (gCo2 / 192.0 * 10).round() / 10;
      expect(carKm, equals(225.0));

      // smartphone_charges = floor(G / 8.22)
      final smartphoneCharges = (gCo2 / 8.22).floor();
      expect(smartphoneCharges, equals(5255));

      // plastic_bottles_recycled = floor(G / 82.80)
      final plasticBottles = (gCo2 / 82.80).floor();
      expect(plasticBottles, equals(521));
    });
  });
}
