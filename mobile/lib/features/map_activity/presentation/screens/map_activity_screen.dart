import 'dart:async';
import 'dart:math' as math;

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:ecotrack_mobile/core/utils/polyline_simplifier.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/map_activity_bloc.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

final class const MapActivityScreen({
  final MapScreenMode initialMode = .myRoutes,
  final String? initialDateIso,
  super.key,
}) extends StatefulWidget {
  @override
  State<MapActivityScreen> createState() => _MapActivityScreenState();
}

final class _MapActivityScreenState() extends State<MapActivityScreen> {
  final MapController _mapController = MapController();
  final LayerHitNotifier<int> _segmentHitNotifier = ValueNotifier(null);
  final CacheStore _tileCacheStore = MemCacheStore();

  StreamSubscription<MapEvent>? _mapEventSub;
  Timer? _bboxDebounceTimer;
  double _currentZoom = 13.0;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<MapActivityBloc>();
    final initialDate = widget.initialDateIso;
    if (bloc.state is MapActivityLoading) {
      bloc.add(
        MapStarted(
          initialMode: widget.initialMode,
          initialDateIso: initialDate,
        ),
      );
    } else if (initialDate != null) {
      bloc.add(MapDateSelected(initialDate));
    }

    _segmentHitNotifier.addListener(_onPolylineHitChanged);
    _mapEventSub = _mapController.mapEventStream.listen(_onMapEvent);
  }

  @override
  void didUpdateWidget(covariant MapActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bloc = context.read<MapActivityBloc>();
    if (oldWidget.initialMode != widget.initialMode) {
      bloc.add(MapModeToggled(widget.initialMode));
    }
    final nextDate = widget.initialDateIso;
    if (oldWidget.initialDateIso != nextDate && nextDate != null) {
      bloc.add(MapDateSelected(nextDate));
    }
  }

  @override
  void dispose() {
    _bboxDebounceTimer?.cancel();
    unawaited(_mapEventSub?.cancel());
    _segmentHitNotifier
      ..removeListener(_onPolylineHitChanged)
      ..dispose();
    _mapController.dispose();
    unawaited(_tileCacheStore.close());
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd || event is MapEventRotateEnd) {
      _currentZoom = event.camera.zoom;
      final state = context.read<MapActivityBloc>().state;
      if (state is! MapActivityReady || state.mode != .recyclingMap) {
        return;
      }
      _bboxDebounceTimer?.cancel();
      _bboxDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        final bounds = _mapController.camera.visibleBounds;
        context.read<MapActivityBloc>().add(
          MapWastePointsBboxChanged(
            minLat: bounds.south,
            minLon: bounds.west,
            maxLat: bounds.north,
            maxLon: bounds.east,
            zoom: _mapController.camera.zoom.round().clamp(3, 20),
          ),
        );
      });
    }
  }

  void _onPolylineHitChanged() {
    final hit = _segmentHitNotifier.value;
    final state = context.read<MapActivityBloc>().state;
    if (hit == null || state is! MapActivityReady || state.mode != .myRoutes) {
      return;
    }
    final hitIndex = hit.hitValues.firstOrNull;
    final detail = state.routeView.detail;
    if (hitIndex == null || detail == null) return;
    if (hitIndex < 0) {
      EcoTopBannerOverlay.instance.showMessage(
        'Участок на транспорте (высокая скорость без шагов) не может быть отмечен как пеший.',
      );
      return;
    }
    if (hitIndex < detail.allocations.length) {
      unawaited(
        _openTransportSheet(
          state: state,
          existingAllocation: detail.allocations[hitIndex],
        ),
      );
    }
  }

  Future<void> _openTransportSheet({
    required MapActivityReady state,
    RouteSegmentAllocationItem? existingAllocation,
  }) async {
    final detail = state.routeView.detail;
    if (detail == null || detail.trackPoints.length < 2) {
      EcoTopBannerOverlay.instance.showMessage(
        'За выбранный день недостаточно GPS-точек для разметки участка.',
      );
      return;
    }
    final bloc = context.read<MapActivityBloc>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EcoColors.surfacePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: .vertical(top: .circular(28)),
      ),
      builder: (_) => BlocProvider<MapActivityBloc>.value(
        value: bloc,
        child: _TransportAllocationBottomSheet(
          detail: detail,
          presets: state.routeView.presets,
          userCarGPerKm: state.routeView.userCarGPerKm,
          existingAllocation: existingAllocation,
        ),
      ),
    );
  }

  Future<void> _openGpsIntervalPicker(MapActivityReady ready) async {
    final bloc = context.read<MapActivityBloc>();
    const options = [5, 15, 30, 60];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EcoColors.surfacePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: .vertical(top: .circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const .fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              const Text(
                'Интервал записи GPS',
                style: EcoTypography.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options
                    .map(
                      (sec) => ChoiceChip(
                        label: Text('$sec сек'),
                        selected: ready.routeView.gpsIntervalSeconds == sec,
                        onSelected: (_) {
                          Navigator.of(ctx).pop();
                          bloc.add(MapGpsIntervalChanged(sec));
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  bloc.add(const MapGpsToggled());
                },
                child: const Text('Выключить запись GPS'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSuggestPointModal(MapActivityReady ready) async {
    final bloc = context.read<MapActivityBloc>();
    final center = _mapController.camera.center;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EcoColors.surfacePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: .vertical(top: .circular(28)),
      ),
      builder: (_) => BlocProvider<MapActivityBloc>.value(
        value: bloc,
        child: _SuggestWastePointSheet(initialCenter: center),
      ),
    );
  }

  Future<void> _openExternalNavigator(WastePointDetail point) async {
    final title = Uri.encodeComponent(point.title);
    final candidates = [
      Uri.parse(
        'yandexmaps://maps.yandex.ru/?rtext=~${point.lat},${point.lon}&rtt=pd',
      ),
      Uri.parse(
        'dgis://2gis.ru/routeSearch/rsType/pedestrian/to/${point.lon},${point.lat}',
      ),
      Uri.parse(
        'geo:${point.lat},${point.lon}?q=${point.lat},${point.lon}($title)',
      ),
    ];
    for (final uri in candidates) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: .externalApplication);
        return;
      }
    }
    EcoTopBannerOverlay.instance.showMessage(
      'Не найдено установленное приложение карт для построения маршрута.',
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<MapActivityBloc, MapActivityState>(
        listenWhen: (prev, curr) {
          if (curr is! MapActivityReady) return false;
          if (prev is! MapActivityReady) return true;
          return prev.bannerError != curr.bannerError ||
              prev.feedbackMessage != curr.feedbackMessage ||
              prev.wasteView.selectedPoint != curr.wasteView.selectedPoint;
        },
        listener: (context, state) {
          if (state case final MapActivityReady ready) {
            if (ready.bannerError case final err?) {
              EcoErrorBannerPresenter.show(context, err);
              context.read<MapActivityBloc>().add(const MapFeedbackCleared());
            } else if (ready.feedbackMessage case final msg?) {
              EcoTopBannerOverlay.instance.showMessage(msg);
              context.read<MapActivityBloc>().add(const MapFeedbackCleared());
            }
          }
        },
        builder: (context, state) => Scaffold(
          backgroundColor: EcoColors.surfacePrimary,
          body: switch (state) {
            MapActivityLoading() => const Center(
              child: CircularProgressIndicator(color: EcoColors.inkPrimary),
            ),
            MapActivityReady() => _MapViewportStack(
              ready: state,
              mapController: _mapController,
              tileCacheStore: _tileCacheStore,
              segmentHitNotifier: _segmentHitNotifier,
              currentZoom: _currentZoom,
              onOpenGpsInterval: () => unawaited(_openGpsIntervalPicker(state)),
              onOpenTransportSheet: () =>
                  unawaited(_openTransportSheet(state: state)),
              onOpenSuggestModal: () =>
                  unawaited(_openSuggestPointModal(state)),
              onNavigatePoint: (pt) => unawaited(_openExternalNavigator(pt)),
            ),
          },
        ),
      );
}

final class const _MapViewportStack({
  required final MapActivityReady ready,
  required final MapController mapController,
  required final CacheStore tileCacheStore,
  required final LayerHitNotifier<int> segmentHitNotifier,
  required final double currentZoom,
  required final VoidCallback onOpenGpsInterval,
  required final VoidCallback onOpenTransportSheet,
  required final VoidCallback onOpenSuggestModal,
  required final ValueChanged<WastePointDetail> onNavigatePoint,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pos = ready.currentPosition;
    final initialCenter = pos != null
        ? LatLng(pos.lat, pos.lon)
        : const LatLng(58.6035, 49.6680);
    final selectedWaste = ready.wasteView.selectedPoint;

    return Stack(
      children: [
        RepaintBoundary(
          child: FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              minZoom: 3.0,
              maxZoom: 19.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ru.ecotrack.mobile',
                tileProvider: CachedTileProvider(
                  store: tileCacheStore,
                  maxStale: const Duration(days: 14),
                ),
              ),
              if (ready.mode == .myRoutes) ...[
                _RoutesPolylineLayer(
                  detail: ready.routeView.detail,
                  hitNotifier: segmentHitNotifier,
                ),
                _RoutesBadgesMarkerLayer(detail: ready.routeView.detail),
              ] else
                _WasteClusterMapLayer(
                  points: ready.wasteView.points,
                  currentZoom: currentZoom,
                ),
              if (pos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(pos.lat, pos.lon),
                      width: 22,
                      height: 22,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: EcoColors.inkPrimary,
                          shape: .circle,
                          border: .fromBorderSide(
                            BorderSide(
                              color: EcoColors.surfacePrimary,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(ready.wasteView.attributionBannerRu),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const .fromLTRB(16, 10, 16, 8),
                child: _TopModeToggleBar(
                  mode: ready.mode,
                  onModeSelected: (m) =>
                      context.read<MapActivityBloc>().add(MapModeToggled(m)),
                ),
              ),
              if (ready.mode == .myRoutes)
                _RoutesSubHeaderControls(
                  routeView: ready.routeView,
                  onOpenGpsInterval: onOpenGpsInterval,
                )
              else
                _FractionFilterBar(
                  activeFilters: ready.wasteView.activeFilters,
                  isLoading: ready.wasteView.isLoadingPoints,
                ),
            ],
          ),
        ),
        if (ready.mode == .myRoutes)
          Positioned(
            left: 16,
            right: 16,
            bottom: 102,
            child: _RoutesBottomOverlayCard(
              routeView: ready.routeView,
              onOpenTransportSheet: onOpenTransportSheet,
            ),
          )
        else ...[
          if (ready.wasteView.points.isEmpty &&
              !ready.wasteView.isLoadingPoints)
            Positioned(
              left: 16,
              right: 16,
              bottom: 170,
              child: _EmptyWastePointsPill(
                onResetFilters: () => context.read<MapActivityBloc>().add(
                  const MapFractionToggled(null),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 112,
            child: Column(
              crossAxisAlignment: .end,
              children: [
                FloatingActionButton(
                  heroTag: 'locate_me',
                  backgroundColor: EcoColors.surfacePrimary,
                  foregroundColor: EcoColors.inkPrimary,
                  onPressed: () {
                    context.read<MapActivityBloc>().add(
                      const MapLocateMeRequested(),
                    );
                    if (pos != null) {
                      mapController.move(LatLng(pos.lat, pos.lon), 15.0);
                    }
                  },
                  child: const Icon(LucideIcons.locateFixed, size: 22),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: onOpenSuggestModal,
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Предложить точку'),
                ),
              ],
            ),
          ),
        ],
        if (selectedWaste != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _WastePointDetailSheet(
              point: selectedWaste,
              isSubmitting: ready.isSubmitting,
              onClose: () => context.read<MapActivityBloc>().add(
                const MapWastePointClosed(),
              ),
              onNavigate: () => onNavigatePoint(selectedWaste),
            ),
          ),
      ],
    );
  }
}

final class const _RoutesPolylineLayer({
  required final DailyActivityDetail? detail,
  required final LayerHitNotifier<int> hitNotifier,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentDetail = detail;
    if (currentDetail == null || currentDetail.trackPoints.isEmpty) {
      return const SizedBox.shrink();
    }
    final polylines = <Polyline<int>>[];
    final walkingPts = currentDetail.trackPoints
        .where((p) => p.motionClass == .walking)
        .map((p) => LatLng(p.lat, p.lon))
        .toList();
    final simplifiedWalk = walkingPts.length > 2000
        ? PolylineSimplifier.simplifyRdp(walkingPts)
        : walkingPts;
    if (simplifiedWalk.length >= 2) {
      polylines.add(
        Polyline<int>(
          points: simplifiedWalk,
          color: EcoColors.inkPrimary,
          strokeWidth: 4.5,
          pattern: StrokePattern.dashed(segments: const [10, 6]),
          hitValue: 0,
        ),
      );
    }
    final vehiclePts = currentDetail.trackPoints
        .where((p) => p.motionClass == .vehicleSuspected)
        .map((p) => LatLng(p.lat, p.lon))
        .toList();
    if (vehiclePts.length >= 2) {
      polylines.add(
        Polyline<int>(
          points: vehiclePts,
          color: EcoColors.fillDisabled,
          strokeWidth: 2.5,
          hitValue: -1,
        ),
      );
    }
    for (var i = 0; i < currentDetail.allocations.length; i++) {
      final coords = currentDetail.allocations[i].coordinates
          .map((c) => LatLng(c.lat, c.lon))
          .toList();
      if (coords.length >= 2) {
        polylines.add(
          Polyline<int>(
            points: coords,
            color: EcoColors.inkPrimary,
            strokeWidth: 6.5,
            borderColor: EcoColors.surfacePrimary,
            borderStrokeWidth: 2.0,
            hitValue: i,
          ),
        );
      }
    }
    return PolylineLayer<int>(polylines: polylines, hitNotifier: hitNotifier);
  }
}

final class const _RoutesBadgesMarkerLayer({
  required final DailyActivityDetail? detail,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentDetail = detail;
    if (currentDetail == null || currentDetail.allocations.isEmpty) {
      return const SizedBox.shrink();
    }
    final badgeMarkers = <Marker>[];
    for (final alloc in currentDetail.allocations) {
      final coords = alloc.coordinates
          .map((c) => LatLng(c.lat, c.lon))
          .toList();
      if (coords.length >= 2) {
        badgeMarkers.add(
          Marker(
            point: coords[coords.length ~/ 2],
            width: 120,
            height: 30,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: EcoColors.inkPrimary,
                borderRadius: .all(.circular(999)),
              ),
              child: Center(
                child: Text(
                  '${alloc.replacedTransportMode.shortLabelRu} · -${alloc.co2SavedGrams} г',
                  style: EcoTypography.labelSmall.copyWith(
                    color: EcoColors.surfacePrimary,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return MarkerLayer(markers: badgeMarkers);
  }
}

final class const _WasteClusterMapLayer({
  required final List<WastePointMapItem> points,
  required final double currentZoom,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final markers = points
        .map(
          (pt) => Marker(
            point: LatLng(pt.lat, pt.lon),
            width: 48,
            height: 48,
            child: GestureDetector(
              onTap: () => context.read<MapActivityBloc>().add(
                MapWastePointTapped(pt.id),
              ),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: EcoColors.surfacePrimary,
                    shape: .circle,
                    border: .fromBorderSide(
                      BorderSide(
                        color: pt.status == .unverified || pt.trustScore < 50
                            ? EcoColors.inkSecondary
                            : EcoColors.inkPrimary,
                        width: 2,
                      ),
                    ),
                  ),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      LucideIcons.recycle,
                      size: 20,
                      color: EcoColors.inkPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();

    final radius = currentZoom <= 12 ? 80 : 45;
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: radius,
        size: const Size(48, 48),
        markers: markers,
        builder: (context, clusterMarkers) => DecoratedBox(
          decoration: const BoxDecoration(
            color: EcoColors.inkPrimary,
            shape: .circle,
          ),
          child: Center(
            child: Text(
              '${clusterMarkers.length}',
              style: EcoTypography.labelSmall.copyWith(
                color: EcoColors.surfacePrimary,
                fontWeight: .w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class const _TopModeToggleBar({
  required final MapScreenMode mode,
  required final ValueChanged<MapScreenMode> onModeSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfacePrimary,
      borderRadius: .all(.circular(999)),
      border: .fromBorderSide(
        BorderSide(color: EcoColors.inkPrimary, width: 1.5),
      ),
    ),
    child: SizedBox(
      height: 52,
      child: Padding(
        padding: const .all(4),
        child: Row(
          children: [
            _ModeToggleSegment(
              label: 'Мои маршруты',
              selected: mode == .myRoutes,
              onTap: () => onModeSelected(.myRoutes),
            ),
            _ModeToggleSegment(
              label: 'Пункты РСО',
              selected: mode == .recyclingMap,
              onTap: () => onModeSelected(.recyclingMap),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _ModeToggleSegment({
  required final String label,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: const .all(.circular(999)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? EcoColors.inkPrimary : Colors.transparent,
          borderRadius: const .all(.circular(999)),
        ),
        child: Center(
          child: Text(
            label,
            style: EcoTypography.bodyMedium.copyWith(
              color: selected ? EcoColors.surfacePrimary : EcoColors.inkPrimary,
              fontWeight: .w600,
            ),
          ),
        ),
      ),
    ),
  );
}

final class const _RoutesSubHeaderControls({
  required final MapRouteViewState routeView,
  required final VoidCallback onOpenGpsInterval,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayIso = _fmtDate(now);
    final yesterdayIso = _fmtDate(now.subtract(const Duration(days: 1)));
    final bloc = context.read<MapActivityBloc>();

    return Padding(
      padding: const .symmetric(horizontal: 16),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Сегодня'),
            selected: routeView.selectedDateIso == todayIso,
            onSelected: (_) => bloc.add(MapDateSelected(todayIso)),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Вчера'),
            selected: routeView.selectedDateIso == yesterdayIso,
            onSelected: (_) => bloc.add(MapDateSelected(yesterdayIso)),
          ),
          const Spacer(),
          ActionChip(
            label: Text(
              routeView.isGpsEnabled
                  ? '● GPS (${routeView.gpsIntervalSeconds} с)'
                  : '○ GPS выкл.',
              style: EcoTypography.labelSmall.copyWith(
                color: EcoColors.inkPrimary,
              ),
            ),
            backgroundColor: EcoColors.surfacePrimary,
            side: const BorderSide(color: EcoColors.borderMuted, width: 1.5),
            onPressed: routeView.isGpsEnabled
                ? onOpenGpsInterval
                : () => bloc.add(const MapGpsToggled()),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

final class const _FractionFilterBar({
  required final Set<WasteFractionCode> activeFilters,
  required final bool isLoading,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.read<MapActivityBloc>();
    return Column(
      mainAxisSize: .min,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: .horizontal,
            padding: const .symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const .only(right: 6),
                child: ChoiceChip(
                  label: const Text('Все'),
                  selected: activeFilters.isEmpty,
                  onSelected: (_) => bloc.add(const MapFractionToggled(null)),
                ),
              ),
              for (final fraction in WasteFractionCode.values)
                Padding(
                  padding: const .only(right: 6),
                  child: FilterChip(
                    label: Text(fraction.labelRu),
                    selected: activeFilters.contains(fraction),
                    onSelected: (_) => bloc.add(MapFractionToggled(fraction)),
                  ),
                ),
            ],
          ),
        ),
        if (isLoading)
          const Padding(
            padding: .only(top: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: EcoColors.surfacePrimary,
                borderRadius: .all(.circular(999)),
                border: .fromBorderSide(
                  BorderSide(color: EcoColors.borderMuted, width: 1),
                ),
              ),
              child: Padding(
                padding: .symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  'Загрузка пунктов РСО...',
                  style: EcoTypography.labelSmall,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final class const _RoutesBottomOverlayCard({
  required final MapRouteViewState routeView,
  required final VoidCallback onOpenTransportSheet,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.read<MapActivityBloc>();
    final detail = routeView.detail;

    if (!routeView.isGpsEnabled &&
        (detail == null || detail.trackPoints.isEmpty)) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: EcoColors.surfacePrimary,
          borderRadius: .all(.circular(20)),
          border: .fromBorderSide(
            BorderSide(color: EcoColors.borderMuted, width: 1.5),
          ),
        ),
        child: Padding(
          padding: const .all(14),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              const Text(
                'Геолокация маршрутов выключена',
                style: EcoTypography.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Сейчас ваш эковклад рассчитывается автоматически по шагам: 80% дистанции приравнивается к замене автобуса с коэффициентом 0.7.',
                style: EcoTypography.labelSmall,
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => bloc.add(const MapGpsToggled()),
                child: const Text('Включить запись GPS-маршрута'),
              ),
            ],
          ),
        ),
      );
    }

    final ptsCount = detail?.trackPoints.length ?? 0;
    final totalCo2 = detail?.summary.totalCo2SavedGrams ?? 0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfacePrimary,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    ptsCount == 0
                        ? 'Маршрут за день ещё не записан'
                        : 'Точек маршрута: $ptsCount',
                    style: EcoTypography.bodyLarge,
                  ),
                  Text(
                    'Экономия CO₂: $totalCo2 г',
                    style: EcoTypography.labelSmall,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: ptsCount >= 2 ? onOpenTransportSheet : null,
              child: const Text('Указать транспорт'),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _EmptyWastePointsPill({
  required final VoidCallback onResetFilters,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfacePrimary,
      borderRadius: .all(.circular(20)),
      border: .fromBorderSide(
        BorderSide(color: EcoColors.borderMuted, width: 1.5),
      ),
    ),
    child: Padding(
      padding: const .symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'В этой области карты пункты РСО не найдены',
              style: EcoTypography.labelSmall,
            ),
          ),
          TextButton(
            onPressed: onResetFilters,
            child: const Text('Сбросить фильтры'),
          ),
        ],
      ),
    ),
  );
}

final class const _TransportAllocationBottomSheet({
  required final DailyActivityDetail detail,
  required final List<TransportPresetItem> presets,
  required final double userCarGPerKm,
  final RouteSegmentAllocationItem? existingAllocation,
}) extends StatefulWidget {
  @override
  State<_TransportAllocationBottomSheet> createState() =>
      _TransportAllocationBottomSheetState();
}

final class _TransportAllocationBottomSheetState()
    extends State<_TransportAllocationBottomSheet> {
  late int _startSeq;
  late int _endSeq;
  late TransportModeCode _selectedMode;
  bool _showCarPresets = false;

  @override
  void initState() {
    super.initState();
    final minSeq = widget.detail.trackPoints.first.seqNo;
    final maxSeq = widget.detail.trackPoints.last.seqNo;
    _startSeq = widget.existingAllocation?.startSeqNo ?? minSeq;
    _endSeq = widget.existingAllocation?.endSeqNo ?? maxSeq;
    _selectedMode = widget.existingAllocation?.replacedTransportMode ?? .bus;
    _showCarPresets =
        _selectedMode == .carCompact ||
        _selectedMode == .carSedan ||
        _selectedMode == .carSuv ||
        _selectedMode == .carEv;
  }

  double _rateForMode(TransportModeCode mode) {
    if (mode == .personalCar) {
      return widget.userCarGPerKm / 1000.0;
    }
    for (final p in widget.presets) {
      if (p.modeCode == mode) {
        return p.co2GramsPerMeter;
      }
    }
    return mode.defaultCo2GramsPerMeter;
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.detail.trackPoints
        .where((p) => p.seqNo >= _startSeq && p.seqNo <= _endSeq)
        .toList();
    final distM = math.max(
      1.0,
      pts.fold<double>(0.0, (acc, p) => acc + p.deltaDistanceM),
    );
    final steps = pts.fold<int>(0, (acc, p) => acc + p.deltaSteps);
    final exactCo2 = Co2Math.computeSegmentCo2Grams(
      distM,
      _rateForMode(_selectedMode),
    );
    final autoFallbackCo2 = Co2Math.computeAutoDefaultCo2Grams(distM);
    final deltaCo2 = exactCo2 - autoFallbackCo2;
    final bloc = context.read<MapActivityBloc>();
    final existing = widget.existingAllocation;

    return SafeArea(
      child: Padding(
        padding: const .fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Text(
              'Участок маршрута: ${distM.round()} м ($steps шагов)',
              style: EcoTypography.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Укажите, вместо какого транспорта вы прошли пешком:',
              style: EcoTypography.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TransportChipItem(
                  label: 'Автобус (82 г/км)',
                  selected: _selectedMode == .bus,
                  onSelected: () => setState(() => _selectedMode = .bus),
                ),
                _TransportChipItem(
                  label: 'Метро (28 г/км)',
                  selected: _selectedMode == .metro,
                  onSelected: () => setState(() => _selectedMode = .metro),
                ),
                _TransportChipItem(
                  label: 'Трамвай (35 г/км)',
                  selected: _selectedMode == .tram,
                  onSelected: () => setState(() => _selectedMode = .tram),
                ),
                _TransportChipItem(
                  label: 'Мой авто (${widget.userCarGPerKm.round()} г/км)',
                  selected: _selectedMode == .personalCar,
                  onSelected: () =>
                      setState(() => _selectedMode = .personalCar),
                ),
                ChoiceChip(
                  label: const Text('Авто (средний)'),
                  selected: _showCarPresets,
                  onSelected: (sel) => setState(() {
                    _showCarPresets = sel;
                    if (sel) _selectedMode = .carSedan;
                  }),
                ),
              ],
            ),
            if (_showCarPresets) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TransportChipItem(
                    label: 'Компакт (145 г/км)',
                    selected: _selectedMode == .carCompact,
                    onSelected: () =>
                        setState(() => _selectedMode = .carCompact),
                  ),
                  _TransportChipItem(
                    label: 'Седан (192 г/км)',
                    selected: _selectedMode == .carSedan,
                    onSelected: () => setState(() => _selectedMode = .carSedan),
                  ),
                  _TransportChipItem(
                    label: 'Кроссовер (255 г/км)',
                    selected: _selectedMode == .carSuv,
                    onSelected: () => setState(() => _selectedMode = .carSuv),
                  ),
                  _TransportChipItem(
                    label: 'Электро (58 г/км)',
                    selected: _selectedMode == .carEv,
                    onSelected: () => setState(() => _selectedMode = .carEv),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: EcoColors.surfaceSubtle,
                borderRadius: .all(.circular(16)),
              ),
              child: Padding(
                padding: const .all(12),
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      'Расчёт по выбранному транспорту (коэф. 1.0): $exactCo2 г CO₂',
                      style: EcoTypography.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Вместо базового авторасчёта (80% × автобус × 0.7): ${deltaCo2 >= 0 ? '+$deltaCo2' : '$deltaCo2'} г CO₂',
                      style: EcoTypography.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: widget.detail.isEditable
                  ? () {
                      bloc.add(
                        MapAllocationsSaved([
                          RouteSegmentAllocationInput(
                            idempotencyKey: UuidV7.generate(),
                            startSeqNo: _startSeq,
                            endSeqNo: _endSeq,
                            replacedTransportMode: _selectedMode,
                          ),
                        ]),
                      );
                      Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('Сохранить участок'),
            ),
            if (existing != null && widget.detail.isEditable) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  bloc.add(MapAllocationDeleted(existing.id));
                  Navigator.of(context).pop();
                },
                child: const Text('Удалить разметку участка'),
              ),
            ],
            if (_selectedMode == .personalCar)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/profile/vehicle');
                },
                child: const Text('Настроить параметры моего авто'),
              ),
          ],
        ),
      ),
    );
  }
}

final class const _TransportChipItem({
  required final String label,
  required final bool selected,
  required final VoidCallback onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
}

final class const _WastePointDetailSheet({
  required final WastePointDetail point,
  required final bool isSubmitting,
  required final VoidCallback onClose,
  required final VoidCallback onNavigate,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.read<MapActivityBloc>();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfacePrimary,
        borderRadius: .vertical(top: .circular(28)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const .fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(point.title, style: EcoTypography.titleMedium),
                  ),
                  Chip(label: Text('Доверие ${point.trustScore.round()}%')),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              Text(
                '${point.status.labelRu} · Подтверждений: ${point.confirmationsCount}',
                style: EcoTypography.labelSmall,
              ),
              if (point.addressText case final address?) ...[
                const SizedBox(height: 4),
                Text(address, style: EcoTypography.bodyMedium),
              ],
              if (point.openingHours case final hours?) ...[
                const SizedBox(height: 2),
                Text(hours, style: EcoTypography.labelSmall),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: point.acceptedFractions
                    .map((f) => Chip(label: Text(f.labelRu)))
                    .toList(),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: onNavigate,
                icon: const Icon(LucideIcons.navigation, size: 18),
                label: const Text('Построить маршрут во внешнем навигаторе'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Актуальна ли точка?',
                style: EcoTypography.labelSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    [
                          ReportType.confirmWorking,
                          ReportType.overflowing,
                          ReportType.missingBin,
                          ReportType.wrongFractions,
                        ]
                        .map(
                          (reportType) => ActionChip(
                            label: Text(reportType.labelRu),
                            onPressed: isSubmitting
                                ? null
                                : () => bloc.add(
                                    MapWasteReportSubmitted(
                                      pointId: point.id,
                                      reportType: reportType,
                                    ),
                                  ),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class const _SuggestWastePointSheet({required final LatLng initialCenter})
    extends StatefulWidget {
  @override
  State<_SuggestWastePointSheet> createState() =>
      _SuggestWastePointSheetState();
}

final class _SuggestWastePointSheetState()
    extends State<_SuggestWastePointSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final Set<WasteFractionCode> _selectedFractions = {.plastic};

  @override
  void dispose() {
    _titleController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<MapActivityBloc>();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              const Text(
                'Предложить новую точку РСО',
                style: EcoTypography.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Координаты: ${widget.initialCenter.latitude.toStringAsFixed(5)}, ${widget.initialCenter.longitude.toStringAsFixed(5)}',
                style: EcoTypography.labelSmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Название пункта (например, Сетка у подъезда)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hoursController,
                decoration: const InputDecoration(
                  labelText: 'Режим работы (опционально)',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: WasteFractionCode.values
                    .map(
                      (f) => FilterChip(
                        label: Text(f.labelRu),
                        selected: _selectedFractions.contains(f),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _selectedFractions.add(f);
                          } else if (_selectedFractions.length > 1) {
                            _selectedFractions.remove(f);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final title = _titleController.text.trim();
                  if (title.isEmpty) return;
                  bloc.add(
                    MapWastePointSuggested(
                      SuggestWastePointRequest(
                        title: title,
                        openingHours: _hoursController.text.trim(),
                        acceptedFractions: _selectedFractions.toList(),
                        lat: widget.initialCenter.latitude,
                        lon: widget.initialCenter.longitude,
                      ),
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('Отправить на карту'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
