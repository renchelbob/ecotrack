import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

sealed class const ProfileSettingsState();

final class const ProfileSettingsLoading() extends ProfileSettingsState;

final class const ProfileSettingsLoaded({
  required final UserProfile profile,
  required final BadgesListResponse badges,
  required final MascotInventoryResponse accessories,
  required final ConsentHistoryListResponse consents,
  final AccountDeletionReceipt? deletionReceipt,
  final bool isSaving = false,
  final bool pushNotificationsEnabled = true,
  final AppError? activeError,
}) extends ProfileSettingsState {
  ProfileSettingsLoaded copyWith({
    UserProfile? profile,
    BadgesListResponse? badges,
    MascotInventoryResponse? accessories,
    ConsentHistoryListResponse? consents,
    AccountDeletionReceipt? deletionReceipt,
    bool? isSaving,
    bool? pushNotificationsEnabled,
    AppError? activeError,
    bool clearError = false,
  }) => ProfileSettingsLoaded(
    profile: profile ?? this.profile,
    badges: badges ?? this.badges,
    accessories: accessories ?? this.accessories,
    consents: consents ?? this.consents,
    deletionReceipt: deletionReceipt ?? this.deletionReceipt,
    isSaving: isSaving ?? this.isSaving,
    pushNotificationsEnabled:
        pushNotificationsEnabled ?? this.pushNotificationsEnabled,
    activeError: clearError ? null : (activeError ?? this.activeError),
  );
}

final class const ProfileSettingsFailure(final AppError error)
    extends ProfileSettingsState;

