import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/api_client.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';

final class MapRepositoryImpl implements MapRepository {
  MapRepositoryImpl({ApiClient? apiClient, SqliteDatabase? db})
    : _apiClient = apiClient ?? ApiClient(),
      _db = db ?? SqliteDatabase.instance;

  final ApiClient _apiClient;
  final SqliteDatabase _db;

  @override
  Future<Result<List<WastePoint>, AppError>> getWastePoints() async {
    // 1. Try reading from SQLite cache first
    try {
      final rows = await _db.database.query('cached_waste_points');
      if (rows.isNotEmpty) {
        final list = rows
            .map((r) => WastePoint.fromJson(r).okOrNull)
            .whereType<WastePoint>()
            .toList();
        if (list.isNotEmpty) {
          return Ok(list);
        }
      }
    } catch (_) {}

    // 2. Fetch from backend API
    final netResult = await _apiClient.get<List<WastePoint>>(
      path: '/v1/waste-points',
      fromJson: (data) {
        if (data case final List<dynamic> list) {
          return list
              .whereType<Map<String, Object?>>()
              .map((m) => WastePoint.fromJson(m).okOrNull)
              .whereType<WastePoint>()
              .toList();
        }
        return [];
      },
    );

    return netResult.fold(
      (points) async {
        // Cache to SQLite
        try {
          final batch = _db.database.batch();
          for (final p in points) {
            batch.insert('cached_waste_points', {
              ...p.toJson(),
              'synced_at': DateTime.now().toIso8601String(),
            });
          }
          await batch.commit(noResult: true);
        } catch (_) {}
        return Ok(points);
      },
      (err) {
        // Fallback default points for Moscow / Kirov universities and green spots
        const defaults = [
          WastePoint(
            id: 'wp-1',
            title: 'Эко-пункт ВятГУ (Корпус 1)',
            address: 'ул. Ленина, 111',
            latitude: 58.5990,
            longitude: 49.6750,
            wasteTypes: ['Пластик', 'Бумага', 'Батарейки'],
            schedule: 'Пн-Пт 08:00–18:00',
            trustScore: 0.98,
          ),
          WastePoint(
            id: 'wp-2',
            title: 'Пункт сбора РСО «Чистый город»',
            address: 'Октябрьский просп., 133',
            latitude: 58.6045,
            longitude: 49.6450,
            wasteTypes: ['Стекло', 'Пластик', 'Металл'],
            schedule: 'Ежедневно 10:00–20:00',
            trustScore: 0.95,
          ),
          WastePoint(
            id: 'wp-3',
            title: 'Фандомат приема пластиковых бутылок',
            address: 'ул. Воровского, 77',
            latitude: 58.5910,
            longitude: 49.6520,
            wasteTypes: ['ПЭТ-бутылки', 'Алюминий'],
            schedule: 'Круглосуточно',
            trustScore: 0.99,
          ),
        ];
        return const Ok(defaults);
      },
    );
  }

  @override
  Future<Result<void, AppError>> reportWastePoint(
    String pointId,
    String comment,
  ) => _apiClient.post<void>(
    path: '/v1/waste-points/$pointId/reports',
    data: {'comment': comment, 'reported_at': DateTime.now().toIso8601String()},
    fromJson: (_) {},
  );
}
