import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/login_screen.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeAuthRepository implements AuthRepository {
  @override
  Future<Result<AuthSession, AppError>> login({
    required String email,
    required String password,
  }) async => const Ok(
    AuthSession(
      accessToken: 'fake_access',
      refreshToken: 'fake_refresh',
      userId: 'usr_001',
      displayName: 'Тест',
      email: 'test@ecotrack.ru',
      phoneMasked: '+7 (***) ***-00-00',
      hasFz152Consent: true,
    ),
  );

  @override
  Future<Result<AuthSession, AppError>> register({
    required String displayName,
    required String email,
    required String password,
    required String ruPhone,
    required bool allowPdnProcessing,
    required bool allowTelemetry,
  }) async => const Ok(
    AuthSession(
      accessToken: 'fake_access',
      refreshToken: 'fake_refresh',
      userId: 'usr_001',
      displayName: 'Тест',
      email: 'test@ecotrack.ru',
      phoneMasked: '+7 (***) ***-00-00',
      hasFz152Consent: true,
    ),
  );

  @override
  Future<Result<AuthSession, AppError>> loginWithGoogle({
    required String googleAuthCode,
    String? phone,
  }) async => const Ok(
    AuthSession(
      accessToken: 'fake_access',
      refreshToken: 'fake_refresh',
      userId: 'usr_001',
      displayName: 'Тест',
      email: 'test@ecotrack.ru',
      phoneMasked: '+7 (***) ***-00-00',
      hasFz152Consent: true,
    ),
  );

  @override
  Future<Result<void, AppError>> submitFz152Consent({
    required bool allowPdnProcessing,
    required bool allowTelemetry,
  }) async => const Ok(null);

  @override
  Future<AuthSession?> getCurrentSession() async => null;

  @override
  Future<void> logout() async {}
}

void main() {
  group('Auth & Navigation Flow Widget Tests', () {
    testWidgets('OnboardingScreen renders with 152-FZ consent indicators', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: EcoTheme.darkTheme,
          home: BlocProvider<AuthCubit>(
            create: (_) => AuthCubit(_FakeAuthRepository()),
            child: const OnboardingScreen(),
          ),
        ),
      );

      expect(find.textContaining('EcoTrack'), findsOneWidget);
      expect(
        find.textContaining('Отслеживай свой углеродный след'),
        findsOneWidget,
      );
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Далее'), findsOneWidget);
    });

    testWidgets('LoginScreen renders email/password fields and buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: EcoTheme.darkTheme,
          home: BlocProvider<AuthCubit>(
            create: (_) => AuthCubit(_FakeAuthRepository()),
            child: const LoginScreen(),
          ),
        ),
      );

      expect(find.text('EcoTrack'), findsOneWidget);
      expect(find.text('Вход в аккаунт'), findsOneWidget);
      expect(find.text('Электронная почта'), findsOneWidget);
      expect(find.text('Пароль'), findsOneWidget);
      expect(find.text('Войти'), findsOneWidget);
      expect(find.textContaining('Google'), findsOneWidget);
    });
  });
}
