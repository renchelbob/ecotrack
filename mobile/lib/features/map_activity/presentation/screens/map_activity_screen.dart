import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

enum RouteSegmentStyle() {
  walking,
  allocated,
  indoorPacing,
  vehicleSuspected,
}

final class const ActivityRouteSegment({
  required final int startSequence,
  required final int endSequence,
  required final List<LatLng> points,
  required final RouteSegmentStyle style,
  final String? label,
  final List<int> sequenceNumbers = const [],
}) {
  int sequenceAt(int index) => sequenceNumbers.length == points.length
      ? sequenceNumbers[index]
      : startSequence + index;
}

final class const MapTransportPreset(
  final String code,
  final String label,
  final double gramsPerMeter,
);

final class const RouteAllocationDraft(
  final int startSequence,
  final int endSequence,
  final String transportCode,
);

final class const RecyclingMapPoint({
  required final String id,
  required final LatLng position,
  required final String title,
});

typedef WasteViewportChanged = void Function(LatLngBounds bounds, int zoom);

/// The parent fetches and caches viewport results and handles route edits.
/// An app-managed tile provider can supply a persistent SQLite tile cache.
/// The default flutter_map network provider caches tiles on native platforms.
final class const MapActivityScreen({
  super.key,
  required final LatLng initialCenter,
  required final String tileUrlTemplate,
  required final String userAgentPackageName,
  required final WasteViewportChanged onWasteViewportChanged,
  required final ValueChanged<ActivityRouteSegment> onRouteSegmentSelected,
  required final ValueChanged<RecyclingMapPoint> onWastePointSelected,
  final double initialZoom = 13,
  final List<ActivityRouteSegment> segments = const [],
  final List<RecyclingMapPoint> wastePoints = const [],
  final List<MapTransportPreset> transportPresets = const [],
  final ValueChanged<RouteAllocationDraft>? onAllocationSaved,
  final String attribution =
      '© Участники OpenStreetMap · data.mos.ru · Муниципальные реестры',
  final TileProvider? tileProvider,
}) extends StatefulWidget {
  @override
  State<MapActivityScreen> createState() => _MapActivityScreenState();
}

