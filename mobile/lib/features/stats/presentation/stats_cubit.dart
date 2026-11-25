import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class const StatsState();

final class const StatsLoading() extends StatsState;

final class const StatsLoaded({
  required final EmissionsStatisticsResponse emissions,
  required final PaginatedActivityHistoryResponse history,
  required final EcoEquivalentsResponse equivalents,
  required final FriendsLeaderboardResponse leaderboard,
  final SharedForestChallengeResponse? sharedForest,
  required final String selectedPeriod,
  final bool isRefreshing = false,
  final bool isLoadingMoreHistory = false,
  final int? offlineCachedAtMs,
  final AppError? bannerError,
}) extends StatsState {
  StatsLoaded copyWith({
    EmissionsStatisticsResponse? emissions,
    PaginatedActivityHistoryResponse? history,
    EcoEquivalentsResponse? equivalents,
    FriendsLeaderboardResponse? leaderboard,
    SharedForestChallengeResponse? sharedForest,
    bool clearSharedForest = false,
    String? selectedPeriod,
    bool? isRefreshing,
    bool? isLoadingMoreHistory,
    int? offlineCachedAtMs,
    bool clearOfflineCachedAtMs = false,
    AppError? bannerError,
    bool clearBannerError = false,
  }) => StatsLoaded(
    emissions: emissions ?? this.emissions,
    history: history ?? this.history,
    equivalents: equivalents ?? this.equivalents,
    leaderboard: leaderboard ?? this.leaderboard,
    sharedForest: clearSharedForest
        ? null
        : (sharedForest ?? this.sharedForest),
    selectedPeriod: selectedPeriod ?? this.selectedPeriod,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingMoreHistory: isLoadingMoreHistory ?? this.isLoadingMoreHistory,
    offlineCachedAtMs: clearOfflineCachedAtMs
        ? null
        : (offlineCachedAtMs ?? this.offlineCachedAtMs),
    bannerError: clearBannerError ? null : (bannerError ?? this.bannerError),
  );
}

final class const StatsFailure(final AppError error) extends StatsState;

