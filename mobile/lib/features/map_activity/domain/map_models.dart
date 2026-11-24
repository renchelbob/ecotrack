import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';

enum MapMode { myRoutes, recyclingMap }

final class WastePoint {
  const WastePoint({
    required this.id,
    required this.title,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.wasteTypes,
    this.schedule,
    this.trustScore = 1.0,
  });

  final String id;
  final String title;
  final String address;
  final double latitude;
  final double longitude;
  final List<String> wasteTypes;
  final String? schedule;
  final double trustScore;

  static Result<WastePoint, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'title': final String title,
      'address': final String address,
      'latitude': final num lat,
      'longitude': final num lon,
    }) {
      final rawTypes = json['waste_types'];
      final List<String> types = switch (rawTypes) {
        final List<dynamic> list => list.whereType<String>().toList(),
        final String s => s.split(',').map((e) => e.trim()).toList(),
        _ => ['Пластик', 'Бумага'],
      };

      return Ok(
        WastePoint(
          id: id,
          title: title,
          address: address,
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
          wasteTypes: types,
          schedule: json['schedule'] as String?,
          trustScore: (json['trust_score'] as num?)?.toDouble() ?? 1.0,
        ),
      );
    }
    return Err(
      AppError.fromCode('VALIDATION_ERROR', 'Неверный формат пункта РСО'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'waste_types': wasteTypes.join(','),
    if (schedule != null) 'schedule': schedule,
    'trust_score': trustScore,
  };
}

abstract interface class MapRepository {
  Future<Result<List<WastePoint>, AppError>> getWastePoints();
  Future<Result<void, AppError>> reportWastePoint(
    String pointId,
    String comment,
  );
}
