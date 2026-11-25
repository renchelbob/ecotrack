import 'dart:math' as math;

final class const MotionAntifraudException(final String errorCode)
    implements Exception {
  @override
  String toString() => 'MotionAntifraudException($errorCode)';
}

final class const _ExactDecimal(final BigInt mantissa, final int scale) {
  factory fromDouble(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Must be finite');
    }
    return _ExactDecimal.parse(value.toString());
  }

  factory parse(String raw) {
    final trimmed = raw.trim();
    final eIndex = trimmed.indexOf(RegExp('[eE]'));
    final significandStr = eIndex == -1
        ? trimmed
        : trimmed.substring(0, eIndex);
    final exp = eIndex == -1 ? 0 : int.parse(trimmed.substring(eIndex + 1));

    final isNegative = significandStr.startsWith('-');
    final unsigned = isNegative || significandStr.startsWith('+')
        ? significandStr.substring(1)
        : significandStr;
    final dotIndex = unsigned.indexOf('.');
    final intPart = dotIndex == -1 ? unsigned : unsigned.substring(0, dotIndex);
    final fracPart = dotIndex == -1 ? '' : unsigned.substring(dotIndex + 1);

    final digits = '$intPart$fracPart';
    var parsedMantissa = BigInt.parse(digits.isEmpty ? '0' : digits);
    if (isNegative) {
      parsedMantissa = -parsedMantissa;
    }
    var parsedScale = fracPart.length - exp;
    if (parsedScale < 0) {
      parsedMantissa *= BigInt.from(10).pow(-parsedScale);
      parsedScale = 0;
    }
    return _ExactDecimal(parsedMantissa, parsedScale);
  }

  _ExactDecimal operator *(_ExactDecimal other) =>
      _ExactDecimal(mantissa * other.mantissa, scale + other.scale);

  _ExactDecimal shiftRight(int decimalPlaces) =>
      _ExactDecimal(mantissa, scale + decimalPlaces);

  int roundHalfUpInt() => _roundHalfUpScaled(0).toInt();

  double roundHalfUpDouble(int decimals) {
    final rounded = _roundHalfUpScaled(decimals);
    if (decimals == 0) {
      return rounded.toDouble();
    }
    return rounded.toDouble() / math.pow(10, decimals);
  }

  BigInt _roundHalfUpScaled(int targetScale) {
    final diff = scale - targetScale;
    if (diff <= 0) {
      return mantissa * BigInt.from(10).pow(-diff);
    }
    final divisor = BigInt.from(10).pow(diff);
    final half = divisor ~/ BigInt.two;
    final absMantissa = mantissa.abs();
    final quotient = absMantissa ~/ divisor;
    final remainder = absMantissa % divisor;
    final roundedAbs = remainder >= half ? quotient + BigInt.one : quotient;
    return mantissa.isNegative ? -roundedAbs : roundedAbs;
  }
}

final class const Co2Math() {
  static const int defaultStrideLengthCm = 74;
  static const int minStrideLengthCm = 40;
  static const int maxStrideLengthCm = 120;
  static const double annotatedConfidenceFactor = 1.00;
  static const double defaultAutoConfidenceFactor = 0.70;
  static const double defaultBusSubstitutionRatio = 0.80;
  static const double defaultBusCo2GPerKm = 82.00;
  static const double defaultBusCo2GPerM = 0.08200;
  static const double effectiveAutoCo2GPerM = 0.04592;
  static const int stepsPerEcoPoint = 100;
  static const int streakMinDailySteps = 1000;
  static const int maxDailySteps = 100000;
  static const double maxSustainedCadenceSps = 4.50;
  static const double maxGpsAccuracyMeters = 65.0;
  static const double teleportSpeedMps = 50.00;
  static const double teleportMinDistanceM = 250.0;
  static const double vehicleSpeedMps = 6.50;
  static const double vehicleLowCadenceSpeedMps = 2.50;
  static const double indoorPacingMaxDistM = 6.00;
  static const double minWalkStrideM = 0.30;
  static const double maxWalkStrideM = 2.20;

  static const Map<String, double> fuelEmissionFactorsGPerUnit = {
    'petrol_92': 2310.0,
    'petrol_95': 2330.0,
    'petrol_98': 2350.0,
    'diesel': 2680.0,
    'lpg': 1660.0,
    'cng': 1960.0,
    'hybrid': 2310.0,
    'electric': 340.0,
  };

  static final _ExactDecimal _effectiveAutoDecimal = _ExactDecimal.parse(
    '0.04592',
  );

  int round(double value) => roundHalfUp(value);

  static int roundHalfUp(double value) =>
      _ExactDecimal.fromDouble(value).roundHalfUpInt();

  static double roundHalfUpDecimals(double value, int decimals) =>
      _ExactDecimal.fromDouble(value).roundHalfUpDouble(decimals);