final class StatsCubit(
  final StatsRepository _statsRepo,
  final FriendsRepository _friendsRepo, [
  MapActivityRepository? mapRepo,
  int? Function()? readOfflineTimestamp,
]) extends Cubit<StatsState> {
  this : super(const StatsLoading()) {
    if (mapRepo != null) {
      final todayIso = _todayLocalIso();
      _mapSummarySub = mapRepo.watchDailySummary(todayIso).listen((_) {
        if (!isClosed && state is StatsLoaded) {
          unawaited(refresh());
        }
      });
    }
  }

  static const int _historyPageSize = 20;

  final int? Function()? _readOfflineTimestamp = readOfflineTimestamp;
  StreamSubscription<DailyActivitySummary>? _mapSummarySub;

  static String _todayLocalIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> loadStats({String period = 'days'}) async {
    if (state is! StatsLoaded) {
      emit(const StatsLoading());
    }
    await _fetchAll(period: period, keepExisting: false);
  }

  Future<void> changePeriod(String period) async {
    final current = state;
    if (current is! StatsLoaded) {
      await loadStats(period: period);
      return;
    }
    if (current.selectedPeriod == period) {
      return;
    }
    emit(current.copyWith(selectedPeriod: period, isRefreshing: true));
    final emissionsRes = await _statsRepo.getEmissionsStatistics(period);
    if (isClosed) {
      return;
    }
    final latest = state;
    if (latest is! StatsLoaded) {
      return;
    }
    switch (emissionsRes) {
      case Ok(:final value):
        final cachedMs = _readOfflineTimestamp?.call();
        emit(
          latest.copyWith(
            emissions: value,
            selectedPeriod: period,
            isRefreshing: false,
            offlineCachedAtMs: cachedMs,
            clearOfflineCachedAtMs: cachedMs == null,
            clearBannerError: true,
          ),
        );
      case Err(:final error):
        emit(latest.copyWith(isRefreshing: false, bannerError: error));
    }
  }

  Future<void> refresh() async {
    final current = state;
    final period = current is StatsLoaded ? current.selectedPeriod : 'days';
    if (current is StatsLoaded) {
      emit(current.copyWith(isRefreshing: true, clearBannerError: true));
    }
    await _fetchAll(period: period, keepExisting: current is StatsLoaded);
  }

  Future<void> loadMoreHistory() async {
    final current = state;
    if (current is! StatsLoaded || current.isLoadingMoreHistory) {
      return;
    }
    if (current.history.items.length >= current.history.totalCount) {
      return;
    }
    emit(current.copyWith(isLoadingMoreHistory: true, clearBannerError: true));

    final nextOffset = current.history.items.length;
    final res = await _statsRepo.getActivityHistory(offset: nextOffset);
    if (isClosed) {
      return;
    }
    final latest = state;
    if (latest is! StatsLoaded) {
      return;
    }
    switch (res) {
      case Ok(:final value):
        final seenDates = latest.history.items
            .map((e) => e.activityDate)
            .toSet();
        final merged = <DailyActivitySummary>[
          ...latest.history.items,
          ...value.items.where(
            (item) => !seenDates.contains(item.activityDate),
          ),
        ];
        emit(
          latest.copyWith(
            history: PaginatedActivityHistoryResponse(
              totalCount: value.totalCount,
              limit: value.limit,
              offset: 0,
              items: merged,
            ),
            isLoadingMoreHistory: false,
          ),
        );
      case Err(:final error):
        emit(latest.copyWith(isLoadingMoreHistory: false, bannerError: error));
    }
  }

  void clearBannerError() {
    if (state case final StatsLoaded loaded when loaded.bannerError != null) {
      emit(loaded.copyWith(clearBannerError: true));
    }
  }

  Future<void> _fetchAll({
    required String period,
    required bool keepExisting,
  }) async {
    final emissionsFuture = _statsRepo.getEmissionsStatistics(period);
    final historyFuture = _statsRepo.getActivityHistory();
    final equivalentsFuture = _statsRepo.getEcoEquivalents();
    final leaderboardFuture = _statsRepo.getWeeklyLeaderboard();
    final sharedForestFuture = _statsRepo.getCurrentSharedForest();
    final friendsOverviewFuture = _friendsRepo.getFriendsOverview();

    final emissionsRes = await emissionsFuture;
    final historyRes = await historyFuture;
    final equivalentsRes = await equivalentsFuture;
    final leaderboardRes = await leaderboardFuture;
    final sharedForestRes = await sharedForestFuture;
    await friendsOverviewFuture;

    if (isClosed) {
      return;
    }

    switch (emissionsRes) {
      case Err(:final error):
        if (keepExisting) {
          if (state case final StatsLoaded loaded) {
            emit(loaded.copyWith(isRefreshing: false, bannerError: error));
            return;
          }
        }
        emit(StatsFailure(error));
      case Ok(:final value):
        final fallbackEquivalents = EcoEquivalentsResponse(
          lifetime: value.equivalents,
          currentWeek: value.equivalents,
        );
        final history =
            historyRes.valueOrNull ??
            const PaginatedActivityHistoryResponse(
              totalCount: 0,
              limit: _historyPageSize,
              offset: 0,
              items: [],
            );
        final equivalents = equivalentsRes.valueOrNull ?? fallbackEquivalents;
        final leaderboard = leaderboardRes.valueOrNull ?? _emptyLeaderboard();
        final sharedForest = sharedForestRes.valueOrNull;
        final cachedMs = _readOfflineTimestamp?.call();
        final nonFatalError = _pickSecondaryError(
          historyRes: historyRes,
          leaderboardRes: leaderboardRes,
          sharedForestRes: sharedForestRes,
        );

        emit(
          StatsLoaded(
            emissions: value,
            history: history,
            equivalents: equivalents,
            leaderboard: leaderboard,
            sharedForest: sharedForest,
            selectedPeriod: period,
            offlineCachedAtMs: cachedMs,
            bannerError: nonFatalError,
          ),
        );
    }
  }

  FriendsLeaderboardResponse _emptyLeaderboard() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - DateTime.monday));
    final sunday = monday.add(const Duration(days: 6));
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return FriendsLeaderboardResponse(
      isoYear: now.year,
      isoWeek: 1,
      weekStartDate: fmt(monday),
      weekEndDate: fmt(sunday),
      entries: const [],
    );
  }

  AppError? _pickSecondaryError({
    required Result<PaginatedActivityHistoryResponse, AppError> historyRes,
    required Result<FriendsLeaderboardResponse, AppError> leaderboardRes,
    required Result<SharedForestChallengeResponse, AppError> sharedForestRes,
  }) {
    if (sharedForestRes case Err(:final error)) {
      if (error.code != 'SHARED_FOREST_CHALLENGE_NOT_ACTIVE') {
        return error;
      }
    }
    return historyRes.errorOrNull ?? leaderboardRes.errorOrNull;
  }

  @override
  Future<void> close() async {
    await _mapSummarySub?.cancel();
    await super.close();
  }
}