final class ProfileSettingsCubit(
  final ProfileRepository _profileRepo,
  final AuthRepository _authRepo,
) extends Cubit<ProfileSettingsState> {
  this : super(const ProfileSettingsLoading()) {
    _profileSub = _profileRepo.watchUserProfile().listen(_onProfileBroadcast);
  }

  static const String _pushPrefKey = 'ecotrack_push_notifications_enabled';

  StreamSubscription<UserProfile>? _profileSub;

  void _onProfileBroadcast(UserProfile profile) {
    if (isClosed) {
      return;
    }
    if (state case final ProfileSettingsLoaded loaded) {
      emit(loaded.copyWith(profile: profile));
    }
  }

  Future<void> load() async {
    if (state is! ProfileSettingsLoaded) {
      emit(const ProfileSettingsLoading());
    }
    final profileRes = await _profileRepo.getProfile(forceRefresh: true);
    switch (profileRes) {
      case Err(:final error):
        if (state is ProfileSettingsLoaded) {
          final loaded = state as ProfileSettingsLoaded;
          emit(loaded.copyWith(activeError: error, isSaving: false));
        } else {
          emit(ProfileSettingsFailure(error));
        }
      case Ok(value: final profile):
        final badges = switch (await _profileRepo.listBadges()) {
          Ok(:final value) => value,
          Err() => const BadgesListResponse(
            unlockedCount: 0,
            totalCount: 0,
            badges: [],
          ),
        };
        final accessories = switch (await _profileRepo
            .listMascotAccessories()) {
          Ok(:final value) => value,
          Err() => const MascotInventoryResponse(accessories: []),
        };
        final consents = switch (await _authRepo.getConsentHistory()) {
          Ok(:final value) => value,
          Err() => ConsentHistoryListResponse(
            is152fzConsentActive: profile.is152fzConsentActive,
            entries: const [],
          ),
        };
        final prefs = await SharedPreferences.getInstance();
        final pushEnabled = prefs.getBool(_pushPrefKey) ?? true;

        if (!isClosed) {
          emit(
            ProfileSettingsLoaded(
              profile: profile,
              badges: badges,
              accessories: accessories,
              consents: consents,
              pushNotificationsEnabled: pushEnabled,
            ),
          );
        }
    }
  }

  Future<void> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _applyProfileUpdate(UpdateUserProfileRequest(displayName: trimmed));
  }

  Future<void> updateAvatarSeed(String avatarSeed) =>
      _applyProfileUpdate(UpdateUserProfileRequest(avatarUrl: avatarSeed));

  Future<void> updateGoals({int? dailyStepGoal, int? dailyCo2GoalGrams}) =>
      _applyProfileUpdate(
        UpdateUserProfileRequest(
          dailyStepGoal: dailyStepGoal,
          dailyCo2GoalGrams: dailyCo2GoalGrams,
        ),
      );

  Future<void> updateGpsPrefs({bool? enabled, int? intervalSeconds}) =>
      _applyProfileUpdate(
        UpdateUserProfileRequest(
          isGpsTrackingEnabled: enabled,
          gpsIntervalSeconds: intervalSeconds,
        ),
      );

  Future<void> updatePrivacy({bool? isStatsVisibleToFriends}) =>
      _applyProfileUpdate(
        UpdateUserProfileRequest(
          isStatsVisibleToFriends: isStatsVisibleToFriends,
        ),
      );

  Future<void> togglePushNotifications(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushPrefKey, enabled);
    if (state case final ProfileSettingsLoaded loaded) {
      emit(loaded.copyWith(pushNotificationsEnabled: enabled));
    }
  }

  Future<void> refreshConsents() async {
    if (state case final ProfileSettingsLoaded loaded) {
      final result = await _authRepo.getConsentHistory();
      switch (result) {
        case Ok(:final value):
          emit(loaded.copyWith(consents: value, clearError: true));
        case Err(:final error):
          emit(loaded.copyWith(activeError: error));
      }
    }
  }

  Future<void> revokeConsent() async {
    if (state case final ProfileSettingsLoaded loaded) {
      emit(loaded.copyWith(isSaving: true, clearError: true));
      final res = await _authRepo.recordConsent(
        policyVersion: '1.0.0-2026',
        action: 'revoked',
        scope: const ConsentScopeObject(
          personalData152fz: false,
          healthStepsSensor: false,
          backgroundGeolocation: false,
        ),
      );
      switch (res) {
        case Ok():
          await _profileRepo.getProfile(forceRefresh: true);
          await load();
        case Err(:final error):
          emit(loaded.copyWith(isSaving: false, activeError: error));
      }
    }
  }

  Future<Result<AccountDeletionReceipt, AppError>> deleteAccount(
    String reason,
    String phrase,
  ) async {
    if (state case final ProfileSettingsLoaded loaded) {
      emit(loaded.copyWith(isSaving: true, clearError: true));
    }
    final result = await _profileRepo.deleteAccount(reason, phrase);
    if (isClosed) {
      return result;
    }
    switch (result) {
      case Ok(value: final receipt):
        if (state case final ProfileSettingsLoaded loaded) {
          emit(
            loaded.copyWith(
              deletionReceipt: receipt,
              isSaving: false,
              clearError: true,
            ),
          );
        }
      case Err(:final error):
        if (state case final ProfileSettingsLoaded loaded) {
          emit(loaded.copyWith(isSaving: false, activeError: error));
        }
    }
    return result;
  }

  Future<void> finishAccountDeletionLogout() => _authRepo.logout();

  Future<void> equipAccessory(String? code) async {
    if (state case final ProfileSettingsLoaded loaded) {
      emit(loaded.copyWith(isSaving: true, clearError: true));
      final res = await _profileRepo.equipMascotAccessory(code);
      switch (res) {
        case Ok(value: final updatedProfile):
          final updatedInv = switch (await _profileRepo
              .listMascotAccessories()) {
            Ok(:final value) => value,
            Err() => MascotInventoryResponse(
              accessories: loaded.accessories.accessories
                  .map(
                    (a) => MascotAccessoryItem(
                      code: a.code,
                      nameRu: a.nameRu,
                      slot: a.slot,
                      vectorLayerKey: a.vectorLayerKey,
                      unlockType: a.unlockType,
                      isUnlocked: a.isUnlocked,
                      isEquipped: a.code == code,
                      acquiredAt: a.acquiredAt,
                    ),
                  )
                  .toList(),
            ),
          };
          if (!isClosed) {
            emit(
              loaded.copyWith(
                profile: updatedProfile,
                accessories: updatedInv,
                isSaving: false,
                clearError: true,
              ),
            );
          }
        case Err(:final error):
          if (!isClosed) {
            emit(loaded.copyWith(isSaving: false, activeError: error));
          }
      }
    }
  }

  Future<void> logout() => _authRepo.logout();

  void clearError() {
    if (state case final ProfileSettingsLoaded loaded) {
      emit(loaded.copyWith(clearError: true));
    }
  }

  Future<void> _applyProfileUpdate(UpdateUserProfileRequest req) async {
    if (state case final ProfileSettingsLoaded loaded) {
      emit(loaded.copyWith(isSaving: true, clearError: true));
      final res = await _profileRepo.updateProfile(req);
      if (isClosed) {
        return;
      }
      switch (res) {
        case Ok(value: final updated):
          emit(
            loaded.copyWith(
              profile: updated,
              isSaving: false,
              clearError: true,
            ),
          );
        case Err(:final error):
          emit(loaded.copyWith(isSaving: false, activeError: error));
      }
    }
  }

  @override
  Future<void> close() async {
    await _profileSub?.cancel();
    await super.close();
  }
}
