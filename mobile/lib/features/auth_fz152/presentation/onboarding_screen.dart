import 'dart:async';

import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/fz152_consent_modal.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

typedef MascotWidgetBuilder = Widget Function(
  String moodWire, {
  String? accessoryCode,
});

final class const OnboardingScreen({
  final int initialStep = 1,
  final MascotWidgetBuilder? mascotBuilder,
  final Future<bool> Function()? onRequestStepsPermission,
  final Future<bool> Function()? onRequestGpsPermission,
  super.key,
}) extends StatefulWidget {
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

final class _OnboardingScreenState() extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _stepsPermissionGranted = false;
  bool _gpsTrackingConsent = false;
  bool _fz152ConsentAccepted = false;

  @override
  void initState() {
    super.initState();
    _currentPage = (widget.initialStep - 1).clamp(0, 2);
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void didUpdateWidget(covariant OnboardingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = (widget.initialStep - 1).clamp(0, 2);
    if (oldWidget.initialStep != widget.initialStep && target != _currentPage) {
      _currentPage = target;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(target);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _jumpToStep3() {
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _requestStepAccess() async {
    final callback = widget.onRequestStepsPermission;
    final granted = callback == null || await callback();
    if (mounted) {
      setState(() => _stepsPermissionGranted = granted);
    }
  }

  Future<void> _toggleGps(bool enabled) async {
    final callback = widget.onRequestGpsPermission;
    if (enabled && callback != null) {
      final granted = await callback();
      if (mounted) {
        setState(() => _gpsTrackingConsent = granted);
      }
      return;
    }
    setState(() => _gpsTrackingConsent = enabled);
  }

  void _signInWithProvider(AuthProviderType provider) {
    if (!_fz152ConsentAccepted) {
      return;
    }
    context.read<AuthBloc>().add(
      AuthOAuthRequested(
        provider,
        ConsentScopeObject(
          personalData152fz: _fz152ConsentAccepted,
          healthStepsSensor: true,
          backgroundGeolocation: _gpsTrackingConsent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocListener<AuthBloc, AuthState>(
    listener: (context, state) {
      if (state case AuthError(:final error)) {
        EcoErrorBannerPresenter.show(context, error);
      }
    },
    child: Scaffold(
      backgroundColor: EcoColors.surfacePrimary,
      body: SafeArea(
        child: Column(
          children: [
            _TopProgressHeader(currentPage: _currentPage, onSkip: _jumpToStep3),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [
                  _OnboardingStepOne(
                    mascotBuilder: widget.mascotBuilder,
                    onNext: _nextPage,
                  ),
                  _OnboardingStepTwo(
                    stepsGranted: _stepsPermissionGranted,
                    gpsEnabled: _gpsTrackingConsent,
                    onRequestSteps: () => unawaited(_requestStepAccess()),
                    onGpsChanged: (val) => unawaited(_toggleGps(val)),
                    onNext: _nextPage,
                  ),
                  _OnboardingStepThree(
                    mascotBuilder: widget.mascotBuilder,
                    consentAccepted: _fz152ConsentAccepted,
                    onConsentChanged: (val) =>
                        setState(() => _fz152ConsentAccepted = val),
                    onReadPolicy: () =>
                        unawaited(Fz152PolicySheet.show(context)),
                    onSelectProvider: _signInWithProvider,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _TopProgressHeader({
  required final int currentPage,
  required final VoidCallback onSkip,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const .fromLTRB(20, 10, 12, 4),
    child: Row(
      children: [
        Row(
          children: List.generate(
            3,
            (idx) => Container(
              margin: const .only(right: 6),
              width: idx == currentPage ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: idx == currentPage
                    ? EcoColors.inkPrimary
                    : EcoColors.surfaceCard,
                borderRadius: const .all(.circular(4)),
              ),
            ),
          ),
        ),
        const Spacer(),
        if (currentPage < 2)
          TextButton(onPressed: onSkip, child: const Text('Пропустить'))
        else
          const SizedBox(height: 48),
      ],
    ),
  );
}

final class const _OnboardingStepOne({
  required final MascotWidgetBuilder? mascotBuilder,
  required final VoidCallback onNext,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const .fromLTRB(20, 12, 20, 24),
    children: [
      const Text(
        'Шагайте по городу — копите эко-вклад',
        style: EcoTypography.displayHero,
      ),
      const SizedBox(height: 16),
      const _WireframePillBanner(
        text: 'EcoTrack считает ваши шаги с датчиков смартфона и переводит маршруты в граммы CO₂',
        alignLeft: true,
      ),
      const SizedBox(height: 12),
      const _WireframePillBanner(
        text: 'Накапливайте эко-баллы ★ за каждую прогулку без автомобиля',
        alignLeft: false,
      ),
      const SizedBox(height: 24),
      Center(
        child: _MascotCircleFrame(
          mascotBuilder: mascotBuilder,
          moodWire: 'happy',
          badgeText: 'День 1',
        ),
      ),
      const SizedBox(height: 28),
      SizedBox(
        height: 56,
        child: ElevatedButton(
          onPressed: onNext,
          child: const Row(
            mainAxisAlignment: .center,
            children: [
              Text('Далее'),
              SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, size: 20),
            ],
          ),
        ),
      ),
    ],
  );
}

final class const _OnboardingStepTwo({
  required final bool stepsGranted,
  required final bool gpsEnabled,
  required final VoidCallback onRequestSteps,
  required final ValueChanged<bool> onGpsChanged,
  required final VoidCallback onNext,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const .fromLTRB(20, 12, 20, 24),
    children: [
      const Text(
        'Точный учёт без ручного ввода',
        style: EcoTypography.displayHero,
      ),
      const SizedBox(height: 12),
      const Text(
        'Шаги считываются автоматически через системные датчики здоровья. Если включить запись GPS-маршрута, вы сможете отмечать, вместо какого транспорта прошли пешком, получая 100% коэффициент точности.',
        style: EcoTypography.bodyMedium,
      ),
      const SizedBox(height: 20),
      DecoratedBox(
        decoration: const BoxDecoration(
          color: EcoColors.surfaceCard,
          borderRadius: .all(.circular(20)),
          border: .fromBorderSide(
            BorderSide(color: EcoColors.borderMuted, width: 1.5),
          ),
        ),
        child: Padding(
          padding: const .all(16),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              const Row(
                children: [
                  Icon(
                    LucideIcons.footprints,
                    size: 20,
                    color: EcoColors.inkPrimary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Доступ к датчику шагов (обязательно для начисления ★)',
                      style: EcoTypography.bodyLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRequestSteps,
                icon: Icon(
                  stepsGranted ? LucideIcons.check : LucideIcons.shieldCheck,
                  size: 18,
                ),
                label: Text(
                  stepsGranted ? 'Доступ разрешён' : 'Запросить доступ',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      DecoratedBox(
        decoration: const BoxDecoration(
          color: EcoColors.surfaceSubtle,
          borderRadius: .all(.circular(20)),
          border: .fromBorderSide(
            BorderSide(color: EcoColors.borderMuted, width: 1.5),
          ),
        ),
        child: Padding(
          padding: const .all(16),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.mapPin,
                    size: 20,
                    color: EcoColors.inkPrimary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Фоновая запись маршрута GPS (опционально)',
                      style: EcoTypography.bodyLarge,
                    ),
                  ),
                  Switch(value: gpsEnabled, onChanged: onGpsChanged),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Если GPS выключен, приложение автоматически считает эковклад по базовой формуле (80% × 0.7).',
                style: EcoTypography.labelSmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      SizedBox(
        height: 56,
        child: ElevatedButton(
          onPressed: onNext,
          child: const Row(
            mainAxisAlignment: .center,
            children: [
              Text('Далее'),
              SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, size: 20),
            ],
          ),
        ),
      ),
    ],
  );
}

final class const _OnboardingStepThree({
  required final MascotWidgetBuilder? mascotBuilder,
  required final bool consentAccepted,
  required final ValueChanged<bool> onConsentChanged,
  required final VoidCallback onReadPolicy,
  required final ValueChanged<AuthProviderType> onSelectProvider,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthState>(
    builder: (context, authState) {
      final AuthProviderType? loadingProvider = switch (authState) {
        AuthAuthenticating(:final activeProvider) => activeProvider,
        _ => null,
      };
      final bool anyLoading = authState is AuthAuthenticating;

      return ListView(
        padding: const .fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Забота о природе приносит пользу и подарки',
            style: EcoTypography.displayHero,
          ),
          const SizedBox(height: 14),
          const _WireframePillBanner(
            text: 'Виртуальный зверёк растёт и развивается вместе с вашими успехами',
            alignLeft: true,
          ),
          const SizedBox(height: 10),
          const _WireframePillBanner(
            text: 'Обменивайте накопленные баллы на скидки и промокоды от наших партнёров',
            alignLeft: false,
          ),
          const SizedBox(height: 16),
          Center(
            child: _MascotCircleFrame(
              mascotBuilder: mascotBuilder,
              moodWire: 'thriving',
              badgeText: '+100 ★ за старт',
            ),
          ),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: EcoColors.surfacePrimary,
              borderRadius: .all(.circular(16)),
              border: .fromBorderSide(
                BorderSide(color: EcoColors.inkPrimary, width: 1.5),
              ),
            ),
            child: InkWell(
              onTap: () => onConsentChanged(!consentAccepted),
              borderRadius: const .all(.circular(16)),
              child: Padding(
                padding: const .symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  crossAxisAlignment: .start,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Checkbox(
                        value: consentAccepted,
                        onChanged: (v) => onConsentChanged(v ?? false),
                      ),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: .only(top: 6),
                        child: Text(
                          'Я принимаю Политику конфиденциальности и даю согласие на обработку персональных данных (включая показатели активности и геопозицию) согласно 152-ФЗ РФ.',
                          style: EcoTypography.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: .centerLeft,
            child: TextButton(
              onPressed: onReadPolicy,
              child: const Text('Читать полный текст согласия 152-ФЗ'),
            ),
          ),
          const SizedBox(height: 8),
          _OAuthProviderButton(
            label: 'Войти через Яндекс ID',
            enabled: consentAccepted && !anyLoading,
            isLoading: loadingProvider == .yandex,
            variant: _OAuthButtonVariant.yandex,
            onPressed: () => onSelectProvider(.yandex),
          ),
          const SizedBox(height: 10),
          _OAuthProviderButton(
            label: 'Войти через VK ID',
            enabled: consentAccepted && !anyLoading,
            isLoading: loadingProvider == .vk,
            variant: _OAuthButtonVariant.vk,
            onPressed: () => onSelectProvider(.vk),
          ),
          const SizedBox(height: 10),
          _OAuthProviderButton(
            label: 'Войти через Google (Лаб. режим)',
            enabled: consentAccepted && !anyLoading,
            isLoading: loadingProvider == .google,
            variant: _OAuthButtonVariant.google,
            onPressed: () => onSelectProvider(.google),
          ),
        ],
      );
    },
  );
}

enum _OAuthButtonVariant() {
  yandex,
  vk,
  google,
}

final class const _OAuthProviderButton({
  required final String label,
  required final bool enabled,
  required final bool isLoading,
  required final _OAuthButtonVariant variant,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color fgColor;
    final BorderSide side;
    if (!enabled) {
      bgColor = EcoColors.fillDisabled;
      fgColor = EcoColors.inkSecondary;
      side = .none;
    } else {
      switch (variant) {
        case .yandex:
          bgColor = EcoColors.inkPrimary;
          fgColor = EcoColors.surfacePrimary;
          side = .none;
        case .vk:
          bgColor = EcoColors.surfacePrimary;
          fgColor = EcoColors.inkPrimary;
          side = const BorderSide(color: EcoColors.inkPrimary, width: 1.5);
        case .google:
          bgColor = EcoColors.surfaceSubtle;
          fgColor = EcoColors.inkPrimary;
          side = const BorderSide(color: EcoColors.borderMuted, width: 1.5);
      }
    }

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          disabledBackgroundColor: EcoColors.fillDisabled,
          disabledForegroundColor: EcoColors.inkSecondary,
          side: side,
          shape: const RoundedRectangleBorder(
            borderRadius: .all(.circular(28)),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fgColor,
                ),
              )
            : Text(
                label,
                style: EcoTypography.bodyLarge.copyWith(color: fgColor),
              ),
      ),
    );
  }
}

final class const _WireframePillBanner({
  required final String text,
  required final bool alignLeft,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Align(
    alignment: alignLeft ? .centerLeft : .centerRight,
    child: FractionallySizedBox(
      widthFactor: 0.9,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: EcoColors.surfaceCard,
          borderRadius: .all(.circular(28)),
        ),
        child: Padding(
          padding: const .symmetric(horizontal: 18, vertical: 14),
          child: Text(
            text,
            textAlign: .center,
            style: EcoTypography.bodyMedium,
          ),
        ),
      ),
    ),
  );
}

final class const _MascotCircleFrame({
  required final MascotWidgetBuilder? mascotBuilder,
  required final String moodWire,
  required final String badgeText,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: .min,
    children: [
      DecoratedBox(
        decoration: const BoxDecoration(
          color: EcoColors.surfaceSubtle,
          shape: .circle,
          border: .fromBorderSide(
            BorderSide(color: EcoColors.borderMuted, width: 1.5),
          ),
        ),
        child: SizedBox(
          width: 176,
          height: 176,
          child: Center(
            child:
                mascotBuilder?.call(moodWire) ??
                const Icon(
                  LucideIcons.sparkles,
                  size: 56,
                  color: EcoColors.inkPrimary,
                ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      DecoratedBox(
        decoration: const BoxDecoration(
          color: EcoColors.surfacePrimary,
          borderRadius: .all(.circular(999)),
          border: .fromBorderSide(
            BorderSide(color: EcoColors.borderMuted, width: 1.5),
          ),
        ),
        child: Padding(
          padding: const .symmetric(horizontal: 12, vertical: 4),
          child: Text(badgeText, style: EcoTypography.labelSmall),
        ),
      ),
    ],
  );
}
