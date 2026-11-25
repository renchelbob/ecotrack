import 'dart:async';

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:ecotrack_mobile/features/profile_social/data/profile_sqlite_dao.dart';
import 'package:ecotrack_mobile/features/profile_social/data/vehicle_sqlite_dao.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class ProfileRepositoryImpl(
  final DioClient _dioClient,
  final SqliteDatabase _db,
  final TokenStore _tokenStore,
  final OutboxDispatcher _outbox,
) implements ProfileRepository {
  late final ProfileSqliteDao _profileDao = ProfileSqliteDao(_db, _outbox);
  late final VehicleSqliteDao _vehicleDao = VehicleSqliteDao(_db, _outbox);
  final StreamController<UserProfile> _profileController =
      StreamController<UserProfile>.broadcast();

  @override
  Stream<UserProfile> watchUserProfile() => _profileController.stream;

  Future<void> dispose() => _profileController.close();

  @override
  Future<Result<UserProfile, AppError>> getProfile({
    bool forceRefresh = false,
  }) async {
    final cachedVehicle = await _vehicleDao.getCachedVehicle();
    final cached = await _profileDao.getCachedProfile(vehicle: cachedVehicle);
    if (!forceRefresh && cached != null) {
      return Ok(cached);
    }

    final result = await _dioClient.get<UserProfile>(
      '/api/v1/users/me',
      parser: (data) => _parseOrThrow(
        data,
        (map) => UserProfile.fromJson(
          map,
          authProviderOverride: cached?.authProvider,
          isForeignLabModeOverride: cached?.isForeignProviderLabMode,
        ),
      ),
    );

    switch (result) {
      case Ok(:final value):
        await cacheProfile(
          value,
          authProvider: cached?.authProvider,
          isForeignLabMode: cached?.isForeignProviderLabMode,
        );
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error) && cached != null) {
          return Ok(cached);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<UserProfile, AppError>> updateProfile(
    UpdateUserProfileRequest req,
  ) async {
    final cachedVehicle = await _vehicleDao.getCachedVehicle();
    final cached = await _profileDao.getCachedProfile(vehicle: cachedVehicle);
    final payload = req.toJson();

    final result = await _dioClient.patch<UserProfile>(
      '/api/v1/users/me',
      data: payload,
      parser: (data) => _parseOrThrow(
        data,
        (map) => UserProfile.fromJson(
          map,
          authProviderOverride: cached?.authProvider,
          isForeignLabModeOverride: cached?.isForeignProviderLabMode,
        ),
      ),
    );

    switch (result) {
      case Ok(:final value):
        await cacheProfile(
          value,
          authProvider: cached?.authProvider,
          isForeignLabMode: cached?.isForeignProviderLabMode,
        );
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error) && cached != null) {
          final optimistic = cached.copyWith(
            displayName: req.displayName,
            avatarUrl: req.avatarUrl,
            dailyStepGoal: req.dailyStepGoal,
            dailyCo2GoalGrams: req.dailyCo2GoalGrams,
            strideLengthCm: req.strideLengthCm,
            gpsIntervalSeconds: req.gpsIntervalSeconds,
            isGpsTrackingEnabled: req.isGpsTrackingEnabled,
            isStatsVisibleToFriends: req.isStatsVisibleToFriends,
          );
          await _profileDao.updateProfileAndEnqueueOutbox(
            optimisticProfile: optimistic,
            patchPayload: payload,
            idempotencyKey: UuidV7.generate(),
          );
          _emitProfile(optimistic);
          unawaited(_outbox.flush());
          return Ok(optimistic);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<UserVehicle, AppError>> getMyVehicle() async {
    final result = await _dioClient.get<UserVehicle>(
      '/api/v1/users/me/vehicle',
      parser: (data) => _parseOrThrow(data, UserVehicle.fromJson),
    );

    switch (result) {
      case Ok(:final value):
        final cachedProfile = await _profileDao.getCachedProfile();
        if (cachedProfile != null) {
          await _vehicleDao.upsertVehicle(cachedProfile.id, value);
        }
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _vehicleDao.getCachedVehicle();
          if (cached != null) {
            return Ok(cached);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<UserVehicle, AppError>> upsertVehicle(
    String vehicleName,
    FuelType fuel,
    double consumptionPer100km,
  ) async {
    if (consumptionPer100km <= 0.0 || consumptionPer100km > 50.0) {
      return Err(AppError.fromCode('INVALID_VEHICLE_CONSUMPTION'));
    }

    final result = await _dioClient.put<UserVehicle>(
      '/api/v1/users/me/vehicle',
      data: {
        'vehicle_name': vehicleName.trim().isEmpty
            ? 'Мой автомобиль'
            : vehicleName.trim(),
        'fuel': fuel.wireName,
        'consumption_per_100km': consumptionPer100km,
      },
      parser: (data) => _parseOrThrow(data, UserVehicle.fromJson),
    );

    switch (result) {
      case Ok(:final value):
        await _syncCachedVehicle(value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cachedProfile = await _profileDao.getCachedProfile();
          if (cachedProfile != null) {
            final factors = Co2Math.computeVehicleCo2Factors(
              fuel.wireName,
              consumptionPer100km,
            );
            final existing = await _vehicleDao.getCachedVehicle();
            final optimistic = UserVehicle(
              id: existing?.id ?? UuidV7.generate(),
              vehicleName: vehicleName.trim().isEmpty
                  ? 'Мой автомобиль'
                  : vehicleName.trim(),
              fuel: fuel,
              consumptionPer100km: consumptionPer100km,
              fuelEmissionFactorGPerUnit: factors.factor,
              computedCo2GPerKm: factors.gPerKm,
              computedCo2GPerMeter: factors.gPerMeter,
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            );
            await _vehicleDao.upsertVehicleAndEnqueueOutbox(
              userId: cachedProfile.id,
              vehicle: optimistic,
              idempotencyKey: UuidV7.generate(),
            );
            _emitProfile(cachedProfile.copyWith(personalVehicle: optimistic));
            unawaited(_outbox.flush());
            return Ok(optimistic);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<void, AppError>> deleteVehicle() async {
    final result = await _dioClient.delete<void>(
      '/api/v1/users/me/vehicle',
      parser: (_) {},
    );

    switch (result) {
      case Ok():
        await _vehicleDao.deleteLocalVehicle();
        final cached = await _profileDao.getCachedProfile();
        if (cached != null) {
          _emitProfile(cached.copyWith(clearPersonalVehicle: true));
        }
        return const Ok(null);
      case Err(:final error):
        if (_isOfflineError(error)) {
          await _vehicleDao.deleteVehicleAndEnqueueOutbox(
            idempotencyKey: UuidV7.generate(),
          );
          final cached = await _profileDao.getCachedProfile();
          if (cached != null) {
            _emitProfile(cached.copyWith(clearPersonalVehicle: true));
          }
          unawaited(_outbox.flush());
          return const Ok(null);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<List<TransportPresetItem>, AppError>>
  listTransportPresets() async {
    final result = await _dioClient.get<List<TransportPresetItem>>(
      '/api/v1/transport/presets',
      parser: (data) {
        if (data case {'presets': final List<Object?> rawPresets}) {
          final items = <TransportPresetItem>[];
          for (final item in rawPresets) {
            if (item is Map<String, Object?>) {
              if (TransportPresetItem.fromJson(item) case Ok(:final value)) {
                items.add(value);
              }
            }
          }
          return items;
        }
        throw AppError.fromCode('VALIDATION_ERROR');
      },
    );

    switch (result) {
      case Ok(:final value):
        await _vehicleDao.replaceTransportPresets(value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _vehicleDao.getTransportPresets();
          if (cached.isNotEmpty) {
            return Ok(cached);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<BadgesListResponse, AppError>> listBadges() async {
    final result = await _dioClient.get<BadgesListResponse>(
      '/api/v1/badges',
      parser: (data) => _parseOrThrow(data, BadgesListResponse.fromJson),
    );

    switch (result) {
      case Ok(:final value):
        await _profileDao.cacheBadges(value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _profileDao.getCachedBadges();
          if (cached != null) {
            return Ok(cached);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<MascotInventoryResponse, AppError>>
  listMascotAccessories() async {
    final result = await _dioClient.get<MascotInventoryResponse>(
      '/api/v1/mascot/inventory',
      parser: (data) => _parseOrThrow(data, MascotInventoryResponse.fromJson),
    );

    switch (result) {
      case Ok(:final value):
        await _profileDao.cacheAccessories(value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _profileDao.getCachedAccessories();
          if (cached != null) {
            return Ok(cached);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<UserProfile, AppError>> equipMascotAccessory(
    String? accessoryCode,
  ) async {
    final cachedVehicle = await _vehicleDao.getCachedVehicle();
    final cached = await _profileDao.getCachedProfile(vehicle: cachedVehicle);

    final result = await _dioClient.put<UserProfile>(
      '/api/v1/users/me/mascot/accessory',
      data: {'accessory_code': accessoryCode},
      parser: (data) => _parseOrThrow(
        data,
        (map) => UserProfile.fromJson(
          map,
          authProviderOverride: cached?.authProvider,
          isForeignLabModeOverride: cached?.isForeignProviderLabMode,
        ),
      ),
    );

    switch (result) {
      case Ok(:final value):
        await cacheProfile(
          value,
          authProvider: cached?.authProvider,
          isForeignLabMode: cached?.isForeignProviderLabMode,
        );
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error) && cached != null) {
          final optimistic = cached.copyWith(
            mascot: cached.mascot.copyWith(
              equippedAccessoryCode: accessoryCode,
              clearEquippedAccessory: accessoryCode == null,
            ),
          );
          await _profileDao.saveEquippedAccessoryAndEnqueueOutbox(
            optimisticProfile: optimistic,
            accessoryCode: accessoryCode,
            idempotencyKey: UuidV7.generate(),
          );
          _emitProfile(optimistic);
          unawaited(_outbox.flush());
          return Ok(optimistic);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<AccountDeletionReceipt, AppError>> deleteAccount(
    String reason,
    String confirmationPhrase,
  ) async {
    if (confirmationPhrase != 'DELETE_MY_DATA_152FZ') {
      return Err(AppError.fromCode('FZ152_INVALID_CONFIRMATION_PHRASE'));
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.length < 3 || normalizedReason.length > 128) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }

    final result = await _dioClient.delete<AccountDeletionReceipt>(
      '/api/v1/users/me',
      data: {
        'deletion_reason': normalizedReason,
        'confirmation_phrase': confirmationPhrase,
      },
      parser: (data) => _parseOrThrow(data, AccountDeletionReceipt.fromJson),
    );

    if (result case Ok(:final value)) {
      await _tokenStore.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _db.wipeAllUserData();
      return Ok(value);
    }
    return result;
  }

  @override
  Future<void> cacheProfile(
    UserProfile profile, {
    AuthProviderType? authProvider,
    bool? isForeignLabMode,
  }) async {
    final resolved = profile.copyWith(
      authProvider: authProvider ?? profile.authProvider,
      isForeignProviderLabMode:
          isForeignLabMode ?? profile.isForeignProviderLabMode,
    );
    await _profileDao.upsertProfile(
      resolved,
      authProvider: resolved.authProvider,
      isForeignLabMode: resolved.isForeignProviderLabMode,
    );
    _emitProfile(resolved);
  }

  @override
  Future<UserProfile?> getCachedProfileSnapshot() async {
    final cachedVehicle = await _vehicleDao.getCachedVehicle();
    return await _profileDao.getCachedProfile(vehicle: cachedVehicle);
  }

  @override
  Future<void> updateLocalConsentActive({required bool isActive}) async {
    await _profileDao.updateConsentActive(isActive: isActive);
    final cached = await getCachedProfileSnapshot();
    if (cached != null) {
      _emitProfile(cached.copyWith(is152fzConsentActive: isActive));
    }
  }

  @override
  Future<void> clearAllLocalUserData() => _db.wipeAllUserData();

  Future<void> _syncCachedVehicle(UserVehicle vehicle) async {
    final cached = await _profileDao.getCachedProfile();
    if (cached != null) {
      await _vehicleDao.upsertVehicle(cached.id, vehicle);
      _emitProfile(cached.copyWith(personalVehicle: vehicle));
    }
  }

  void _emitProfile(UserProfile profile) {
    if (!_profileController.isClosed) {
      _profileController.add(profile);
    }
  }

  bool _isOfflineError(AppError error) =>
      error.clientAction == ClientErrorAction.queueRetry ||
      error.httpStatus == 0 ||
      error.httpStatus == 503;

  T _parseOrThrow<T>(
    Object? data,
    Result<T, AppError> Function(Map<String, Object?>) parser,
  ) {
    if (data is Map<String, Object?>) {
      return switch (parser(data)) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };
    }
    throw AppError.fromCode('VALIDATION_ERROR');
  }
}
