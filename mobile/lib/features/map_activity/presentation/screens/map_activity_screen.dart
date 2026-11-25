import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:path_provider/path_provider.dart';
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
  final CacheStore _tileCacheStore = BackupCacheStore(
    primary: MemCacheStore(
      maxSize: 16 * 1024 * 1024,
      maxEntrySize: 1024 * 1024,
    ),
    secondary: _FileTileCacheStore(),
  );

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
    if (hitIndex == -1) {
      EcoTopBannerOverlay.instance.showMessage(
        'Участок на транспорте (высокая скорость без шагов) не может быть отмечен как пеший.',
      );
      return;
    }
    if (hitIndex == -2) {
      EcoTopBannerOverlay.instance.showMessage(
        'Движение в помещении · автоформула',
      );
      return;
    }
    if (hitIndex < 0) {
      final runs = _extractUnallocatedWalkingRuns(detail);
      final runIdx = -100 - hitIndex;
      final matched = (runIdx >= 0 && runIdx < runs.length)
          ? runs[runIdx]
          : null;
      unawaited(
        _openTransportSheet(
          state: state,
          initialRange: matched != null
              ? (startSeq: matched.startSeq, endSeq: matched.endSeq)
              : null,
        ),
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
    ({int startSeq, int endSeq})? initialRange,
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
          initialRange: initialRange,
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
        child: _SuggestWastePointSheet(
          initialCenter: center,
          tileCacheStore: _tileCacheStore,
        ),
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

List<({int startSeq, int endSeq, List<LatLng> points})>
_extractUnallocatedWalkingRuns(DailyActivityDetail detail) {
  final pts = detail.trackPoints;
  final runs = <({int startSeq, int endSeq, List<LatLng> points})>[];
  var i = 0;
  while (i < pts.length) {
    final p = pts[i];
    final isAllocated = detail.allocations.any(
      (a) => p.seqNo > a.startSeqNo && p.seqNo <= a.endSeqNo,
    );
    if (p.motionClass == .walking && !isAllocated) {
      final startIdx = i > 0 ? i - 1 : i;
      var endIdx = i;
      while (endIdx + 1 < pts.length) {
        final next = pts[endIdx + 1];
        final nextAllocated = detail.allocations.any(
          (a) => next.seqNo > a.startSeqNo && next.seqNo <= a.endSeqNo,
        );
        if (next.motionClass == .walking && !nextAllocated) {
          endIdx++;
        } else {
          break;
        }
      }
      final rawCoords = <LatLng>[
        for (var k = startIdx; k <= endIdx; k++) LatLng(pts[k].lat, pts[k].lon),
      ];
      if (rawCoords.length >= 2) {
        final simplified = rawCoords.length > 2000
            ? PolylineSimplifier.simplifyRdp(rawCoords)
            : rawCoords;
        runs.add((
          startSeq: pts[startIdx].seqNo,
          endSeq: pts[endIdx].seqNo,
          points: simplified,
        ));
      }
      i = endIdx + 1;
    } else {
      i++;
    }
  }
  return runs;
}

List<List<LatLng>> _extractIndoorPacingRuns(DailyActivityDetail detail) {
  final pts = detail.trackPoints;
  final runs = <List<LatLng>>[];
  var i = 0;
  while (i < pts.length) {
    if (pts[i].motionClass == .indoorPacing) {
      final coords = <LatLng>[LatLng(pts[i].lat, pts[i].lon)];
      while (i + 1 < pts.length && pts[i + 1].motionClass == .indoorPacing) {
        i++;
        coords.add(LatLng(pts[i].lat, pts[i].lon));
      }
      runs.add(coords);
    }
    i++;
  }
  return runs;
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
    final walkingRuns = _extractUnallocatedWalkingRuns(currentDetail);
    for (var i = 0; i < walkingRuns.length; i++) {
      polylines.add(
        Polyline<int>(
          points: walkingRuns[i].points,
          color: EcoColors.inkPrimary,
          strokeWidth: 4.5,
          pattern: StrokePattern.dashed(segments: const [10, 6]),
          hitValue: -100 - i,
        ),
      );
    }
    final indoorRuns = _extractIndoorPacingRuns(currentDetail);
    for (final run in indoorRuns) {
      if (run.length >= 2) {
        polylines.add(
          Polyline<int>(
            points: run,
            color: EcoColors.inkSecondary,
            strokeWidth: 3.0,
            pattern: const StrokePattern.dotted(),
            hitValue: -2,
          ),
        );
      }
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
    if (currentDetail == null) {
      return const SizedBox.shrink();
    }
    final markers = <Marker>[];
    final indoorRuns = _extractIndoorPacingRuns(currentDetail);
    for (final run in indoorRuns) {
      final anchor = run[run.length ~/ 2];
      markers.add(
        Marker(
          point: anchor,
          width: 48,
          height: 48,
          child: Tooltip(
            message: 'Движение в помещении · автоформула',
            child: GestureDetector(
              onTap: () => EcoTopBannerOverlay.instance.showMessage(
                'Движение в помещении · автоформула',
              ),
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: EcoColors.inkSecondary,
                      shape: .circle,
                      border: .fromBorderSide(
                        BorderSide(color: EcoColors.surfacePrimary, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    for (final alloc in currentDetail.allocations) {
      final coords = alloc.coordinates
          .map((c) => LatLng(c.lat, c.lon))
          .toList();
      if (coords.length >= 2) {
        markers.add(
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
    if (markers.isEmpty) {
      return const SizedBox.shrink();
    }
    return MarkerLayer(markers: markers);
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
            child: _WastePinMarker(
              isUnverified: pt.status == .unverified || pt.trustScore < 60,
              onTap: () => context.read<MapActivityBloc>().add(
                MapWastePointTapped(pt.id),
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

final class const _WastePinMarker({
  required final bool isUnverified,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Center(
      child: Stack(
        clipBehavior: .none,
        children: [
          if (isUnverified)
            const CustomPaint(
              painter: _DashedCircleBorderPainter(
                color: EcoColors.inkSecondary,
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: EcoColors.surfacePrimary,
                    shape: .circle,
                  ),
                  child: Icon(
                    LucideIcons.recycle,
                    size: 19,
                    color: EcoColors.inkSecondary,
                  ),
                ),
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                color: EcoColors.surfacePrimary,
                shape: .circle,
                border: .fromBorderSide(
                  BorderSide(color: EcoColors.inkPrimary, width: 2),
                ),
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  LucideIcons.recycle,
                  size: 20,
                  color: EcoColors.inkPrimary,
                ),
              ),
            ),
          if (isUnverified)
            Positioned(
              right: -2,
              top: -2,
              child: SizedBox(
                width: 17,
                height: 17,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: EcoColors.inkPrimary,
                    shape: .circle,
                    border: .fromBorderSide(
                      BorderSide(color: EcoColors.surfacePrimary, width: 1.5),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '?',
                      style: EcoTypography.labelSmall.copyWith(
                        fontSize: 10,
                        fontWeight: .w700,
                        color: EcoColors.surfacePrimary,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

final class const _DashedCircleBorderPainter({required final Color color})
    extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 2.0;
    const dashCount = 12;
    const step = (math.pi * 2) / dashCount;
    const sweep = step * 0.58;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(rect, i * step, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCircleBorderPainter oldDelegate) =>
      oldDelegate.color != color;
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
          child: Padding(
            padding: const .symmetric(horizontal: 6),
            child: FittedBox(
              fit: .scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: EcoTypography.bodyMedium.copyWith(
                  fontSize: 13,
                  color: selected
                      ? EcoColors.surfacePrimary
                      : EcoColors.inkPrimary,
                  fontWeight: .w600,
                ),
              ),
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
  final ({int startSeq, int endSeq})? initialRange,
}) extends StatefulWidget {
  @override
  State<_TransportAllocationBottomSheet> createState() =>
      _TransportAllocationBottomSheetState();
}

final class _TransportAllocationBottomSheetState()
    extends State<_TransportAllocationBottomSheet> {
  late int _startIndex;
  late int _endIndex;
  late TransportModeCode _selectedMode;
  bool _showCarPresets = false;

  int get _startSeq => widget.detail.trackPoints[_startIndex].seqNo;
  int get _endSeq => widget.detail.trackPoints[_endIndex].seqNo;

  @override
  void initState() {
    super.initState();
    final pts = widget.detail.trackPoints;
    final targetStart =
        widget.existingAllocation?.startSeqNo ??
        widget.initialRange?.startSeq ??
        pts.first.seqNo;
    final targetEnd =
        widget.existingAllocation?.endSeqNo ??
        widget.initialRange?.endSeq ??
        pts.last.seqNo;
    final startIdx = pts.indexWhere((p) => p.seqNo >= targetStart);
    final endIdx = pts.lastIndexWhere((p) => p.seqNo <= targetEnd);
    _startIndex = (startIdx == -1 ? 0 : startIdx).clamp(0, pts.length - 2);
    _endIndex = (endIdx == -1 ? pts.length - 1 : endIdx).clamp(
      _startIndex + 1,
      pts.length - 1,
    );
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

  void _onRangeChanged(RangeValues values) {
    final maxIdx = widget.detail.trackPoints.length - 1;
    var nextStart = values.start.round().clamp(0, maxIdx - 1);
    var nextEnd = values.end.round().clamp(1, maxIdx);
    if (nextStart >= nextEnd) {
      if (nextStart != _startIndex) {
        nextStart = nextEnd - 1;
      } else {
        nextEnd = nextStart + 1;
      }
    }
    setState(() {
      _startIndex = nextStart;
      _endIndex = nextEnd;
    });
  }

  List<RouteSegmentAllocationInput> _buildAllocationPayload() {
    final existing = widget.existingAllocation;
    final start = _startSeq;
    final end = _endSeq;
    final preserved = <RouteSegmentAllocationInput>[
      for (final item in widget.detail.allocations)
        if (item.id != existing?.id &&
            (item.endSeqNo <= start || item.startSeqNo >= end))
          RouteSegmentAllocationInput(
            idempotencyKey: item.idempotencyKey,
            startSeqNo: item.startSeqNo,
            endSeqNo: item.endSeqNo,
            replacedTransportMode: item.replacedTransportMode,
          ),
      RouteSegmentAllocationInput(
        idempotencyKey: UuidV7.generate(),
        startSeqNo: start,
        endSeqNo: end,
        replacedTransportMode: _selectedMode,
      ),
    ]..sort((a, b) => a.startSeqNo.compareTo(b.startSeqNo));
    return preserved;
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.detail.trackPoints;
    final start = _startSeq;
    final end = _endSeq;
    final intervalPts = pts
        .where((p) => p.seqNo > start && p.seqNo <= end)
        .toList();
    final distM = math.max(
      1.0,
      intervalPts.fold<double>(0.0, (acc, p) => acc + p.deltaDistanceM),
    );
    final steps = intervalPts.fold<int>(0, (acc, p) => acc + p.deltaSteps);
    final hasVehicleMotion = intervalPts.any(
      (p) => p.motionClass == .vehicleSuspected,
    );
    final exactCo2 = Co2Math.computeSegmentCo2Grams(
      distM,
      _rateForMode(_selectedMode),
    );
    final autoFallbackCo2 = Co2Math.computeAutoDefaultCo2Grams(distM);
    final deltaCo2 = exactCo2 - autoFallbackCo2;
    final bloc = context.read<MapActivityBloc>();
    final existing = widget.existingAllocation;

    return SafeArea(
      child: SingleChildScrollView(
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
            if (pts.length > 2) ...[
              const SizedBox(height: 10),
              Text(
                'Границы участка: точки #$start — #$end',
                style: EcoTypography.labelSmall,
              ),
              RangeSlider(
                values: RangeValues(
                  _startIndex.toDouble(),
                  _endIndex.toDouble(),
                ),
                min: 0,
                max: (pts.length - 1).toDouble(),
                divisions: pts.length - 1,
                activeColor: EcoColors.inkPrimary,
                inactiveColor: EcoColors.surfaceCard,
                labels: RangeLabels('#$start', '#$end'),
                onChanged: _onRangeChanged,
              ),
            ],
            if (hasVehicleMotion) ...[
              const SizedBox(height: 4),
              Text(
                'Выбранный интервал включает участок транспорта без шагов — сдвиньте границы на пеший отрезок.',
                style: EcoTypography.labelSmall.copyWith(
                  color: EcoColors.inkPrimary,
                  fontWeight: .w700,
                ),
              ),
            ],
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
              onPressed: widget.detail.isEditable && !hasVehicleMotion
                  ? () {
                      bloc.add(MapAllocationsSaved(_buildAllocationPayload()));
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
  static String _formatVerifiedLabel(String? iso) {
    if (iso == null || iso.isEmpty) {
      return 'Ещё не проверялось пользователями';
    }
    final dt = DateTime.tryParse(iso);
    if (dt == null) {
      return 'Проверено недавно';
    }
    final daysAgo = DateTime.now().difference(dt.toLocal()).inDays;
    if (daysAgo <= 0) {
      return 'Проверено сегодня';
    }
    return 'Проверено $daysAgo дн. назад';
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<MapActivityBloc>();
    final verifiedLabel = _formatVerifiedLabel(point.lastVerifiedAt);
    final operatorText = point.operatorName?.trim();
    final hoursText = point.openingHours?.trim();

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
                '${point.status.labelRu} · $verifiedLabel · Подтверждений: ${point.confirmationsCount}',
                style: EcoTypography.labelSmall,
              ),
              if (point.addressText case final address?) ...[
                const SizedBox(height: 4),
                Text(address, style: EcoTypography.bodyMedium),
              ],
              if (operatorText != null && operatorText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Оператор: $operatorText',
                  style: EcoTypography.labelSmall,
                ),
              ],
              if (hoursText != null && hoursText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Режим работы: $hoursText',
                  style: EcoTypography.labelSmall,
                ),
              ],
              const SizedBox(height: 2),
              Text(
                'Источник: ${point.attributionText}',
                style: EcoTypography.labelSmall.copyWith(
                  color: EcoColors.inkSecondary,
                ),
              ),
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
                            label: Text(
                              reportType == .confirmWorking
                                  ? '${reportType.labelRu} (+15 ★)'
                                  : reportType.labelRu,
                            ),
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

final class const _SuggestWastePointSheet({
  required final LatLng initialCenter,
  required final CacheStore tileCacheStore,
}) extends StatefulWidget {
  @override
  State<_SuggestWastePointSheet> createState() =>
      _SuggestWastePointSheetState();
}

final class _SuggestWastePointSheetState()
    extends State<_SuggestWastePointSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final MapController _miniMapController = MapController();
  late final ValueNotifier<LatLng> _coordsNotifier;
  final Set<WasteFractionCode> _selectedFractions = {.plastic};

  @override
  void initState() {
    super.initState();
    _coordsNotifier = ValueNotifier(widget.initialCenter);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _hoursController.dispose();
    _miniMapController.dispose();
    _coordsNotifier.dispose();
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
              ValueListenableBuilder<LatLng>(
                valueListenable: _coordsNotifier,
                builder: (_, coords, _) => Text(
                  'Переместите карту или нажмите на точку: '
                  '${coords.latitude.toStringAsFixed(5)}, '
                  '${coords.longitude.toStringAsFixed(5)}',
                  style: EcoTypography.labelSmall,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 168,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    borderRadius: .all(.circular(16)),
                    border: .fromBorderSide(
                      BorderSide(color: EcoColors.borderMuted, width: 1.5),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const .all(.circular(15)),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _miniMapController,
                          options: MapOptions(
                            initialCenter: widget.initialCenter,
                            initialZoom: 16.0,
                            minZoom: 5.0,
                            maxZoom: 19.0,
                            interactionOptions: const InteractionOptions(
                              flags:
                                  InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                            onPositionChanged: (camera, _) {
                              _coordsNotifier.value = camera.center;
                            },
                            onTap: (_, latLng) {
                              _miniMapController.move(
                                latLng,
                                _miniMapController.camera.zoom,
                              );
                              _coordsNotifier.value = latLng;
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ru.ecotrack.mobile',
                              tileProvider: CachedTileProvider(
                                store: widget.tileCacheStore,
                                maxStale: const Duration(days: 14),
                              ),
                            ),
                          ],
                        ),
                        const IgnorePointer(
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: EcoColors.surfacePrimary,
                                shape: .circle,
                                border: .fromBorderSide(
                                  BorderSide(
                                    color: EcoColors.inkPrimary,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: .all(6),
                                child: Icon(
                                  LucideIcons.crosshair,
                                  size: 18,
                                  color: EcoColors.inkPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                  final coords = _coordsNotifier.value;
                  bloc.add(
                    MapWastePointSuggested(
                      SuggestWastePointRequest(
                        title: title,
                        openingHours: _hoursController.text.trim(),
                        acceptedFractions: _selectedFractions.toList(),
                        lat: coords.latitude,
                        lon: coords.longitude,
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

final class _FileTileCacheStore() extends CacheStore {
  Directory? _dir;
  bool _unavailable = false;

  Future<Directory?> _resolveDir() async {
    if (_unavailable) return null;
    final existing = _dir;
    if (existing != null) return existing;
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}ecotrack_tiles',
      );
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
      return dir;
    } on Exception {
      _unavailable = true;
      return null;
    }
  }

  File _fileForKey(Directory dir, String key) {
    final safe = base64Url.encode(utf8.encode(key));
    return File('${dir.path}${Platform.pathSeparator}$safe.json');
  }

  @override
  Future<bool> exists(String key) async {
    final dir = await _resolveDir();
    if (dir == null) return false;
    return await _fileForKey(dir, key).exists();
  }

  @override
  Future<CacheResponse?> get(String key) async {
    final dir = await _resolveDir();
    if (dir == null) return null;
    final file = _fileForKey(dir, key);
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, Object?>) return null;
      return _decodeResponse(raw);
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<CacheResponse>> getFromPath(
    RegExp pathPattern, {
    Map<String, String?>? queryParams,
  }) async {
    final dir = await _resolveDir();
    if (dir == null) return const [];
    final out = <CacheResponse>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final resp = await _readFile(entity);
      if (resp != null &&
          pathExists(resp.url, pathPattern, queryParams: queryParams)) {
        out.add(resp);
      }
    }
    return out;
  }

  Future<CacheResponse?> _readFile(File file) async {
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, Object?>) {
        return _decodeResponse(raw);
      }
    } on Exception {
      return null;
    }
    return null;
  }

  @override
  Future<void> set(CacheResponse response) async {
    final dir = await _resolveDir();
    if (dir == null) return;
    try {
      final file = _fileForKey(dir, response.key);
      await file.writeAsString(jsonEncode(_encodeResponse(response)));
    } on Exception {
      _unavailable = true;
    }
  }

  @override
  Future<void> delete(String key, {bool staleOnly = false}) async {
    final dir = await _resolveDir();
    if (dir == null) return;
    final file = _fileForKey(dir, key);
    if (!file.existsSync()) return;
    if (staleOnly) {
      final resp = await _readFile(file);
      if (resp == null || !resp.isStaled()) return;
    }
    try {
      await file.delete();
    } on Exception {
      _unavailable = true;
    }
  }

  @override
  Future<void> deleteFromPath(
    RegExp pathPattern, {
    Map<String, String?>? queryParams,
  }) async {
    final matches = await getFromPath(pathPattern, queryParams: queryParams);
    for (final resp in matches) {
      await delete(resp.key);
    }
  }

  @override
  Future<void> clean({
    CachePriority priorityOrBelow = CachePriority.high,
    bool staleOnly = false,
  }) async {
    final dir = await _resolveDir();
    if (dir == null) return;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final resp = await _readFile(entity);
      if (resp == null) continue;
      final priorityOk = resp.priority.index <= priorityOrBelow.index;
      final staleOk = !staleOnly || resp.isStaled();
      if (priorityOk && staleOk) {
        await entity.delete();
      }
    }
  }

  @override
  Future<void> close() async {}

  Map<String, Object?> _encodeResponse(CacheResponse r) => <String, Object?>{
    'key': r.key,
    'url': r.url,
    'statusCode': r.statusCode,
    'priority': r.priority.index,
    'requestDate': r.requestDate.millisecondsSinceEpoch,
    'responseDate': r.responseDate.millisecondsSinceEpoch,
    if (r.date case final dt?) 'date': dt.millisecondsSinceEpoch,
    if (r.expires case final dt?) 'expires': dt.millisecondsSinceEpoch,
    if (r.maxStale case final dt?) 'maxStale': dt.millisecondsSinceEpoch,
    if (r.eTag case final tag?) 'eTag': tag,
    if (r.lastModified case final lm?) 'lastModified': lm,
    if (r.content case final bytes?) 'content': base64Encode(bytes),
    if (r.headers case final hdrs?) 'headers': base64Encode(hdrs),
    'cc': <String, Object?>{
      'maxAge': r.cacheControl.maxAge,
      'maxStale': r.cacheControl.maxStale,
      'minFresh': r.cacheControl.minFresh,
      'mustRevalidate': r.cacheControl.mustRevalidate,
      'noCache': r.cacheControl.noCache,
      'noStore': r.cacheControl.noStore,
      if (r.cacheControl.privacy case final priv?) 'privacy': priv,
    },
  };

  CacheResponse? _decodeResponse(Map<String, Object?> json) {
    final key = json['key'];
    final url = json['url'];
    final statusCode = json['statusCode'];
    final reqMs = json['requestDate'];
    final respMs = json['responseDate'];
    if (key is! String ||
        url is! String ||
        statusCode is! int ||
        reqMs is! int ||
        respMs is! int) {
      return null;
    }
    final ccMap = json['cc'] as Map<String, Object?>?;
    final priorityIdx =
        (json['priority'] as int?) ?? CachePriority.normal.index;
    final priority = CachePriority
        .values[priorityIdx.clamp(0, CachePriority.values.length - 1)];
    return CacheResponse(
      key: key,
      url: url,
      statusCode: statusCode,
      priority: priority,
      requestDate: DateTime.fromMillisecondsSinceEpoch(reqMs),
      responseDate: DateTime.fromMillisecondsSinceEpoch(respMs),
      date: _decodeDt(json['date']),
      expires: _decodeDt(json['expires']),
      maxStale: _decodeDt(json['maxStale']),
      eTag: json['eTag'] as String?,
      lastModified: json['lastModified'] as String?,
      content: _decodeBytes(json['content']),
      headers: _decodeBytes(json['headers']),
      cacheControl: CacheControl(
        maxAge: (ccMap?['maxAge'] as int?) ?? -1,
        maxStale: (ccMap?['maxStale'] as int?) ?? -1,
        minFresh: (ccMap?['minFresh'] as int?) ?? -1,
        mustRevalidate: (ccMap?['mustRevalidate'] as bool?) ?? false,
        noCache: (ccMap?['noCache'] as bool?) ?? false,
        noStore: (ccMap?['noStore'] as bool?) ?? false,
        privacy: ccMap?['privacy'] as String?,
      ),
    );
  }

  DateTime? _decodeDt(Object? raw) =>
      raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;

  List<int>? _decodeBytes(Object? raw) =>
      raw is String ? base64Decode(raw) : null;
}
