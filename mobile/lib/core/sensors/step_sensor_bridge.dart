import 'dart:async';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';

final class StepSensorBridge {
  StepSensorBridge({Health? customHealth}) : _health = customHealth ?? Health();

  final Health _health;
  StreamSubscription<StepCount>? _pedometerSubscription;
  int _latestLiveSteps = 0;

  int get latestLiveSteps => _latestLiveSteps;

  Future<bool> requestPermissions() async {
    try {
      final types = [HealthDataType.STEPS];
      final permissions = [HealthDataAccess.READ];
      final granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<int> fetchHistoricalStepsForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    try {
      final steps = await _health.getTotalStepsInInterval(startOfDay, endOfDay);
      return steps ?? 0;
    } catch (_) {
      return _latestLiveSteps;
    }
  }

  void startLivePedometer({void Function(int steps)? onStepUpdate}) {
    _pedometerSubscription?.cancel();
    try {
      _pedometerSubscription = Pedometer.stepCountStream.listen(
        (event) {
          _latestLiveSteps = event.steps;
          onStepUpdate?.call(event.steps);
        },
        onError: (_) {
          // Pedometer sensor failure handled gracefully
        },
      );
    } catch (_) {
      // Platform unsupported or sensor unavailable
    }
  }

  void dispose() {
    _pedometerSubscription?.cancel();
    _pedometerSubscription = null;
  }
}
