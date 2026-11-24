import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/sensors/gps_foreground_service.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class MapActivityState {
  const MapActivityState();
}

final class MapActivityLoading extends MapActivityState {
  const MapActivityLoading();
}

final class MapActivityLoaded extends MapActivityState {
  const MapActivityLoaded({
    required this.mode,
    required this.wastePoints,
    required this.isTrackingGps,
    required this.recordedPoints,
    this.selectedWastePoint,
    this.currentPosition,
  });

  final MapMode mode;
  final List<WastePoint> wastePoints;
  final bool isTrackingGps;
  final List<GpsPoint> recordedPoints;
  final WastePoint? selectedWastePoint;
  final GpsPoint? currentPosition;

  MapActivityLoaded copyWith({
    MapMode? mode,
    List<WastePoint>? wastePoints,
    bool? isTrackingGps,
    List<GpsPoint>? recordedPoints,
    WastePoint? selectedWastePoint,
    bool clearSelectedWastePoint = false,
    GpsPoint? currentPosition,
  }) => MapActivityLoaded(
    mode: mode ?? this.mode,
    wastePoints: wastePoints ?? this.wastePoints,
    isTrackingGps: isTrackingGps ?? this.isTrackingGps,
    recordedPoints: recordedPoints ?? this.recordedPoints,
    selectedWastePoint: clearSelectedWastePoint
        ? null
        : (selectedWastePoint ?? this.selectedWastePoint),
    currentPosition: currentPosition ?? this.currentPosition,
  );
}

final class MapActivityFailure extends MapActivityState {
  const MapActivityFailure(this.error);
  final AppError error;
}

final class MapActivityCubit extends Cubit<MapActivityState> {
  MapActivityCubit({
    required MapRepository repository,
    required GpsForegroundService gpsService,
  }) : _repository = repository,
       _gpsService = gpsService,
       super(const MapActivityLoading());

  final MapRepository _repository;
  final GpsForegroundService _gpsService;

  Future<void> loadMapData() async {
    emit(const MapActivityLoading());
    final result = await _repository.getWastePoints();
    final pos = await _gpsService.getCurrentPosition();
    final userGps = pos != null
        ? GpsPoint(
            latitude: pos.latitude,
            longitude: pos.longitude,
            altitude: pos.altitude,
            speedMs: pos.speed,
            recordedAt: pos.timestamp,
          )
        : null;

    switch (result) {
      case Ok(value: final points):
        emit(
          MapActivityLoaded(
            mode: MapMode.recyclingMap,
            wastePoints: points,
            isTrackingGps: _gpsService.isTracking,
            recordedPoints: _gpsService.recordedPoints,
            currentPosition: userGps,
          ),
        );
      case Err(error: final appError):
        emit(MapActivityFailure(appError));
    }
  }

  Future<GpsPoint?> locateMe() async {
    final pos = await _gpsService.getCurrentPosition();
    if (pos != null) {
      final point = GpsPoint(
        latitude: pos.latitude,
        longitude: pos.longitude,
        altitude: pos.altitude,
        speedMs: pos.speed,
        recordedAt: pos.timestamp,
      );
      if (state case final MapActivityLoaded loaded) {
        emit(loaded.copyWith(currentPosition: point));
      }
      return point;
    }
    return null;
  }

  void switchMode(MapMode newMode) {
    if (state case final MapActivityLoaded loaded) {
      emit(loaded.copyWith(mode: newMode));
    }
  }

  void selectWastePoint(WastePoint? point) {
    if (state case final MapActivityLoaded loaded) {
      emit(
        loaded.copyWith(
          selectedWastePoint: point,
          clearSelectedWastePoint: point == null,
        ),
      );
    }
  }

  Future<void> toggleGpsTracking() async {
    if (state case final MapActivityLoaded loaded) {
      if (loaded.isTrackingGps) {
        final pts = await _gpsService.stopTracking();
        emit(loaded.copyWith(isTrackingGps: false, recordedPoints: pts));
      } else {
        await _gpsService.startTracking(
          onPoint: (pt) {
            if (state case final MapActivityLoaded cur) {
              emit(
                cur.copyWith(
                  recordedPoints: [...cur.recordedPoints, pt],
                  currentPosition: pt,
                ),
              );
            }
          },
        );
        emit(loaded.copyWith(isTrackingGps: true));
      }
    }
  }
}
