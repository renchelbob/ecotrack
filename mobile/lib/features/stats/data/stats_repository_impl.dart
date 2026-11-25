import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/features/stats/data/stats_sqlite_dao.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';

Result<T, AppError> _flattenParserResult<T>(
  Result<Result<T, AppError>, AppError> outer,
) => switch (outer) {
  Ok(:final value) => value,
  Err(:final error) => Err(error),
};

final class StatsRepositoryImpl(
  final DioClient _dioClient, [
  StatsSqliteDao? dao,
  SqliteDatabase? db,
]) implements StatsRepository {
  final StatsSqliteDao _dao = dao ?? StatsSqliteDao(db);

  int? _lastOfflineCachedAtMs;

  int? get lastOfflineCachedAtMs => _lastOfflineCachedAtMs;

  @override
  Future<Result<EmissionsStatisticsResponse, AppError>> getEmissionsStatistics(
    String period, {
    String? referenceDate,
  }) async {
    final netOuter = await _dioClient
        .get<Result<EmissionsStatisticsResponse, AppError>>(
          '/api/v1/stats/emissions',
          queryParameters: <String, Object?>{
            'period': period,
            if (referenceDate != null) 'reference_date': referenceDate,
          },
          parser: (raw) => switch (raw) {
            final Map<String, Object?> map =>
              EmissionsStatisticsResponse.fromJson(map),
            _ => Err(AppError.fromCode('VALIDATION_ERROR')),
          },
        );

    final netResult = _flattenParserResult(netOuter);
    switch (netResult) {
      case Ok(:final value):
        _lastOfflineCachedAtMs = null;
        final enriched = await _dao.enrichWithTransportShares(value);
        await _dao.saveEmissionsSnapshot(enriched);
        return Ok(enriched);
      case Err(:final error):
        final cached = await _dao.loadEmissionsSnapshot(period);
        if (cached != null) {
          _lastOfflineCachedAtMs = cached.updatedAtMs;
          return Ok(cached.stats);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<PaginatedActivityHistoryResponse, AppError>>
  getActivityHistory({int limit = 20, int offset = 0}) async {
    final netOuter = await _dioClient
        .get<Result<PaginatedActivityHistoryResponse, AppError>>(
          '/api/v1/stats/history',
          queryParameters: <String, Object?>{'limit': limit, 'offset': offset},
          parser: (raw) => switch (raw) {
            final Map<String, Object?> map =>
              PaginatedActivityHistoryResponse.fromJson(map),
            _ => Err(AppError.fromCode('VALIDATION_ERROR')),
          },
        );

    final netResult = _flattenParserResult(netOuter);
    switch (netResult) {
      case Ok(:final value):
        return Ok(value);
      case Err(:final error):
        final localHistory = await _dao.loadLocalHistory(
          limit: limit,
          offset: offset,
        );
        if (localHistory != null) {
          return Ok(localHistory);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<EcoEquivalentsResponse, AppError>> getEcoEquivalents() async {
    final netOuter = await _dioClient
        .get<Result<EcoEquivalentsResponse, AppError>>(
          '/api/v1/stats/equivalents',
          parser: (raw) => switch (raw) {
            final Map<String, Object?> map => EcoEquivalentsResponse.fromJson(
              map,
            ),
            _ => Err(AppError.fromCode('VALIDATION_ERROR')),
          },
        );

    final netResult = _flattenParserResult(netOuter);
    switch (netResult) {
      case Ok(:final value):
        await _dao.saveEquivalentsSnapshot(value);
        return Ok(value);
      case Err(:final error):
        final cached = await _dao.loadEquivalentsSnapshot();
        if (cached != null) {
          _lastOfflineCachedAtMs = cached.updatedAtMs;
          return Ok(cached.equivalents);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<FriendsLeaderboardResponse, AppError>>
  getWeeklyLeaderboard() async {
    final netOuter = await _dioClient
        .get<Result<FriendsLeaderboardResponse, AppError>>(
          '/api/v1/friends/leaderboard',
          parser: (raw) => switch (raw) {
            final Map<String, Object?> map =>
              FriendsLeaderboardResponse.fromJson(map),
            _ => Err(AppError.fromCode('VALIDATION_ERROR')),
          },
        );

    final netResult = _flattenParserResult(netOuter);
    switch (netResult) {
      case Ok(:final value):
        await _dao.saveLeaderboard(value);
        return Ok(value);
      case Err(:final error):
        final cached = await _dao.loadLeaderboard();
        if (cached != null) {
          _lastOfflineCachedAtMs = cached.updatedAtMs;
          return Ok(cached.board);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<SharedForestChallengeResponse, AppError>>
  getCurrentSharedForest() async {
    final netOuter = await _dioClient
        .get<Result<SharedForestChallengeResponse, AppError>>(
          '/api/v1/challenges/shared-forest/current',
          parser: (raw) => switch (raw) {
            final Map<String, Object?> map =>
              SharedForestChallengeResponse.fromJson(map),
            _ => Err(AppError.fromCode('VALIDATION_ERROR')),
          },
        );

    final netResult = _flattenParserResult(netOuter);
    switch (netResult) {
      case Ok(:final value):
        await _dao.saveSharedForestSnapshot(value);
        return Ok(value);
      case Err(:final error):
        if (error.code == 'SHARED_FOREST_CHALLENGE_NOT_ACTIVE') {
          return Err(error);
        }
        final cached = await _dao.loadSharedForestSnapshot();
        if (cached != null) {
          _lastOfflineCachedAtMs = cached.updatedAtMs;
          return Ok(cached.challenge);
        }
        return Err(error);
    }
  }
}