  static double computeStepDistanceM(int validatedSteps, int strideLengthCm) {
    final stepsDec = _ExactDecimal(BigInt.from(validatedSteps), 0);
    final strideDec = _ExactDecimal(BigInt.from(strideLengthCm), 0);
    return (stepsDec * strideDec).shiftRight(2).roundHalfUpDouble(2);
  }

  static int computeAutoDefaultCo2Grams(double unallocatedDistanceM) {
    final clamped = unallocatedDistanceM <= 0.0 ? 0.0 : unallocatedDistanceM;
    final distDec = _ExactDecimal.fromDouble(clamped);
    return (distDec * _effectiveAutoDecimal).roundHalfUpInt();
  }

  static int computeSegmentCo2Grams(
    double segmentDistanceM,
    double co2GPerMeter,
  ) {
    final clampedDist = segmentDistanceM <= 0.0 ? 0.0 : segmentDistanceM;
    final clampedRate = co2GPerMeter <= 0.0 ? 0.0 : co2GPerMeter;
    final product =
        _ExactDecimal.fromDouble(clampedDist) *
        _ExactDecimal.fromDouble(clampedRate);
    return product.roundHalfUpInt();
  }

  static int computeDailyStepPointsTarget(int validatedSteps) =>
      validatedSteps <= 0 ? 0 : validatedSteps ~/ stepsPerEcoPoint;

  static ({double gPerKm, double gPerMeter, double factor})
  computeVehicleCo2Factors(String fuelWireName, double consumptionPer100km) {
    final factor = fuelEmissionFactorsGPerUnit[fuelWireName];
    if (factor == null) {
      throw ArgumentError.value(
        fuelWireName,
        'fuelWireName',
        'Unsupported fuel type',
      );
    }
    if (consumptionPer100km <= 0.0 || consumptionPer100km > 50.0) {
      throw ArgumentError.value(
        consumptionPer100km,
        'consumptionPer100km',
        'Must be > 0.0 and <= 50.0',
      );
    }
    final product =
        _ExactDecimal.fromDouble(consumptionPer100km) *
        _ExactDecimal.fromDouble(factor);
    final gPerKm = product.shiftRight(2).roundHalfUpDouble(2);
    final gPerMeter = product.shiftRight(5).roundHalfUpDouble(5);
    return (gPerKm: gPerKm, gPerMeter: gPerMeter, factor: factor);
  }

  static int computeRebootSafeStepDelta(
    int prevCumulative,
    int currCumulative,
  ) {
    if (prevCumulative < 0 || currCumulative < 0) {
      throw ArgumentError('Cumulative steps must be non-negative');
    }
    return currCumulative >= prevCumulative
        ? currCumulative - prevCumulative
        : currCumulative;
  }

  static String classifyMotionInterval({
    required double deltaTSec,
    required double deltaDistM,
    required int deltaSteps,
    required double accuracyM,
  }) {
    if (accuracyM > maxGpsAccuracyMeters) {
      return 'unknown';
    }
    final dt = deltaTSec < 1.0 ? 1.0 : deltaTSec;
    final speedMps = deltaDistM / dt;
    final cadenceSps = deltaSteps / dt;
    final strideM = deltaSteps > 0 ? deltaDistM / deltaSteps : double.infinity;

    if (speedMps > teleportSpeedMps && deltaDistM > teleportMinDistanceM) {
      throw const MotionAntifraudException('ANTIFRAUD_SPEED_SPOOFING_DETECTED');
    }
    if (dt >= 10.0 && cadenceSps > maxSustainedCadenceSps) {
      throw const MotionAntifraudException('ANTIFRAUD_STEP_SPIKE_DETECTED');
    }
    if (speedMps > vehicleSpeedMps ||
        (deltaDistM >= 25.0 && deltaSteps < 5) ||
        (speedMps >= vehicleLowCadenceSpeedMps && strideM > maxWalkStrideM)) {
      return 'vehicle_suspected';
    }
    if (deltaSteps >= 10 && deltaDistM < indoorPacingMaxDistM) {
      return 'indoor_pacing';
    }
    if (deltaSteps < 4 && deltaDistM < indoorPacingMaxDistM) {
      return 'stationary';
    }
    if (deltaSteps >= 4 &&
        deltaDistM >= indoorPacingMaxDistM &&
        strideM >= minWalkStrideM &&
        strideM <= maxWalkStrideM &&
        speedMps <= vehicleSpeedMps) {
      return 'walking';
    }
    return 'unknown';
  }

  static ({String motionClass, String? antifraudCode})
  classifyMotionIntervalSafe({
    required double deltaTSec,
    required double deltaDistM,
    required int deltaSteps,
    required double accuracyM,
  }) {
    try {
      final motionClass = classifyMotionInterval(
        deltaTSec: deltaTSec,
        deltaDistM: deltaDistM,
        deltaSteps: deltaSteps,
        accuracyM: accuracyM,
      );
      return (motionClass: motionClass, antifraudCode: null);
    } on MotionAntifraudException catch (error) {
      return (motionClass: 'unknown', antifraudCode: error.errorCode);
    }
  }
}
