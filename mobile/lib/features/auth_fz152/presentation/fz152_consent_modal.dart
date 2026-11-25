import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

final class const GoogleLabModeBanner({
  required final String message,
  super.key,
}) extends StatefulWidget {
  @override
  State<GoogleLabModeBanner> createState() => _GoogleLabModeBannerState();
}

final class _GoogleLabModeBannerState() extends State<GoogleLabModeBanner> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    if (_collapsed) {
      return Align(
        alignment: .centerLeft,
        child: ActionChip(
          avatar: const Icon(
            LucideIcons.triangleAlert,
            size: 16,
            color: EcoColors.inkPrimary,
          ),
          label: const Text(
            'Лаб. режим 406-ФЗ (Google)',
            style: EcoTypography.labelSmall,
          ),
          backgroundColor: EcoColors.surfaceSubtle,
          side: const BorderSide(color: EcoColors.borderMuted, width: 1.5),
          onPressed: () => setState(() => _collapsed = false),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceSubtle,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Row(
              crossAxisAlignment: .start,
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  size: 18,
                  color: EcoColors.inkPrimary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.message, style: EcoTypography.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: .centerRight,
              child: TextButton(
                onPressed: () => setState(() => _collapsed = true),
                child: const Text('Понятно'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class const Fz152PolicySheet({super.key}) extends StatelessWidget {
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: EcoColors.surfacePrimary,
    shape: const RoundedRectangleBorder(
      borderRadius: .vertical(top: .circular(28)),
    ),
    builder: (_) => const Fz152PolicySheet(),
  );

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.72,
    minChildSize: 0.5,
    maxChildSize: 0.92,
    builder: (context, controller) => SafeArea(
      child: ListView(
        controller: controller,
        padding: const .fromLTRB(20, 16, 20, 24),
        children: [
          const Row(
            children: [
              Icon(
                LucideIcons.shieldCheck,
                size: 24,
                color: EcoColors.inkPrimary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Политика конфиденциальности (152-ФЗ)',
                  style: EcoTypography.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Версия политики: 1.0.0-2026',
            style: EcoTypography.labelSmall.copyWith(
              color: EcoColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '1. Оператор персональных данных (EcoTrack) обеспечивает хранение и первичную обработку персональных данных пользователей-граждан РФ на серверах, расположенных на территории Российской Федерации (ч. 5 ст. 18 152-ФЗ).\n\n'
            '2. Перечень обрабатываемых данных: идентификатор аккаунта OAuth 2.1, отображаемое имя, электронная почта (при передаче провайдером), суточное количество шагов из системных датчиков (без ручного ввода), интервальные GPS-координаты (только при включённом пользователем тумблере) и выбранные участки замещённого транспорта.\n\n'
            '3. Все события выдачи и отзыва согласия фиксируются в неизменяемом журнале согласий 152-ФЗ.\n\n'
            '4. Вы можете в любой момент отозвать согласие или полностью удалить аккаунт с безвозвратным затиранием локальной SQLite БД и защищённого хранилища (ст. 21 152-ФЗ).',
            style: EcoTypography.bodyMedium,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    ),
  );
}

final class const Fz152ConsentResolutionScreen({super.key})
    extends StatefulWidget {
  @override
  State<Fz152ConsentResolutionScreen> createState() =>
      _Fz152ConsentResolutionScreenState();
}

final class _Fz152ConsentResolutionScreenState()
    extends State<Fz152ConsentResolutionScreen> {
  bool _personalDataAccepted = false;
  bool _healthStepsAccepted = true;
  bool _gpsAccepted = false;

  void _grantConsent() {
    context.read<AuthBloc>().add(
      AuthConsentSubmitted(
        'granted',
        ConsentScopeObject(
          personalData152fz: _personalDataAccepted,
          healthStepsSensor: _healthStepsAccepted,
          backgroundGeolocation: _gpsAccepted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state case AuthConsentResolutionRequired(:final inlineError?)) {
          EcoErrorBannerPresenter.show(context, inlineError);
        } else if (state case AuthError(:final error)) {
          EcoErrorBannerPresenter.show(context, error);
        }
      },
      builder: (context, state) {
        final isSubmitting =
            state is AuthConsentResolutionRequired && state.isSubmitting;
        final AppError? inlineErr = state is AuthConsentResolutionRequired
            ? state.inlineError
            : null;
        return Scaffold(
          backgroundColor: EcoColors.surfacePrimary,
          body: SafeArea(
            child: ListView(
              padding: const .fromLTRB(20, 24, 20, 24),
              children: [
                const Icon(
                  LucideIcons.shieldAlert,
                  size: 40,
                  color: EcoColors.inkPrimary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Требуется согласие на обработку ПДн (152-ФЗ)',
                  style: EcoTypography.headlineLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Обработка шагов, расчёт CO₂ и синхронизация профиля приостановлены до подтверждения согласия версии 1.0.0-2026.',
                  style: EcoTypography.bodyMedium,
                ),
                const SizedBox(height: 20),
                _ConsentToggleTile(
                  title: 'Обязательное согласие на обработку ПДн согласно 152-ФЗ РФ',
                  value: _personalDataAccepted,
                  onChanged: (val) =>
                      setState(() => _personalDataAccepted = val),
                ),
                const SizedBox(height: 10),
                _ConsentToggleTile(
                  title: 'Синхронизация шагов через Health Connect / шагомер',
                  value: _healthStepsAccepted,
                  onChanged: (val) =>
                      setState(() => _healthStepsAccepted = val),
                ),
                const SizedBox(height: 10),
                _ConsentToggleTile(
                  title: 'Интервальная запись GPS-маршрутов (опционально)',
                  value: _gpsAccepted,
                  onChanged: (val) => setState(() => _gpsAccepted = val),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: .centerLeft,
                  child: TextButton(
                    onPressed: () => unawaited(Fz152PolicySheet.show(context)),
                    child: const Text('Читать полный текст согласия 152-ФЗ'),
                  ),
                ),
                if (inlineErr != null) ...[
                  const SizedBox(height: 8),
                  _InlineErrorCallout(message: inlineErr.uiMessageRu),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _personalDataAccepted && !isSubmitting
                      ? _grantConsent
                      : null,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: EcoColors.surfacePrimary,
                          ),
                        )
                      : const Text('Подтвердить согласие и продолжить'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () => context.read<AuthBloc>().add(
                          const AuthLogoutRequested(),
                        ),
                  child: const Text('Выйти из аккаунта'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

final class const _ConsentToggleTile({
  required final String title,
  required final bool value,
  required final ValueChanged<bool> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfaceSubtle,
      borderRadius: .all(.circular(16)),
      border: .fromBorderSide(
        BorderSide(color: EcoColors.borderMuted, width: 1.5),
      ),
    ),
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: const .all(.circular(16)),
      child: Padding(
        padding: const .symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: EcoTypography.bodyMedium)),
          ],
        ),
      ),
    ),
  );
}

final class const GoogleFormalPhoneModalScreen({super.key})
    extends StatefulWidget {
  @override
  State<GoogleFormalPhoneModalScreen> createState() =>
      _GoogleFormalPhoneModalScreenState();
}

final class _GoogleFormalPhoneModalScreenState()
    extends State<GoogleFormalPhoneModalScreen> {
  final TextEditingController _phoneController = TextEditingController(
    text: '+7',
  );
  String? _localValidationError;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String _normalizeToE164(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp('[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('8')) {
      return '+7${digits.substring(1)}';
    }
    if (trimmed.startsWith('+')) {
      return '+$digits';
    }
    if (digits.length == 10) {
      return '+7$digits';
    }
    return '+$digits';
  }

  void _onPhoneChanged(String raw) {
    final digits = raw.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) {
      return;
    }
    if (_localValidationError != null) {
      setState(() => _localValidationError = null);
    }
  }

  void _submit() {
    final e164 = _normalizeToE164(_phoneController.text);
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(e164)) {
      setState(
        () => _localValidationError =
            'Введите номер в формате +7 (999) 123-45-67 или E.164',
      );
      return;
    }
    context.read<AuthBloc>().add(AuthGooglePhoneSubmitted(e164));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state case AuthError(:final error)) {
          EcoErrorBannerPresenter.show(context, error);
        }
      },
      builder: (context, state) {
        final isSubmitting =
            state is AuthGooglePhoneRequired && state.isSubmitting;
        final String bannerText = state is AuthGooglePhoneRequired
            ? (state.warningBanner ?? AuthBloc.defaultGoogleLabBanner)
            : AuthBloc.defaultGoogleLabBanner;
        final String? serverErrorText = state is AuthGooglePhoneRequired
            ? state.inlineError?.uiMessageRu
            : null;
        final displayError = _localValidationError ?? serverErrorText;

        return Scaffold(
          backgroundColor: EcoColors.surfacePrimary,
          body: SafeArea(
            child: ListView(
              padding: const .fromLTRB(20, 16, 20, 24),
              children: [
                GoogleLabModeBanner(message: bannerText),
                const SizedBox(height: 24),
                const Text(
                  'Укажите контактный телефон',
                  style: EcoTypography.headlineLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Для завершения лабораторной авторизации через иностранный провайдер укажите номер телефона. Реальная отправка SMS-кода в демо-режиме не производится.',
                  style: EcoTypography.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  onChanged: _onPhoneChanged,
                  decoration: const InputDecoration(
                    labelText: 'Контактный телефон',
                    hintText: '+7 (___) ___-__-__',
                    prefixIcon: Icon(LucideIcons.phone),
                  ),
                ),
                if (displayError != null) ...[
                  const SizedBox(height: 10),
                  _InlineErrorCallout(message: displayError),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isSubmitting ? null : _submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: EcoColors.surfacePrimary,
                          ),
                        )
                      : const Text('Сохранить и продолжить'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () => context.read<AuthBloc>().add(
                          const AuthLogoutRequested(),
                        ),
                  child: const Text('Выйти и выбрать другой вход'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

final class const _InlineErrorCallout({required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: .start,
    children: [
      const Icon(
        LucideIcons.triangleAlert,
        size: 16,
        color: EcoColors.inkPrimary,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: EcoTypography.labelSmall.copyWith(
            fontSize: 12,
            fontWeight: .w700,
            color: EcoColors.inkPrimary,
          ),
        ),
      ),
    ],
  );
}