final class _MapActivityScreenState() extends State<MapActivityScreen> {
  final MapController _controller = MapController();
  final LayerHitNotifier<int> _routeHits = ValueNotifier(null);
  Timer? _debounce;
  bool _recycling = false;
  bool _showVehicleNotice = false;
  bool _ready = false;
  static const double _clusterDetailZoom = 18;
  double _zoom = 13;
  late List<Polyline<int>> _routeLines;
  ActivityRouteSegment? _selection;
  int _selectionStart = 0;
  int _selectionEnd = 0;
  Offset? _dragPosition;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
    _buildRoutes();
  }

  @override
  void didUpdateWidget(covariant MapActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments) {
      _buildRoutes();
      if (!widget.segments.contains(_selection)) _selection = null;
    }
  }

  void _buildRoutes() {
    _routeLines = [
      for (final (index, segment) in widget.segments.indexed)
        if (segment.points.length >= 2) _polyline(segment, index),
    ];
  }

  Polyline<int> _polyline(ActivityRouteSegment segment, int index) {
    final (color, width, pattern) = switch (segment.style) {
      RouteSegmentStyle.walking => (
        const Color(0xff1e1e1e),
        4.5,
        StrokePattern.dashed(segments: const [10, 6]),
      ),
      RouteSegmentStyle.allocated => (
        const Color(0xff1e1e1e),
        6.5,
        const StrokePattern.solid(),
      ),
      RouteSegmentStyle.indoorPacing => (
        const Color(0xff868686),
        3.0,
        const StrokePattern.dotted(),
      ),
      RouteSegmentStyle.vehicleSuspected => (
        const Color(0xffc4c4c4),
        2.5,
        const StrokePattern.solid(),
      ),
    };
    return Polyline<int>(
      points: _simplify(segment.points),
      color: color,
      strokeWidth: width,
      pattern: pattern,
      borderStrokeWidth: segment.style == RouteSegmentStyle.allocated ? 2 : 0,
      borderColor: Colors.white,
      hitValue: index,
    );
  }

  void _moveEnded() {
    if (!_ready || !_recycling) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || !_recycling) return;
      final camera = _controller.camera;
      if (_zoom != camera.zoom) setState(() => _zoom = camera.zoom);
      widget.onWasteViewportChanged(camera.visibleBounds, camera.zoom.round());
    });
  }

  void _selectRoute() {
    final hits = _routeHits.value?.hitValues;
    if (hits == null || hits.isEmpty || hits.first >= widget.segments.length) {
      return;
    }
    final segment = widget.segments[hits.first];
    if (segment.style == RouteSegmentStyle.vehicleSuspected) {
      setState(() {
        _showVehicleNotice = true;
        _selection = null;
      });
      return;
    }
    if (_showVehicleNotice) setState(() => _showVehicleNotice = false);
    final hasOriginalSequences =
        segment.sequenceNumbers.length == segment.points.length ||
        segment.endSequence - segment.startSequence ==
            segment.points.length - 1;
    if (widget.onAllocationSaved == null ||
        widget.transportPresets.isEmpty ||
        !hasOriginalSequences ||
        segment.points.length < 2) {
      widget.onRouteSegmentSelected(segment);
      return;
    }
    setState(() {
      _selection = segment;
      _selectionStart = 0;
      _selectionEnd = segment.points.length - 1;
    });
  }

  Marker _routeHandle(ActivityRouteSegment segment, {required bool start}) {
    final point = segment.points[start ? _selectionStart : _selectionEnd];
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: GestureDetector(
        onPanStart: (_) =>
            _dragPosition = _controller.camera.latLngToScreenOffset(point),
        onPanUpdate: (event) {
          final dragPosition = _dragPosition;
          if (_selection != segment || dragPosition == null) return;
          final camera = _controller.camera;
          final target = dragPosition + event.delta;
          _dragPosition = target;
          final first = start ? 0 : _selectionStart + 1;
          final last = start ? _selectionEnd - 1 : segment.points.length - 1;
          var nearest = first;
          var minimum = double.infinity;
          for (var index = first; index <= last; index++) {
            final distance =
                (camera.latLngToScreenOffset(segment.points[index]) - target)
                    .distanceSquared;
            if (distance < minimum) {
              minimum = distance;
              nearest = index;
            }
          }
          setState(() {
            if (start) {
              _selectionStart = nearest;
            } else {
              _selectionEnd = nearest;
            }
          });
        },
        onPanEnd: (_) => _dragPosition = null,
        onPanCancel: () => _dragPosition = null,
        child: CircleAvatar(child: Text(start ? 'A' : 'B')),
      ),
    );
  }

  Future<void> _chooseTransport(ActivityRouteSegment segment) async {
    final start = _selectionStart;
    final end = _selectionEnd;
    const distance = Distance(roundResult: false);
    var meters = 0.0;
    for (var i = start + 1; i <= end; i++) {
      meters += distance.as(
        LengthUnit.Meter,
        segment.points[i - 1],
        segment.points[i],
      );
    }
    final selected = await showModalBottomSheet<MapTransportPreset>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Вместо какого транспорта вы прошли этот участок?'),
              Text('Длина участка: ${meters.round()} м'),
              Text(
                'Автоматическая оценка: ${(meters * .80 * .082 * .70).round()} г CO₂',
              ),
              for (final preset in widget.transportPresets)
                ListTile(
                  title: Text(preset.label),
                  trailing: Text(
                    '${(meters * preset.gramsPerMeter).round()} г CO₂',
                  ),
                  onTap: () => Navigator.of(context).pop(preset),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || _selection != segment) return;
    widget.onAllocationSaved?.call(
      RouteAllocationDraft(
        segment.sequenceAt(start),
        segment.sequenceAt(end),
        selected.code,
      ),
    );
    setState(() => _selection = null);
  }

  List<Marker> _wasteMarkers() {
    final radius = _zoom >= 13 ? 45 : 80;
    final size = 256 * math.pow(2, _zoom);
    final buckets = <(int, int), List<RecyclingMapPoint>>{};
    for (final point in widget.wastePoints) {
      final latitude = point.position.latitude.clamp(-85.05112878, 85.05112878);
      final sin = math.sin(latitude * math.pi / 180);
      final x = (point.position.longitude + 180) / 360 * size;
      final y = (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * size;
      (buckets[((x / radius).floor(), (y / radius).floor())] ??= []).add(point);
    }
    return [
      for (final points in buckets.values)
        if (points.length == 1)
          Marker(
            point: points.single.position,
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: points.single.title,
              onPressed: () => widget.onWastePointSelected(points.single),
              icon: const Icon(Icons.recycling),
            ),
          )
        else
          _clusterMarker(points),
    ];
  }

  Marker _clusterMarker(List<RecyclingMapPoint> points) {
    final positions = points.map((point) => point.position).toList();
    final bounds = LatLngBounds.fromPoints(positions);
    final label =
        '\u041f\u0443\u043d\u043a\u0442\u044b \u0441\u0431\u043e\u0440\u0430: ${points.length}';
    final badge = DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xff1e1e1e),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${points.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
    final canZoom =
        _zoom < _clusterDetailZoom &&
        positions.any((point) => point != positions.first);
    return Marker(
      point: bounds.center,
      width: 48,
      height: 48,
      child: canZoom
          ? Semantics(
              button: true,
              label: label,
              child: GestureDetector(
                onTap: () {
                  final zoom = _controller.camera.zoom;
                  final moved = _controller.fitCamera(
                    CameraFit.bounds(
                      bounds: bounds,
                      minZoom: math.min(zoom + 1, _clusterDetailZoom),
                      maxZoom: _clusterDetailZoom,
                      padding: const EdgeInsets.all(56),
                    ),
                  );
                  if (!moved) _moveEnded();
                },
                child: badge,
              ),
            )
          : PopupMenuButton<RecyclingMapPoint>(
              tooltip: label,
              onSelected: widget.onWastePointSelected,
              itemBuilder: (_) => [
                for (final point in points)
                  PopupMenuItem(value: point, child: Text(point.title)),
              ],
              child: badge,
            ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Мои маршруты')),
          ButtonSegment(value: true, label: Text('Пункты РСО')),
        ],
        selected: {_recycling},
        onSelectionChanged: (value) {
          if (_recycling == value.single) return;
          setState(() {
            _recycling = value.single;
            _selection = null;
            _showVehicleNotice = false;
          });
          _debounce?.cancel();
          _moveEnded();
        },
      ),
      if (_showVehicleNotice)
        Semantics(
          liveRegion: true,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Участок содержит движение на транспорте.'),
          ),
        ),
      Expanded(
        child: RepaintBoundary(
          child: FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              onMapReady: () {
                _ready = true;
                _moveEnded();
              },
              onMapEvent: (event) {
                if (event is MapEventMoveEnd || event is MapEventRotateEnd) {
                  _moveEnded();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: widget.tileUrlTemplate,
                userAgentPackageName: widget.userAgentPackageName,
                tileProvider: widget.tileProvider,
              ),
              if (!_recycling)
                GestureDetector(
                  onTap: _selectRoute,
                  child: PolylineLayer<int>(
                    polylines: _routeLines,
                    hitNotifier: _routeHits,
                  ),
                ),
              if (!_recycling)
                MarkerLayer(
                  markers: [
                    for (final segment in widget.segments)
                      if (segment.label case final label?
                          when segment.points.isNotEmpty)
                        Marker(
                          point: segment.points[segment.points.length ~/ 2],
                          width: 76,
                          height: 32,
                          child: IgnorePointer(child: Chip(label: Text(label))),
                        ),
                  ],
                ),
              if (_selection case final selected?)
                MarkerLayer(
                  markers: [
                    _routeHandle(selected, start: true),
                    _routeHandle(selected, start: false),
                  ],
                ),
              if (_recycling) MarkerLayer(markers: _wasteMarkers()),
              RichAttributionWidget(
                attributions: [TextSourceAttribution(widget.attribution)],
              ),
            ],
          ),
        ),
      ),
      if (_selection case final selected?)
        FilledButton(
          onPressed: () => unawaited(_chooseTransport(selected)),
          child: const Text('Выбрать транспорт'),
        ),
    ],
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _routeHits.dispose();
    _controller.dispose();
    super.dispose();
  }
}

