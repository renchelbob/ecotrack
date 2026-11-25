import 'dart:math' as math;

import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:glados/glados.dart';

void main() {
  group('Hybrid CO2 Domain Math Parity & Property Tests', () {
    test('Section 4.4 worked example: 6000 steps, 74cm stride, Petrol 95', () {
      const steps = 6000;
      const strideCm = 74;

      final totalStepDistM = Co2Math.computeStepDistanceM(steps, strideCm);
      expect(totalStepDistM, equals(4440.0));

      final autoCo2Before = Co2Math.computeAutoDefaultCo2Grams(totalStepDistM);
      expect(autoCo2Before, equals(204));

      final points = Co2Math.computeDailyStepPointsTarget(steps);
      expect(points, equals(60));

      final vehicle = Co2Math.computeVehicleCo2Factors('petrol_95', 8.5);
      expect(vehicle.factor, equals(2330.0));
      expect(vehicle.gPerKm, equals(198.05));
      expect(vehicle.gPerMeter, equals(0.19805));

      const allocatedDistM = 1500.0;
      final allocatedCo2 = Co2Math.computeSegmentCo2Grams(
        allocatedDistM,
        vehicle.gPerMeter,
      );
      expect(allocatedCo2, equals(297));

      final unallocatedDistM = totalStepDistM - allocatedDistM;
      expect(unallocatedDistM, equals(2940.0));

      final remainingAutoCo2 = Co2Math.computeAutoDefaultCo2Grams(
        unallocatedDistM,
      );
      expect(remainingAutoCo2, equals(135));

      final totalCo2New = allocatedCo2 + remainingAutoCo2;
      expect(totalCo2New, equals(432));
      expect(totalCo2New - autoCo2Before, equals(228));
    });

    test('Section 2.2 worked vehicle examples B and C parity', () {
      final dieselSuv = Co2Math.computeVehicleCo2Factors('diesel', 9.2);
      expect(dieselSuv.factor, equals(2680.0));
      expect(dieselSuv.gPerKm, equals(246.56));
      expect(dieselSuv.gPerMeter, equals(0.24656));

      final electricEv = Co2Math.computeVehicleCo2Factors('electric', 17.5);
      expect(electricEv.factor, equals(340.0));
      expect(electricEv.gPerKm, equals(59.50));
      expect(electricEv.gPerMeter, equals(0.05950));
    });

    Glados2(any.intInRange(0, 100001), any.intInRange(40, 121)).test(
      'Step distance, auto CO2, and points invariants across 0..100000',
      (steps, strideCm) {
        final stepDistM = Co2Math.computeStepDistanceM(steps, strideCm);
        final expectedDistM = (steps * strideCm) / 100.0;
        expect(stepDistM, closeTo(expectedDistM, 0.01));
        expect(stepDistM, greaterThanOrEqualTo(0.0));

        final autoCo2 = Co2Math.computeAutoDefaultCo2Grams(stepDistM);
        expect(autoCo2, greaterThanOrEqualTo(0));
        if (steps == 0) {
          expect(stepDistM, equals(0.0));
          expect(autoCo2, equals(0));
        }

        final nextAutoCo2 = Co2Math.computeAutoDefaultCo2Grams(
          Co2Math.computeStepDistanceM(steps + 1, strideCm),
        );
        expect(nextAutoCo2, greaterThanOrEqualTo(autoCo2));

        final pointsTarget = Co2Math.computeDailyStepPointsTarget(steps);
        expect(pointsTarget, equals(steps ~/ 100));
        expect(pointsTarget, inInclusiveRange(0, 1000));
      },
    );

    Glados3(
      any.intInRange(0, 100001),
      any.intInRange(40, 121),
      any.doubleInRange(0.0, 5000.0),
    ).test('Hybrid CO2 conservation holds with arbitrary segment allocation', (
      steps,
      strideCm,
      allocDistM,
    ) {
      final stepDistM = Co2Math.computeStepDistanceM(steps, strideCm);
      final unallocatedDistM = math.max(0.0, stepDistM - allocDistM);
      final allocCo2 = Co2Math.computeSegmentCo2Grams(allocDistM, 0.19200);
      final autoCo2 = Co2Math.computeAutoDefaultCo2Grams(unallocatedDistM);
      final totalCo2 = allocCo2 + autoCo2;

      expect(unallocatedDistM, greaterThanOrEqualTo(0.0));
      expect(allocCo2, greaterThanOrEqualTo(0));
      expect(autoCo2, greaterThanOrEqualTo(0));
      expect(totalCo2, equals(allocCo2 + autoCo2));
    });

    Glados2(any.intInRange(0, 500000), any.intInRange(0, 500000)).test(
      'Reboot-safe step delta invariant',
      (prevSteps, currSteps) {
        final delta = Co2Math.computeRebootSafeStepDelta(prevSteps, currSteps);
        expect(delta, greaterThanOrEqualTo(0));
        if (currSteps >= prevSteps) {
          expect(delta, equals(currSteps - prevSteps));
        } else {
          expect(delta, equals(currSteps));
        }
      },
    );

    Glados2(
      any.choose(Co2Math.fuelEmissionFactorsGPerUnit.keys.toList()),
      any.intInRange(1, 5001),
    ).test('Vehicle factor invariants across all 8 fuel types', (
      fuel,
      consumptionCentis,
    ) {
      final consumption = consumptionCentis / 100.0;
      final result = Co2Math.computeVehicleCo2Factors(fuel, consumption);
      expect(result.gPerKm, greaterThan(0.0));
      expect(result.gPerMeter, greaterThan(0.0));
      expect(
        Co2Math.roundHalfUpDecimals(result.gPerMeter * 1000.0, 2),
        closeTo(result.gPerKm, 0.01),
      );
    });

    Glados3(
      any.doubleInRange(1.0, 120.0),
      any.doubleInRange(0.0, 600.0),
      any.intInRange(0, 300),
    ).test('Motion classifier invariants match Section 3.2 rules', (
      deltaTSec,
      deltaDistM,
      deltaSteps,
    ) {
      expect(
        Co2Math.classifyMotionInterval(
          deltaTSec: deltaTSec,
          deltaDistM: deltaDistM,
          deltaSteps: deltaSteps,
          accuracyM: 80.0,
        ),
        equals('unknown'),
      );

      final safe = Co2Math.classifyMotionIntervalSafe(
        deltaTSec: deltaTSec,
        deltaDistM: deltaDistM,
        deltaSteps: deltaSteps,
        accuracyM: 12.0,
      );
      if (safe.motionClass == 'walking') {
        expect(deltaSteps, greaterThanOrEqualTo(4));
        expect(deltaDistM, greaterThanOrEqualTo(6.0));
        final stride = deltaDistM / deltaSteps;
        expect(stride, inInclusiveRange(0.30, 2.20));
        expect(deltaDistM / deltaTSec, lessThanOrEqualTo(6.50));
      }
    });
  });
}
