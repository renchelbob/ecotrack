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
      body: PageView(
        controller: _pageController,
        onPageChanged: (idx) => setState(() => _currentPage = idx),
        children: [
          _OnboardingStepOne(
            mascotBuilder: widget.mascotBuilder,
            onNext: _nextPage,
          ),
          _OnboardingStepTwo(
            mascotBuilder: widget.mascotBuilder,
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
            onReadPolicy: () => unawaited(Fz152PolicySheet.show(context)),
            onSelectProvider: _signInWithProvider,
          ),
        ],
      ),
    ),
  );
}

final class const _MascotArt({
  required final MascotWidgetBuilder? mascotBuilder,
  required final String moodWire,
  required final double size,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final child = mascotBuilder?.call(moodWire);
    if (child != null) {
      return SizedBox(
        width: size,
        height: size,
        child: FittedBox(child: child),
      );
    }
    return Icon(
      LucideIcons.sparkles,
      size: size * 0.45,
      color: EcoColors.inkPrimary,
    );
  }
}

final class const _OnboardingStepOne({
  required final MascotWidgetBuilder? mascotBuilder,
  required final VoidCallback onNext,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: EcoColors.surfacePrimary,
    child: Stack(
      children: [
        const Positioned(
          top: 90,
          right: -110,
          width: 340,
          height: 360,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: .circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFB3B3B3),
                    Color(0x66CCCCCC),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const .fromLTRB(28, 28, 28, 24),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  'EcoTrack',
                  style: EcoTypography.displayHero.copyWith(
                    fontSize: 44,
                    fontWeight: .w400,
                    letterSpacing: -0.8,
                  ),
                ),
                const Spacer(flex: 2),
                Align(
                  alignment: const Alignment(-0.22, 0),
                  child: _MascotArt(
                    mascotBuilder: mascotBuilder,
                    moodWire: 'neutral',
                    size: 230,
                  ),
                ),
                const Spacer(flex: 2),
                const _FeaturePhraseList(),
                const SizedBox(height: 24),
                const _OnboardingDots(activeIndex: 0),
                const SizedBox(height: 22),
                _WireframeActionButton(
                  label: 'Продолжить',
                  enabled: true,
                  isLoading: false,
                  onPressed: onNext,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

final class const _FeaturePhraseList() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: .min,
    children: [
      Text(
        'сокращай углеродный след',
        textAlign: .center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16.5,
          fontWeight: .w400,
          color: EcoColors.inkPrimary,
        ),
      ),
      SizedBox(height: 8),
      Icon(LucideIcons.leaf, size: 22, color: Color(0xFFC0C0C0)),
      SizedBox(height: 8),
      Text(
        'поддерживай эко-привычки',
        textAlign: .center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16.5,
          fontWeight: .w400,
          color: EcoColors.inkPrimary,
        ),
      ),
      SizedBox(height: 8),
      Icon(LucideIcons.leaf, size: 22, color: Color(0xFFC0C0C0)),
      SizedBox(height: 8),
      Text(
        'получай бонусы и скидки',
        textAlign: .center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16.5,
          fontWeight: .w400,
          color: EcoColors.inkPrimary,
        ),
      ),
    ],
  );
}