/// Iterative Ramer–Douglas–Peucker for display only. The original coordinates
/// and endpoint sequences stay on ActivityRouteSegment for API submissions.
List<LatLng> _simplify(List<LatLng> points) {
  if (points.length <= 2000) return points;
  const metersPerDegree = 111195.0;
  final reference = points.first;
  final lonScale =
      metersPerDegree * math.cos(reference.latitude * math.pi / 180);
  final projected = [
    for (final p in points)
      Offset(
        ((p.longitude - reference.longitude + 540) % 360 - 180) * lonScale,
        (p.latitude - reference.latitude) * metersPerDegree,
      ),
  ];
  final last = points.length - 1;
  final keep = <int>{0, last};
  final pending = <(int, int)>[(0, last)];
  while (pending.isNotEmpty) {
    final (begin, end) = pending.removeLast();
    final start = projected[begin];
    final vector = projected[end] - start;
    var limit = 1.5 * 1.5;
    int? split;
    for (var i = begin + 1; i < end; i++) {
      final relative = projected[i] - start;
      final t = vector.distanceSquared == 0
          ? 0.0
          : ((relative.dx * vector.dx + relative.dy * vector.dy) /
                    vector.distanceSquared)
                .clamp(0.0, 1.0);
      final deviation = (relative - vector * t).distanceSquared;
      if (deviation > limit) {
        limit = deviation;
        split = i;
      }
    }
    if (split != null) {
      keep.add(split);
      pending.addAll([(begin, split), (split, end)]);
    }
  }
  return [for (final i in keep.toList()..sort()) points[i]];
}
