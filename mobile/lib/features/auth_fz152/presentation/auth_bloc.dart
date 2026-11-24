import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class AuthState {
  const AuthState();
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthLoading extends AuthState {
  const AuthLoading();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);
  final AuthSession session;
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

final class AuthFailure extends AuthState {
  const AuthFailure(this.error);
  final AppError error;
}

final class AuthPhoneRequiredState extends AuthState {
  const AuthPhoneRequiredState(this.authCode);
  final String authCode;
}

final class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository) : super(const AuthInitial());

  final AuthRepository _authRepository;

  Future<void> checkSession() async {
    final session = await _authRepository.getCurrentSession();
    if (session != null) {
      emit(AuthAuthenticated(session));
    } else {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> login(String email, String password) async {
    emit(const AuthLoading());
    final result = await _authRepository.login(
      email: email,
      password: password,
    );
    switch (result) {
      case Ok(value: final session):
        emit(AuthAuthenticated(session));
      case Err(error: final appError):
        emit(AuthFailure(appError));
    }
  }

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
    required String ruPhone,
    required bool allowPdnProcessing,
    required bool allowTelemetry,
  }) async {
    emit(const AuthLoading());
    final result = await _authRepository.register(
      displayName: displayName,
      email: email,
      password: password,
      ruPhone: ruPhone,
      allowPdnProcessing: allowPdnProcessing,
      allowTelemetry: allowTelemetry,
    );
    switch (result) {
      case Ok(value: final session):
        emit(AuthAuthenticated(session));
      case Err(error: final appError):
        emit(AuthFailure(appError));
    }
  }

  Future<void> loginWithGoogle(String authCode, [String? phone]) async {
    emit(const AuthLoading());
    final result = await _authRepository.loginWithGoogle(
      googleAuthCode: authCode,
      phone: phone,
    );
    switch (result) {
      case Ok(value: final session):
        emit(AuthAuthenticated(session));
      case Err(error: final appError):
        if (appError.code == 'FZ152_GOOGLE_PHONE_REQUIRED') {
          emit(AuthPhoneRequiredState(authCode));
        } else {
          emit(AuthFailure(appError));
        }
    }
  }

  Future<void> submitConsent({
    required bool allowPdnProcessing,
    required bool allowTelemetry,
  }) async {
    final result = await _authRepository.submitFz152Consent(
      allowPdnProcessing: allowPdnProcessing,
      allowTelemetry: allowTelemetry,
    );
    if (result is Err) {
      emit(AuthFailure(result.error));
    }
  }

  Future<void> logout() async {
    await _authRepository.logout();
    emit(const AuthUnauthenticated());
  }
}
