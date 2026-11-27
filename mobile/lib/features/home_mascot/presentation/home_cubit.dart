import 'dart:async';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class const HomeState();

final class const HomeLoading() extends HomeState;

final class const HomeReady({
  required final UserProfile profile,
  required final DailyActivitySummary todaySummary,
  required final MascotVisualState mascot,
  final bool isPointerSquinting = false,
  final bool isRefreshing = false,
  final AppError? bannerError,
}) extends HomeState {
  MascotVisualSnapshot get mascotSnapshot =>
      MascotVisualSnapshot.fromProfileAndSummary(
        profile: profile,
        summary: todaySummary,
        isPointerSquinting: isPointerSquinting,
      );

  TodayCardMetrics get todayMetrics => TodayCardMetrics.fromProfileAndSummary(
    profile: profile,
    summary: todaySummary,
  );

  HomeReady copyWith({
    UserProfile? profile,
    DailyActivitySummary? todaySummary,
    MascotVisualState? mascot,
    bool? isPointerSquinting,
    bool? isRefreshing,
    AppError? bannerError,
    bool clearBannerError = false,
  }) => HomeReady(
    profile: profile ?? this.profile,
    todaySummary: todaySummary ?? this.todaySummary,
    mascot: mascot ?? this.mascot,
    isPointerSquinting: isPointerSquinting ?? this.isPointerSquinting,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    bannerError: clearBannerError ? null : (bannerError ?? this.bannerError),
  );
}

