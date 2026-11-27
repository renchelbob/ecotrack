import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum MapScreenMode() {
  myRoutes,
  recyclingMap,
}

sealed class const MapActivityEvent();

final class const MapStarted({
  final MapScreenMode initialMode = .myRoutes,
  final String? initialDateIso,
}) extends MapActivityEvent;

final class const MapModeToggled(final MapScreenMode mode)
    extends MapActivityEvent;

final class const MapDateSelected(final String activityDate)
    extends MapActivityEvent;

final class const MapGpsToggled() extends MapActivityEvent;

final class const MapGpsIntervalChanged(final int intervalSeconds)
    extends MapActivityEvent;

final class const MapAllocationsSaved(
  final List<RouteSegmentAllocationInput> allocations,
) extends MapActivityEvent;

final class const MapAllocationDeleted(final String allocationId)
    extends MapActivityEvent;

final class const MapWastePointsBboxChanged({
  required final double minLat,
  required final double minLon,
  required final double maxLat,
  required final double maxLon,
  required final int zoom,
}) extends MapActivityEvent;

final class const MapFractionToggled(final WasteFractionCode? fraction)
    extends MapActivityEvent;

final class const MapWastePointTapped(final String pointId)
    extends MapActivityEvent;

final class const MapWastePointClosed() extends MapActivityEvent;

final class const MapWasteReportSubmitted({
  required final String pointId,
  required final ReportType reportType,
  final String? comment,
}) extends MapActivityEvent;

final class const MapWastePointSuggested(final SuggestWastePointRequest request)
    extends MapActivityEvent;

final class const MapLocateMeRequested() extends MapActivityEvent;

final class const MapFeedbackCleared() extends MapActivityEvent;

final class const _MapPositionObserved(
  final ({double lat, double lon, double accuracy}) pos,
) extends MapActivityEvent;

final class const _MapSummaryObserved(final DailyActivitySummary summary)
    extends MapActivityEvent;

final class const _MapProfileObserved(final UserProfile profile)
    extends MapActivityEvent;

sealed class const MapActivityState();

final class const MapActivityLoading() extends MapActivityState;

final class const MapRouteViewState({
  required final String selectedDateIso,
  final DailyActivityDetail? detail,
  final List<TransportPresetItem> presets = const [],
  final double userCarGPerKm = 192.0,
  final bool isGpsEnabled = false,
  final int gpsIntervalSeconds = 15,
  final bool isLoading = false,
}) {
  MapRouteViewState copyWith({
    String? selectedDateIso,
    DailyActivityDetail? detail,
    List<TransportPresetItem>? presets,
    double? userCarGPerKm,
    bool? isGpsEnabled,
    int? gpsIntervalSeconds,
    bool? isLoading,
  }) => MapRouteViewState(
    selectedDateIso: selectedDateIso ?? this.selectedDateIso,
    detail: detail ?? this.detail,
    presets: presets ?? this.presets,
    userCarGPerKm: userCarGPerKm ?? this.userCarGPerKm,
    isGpsEnabled: isGpsEnabled ?? this.isGpsEnabled,
    gpsIntervalSeconds: gpsIntervalSeconds ?? this.gpsIntervalSeconds,
    isLoading: isLoading ?? this.isLoading,
  );
}

final class const MapWasteViewState({
  final List<WastePointMapItem> points = const [],
  final String attributionBannerRu =
      WastePointsBboxResponse.defaultAttributionBannerRu,
  final Set<WasteFractionCode> activeFilters = const {},
  final WastePointDetail? selectedPoint,
  final bool isLoadingPoints = false,
  final bool isLoadingDetail = false,
}) {
  MapWasteViewState copyWith({
    List<WastePointMapItem>? points,
    String? attributionBannerRu,
    Set<WasteFractionCode>? activeFilters,
    WastePointDetail? selectedPoint,
    bool clearSelectedPoint = false,
    bool? isLoadingPoints,
    bool? isLoadingDetail,
  }) => MapWasteViewState(
    points: points ?? this.points,
    attributionBannerRu: attributionBannerRu ?? this.attributionBannerRu,
    activeFilters: activeFilters ?? this.activeFilters,
    selectedPoint: clearSelectedPoint
        ? null
        : (selectedPoint ?? this.selectedPoint),
    isLoadingPoints: isLoadingPoints ?? this.isLoadingPoints,
    isLoadingDetail: isLoadingDetail ?? this.isLoadingDetail,
  );
}

