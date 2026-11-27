import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class const AuthEvent();

final class const AuthSessionChecked() extends AuthEvent;

final class const AuthOnboardingCompleted() extends AuthEvent;

final class const AuthOAuthRequested(
  final AuthProviderType provider,
  final ConsentScopeObject consentScope,
) extends AuthEvent;

final class const AuthGooglePhoneSubmitted(final String phoneE164)
    extends AuthEvent;

final class const AuthConsentSubmitted(
  final String action,
  final ConsentScopeObject scope,
) extends AuthEvent;

final class const AuthLogoutRequested() extends AuthEvent;

final class const AuthForceLogoutRequested([final AppError? error])
    extends AuthEvent;

final class const AuthBannerDismissed() extends AuthEvent;

final class const AuthProfileUpdated(final UserProfile profile)
    extends AuthEvent;

final class const AuthExternalLogoutObserved() extends AuthEvent;

sealed class const AuthState();

final class const AuthInitial() extends AuthState;

final class const AuthOnboardingRequired() extends AuthState;

final class const AuthUnauthenticated() extends AuthState;

final class const AuthAuthenticating([final AuthProviderType? activeProvider])
    extends AuthState;

final class const AuthGooglePhoneRequired(
  final UserProfile profile, [
  final String? warningBanner,
  final AppError? inlineError,
  final bool isSubmitting = false,
]) extends AuthState;

final class const AuthConsentResolutionRequired(
  final UserProfile profile,
  final bool isRevoked, [
  final AppError? inlineError,
  final bool isSubmitting = false,
]) extends AuthState;

final class const AuthAuthenticated(
  final UserProfile profile,
  final bool isForeignLabMode, [
  final String? warningBanner,
]) extends AuthState;

final class const AuthError(final AppError error) extends AuthState;

