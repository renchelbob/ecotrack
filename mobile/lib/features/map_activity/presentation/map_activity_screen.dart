import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/map_activity/presentation/map_activity_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapActivityScreen extends StatefulWidget {
  const MapActivityScreen({super.key});

  @override
  State<MapActivityScreen> createState() => _MapActivityScreenState();
}

class _MapActivityScreenState extends State<MapActivityScreen> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _showPointDetails(BuildContext context, WastePoint point) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EcoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.recycling,
                  color: EcoColors.primaryGreen,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    point.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              point.address,
              style: const TextStyle(
                color: EcoColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Принимаемые фракции:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: point.wasteTypes
                  .map(
                    (type) => Chip(
                      label: Text(type, style: const TextStyle(fontSize: 12)),
                      backgroundColor: EcoColors.surfaceVariant,
                      side: const BorderSide(color: EcoColors.divider),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Индекс доверия: ${(point.trustScore * 100).toInt()}%',
                  style: const TextStyle(
                    color: EcoColors.primaryGreenLight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (point.schedule != null)
                  Text(
                    point.schedule ?? '',
                    style: const TextStyle(
                      color: EcoColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Построить маршрут'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: BlocBuilder<MapActivityCubit, MapActivityState>(
        builder: (context, state) {
          final currentMode = switch (state) {
            MapActivityLoaded(mode: final m) => m,
            _ => MapMode.recyclingMap,
          };
          return SegmentedButton<MapMode>(
            segments: const [
              ButtonSegment(
                value: MapMode.myRoutes,
                label: Text('Мои маршруты', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.route, size: 16),
              ),
              ButtonSegment(
                value: MapMode.recyclingMap,
                label: Text('Пункты РСО', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.recycling, size: 16),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                context.read<MapActivityCubit>().switchMode(selection.first);
              }
            },
          );
        },
      ),
    ),
    body: BlocBuilder<MapActivityCubit, MapActivityState>(
      builder: (context, state) => switch (state) {
        MapActivityLoading() => const Center(
          child: CircularProgressIndicator(color: EcoColors.primaryGreen),
        ),
        MapActivityFailure(error: final err) => Center(
          child: Text(err.uiMessageRu),
        ),
        MapActivityLoaded() => _buildMap(context, state),
      },
    ),
    floatingActionButton: BlocBuilder<MapActivityCubit, MapActivityState>(
      builder: (context, state) {
        if (state is! MapActivityLoaded || state.mode != MapMode.myRoutes) {
          return const SizedBox.shrink();
        }
        final isTracking = state.isTrackingGps;
        return FloatingActionButton.extended(
          backgroundColor: isTracking
              ? EcoColors.errorRed
              : EcoColors.primaryGreen,
          foregroundColor: Colors.white,
          icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
          label: Text(isTracking ? 'Остановить запись' : 'Начать запись'),
          onPressed: () => context.read<MapActivityCubit>().toggleGpsTracking(),
        );
      },
    ),
  );

  Widget _buildMap(BuildContext context, MapActivityLoaded state) {
    const center = LatLng(58.5990, 49.6600); // Default Kirov/Campus center

    final routePoints = state.recordedPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(initialCenter: center, initialZoom: 13.5),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ru.vyatsu.ecotrack',
        ),
        if (state.mode == MapMode.myRoutes && routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 5.0,
                color: EcoColors.accentBlue,
              ),
            ],
          ),
        if (state.mode == MapMode.recyclingMap)
          MarkerLayer(
            markers: state.wastePoints
                .map(
                  (point) => Marker(
                    point: LatLng(point.latitude, point.longitude),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => _showPointDetails(context, point),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: EcoColors.primaryGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.recycling,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}