final class const MapActivityReady({
  required final MapScreenMode mode,
  required final MapRouteViewState routeView,
  required final MapWasteViewState wasteView,
  final ({double lat, double lon, double accuracy})? currentPosition,
  final bool isSubmitting = false,
  final AppError? bannerError,
  final String? feedbackMessage,
}) extends MapActivityState {
  MapActivityReady copyWith({
    MapScreenMode? mode,
    MapRouteViewState? routeView,
    MapWasteViewState? wasteView,
    ({double lat, double lon, double accuracy})? currentPosition,
    bool? isSubmitting,
    AppError? bannerError,
    String? feedbackMessage,
    bool clearFeedback = false,
  }) => MapActivityReady(
    mode: mode ?? this.mode,
    routeView: routeView ?? this.routeView,
    wasteView: wasteView ?? this.wasteView,
    currentPosition: currentPosition ?? this.currentPosition,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    bannerError: clearFeedback ? null : (bannerError ?? this.bannerError),
    feedbackMessage: clearFeedback
        ? null
        : (feedbackMessage ?? this.feedbackMessage),
  );
}

final class MapActivityBloc(
  final MapActivityRepository _mapRepo,
  final ProfileRepository _profileRepo,
) extends Bloc<MapActivityEvent, MapActivityState> {
  this : super(const MapActivityLoading()) {
    on<MapStarted>(_onStarted);
    on<MapModeToggled>(_onModeToggled);
    on<MapDateSelected>(_onDateSelected);
    on<MapGpsToggled>(_onGpsToggled);
    on<MapGpsIntervalChanged>(_onGpsIntervalChanged);
    on<MapAllocationsSaved>(_onAllocationsSaved);
    on<MapAllocationDeleted>(_onAllocationDeleted);
    on<MapWastePointsBboxChanged>(_onBboxChanged);
    on<MapFractionToggled>(_onFractionToggled);
    on<MapWastePointTapped>(_onWastePointTapped);
    on<MapWastePointClosed>(_onWastePointClosed);
    on<MapWasteReportSubmitted>(_onWasteReportSubmitted);
    on<MapWastePointSuggested>(_onWastePointSuggested);
    on<MapLocateMeRequested>(_onLocateMe);
    on<MapFeedbackCleared>(_onFeedbackCleared);
    on<_MapPositionObserved>(_onPositionObserved);
    on<_MapSummaryObserved>(_onSummaryObserved);
    on<_MapProfileObserved>(_onProfileObserved);
  }

  StreamSubscription<({double lat, double lon, double accuracy})>? _posSub;
  StreamSubscription<DailyActivitySummary>? _summarySub;
  StreamSubscription<UserProfile>? _profileSub;
  ({double minLat, double minLon, double maxLat, double maxLon, int zoom})?
  _lastBbox;

  TileCacheStorage? get tileCacheStorage => switch (_mapRepo) {
    final TileCacheStorageProvider provider => provider.tileCacheStorage,
    _ => null,
  };

  Future<void> _onStarted(
    MapStarted event,
    Emitter<MapActivityState> emit,
  ) async {
    final targetDate = event.initialDateIso ?? _todayIso();
    await _subscribeAuxiliaryStreams(targetDate);

    final profileRes = await _profileRepo.getProfile();
    final presetsRes = await _profileRepo.listTransportPresets();
    final detailRes = await _mapRepo.getDailyActivityDetail(targetDate);
    final pos = await _mapRepo.getLastKnownOrCurrentPosition();

    final profile = profileRes.valueOrNull;
    final presets = presetsRes.valueOrNull ?? const <TransportPresetItem>[];
    final detail = detailRes.valueOrNull;
    final userCarGPerKm = profile?.personalVehicle?.computedCo2GPerKm ?? 192.0;
    final isGpsEnabled = profile?.isGpsTrackingEnabled ?? false;
    final gpsInterval = profile?.gpsIntervalSeconds ?? 15;

    if (isGpsEnabled) {
      unawaited(
        _mapRepo.setGpsTrackingEnabled(true, intervalSeconds: gpsInterval),
      );
    }

    final initialBbox = _defaultBboxForPosition(pos);
    _lastBbox = initialBbox;
    final wasteRes = await _mapRepo.queryWastePoints(
      minLat: initialBbox.minLat,
      minLon: initialBbox.minLon,
      maxLat: initialBbox.maxLat,
      maxLon: initialBbox.maxLon,
      zoom: initialBbox.zoom,
    );

    emit(
      MapActivityReady(
        mode: event.initialMode,
        routeView: MapRouteViewState(
          selectedDateIso: targetDate,
          detail: detail,
          presets: presets,
          userCarGPerKm: userCarGPerKm,
          isGpsEnabled: isGpsEnabled,
          gpsIntervalSeconds: gpsInterval,
        ),
        wasteView: MapWasteViewState(
          points: wasteRes.valueOrNull?.points ?? const [],
          attributionBannerRu:
              wasteRes.valueOrNull?.attributionBannerRu ??
              WastePointsBboxResponse.defaultAttributionBannerRu,
        ),
        currentPosition: pos,
        bannerError: detailRes.errorOrNull ?? wasteRes.errorOrNull,
      ),
    );
  }

  Future<void> _subscribeAuxiliaryStreams(String targetDate) async {
    await _posSub?.cancel();
    await _summarySub?.cancel();
    await _profileSub?.cancel();
    _posSub = _mapRepo.currentPositionStream.listen(
      (pos) => add(_MapPositionObserved(pos)),
    );
    _summarySub = _mapRepo
        .watchDailySummary(targetDate)
        .listen((s) => add(_MapSummaryObserved(s)));
    _profileSub = _profileRepo.watchUserProfile().listen(
      (p) => add(_MapProfileObserved(p)),
    );
  }

  Future<void> _onModeToggled(
    MapModeToggled event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      emit(ready.copyWith(mode: event.mode, clearFeedback: true));
      if (event.mode == .recyclingMap && ready.wasteView.points.isEmpty) {
        final box = _lastBbox ?? _defaultBboxForPosition(ready.currentPosition);
        add(
          MapWastePointsBboxChanged(
            minLat: box.minLat,
            minLon: box.minLon,
            maxLat: box.maxLat,
            maxLon: box.maxLon,
            zoom: box.zoom,
          ),
        );
      }
    }
  }

  Future<void> _onDateSelected(
    MapDateSelected event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      await _summarySub?.cancel();
      _summarySub = _mapRepo
          .watchDailySummary(event.activityDate)
          .listen((s) => add(_MapSummaryObserved(s)));
      emit(
        ready.copyWith(
          routeView: ready.routeView.copyWith(
            selectedDateIso: event.activityDate,
            isLoading: true,
          ),
          clearFeedback: true,
        ),
      );
      final res = await _mapRepo.getDailyActivityDetail(event.activityDate);
      if (state case final MapActivityReady current) {
        emit(
          current.copyWith(
            routeView: current.routeView.copyWith(
              detail: res.valueOrNull,
              isLoading: false,
            ),
            bannerError: res.errorOrNull,
          ),
        );
      }
    }
  }

  Future<void> _onGpsToggled(
    MapGpsToggled event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      final nextEnabled = !ready.routeView.isGpsEnabled;
      final interval = ready.routeView.gpsIntervalSeconds;
      await _mapRepo.setGpsTrackingEnabled(
        nextEnabled,
        intervalSeconds: interval,
      );
      unawaited(
        _profileRepo.updateProfile(
          UpdateUserProfileRequest(isGpsTrackingEnabled: nextEnabled),
        ),
      );
      emit(
        ready.copyWith(
          routeView: ready.routeView.copyWith(isGpsEnabled: nextEnabled),
          feedbackMessage: nextEnabled
              ? 'Запись GPS-маршрута включена ($interval с)'
              : 'Запись GPS-маршрута остановлена',
        ),
      );
    }
  }

  Future<void> _onGpsIntervalChanged(
    MapGpsIntervalChanged event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      if (ready.routeView.isGpsEnabled) {
        await _mapRepo.setGpsTrackingEnabled(
          true,
          intervalSeconds: event.intervalSeconds,
        );
      }
      unawaited(
        _profileRepo.updateProfile(
          UpdateUserProfileRequest(gpsIntervalSeconds: event.intervalSeconds),
        ),
      );
      emit(
        ready.copyWith(
          routeView: ready.routeView.copyWith(
            gpsIntervalSeconds: event.intervalSeconds,
          ),
          feedbackMessage: 'Интервал GPS: ${event.intervalSeconds} сек',
        ),
      );
    }
  }

  Future<void> _onAllocationsSaved(
    MapAllocationsSaved event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      emit(ready.copyWith(isSubmitting: true, clearFeedback: true));
      final res = await _mapRepo.saveRouteAllocations(
        activityDate: ready.routeView.selectedDateIso,
        allocations: event.allocations,
      );
      if (state case final MapActivityReady current) {
        switch (res) {
          case Ok(:final value):
            emit(
              current.copyWith(
                isSubmitting: false,
                routeView: current.routeView.copyWith(detail: value),
                feedbackMessage: 'Участок маршрута сохранён',
              ),
            );
          case Err(:final error):
            emit(current.copyWith(isSubmitting: false, bannerError: error));
        }
      }
    }
  }

  Future<void> _onAllocationDeleted(
    MapAllocationDeleted event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      emit(ready.copyWith(isSubmitting: true, clearFeedback: true));
      final res = await _mapRepo.deleteRouteAllocation(
        activityDate: ready.routeView.selectedDateIso,
        allocationId: event.allocationId,
      );
      if (state case final MapActivityReady current) {
        switch (res) {
          case Ok(:final value):
            emit(
              current.copyWith(
                isSubmitting: false,
                routeView: current.routeView.copyWith(detail: value),
                feedbackMessage: 'Разметка участка удалена',
              ),
            );
          case Err(:final error):
            emit(current.copyWith(isSubmitting: false, bannerError: error));
        }
      }
    }
  }

  Future<void> _onBboxChanged(
    MapWastePointsBboxChanged event,
    Emitter<MapActivityState> emit,
  ) async {
    _lastBbox = (
      minLat: event.minLat,
      minLon: event.minLon,
      maxLat: event.maxLat,
      maxLon: event.maxLon,
      zoom: event.zoom,
    );
    if (state case final MapActivityReady ready) {
      emit(
        ready.copyWith(
          wasteView: ready.wasteView.copyWith(isLoadingPoints: true),
          clearFeedback: true,
        ),
      );
      final res = await _mapRepo.queryWastePoints(
        minLat: event.minLat,
        minLon: event.minLon,
        maxLat: event.maxLat,
        maxLon: event.maxLon,
        zoom: event.zoom,
        fractions: ready.wasteView.activeFilters.toList(),
      );
      if (state case final MapActivityReady current) {
        switch (res) {
          case Ok(:final value):
            emit(
              current.copyWith(
                wasteView: current.wasteView.copyWith(
                  points: value.points,
                  attributionBannerRu: value.attributionBannerRu,
                  isLoadingPoints: false,
                ),
              ),
            );
          case Err(:final error):
            emit(
              current.copyWith(
                wasteView: current.wasteView.copyWith(isLoadingPoints: false),
                bannerError: error,
              ),
            );
        }
      }
    }
  }

  Future<void> _onFractionToggled(
    MapFractionToggled event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      final nextFilters = <WasteFractionCode>{...ready.wasteView.activeFilters};
      final fraction = event.fraction;
      if (fraction == null) {
        nextFilters.clear();
      } else if (!nextFilters.add(fraction)) {
        nextFilters.remove(fraction);
      }
      emit(
        ready.copyWith(
          wasteView: ready.wasteView.copyWith(activeFilters: nextFilters),
          clearFeedback: true,
        ),
      );
      final box = _lastBbox ?? _defaultBboxForPosition(ready.currentPosition);
      add(
        MapWastePointsBboxChanged(
          minLat: box.minLat,
          minLon: box.minLon,
          maxLat: box.maxLat,
          maxLon: box.maxLon,
          zoom: box.zoom,
        ),
      );
    }
  }

  Future<void> _onWastePointTapped(
    MapWastePointTapped event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      emit(
        ready.copyWith(
          wasteView: ready.wasteView.copyWith(isLoadingDetail: true),
          clearFeedback: true,
        ),
      );
      final res = await _mapRepo.getWastePointDetail(event.pointId);
      if (state case final MapActivityReady current) {
        switch (res) {
          case Ok(:final value):
            emit(
              current.copyWith(
                wasteView: current.wasteView.copyWith(
                  selectedPoint: value,
                  isLoadingDetail: false,
                ),
              ),
            );
          case Err(:final error):
            emit(
              current.copyWith(
                wasteView: current.wasteView.copyWith(isLoadingDetail: false),
                bannerError: error,
              ),
            );
        }
      }
    }
  }

  void _onWastePointClosed(
    MapWastePointClosed event,
    Emitter<MapActivityState> emit,
  ) {
    if (state case final MapActivityReady ready) {
      emit(
        ready.copyWith(
          wasteView: ready.wasteView.copyWith(clearSelectedPoint: true),
        ),
      );
    }
  }

  Future<void> _onWasteReportSubmitted(
    MapWasteReportSubmitted event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      emit(ready.copyWith(isSubmitting: true, clearFeedback: true));
      final pos =
          ready.currentPosition ??
          await _mapRepo.getLastKnownOrCurrentPosition();
      final selected = ready.wasteView.selectedPoint;
      final lat = pos?.lat ?? selected?.lat ?? 58.6035;
      final lon = pos?.lon ?? selected?.lon ?? 49.6680;
      final res = await _mapRepo.submitWastePointReport(
        pointId: event.pointId,
        reportType: event.reportType,
        comment: event.comment,
        userLat: lat,
        userLon: lon,
      );
      if (state case final MapActivityReady current) {
        switch (res) {
          case Ok(:final value):
            final detailRes = await _mapRepo.getWastePointDetail(event.pointId);
            final latestDetail =
                detailRes.valueOrNull ?? current.wasteView.selectedPoint;
            final isConfirmation = event.reportType == .confirmWorking;
            final updatedPts = current.wasteView.points
                .map(
                  (p) => p.id == event.pointId
                      ? WastePointMapItem(
                          id: p.id,
                          title: p.title,
                          addressText: p.addressText,
                          acceptedFractions: p.acceptedFractions,
                          lat: p.lat,
                          lon: p.lon,
                          status: value.updatedStatus,
                          trustScore: value.updatedTrustScore,
                          confirmationsCount:
                              detailRes.isOk && latestDetail != null
                              ? latestDetail.confirmationsCount
                              : p.confirmationsCount + (isConfirmation ? 1 : 0),
                          issuesCount: detailRes.isOk && latestDetail != null
                              ? latestDetail.issuesCount
                              : p.issuesCount + (isConfirmation ? 0 : 1),
                        )
                      : p,
                )
                .toList();
            emit(
              current.copyWith(
                isSubmitting: false,
                wasteView: current.wasteView.copyWith(
                  points: updatedPts,
                  selectedPoint: latestDetail,
                ),
                feedbackMessage: value.pointsRewarded > 0
                    ? 'Отчёт учтён! Начислено +${value.pointsRewarded} ★'
                    : 'Статус пункта РСО обновлён',
              ),
            );
          case Err(:final error):
            emit(current.copyWith(isSubmitting: false, bannerError: error));
        }
      }
    }
  }

  Future<void> _onWastePointSuggested(
    MapWastePointSuggested event,
    Emitter<MapActivityState> emit,
  ) async {
    if (state case final MapActivityReady ready) {
      emit(ready.copyWith(isSubmitting: true, clearFeedback: true));
      final res = await _mapRepo.suggestWastePoint(event.request);
      if (state case final MapActivityReady current) {
        switch (res) {
          case Ok(:final value):
            final addedItem = WastePointMapItem(
              id: value.id,
              title: value.title,
              addressText: value.addressText,
              acceptedFractions: value.acceptedFractions,
              lat: value.lat,
              lon: value.lon,
              status: value.status,
              trustScore: value.trustScore,
              confirmationsCount: value.confirmationsCount,
              issuesCount: value.issuesCount,
            );
            emit(
              current.copyWith(
                isSubmitting: false,
                wasteView: current.wasteView.copyWith(
                  points: [...current.wasteView.points, addedItem],
                  selectedPoint: value,
                ),
                feedbackMessage: 'Новая точка РСО отправлена на карту',
              ),
            );
          case Err(:final error):
            emit(current.copyWith(isSubmitting: false, bannerError: error));
        }
      }
    }
  }

  Future<void> _onLocateMe(
    MapLocateMeRequested event,
    Emitter<MapActivityState> emit,
  ) async {
    final pos = await _mapRepo.getLastKnownOrCurrentPosition();
    if (pos != null && state is MapActivityReady) {
      final ready = state as MapActivityReady;
      emit(ready.copyWith(currentPosition: pos));
    }
  }

  void _onFeedbackCleared(
    MapFeedbackCleared event,
    Emitter<MapActivityState> emit,
  ) {
    if (state case final MapActivityReady ready) {
      emit(ready.copyWith(clearFeedback: true));
    }
  }

  void _onPositionObserved(
    _MapPositionObserved event,
    Emitter<MapActivityState> emit,
  ) {
    if (state case final MapActivityReady ready) {
      emit(ready.copyWith(currentPosition: event.pos));
    }
  }

  void _onSummaryObserved(
    _MapSummaryObserved event,
    Emitter<MapActivityState> emit,
  ) {
    if (state case final MapActivityReady ready) {
      final prevDetail = ready.routeView.detail;
      if (prevDetail != null &&
          prevDetail.summary.activityDate == event.summary.activityDate) {
        emit(
          ready.copyWith(
            routeView: ready.routeView.copyWith(
              detail: DailyActivityDetail(
                summary: event.summary,
                isEditable: prevDetail.isEditable,
                totalGpsWalkingDistanceM: prevDetail.totalGpsWalkingDistanceM,
                trackPoints: prevDetail.trackPoints,
                allocations: prevDetail.allocations,
                co2DeltaAppliedGrams: prevDetail.co2DeltaAppliedGrams,
              ),
            ),
          ),
        );
      }
    }
  }

  void _onProfileObserved(
    _MapProfileObserved event,
    Emitter<MapActivityState> emit,
  ) {
    if (state case final MapActivityReady ready) {
      emit(
        ready.copyWith(
          routeView: ready.routeView.copyWith(
            userCarGPerKm:
                event.profile.personalVehicle?.computedCo2GPerKm ?? 192.0,
            gpsIntervalSeconds: event.profile.gpsIntervalSeconds,
          ),
        ),
      );
    }
  }

  ({double minLat, double minLon, double maxLat, double maxLon, int zoom})
  _defaultBboxForPosition(({double lat, double lon, double accuracy})? pos) {
    final centerLat = pos?.lat ?? 58.6035;
    final centerLon = pos?.lon ?? 49.6680;
    return (
      minLat: centerLat - 0.08,
      minLon: centerLon - 0.12,
      maxLat: centerLat + 0.08,
      maxLon: centerLon + 0.12,
      zoom: 13,
    );
  }

  static String _todayIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<void> close() async {
    await _posSub?.cancel();
    await _summarySub?.cancel();
    await _profileSub?.cancel();
    await super.close();
  }
}