final class HomeCubit(
  final ProfileRepository _profileRepo,
  final MapActivityRepository _mapRepo,
) extends Cubit<HomeState> {
  this : super(const HomeLoading()) {
    _subscribeStreams();
  }

  StreamSubscription<UserProfile>? _profileSub;
  StreamSubscription<DailyActivitySummary>? _summarySub;
  String _subscribedDate = _todayIso();

  static String _todayIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _subscribeStreams() {
    _profileSub = _profileRepo.watchUserProfile().listen(_onProfileUpdated);
    _subscribedDate = _todayIso();
    _summarySub = _mapRepo
        .watchDailySummary(_subscribedDate)
        .listen(_onSummaryUpdated);
  }

  void _onProfileUpdated(UserProfile profile) {
    if (isClosed) return;
    if (state case final HomeReady ready) {
      final mascot = _buildVisualState(
        profile: profile,
        summary: ready.todaySummary,
        isSquinting: ready.isPointerSquinting,
      );
      emit(ready.copyWith(profile: profile, mascot: mascot));
    }
  }

  void _onSummaryUpdated(DailyActivitySummary summary) {
    if (isClosed) return;
    if (state case final HomeReady ready) {
      final updatedProfile = ready.profile.copyWith(
        pointsBalance: math.max(
          ready.profile.pointsBalance,
          summary.pointsBalance,
        ),
      );
      final mascot = _buildVisualState(
        profile: updatedProfile,
        summary: summary,
        isSquinting: ready.isPointerSquinting,
      );
      emit(
        ready.copyWith(
          profile: updatedProfile,
          todaySummary: summary,
          mascot: mascot,
        ),
      );
    }
  }

  Future<void> loadHome() async {
    final currentDate = _todayIso();
    if (currentDate != _subscribedDate) {
      await _summarySub?.cancel();
      _subscribedDate = currentDate;
      _summarySub = _mapRepo
          .watchDailySummary(currentDate)
          .listen(_onSummaryUpdated);
    }

    final profileRes = await _profileRepo.getProfile();
    final summaryRes = await _mapRepo.getTodaySummary();
    if (isClosed) return;

    final profile = switch (profileRes) {
      Ok(:final value) => value,
      Err() => switch (state) {
        HomeReady(:final profile) => profile,
        HomeLoading() => null,
      },
    };
    if (profile == null) {
      final err =
          profileRes.errorOrNull ?? AppError.fromCode('INTERNAL_SERVER_ERROR');
      final fallbackProfile = _emptyFallbackProfile();
      final fallbackSummary = switch (summaryRes) {
        Ok(:final value) => value,
        Err() => DailyActivitySummary.emptyForDate(currentDate),
      };
      emit(
        HomeReady(
          profile: fallbackProfile,
          todaySummary: fallbackSummary,
          mascot: _buildVisualState(
            profile: fallbackProfile,
            summary: fallbackSummary,
            isSquinting: false,
          ),
          bannerError: err,
        ),
      );
      return;
    }

    final summary = switch (summaryRes) {
      Ok(:final value) => value,
      Err() => DailyActivitySummary.emptyForDate(
        currentDate,
        strideLengthCm: profile.strideLengthCm,
        pointsBalance: profile.pointsBalance,
      ),
    };
    final bannerError = switch (profileRes) {
      Err(:final error) => error,
      Ok() => summaryRes.errorOrNull,
    };
    emit(
      HomeReady(
        profile: profile,
        todaySummary: summary,
        mascot: _buildVisualState(
          profile: profile,
          summary: summary,
          isSquinting: false,
        ),
        bannerError: bannerError,
      ),
    );
  }

  Future<void> refreshSensors() async {
    final current = state;
    if (current is HomeReady) {
      emit(current.copyWith(isRefreshing: true, clearBannerError: true));
    }

    final today = _todayIso();
    final currentSteps = current is HomeReady
        ? current.todaySummary.rawSensorSteps
        : 0;
    final syncRes = await _mapRepo.syncDailySteps(
      activityDate: today,
      rawSensorSteps: currentSteps,
      manualRefresh: true,
    );
    if (isClosed) return;

    final latestProfileRes = await _profileRepo.getProfile(forceRefresh: true);
    if (isClosed) return;

    if (state case final HomeReady ready) {
      final nextProfile = latestProfileRes.valueOrNull ?? ready.profile;
      switch (syncRes) {
        case Ok(:final value):
          emit(
            ready.copyWith(
              profile: nextProfile,
              todaySummary: value,
              mascot: _buildVisualState(
                profile: nextProfile,
                summary: value,
                isSquinting: ready.isPointerSquinting,
              ),
              isRefreshing: false,
              clearBannerError: true,
            ),
          );
        case Err(:final error):
          emit(
            ready.copyWith(
              profile: nextProfile,
              isRefreshing: false,
              bannerError: error,
            ),
          );
      }
      return;
    }

    await loadHome();
  }

  void setPointerSquinting(bool down) {
    if (isClosed) return;
    if (state case final HomeReady ready) {
      if (ready.isPointerSquinting == down) return;
      emit(
        ready.copyWith(
          isPointerSquinting: down,
          mascot: _buildVisualState(
            profile: ready.profile,
            summary: ready.todaySummary,
            isSquinting: down,
          ),
        ),
      );
    }
  }

  void dismissBanner() {
    if (isClosed) return;
    if (state case final HomeReady ready) {
      emit(ready.copyWith(clearBannerError: true));
    }
  }

  MascotVisualState _buildVisualState({
    required UserProfile profile,
    required DailyActivitySummary summary,
    required bool isSquinting,
  }) {
    final goal = math.max(1, profile.dailyCo2GoalGrams);
    final ratio = math.max(0.0, summary.totalCo2SavedGrams / goal);
    final mood = MascotVisualSnapshot.resolveMood(
      ratio: ratio,
      isPointerSquinting: isSquinting,
    );
    return profile.mascot.copyWith(mood: mood, dailyGoalProgressRatio: ratio);
  }

  static UserProfile _emptyFallbackProfile() => UserProfile(
    id: '',
    displayName: 'Пользователь',
    friendCode: 'ECO-0000-0000',
    requiresFormalPhone: false,
    pointsBalance: 0,
    lifetimePointsEarned: 0,
    lifetimeCo2SavedGrams: 0,
    currentStreakDays: 0,
    longestStreakDays: 0,
    streakFreezeCount: 0,
    isGpsTrackingEnabled: false,
    isStatsVisibleToFriends: true,
    is152fzConsentActive: true,
    mascot: MascotVisualState.initial(),
    createdAt: '',
  );

  @override
  Future<void> close() async {
    await _profileSub?.cancel();
    await _summarySub?.cancel();
    await super.close();
  }
}
