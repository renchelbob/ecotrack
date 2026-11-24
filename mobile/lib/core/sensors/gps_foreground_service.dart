import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

final class GpsPoint {
  const GpsPoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speedMs,
    required this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final double altitude;
  final double speedMs;
  final DateTime recordedAt;

  Map<String, Object?> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'speed_ms': speedMs,
    'recorded_at': recordedAt.toIso8601String(),
  };
}

final class GpsForegroundService {
  GpsForegroundService();

  StreamSubscription<Position>? _positionSubscription;
  final List<GpsPoint> _recordedPoints = [];
  bool _isTracking = false;

  bool get isTracking => _isTracking;
  List<GpsPoint> get recordedPoints => List.unmodifiable(_recordedPoints);

  Future<bool> checkAndRequestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> startTracking({void Function(GpsPoint point)? onPoint}) async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      return;
    }

    _isTracking = true;
    _recordedPoints.clear();

    // Start FlutterForegroundTask notification
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'EcoTrack',
        notificationText: 'Идет запись экологичного маршрута...',
      );
    } catch (_) {}

    await _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((pos) {
          final point = GpsPoint(
            latitude: pos.latitude,
            longitude: pos.longitude,
            altitude: pos.altitude,
            speedMs: pos.speed,
            recordedAt: pos.timestamp,
          );
          _recordedPoints.add(point);
          onPoint?.call(point);
        }, onError: (_) {});
  }

  Future<List<GpsPoint>> stopTracking() async {
    _isTracking = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}

    return List.unmodifiable(_recordedPoints);
  }

  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
  }
}
