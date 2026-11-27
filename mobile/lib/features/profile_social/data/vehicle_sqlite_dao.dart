import 'dart:convert';

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:sqflite/sqflite.dart';

final class VehicleSqliteDao(
  final SqliteDatabase _db,
  final OutboxDispatcher _outbox,
) {
  Future<UserVehicle?> getCachedVehicle() async {
    final rows = await _db.database.query('local_user_vehicle', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return UserVehicle.fromSqliteRow(rows.first);
  }

  Future<void> upsertVehicle(
    String userId,
    UserVehicle vehicle, {
    bool isDirty = false,
  }) async {
    await _upsertVehicleTxn(
      _db.database,
      userId,
      vehicle,
      isDirty: isDirty,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> upsertVehicleAndEnqueueOutbox({
    required String userId,
    required UserVehicle vehicle,
    required String idempotencyKey,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.database.transaction(
      (txn) =>
          _upsertVehicleTxn(txn, userId, vehicle, isDirty: true, nowMs: nowMs),
    );
    await _outbox.enqueue(
      operationType: 'update_user_vehicle',
      httpMethod: 'PUT',
      endpointPath: '/api/v1/users/me/vehicle',
      payloadJson: jsonEncode({
        'vehicle_name': vehicle.vehicleName,
        'fuel': vehicle.fuel.wireName,
        'consumption_per_100km': vehicle.consumptionPer100km,
      }),
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> deleteLocalVehicle() async {
    await _db.database.delete('local_user_vehicle');
  }

  Future<void> deleteVehicleAndEnqueueOutbox({
    required String idempotencyKey,
  }) async {
    await _db.database.delete('local_user_vehicle');
    await _outbox.enqueue(
      operationType: 'update_user_vehicle',
      httpMethod: 'DELETE',
      endpointPath: '/api/v1/users/me/vehicle',
      payloadJson: '{}',
      idempotencyKey: idempotencyKey,
    );
  }

  Future<List<TransportPresetItem>> getTransportPresets() async {
    final rows = await _db.database.query(
      'local_transport_catalog',
      orderBy: 'sort_order ASC',
    );
    return rows.map(TransportPresetItem.fromSqliteRow).toList();
  }

  Future<void> replaceTransportPresets(
    List<TransportPresetItem> presets,
  ) async {
    await _db.database.transaction((txn) async {
      await txn.delete('local_transport_catalog');
      for (var i = 0; i < presets.length; i++) {
        final item = presets[i];
        await txn.insert('local_transport_catalog', {
          'mode_code': item.modeCode.wireName,
          'display_name_ru': item.displayNameRu,
          'display_name_en': item.displayNameEn,
          'co2_grams_per_km': item.co2GramsPerKm,
          'co2_grams_per_meter': item.co2GramsPerMeter,
          'is_personal_vehicle_slot': item.isPersonalVehicleSlot ? 1 : 0,
          'sort_order': i,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> _upsertVehicleTxn(
    DatabaseExecutor txn,
    String userId,
    UserVehicle vehicle, {
    required bool isDirty,
    required int nowMs,
  }) async {
    await txn.insert('local_user_vehicle', {
      'id': vehicle.id,
      'user_id': userId,
      'vehicle_name': vehicle.vehicleName,
      'fuel': vehicle.fuel.wireName,
      'consumption_per_100km': vehicle.consumptionPer100km,
      'fuel_emission_factor_g_per_unit': vehicle.fuelEmissionFactorGPerUnit,
      'computed_co2_g_per_km': vehicle.computedCo2GPerKm,
      'computed_co2_g_per_meter': vehicle.computedCo2GPerMeter,
      'is_dirty': isDirty ? 1 : 0,
      'updated_at_ms': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