final class AuthBloc(
  final AuthRepository _authRepo,
  final ProfileRepository _profileRepo, {
  final Future<void> Function()? onSessionActivated,
  final Future<void> Function()? onSessionCleared,
}) extends Bloc<AuthEvent, AuthState> {
  this : super(const AuthInitial()) {
    on<AuthSessionChecked>(_onSessionChecked);
    on<AuthOnboardingCompleted>(_onOnboardingCompleted);
    on<AuthOAuthRequested>(_onOAuthRequested);
    on<AuthGooglePhoneSubmitted>(_onGooglePhoneSubmitted);
    on<AuthConsentSubmitted>(_onConsentSubmitted);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthForceLogoutRequested>(_onForceLogoutRequested);
    on<AuthBannerDismissed>(_onBannerDismissed);
    on<AuthProfileUpdated>(_onProfileUpdated);
    on<AuthExternalLogoutObserved>(_onExternalLogoutObserved);

    _profileSub = _profileRepo.watchUserProfile().listen(
      (profile) => add(AuthProfileUpdated(profile)),
    );
    if (_authRepo case final AuthSessionNotifier notifier) {
      _sessionEndedSub = notifier.onSessionEnded.listen(
        (_) => add(const AuthExternalLogoutObserved()),
      );
    }
  }

  static const String defaultGoogleLabBanner =
      'Внимание: регистрация и вход через иностранный провайдер (Google OAuth) не соответствуют требованиям 406-ФЗ РФ. Данный способ входа включён исключительно для академического / лабораторного тестирования.';

  StreamSubscription<UserProfile>? _profileSub;
  StreamSubscription<void>? _sessionEndedSub;
  bool _isClearingSession = false;

  Future<void> _clearLocalSessionOnly() async {
    if (_isClearingSession) {
      return;
    }
    _isClearingSession = true;
    try {
      await onSessionCleared?.call();
      if (_authRepo case final AuthSessionNotifier clearer) {
        await clearer.clearLocalSessionOnly();
      } else {
        await _profileRepo.clearAllLocalUserData();
      }
    } finally {
      _isClearingSession = false;
    }
  }

  Future<void> _onSessionChecked(
    AuthSessionChecked event,
    Emitter<AuthState> emit,
  ) async {
    final result = await _authRepo.restoreSession();
    switch (result) {
      case Ok(value: final session):
        if (session == null) {
          final seen = await _authRepo.hasCompletedOnboarding();
          emit(
            seen ? const AuthUnauthenticated() : const AuthOnboardingRequired(),
          );
          return;
        }
        await _emitResolvedUser(
          emit,
          session.user,
          isForeignLabMode: session.isForeignProviderLabMode,
          warningBanner: session.labModeWarningBanner,
        );
      case Err(:final error):
        if (error.clientAction == ClientErrorAction.forceLogout) {
          await _clearLocalSessionOnly();
          emit(const AuthUnauthenticated());
        } else {
          emit(AuthError(error));
        }
    }
  }

  Future<void> _onOnboardingCompleted(
    AuthOnboardingCompleted event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepo.markOnboardingStepSeen();
    if (state is AuthOnboardingRequired) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onOAuthRequested(
    AuthOAuthRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthAuthenticating(event.provider));
    final result = await _authRepo.signInWithOAuth(
      provider: event.provider,
      consentScope: event.consentScope,
    );
    switch (result) {
      case Ok(value: final session):
        final banner = session.isForeignProviderLabMode
            ? (session.labModeWarningBanner ?? defaultGoogleLabBanner)
            : null;
        await _emitResolvedUser(
          emit,
          session.user,
          isForeignLabMode: session.isForeignProviderLabMode,
          warningBanner: banner,
        );
      case Err(:final error):
        emit(AuthError(error));
    }
  }

  Future<void> _onGooglePhoneSubmitted(
    AuthGooglePhoneSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    final profile = switch (current) {
      AuthGooglePhoneRequired(:final profile) => profile,
      AuthInitial() ||
      AuthOnboardingRequired() ||
      AuthUnauthenticated() ||
      AuthAuthenticating() ||
      AuthConsentResolutionRequired() ||
      AuthAuthenticated() ||
      AuthError() => null,
    };
    final banner = switch (current) {
      AuthGooglePhoneRequired(:final warningBanner) => warningBanner,
      AuthInitial() ||
      AuthOnboardingRequired() ||
      AuthUnauthenticated() ||
      AuthAuthenticating() ||
      AuthConsentResolutionRequired() ||
      AuthAuthenticated() ||
      AuthError() => defaultGoogleLabBanner,
    };
    if (profile != null) {
      emit(AuthGooglePhoneRequired(profile, banner, null, true));
    }

    final result = await _authRepo.submitGoogleFormalPhone(event.phoneE164);
    switch (result) {
      case Ok(value: final updated):
        await _emitResolvedUser(
          emit,
          updated,
          isForeignLabMode: true,
          warningBanner: banner ?? defaultGoogleLabBanner,
        );
      case Err(:final error):
        if (error.clientAction == ClientErrorAction.forceLogout) {
          await _clearLocalSessionOnly();
          emit(const AuthUnauthenticated());
          return;
        }
        if (profile != null) {
          emit(AuthGooglePhoneRequired(profile, banner, error));
        } else {
          emit(AuthError(error));
        }
    }
  }

  Future<void> _onConsentSubmitted(
    AuthConsentSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    final currentProfile = switch (current) {
      AuthConsentResolutionRequired(:final profile) => profile,
      AuthAuthenticated(:final profile) => profile,
      AuthInitial() ||
      AuthOnboardingRequired() ||
      AuthUnauthenticated() ||
      AuthAuthenticating() ||
      AuthGooglePhoneRequired() ||
      AuthError() => null,
    };
    final wasRevoked = switch (current) {
      AuthConsentResolutionRequired(:final isRevoked) => isRevoked,
      AuthInitial() ||
      AuthOnboardingRequired() ||
      AuthUnauthenticated() ||
      AuthAuthenticating() ||
      AuthGooglePhoneRequired() ||
      AuthAuthenticated() ||
      AuthError() => true,
    };
    if (currentProfile != null) {
      emit(
        AuthConsentResolutionRequired(currentProfile, wasRevoked, null, true),
      );
    }

    final consentResult = await _authRepo.recordConsent(
      policyVersion: '1.0.0-2026',
      action: event.action,
      scope: event.scope,
    );
    switch (consentResult) {
      case Ok():
        final profileRes = await _profileRepo.getProfile(forceRefresh: true);
        switch (profileRes) {
          case Ok(value: final refreshed):
            await _emitResolvedUser(
              emit,
              refreshed,
              isForeignLabMode: refreshed.isForeignProviderLabMode,
              warningBanner: refreshed.isForeignProviderLabMode
                  ? defaultGoogleLabBanner
                  : null,
            );
          case Err(:final error):
            if (error.clientAction == ClientErrorAction.forceLogout) {
              await _clearLocalSessionOnly();
              emit(const AuthUnauthenticated());
              return;
            }
            if (currentProfile != null) {
              emit(
                AuthConsentResolutionRequired(
                  currentProfile,
                  wasRevoked,
                  error,
                ),
              );
            } else {
              emit(AuthError(error));
            }
        }
      case Err(:final error):
        if (error.clientAction == ClientErrorAction.forceLogout) {
          await _clearLocalSessionOnly();
          emit(const AuthUnauthenticated());
          return;
        }
        if (currentProfile != null) {
          emit(
            AuthConsentResolutionRequired(currentProfile, wasRevoked, error),
          );
        } else {
          emit(AuthError(error));
        }
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (_isClearingSession) {
      return;
    }
    _isClearingSession = true;
    try {
      await onSessionCleared?.call();
      await _authRepo.logout();
      emit(const AuthUnauthenticated());
    } finally {
      _isClearingSession = false;
    }
  }

  Future<void> _onForceLogoutRequested(
    AuthForceLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (_isClearingSession ||
        state is AuthUnauthenticated ||
        state is AuthOnboardingRequired) {
      return;
    }
    await _clearLocalSessionOnly();
    emit(const AuthUnauthenticated());
  }

  void _onBannerDismissed(AuthBannerDismissed event, Emitter<AuthState> emit) {
    switch (state) {
      case AuthAuthenticated(:final profile, :final isForeignLabMode):
        emit(AuthAuthenticated(profile, isForeignLabMode));
      case AuthGooglePhoneRequired(:final profile, :final inlineError):
        emit(AuthGooglePhoneRequired(profile, null, inlineError));
      case AuthInitial() ||
          AuthOnboardingRequired() ||
          AuthUnauthenticated() ||
          AuthAuthenticating() ||
          AuthConsentResolutionRequired() ||
          AuthError():
        break;
    }
  }

  Future<void> _onProfileUpdated(
    AuthProfileUpdated event,
    Emitter<AuthState> emit,
  ) async {
    final profile = event.profile;
    switch (state) {
      case AuthAuthenticated(:final isForeignLabMode, :final warningBanner):
        await _emitResolvedUser(
          emit,
          profile,
          isForeignLabMode:
              isForeignLabMode || profile.isForeignProviderLabMode,
          warningBanner: warningBanner,
        );
      case AuthGooglePhoneRequired(:final warningBanner):
        await _emitResolvedUser(
          emit,
          profile,
          isForeignLabMode: true,
          warningBanner: warningBanner,
        );
      case AuthConsentResolutionRequired():
        if (profile.is152fzConsentActive) {
          await _emitResolvedUser(
            emit,
            profile,
            isForeignLabMode: profile.isForeignProviderLabMode,
            warningBanner: profile.isForeignProviderLabMode
                ? defaultGoogleLabBanner
                : null,
          );
        }
      case AuthInitial() ||
          AuthOnboardingRequired() ||
          AuthUnauthenticated() ||
          AuthAuthenticating() ||
          AuthError():
        break;
    }
  }

  Future<void> _onExternalLogoutObserved(
    AuthExternalLogoutObserved event,
    Emitter<AuthState> emit,
  ) async {
    if (_isClearingSession ||
        state is AuthUnauthenticated ||
        state is AuthOnboardingRequired) {
      return;
    }
    await onSessionCleared?.call();
    emit(const AuthUnauthenticated());
  }

  Future<void> _emitResolvedUser(
    Emitter<AuthState> emit,
    UserProfile profile, {
    required bool isForeignLabMode,
    String? warningBanner,
  }) async {
    if (!profile.is152fzConsentActive) {
      emit(AuthConsentResolutionRequired(profile, true));
      return;
    }
    if (profile.requiresFormalPhone) {
      emit(
        AuthGooglePhoneRequired(
          profile,
          warningBanner ?? defaultGoogleLabBanner,
        ),
      );
      return;
    }
    await onSessionActivated?.call();
    emit(AuthAuthenticated(profile, isForeignLabMode, warningBanner));
  }

  @override
  Future<void> close() async {
    await _profileSub?.cancel();
    await _sessionEndedSub?.cancel();
    await super.close();
  }
}