final class const _OnboardingStepTwo({
  required final MascotWidgetBuilder? mascotBuilder,
  required final bool stepsGranted,
  required final bool gpsEnabled,
  required final VoidCallback onRequestSteps,
  required final ValueChanged<bool> onGpsChanged,
  required final VoidCallback onNext,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFC5C5C5),
    child: Stack(
      children: [
        Positioned(
          top: 28,
          left: -18,
          child: IgnorePointer(
            child: _MascotArt(
              mascotBuilder: mascotBuilder,
              moodWire: 'neutral',
              size: 256,
            ),
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 220),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: EcoColors.surfacePrimary,
                  borderRadius: .only(topLeft: .circular(72)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const .only(top: 28, bottom: 24),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Padding(
                          padding: const .symmetric(horizontal: 24),
                          child: Text(
                            'Отслеживайте экономию\nCO₂ каждый день',
                            textAlign: .right,
                            style: EcoTypography.displayHero.copyWith(
                              fontSize: 28,
                              fontWeight: .w400,
                              height: 1.18,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _EdgeAttachedPill(
                          alignRight: true,
                          horizontalMargin: 36,
                          text: 'Чтобы фиксировать ваш вклад и переводить шаги в сэкономленный CO₂, свяжи приложение с шагомером или фитнес-браслетом',
                          statusText: stepsGranted
                              ? 'Доступ к шагомеру разрешён'
                              : null,
                          onTap: onRequestSteps,
                        ),
                        const SizedBox(height: 22),
                        _EdgeAttachedPill(
                          alignRight: false,
                          horizontalMargin: 44,
                          text: 'Вноси свои поездки, а алгоритм посчитает, сколько выбросов CO₂ удалось избежать',
                          statusText: gpsEnabled
                              ? 'GPS-трек маршрута включён'
                              : null,
                          onTap: () => onGpsChanged(!gpsEnabled),
                        ),
                        const Spacer(),
                        const _OnboardingDots(activeIndex: 1),
                        const SizedBox(height: 22),
                        Padding(
                          padding: const .symmetric(horizontal: 28),
                          child: _WireframeActionButton(
                            label: 'Продолжить',
                            enabled: true,
                            isLoading: false,
                            onPressed: onNext,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
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
      final loadingProvider = switch (authState) {
        AuthAuthenticating(:final activeProvider) => activeProvider,
        _ => null,
      };
      final anyLoading = authState is AuthAuthenticating;

      return ColoredBox(
        color: EcoColors.surfacePrimary,
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _StepThreeWavePainter()),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const .only(top: 14, bottom: 16),
                        child: Column(
                          crossAxisAlignment: .stretch,
                          children: [
                            Padding(
                              padding: const .symmetric(horizontal: 22),
                              child: Text(
                                'Забота о природе приносит\nпользу и подарки',
                                style: EcoTypography.displayHero.copyWith(
                                  fontSize: 28,
                                  fontWeight: .w400,
                                  height: 1.18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const _EdgeAttachedPill(
                              alignRight: false,
                              horizontalMargin: 36,
                              text: 'Виртуальный зверёк растёт и развивается вместе с вашими успехами',
                            ),
                            const SizedBox(height: 14),
                            const _EdgeAttachedPill(
                              alignRight: true,
                              horizontalMargin: 48,
                              text: 'Обменивайте накопленные баллы на скидки и промокоды от наших партнёров',
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: .centerLeft,
                              child: Padding(
                                padding: const .only(left: 18),
                                child: _StepThreeMascotCircle(
                                  mascotBuilder: mascotBuilder,
                                ),
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const .symmetric(horizontal: 24),
                              child: _ConsentBox(
                                accepted: consentAccepted,
                                onChanged: onConsentChanged,
                                onReadPolicy: onReadPolicy,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const _OnboardingDots(
                              activeIndex: 2,
                              onDarkCard: true,
                            ),
                            const SizedBox(height: 14),
                            Padding(
                              padding: const .symmetric(horizontal: 24),
                              child: Column(
                                crossAxisAlignment: .stretch,
                                children: [
                                  _OAuthProviderButton(
                                    label: 'Войти через Яндекс ID',
                                    enabled: consentAccepted && !anyLoading,
                                    isLoading: loadingProvider == .yandex,
                                    bgColor: EcoColors.inkPrimary,
                                    fgColor: EcoColors.surfacePrimary,
                                    side: .none,
                                    onPressed: () => onSelectProvider(.yandex),
                                  ),
                                  const SizedBox(height: 8),
                                  _OAuthProviderButton(
                                    label: 'Войти через VK ID',
                                    enabled: consentAccepted && !anyLoading,
                                    isLoading: loadingProvider == .vk,
                                    bgColor: EcoColors.surfacePrimary,
                                    fgColor: EcoColors.inkPrimary,
                                    side: const BorderSide(
                                      color: EcoColors.inkPrimary,
                                      width: 1.5,
                                    ),
                                    onPressed: () => onSelectProvider(.vk),
                                  ),
                                  const SizedBox(height: 8),
                                  _OAuthProviderButton(
                                    label: 'Войти через Google (Лаб. режим)',
                                    enabled: consentAccepted && !anyLoading,
                                    isLoading: loadingProvider == .google,
                                    bgColor: EcoColors.surfaceSubtle,
                                    fgColor: EcoColors.inkPrimary,
                                    side: const BorderSide(
                                      color: EcoColors.borderMuted,
                                      width: 1.5,
                                    ),
                                    onPressed: () => onSelectProvider(.google),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class const _StepThreeWavePainter() extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFCCCCCC);
    final path = Path()
      ..moveTo(0, size.height * 0.67)
      ..lineTo(size.width * 0.65, size.height * 0.67)
      ..quadraticBezierTo(
        size.width * 0.96,
        size.height * 0.67,
        size.width,
        size.height * 0.48,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class const _StepThreeMascotCircle({
  required final MascotWidgetBuilder? mascotBuilder,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 186,
    height: 186,
    child: DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFE0E0E0), shape: .circle),
      child: Stack(
        alignment: .center,
        children: [
          Positioned(
            left: 10,
            bottom: 8,
            child: _MascotArt(
              mascotBuilder: mascotBuilder,
              moodWire: 'neutral',
              size: 152,
            ),
          ),
          const Positioned(
            right: 20,
            bottom: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: EcoColors.surfacePrimary,
                borderRadius: .all(.circular(8)),
                border: .fromBorderSide(
                  BorderSide(color: EcoColors.inkPrimary, width: 1.2),
                ),
              ),
              child: Padding(
                padding: .all(5),
                child: Icon(
                  LucideIcons.gift,
                  size: 20,
                  color: EcoColors.inkPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class const _EdgeAttachedPill({
  required final bool alignRight,
  required final double horizontalMargin,
  required final String text,
  final String? statusText,
  final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final radius = alignRight
        ? const BorderRadius.horizontal(left: .circular(48))
        : const BorderRadius.horizontal(right: .circular(48));

    return Padding(
      padding: alignRight
          ? .only(left: horizontalMargin)
          : .only(right: horizontalMargin),
      child: Material(
        color: const Color(0xFFD9D9D9),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const .symmetric(horizontal: 24, vertical: 18),
            child: Column(
              mainAxisSize: .min,
              children: [
                Text(
                  text,
                  textAlign: .center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: .w400,
                    height: 1.35,
                    color: EcoColors.inkPrimary,
                  ),
                ),
                if (statusText case final String status) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: .min,
                    children: [
                      const Icon(
                        LucideIcons.check,
                        size: 15,
                        color: EcoColors.inkPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: EcoTypography.labelSmall.copyWith(
                          color: EcoColors.inkPrimary,
                          fontWeight: .w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class const _ConsentBox({
  required final bool accepted,
  required final ValueChanged<bool> onChanged,
  required final VoidCallback onReadPolicy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfacePrimary,
      borderRadius: .all(.circular(12)),
      border: .fromBorderSide(
        BorderSide(color: EcoColors.inkPrimary, width: 1.5),
      ),
    ),
    child: InkWell(
      onTap: () => onChanged(!accepted),
      borderRadius: const .all(.circular(12)),
      child: Padding(
        padding: const .symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Checkbox(value: accepted, onChanged: (v) => onChanged(v ?? false)),
            const Expanded(
              child: Text(
                'Я согласен на обработку персональных данных',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  fontWeight: .w400,
                  color: EcoColors.inkPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Политика 152-ФЗ',
              onPressed: onReadPolicy,
              icon: const Icon(
                LucideIcons.info,
                size: 18,
                color: EcoColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _OnboardingDots({
  required final int activeIndex,
  final bool onDarkCard = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: .center,
    children: List.generate(3, (idx) {
      final active = idx == activeIndex;
      final Color color;
      if (onDarkCard) {
        color = active ? const Color(0xFFECECEC) : const Color(0xFFDCDCDC);
      } else {
        color = active ? const Color(0xFFCFCFCF) : const Color(0xFFE0E0E0);
      }
      return Container(
        margin: const .symmetric(horizontal: 5),
        width: active ? 24 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const .all(.circular(4)),
        ),
      );
    }),
  );
}

final class const _WireframeActionButton({
  required final String label,
  required final bool enabled,
  required final bool isLoading,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bgColor = enabled ? const Color(0xFFDDDDDD) : const Color(0xFFD6D6D6);
    final fgColor = enabled ? EcoColors.inkPrimary : EcoColors.inkSecondary;

    return SizedBox(
      height: 54,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          disabledBackgroundColor: bgColor,
          disabledForegroundColor: EcoColors.inkSecondary,
          side: .none,
          shape: const RoundedRectangleBorder(
            borderRadius: .all(.circular(28)),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EcoColors.inkPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: .center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: .w400,
                      color: fgColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(LucideIcons.chevronRight, size: 20, color: fgColor),
                ],
              ),
      ),
    );
  }
}

final class const _OAuthProviderButton({
  required final String label,
  required final bool enabled,
  required final bool isLoading,
  required final Color bgColor,
  required final Color fgColor,
  required final BorderSide side,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final effectiveBg = enabled ? bgColor : EcoColors.fillDisabled;
    final effectiveFg = enabled ? fgColor : EcoColors.inkSecondary;

    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: effectiveBg,
          foregroundColor: effectiveFg,
          disabledBackgroundColor: EcoColors.fillDisabled,
          disabledForegroundColor: EcoColors.inkSecondary,
          side: enabled ? side : .none,
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
                  color: effectiveFg,
                ),
              )
            : Text(
                label,
                style: EcoTypography.bodyLarge.copyWith(color: effectiveFg),
              ),
      ),
    );
  }
}
