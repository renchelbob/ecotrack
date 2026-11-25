import 'dart:async';

import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/profile_settings_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

final class const ProfileSettingsScreen({
  final Future<void> Function(BuildContext context)? onReadPolicy,
  super.key,
}) extends StatefulWidget {
  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

final class _ProfileSettingsScreenState() extends State<ProfileSettingsScreen> {
  static const List<String> _avatarSeeds = [
    'fox_classic',
    'fox_leaf',
    'fox_glasses',
    'fox_crown',
  ];

  bool _labBannerCollapsed = false;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ProfileSettingsCubit>();
    if (cubit.state is ProfileSettingsLoading) {
      unawaited(cubit.load());
    }
  }

  void _cycleAvatar(UserProfile profile) {
    final idx = _avatarSeeds.indexOf(profile.avatarUrl ?? 'fox_classic');
    final nextSeed = _avatarSeeds[(idx + 1) % _avatarSeeds.length];
    unawaited(context.read<ProfileSettingsCubit>().updateAvatarSeed(nextSeed));
  }

  Future<void> _editDisplayName(UserProfile profile) async {
    final controller = TextEditingController(text: profile.displayName);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoColors.surfacePrimary,
        title: const Text('Имя в профиле', style: EcoTypography.titleMedium),
        content: TextField(
          controller: controller,
          maxLength: 48,
          decoration: const InputDecoration(hintText: 'Введите имя'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated != null && updated.isNotEmpty && mounted) {
      await context.read<ProfileSettingsCubit>().updateDisplayName(updated);
    }
  }

  Future<void> _copyFriendCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      EcoTopBannerOverlay.instance.showMessage('Код друга $code скопирован');
    }
  }

  Future<void> _openConsentHistorySheet(ConsentHistoryListResponse consents) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: EcoColors.surfacePrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: .vertical(top: .circular(28)),
        ),
        builder: (_) => _ConsentJournalSheet(
          consents: consents,
          onReadPolicy: widget.onReadPolicy,
        ),
      );

  Future<void> _confirmRevokeConsent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoColors.surfacePrimary,
        title: const Text(
          'Отозвать согласие 152-ФЗ?',
          style: EcoTypography.titleMedium,
        ),
        content: const Text(
          'Подсчёт шагов, запись GPS-маршрутов и синхронизация профиля будут приостановлены до повторного подтверждения согласия.',
          style: EcoTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<ProfileSettingsCubit>().revokeConsent();
    }
  }

  Future<void> _openDeleteAccountFlow() async {
    final cubit = context.read<ProfileSettingsCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: EcoColors.surfacePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: .vertical(top: .circular(28)),
      ),
      builder: (_) => BlocProvider<ProfileSettingsCubit>.value(
        value: cubit,
        child: const _DeleteAccountSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ProfileSettingsCubit, ProfileSettingsState>(
        listener: (context, state) {
          if (state case ProfileSettingsLoaded(:final activeError?)) {
            EcoErrorBannerPresenter.show(context, activeError);
            context.read<ProfileSettingsCubit>().clearError();
          } else if (state case ProfileSettingsFailure(:final error)) {
            EcoErrorBannerPresenter.show(context, error);
          }
        },
        builder: (context, state) => Scaffold(
          backgroundColor: EcoColors.surfacePrimary,
          body: SafeArea(
            child: switch (state) {
              ProfileSettingsLoading() => const Center(
                child: CircularProgressIndicator(color: EcoColors.inkPrimary),
              ),
              ProfileSettingsFailure(:final error) => _ProfileErrorView(
                message: error.uiMessageRu,
                onRetry: () =>
                    unawaited(context.read<ProfileSettingsCubit>().load()),
              ),
              ProfileSettingsLoaded() => _ProfileLoadedBody(
                state: state,
                labBannerCollapsed: _labBannerCollapsed,
                onCollapseLabBanner: () =>
                    setState(() => _labBannerCollapsed = true),
                onExpandLabBanner: () =>
                    setState(() => _labBannerCollapsed = false),
                onCycleAvatar: () => _cycleAvatar(state.profile),
                onEditName: () => unawaited(_editDisplayName(state.profile)),
                onCopyFriendCode: () =>
                    unawaited(_copyFriendCode(state.profile.friendCode)),
                onOpenConsents: () =>
                    unawaited(_openConsentHistorySheet(state.consents)),
                onRevokeConsent: () => unawaited(_confirmRevokeConsent()),
                onDeleteAccount: () => unawaited(_openDeleteAccountFlow()),
              ),
            },
          ),
        ),
      );
}

final class const _ProfileLoadedBody({
  required final ProfileSettingsLoaded state,
  required final bool labBannerCollapsed,
  required final VoidCallback onCollapseLabBanner,
  required final VoidCallback onExpandLabBanner,
  required final VoidCallback onCycleAvatar,
  required final VoidCallback onEditName,
  required final VoidCallback onCopyFriendCode,
  required final VoidCallback onOpenConsents,
  required final VoidCallback onRevokeConsent,
  required final VoidCallback onDeleteAccount,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final cubit = context.read<ProfileSettingsCubit>();
    return RefreshIndicator(
      color: EcoColors.inkPrimary,
      onRefresh: cubit.load,
      child: ListView(
        padding: const .fromLTRB(16, 12, 16, 112),
        children: [
          const Center(
            child: Text('Настройки', style: EcoTypography.titleMedium),
          ),
          const SizedBox(height: 14),
          if (profile.isForeignProviderLabMode) ...[
            _ProfileGoogleLabBanner(
              collapsed: labBannerCollapsed,
              onCollapse: onCollapseLabBanner,
              onExpand: onExpandLabBanner,
            ),
            const SizedBox(height: 12),
          ],
          _ProfileHeaderCard(
            profile: profile,
            badges: state.badges,
            onCycleAvatar: onCycleAvatar,
            onEditName: onEditName,
            onCopyFriendCode: onCopyFriendCode,
          ),
          const SizedBox(height: 12),
          _BentoShortcutsRow(profile: profile),
          const SizedBox(height: 12),
          _GoalsSectionCard(profile: profile),
          const SizedBox(height: 12),
          _GpsAndPrivacyCard(
            profile: profile,
            pushEnabled: state.pushNotificationsEnabled,
          ),
          const SizedBox(height: 12),
          _Legal152FzSectionCard(
            onOpenConsents: onOpenConsents,
            onRevokeConsent: onRevokeConsent,
            onDeleteAccount: onDeleteAccount,
            onLogout: () => unawaited(cubit.logout()),
          ),
        ],
      ),
    );
  }
}

final class const _ProfileGoogleLabBanner({
  required final bool collapsed,
  required final VoidCallback onCollapse,
  required final VoidCallback onExpand,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (collapsed) {
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
          onPressed: onExpand,
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
            const Row(
              crossAxisAlignment: .start,
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  size: 18,
                  color: EcoColors.inkPrimary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Внимание: регистрация и вход через иностранный провайдер (Google OAuth) не соответствуют требованиям 406-ФЗ РФ. Данный способ входа включён исключительно для академического / лабораторного тестирования.',
                    style: EcoTypography.bodyMedium,
                  ),
                ),
              ],
            ),
            Align(
              alignment: .centerRight,
              child: TextButton(
                onPressed: onCollapse,
                child: const Text('Понятно'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _ProfileHeaderCard({
  required final UserProfile profile,
  required final BadgesListResponse badges,
  required final VoidCallback onCycleAvatar,
  required final VoidCallback onEditName,
  required final VoidCallback onCopyFriendCode,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final badgeIcons = [
      LucideIcons.award,
      LucideIcons.leaf,
      LucideIcons.sparkles,
      LucideIcons.gift,
    ];
    final previewItems = badges.badges.take(4).toList();

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceCard,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Column(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                color: EcoColors.surfaceSubtle,
                borderRadius: .all(.circular(16)),
              ),
              child: Padding(
                padding: const .all(12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: onCycleAvatar,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: EcoColors.fillDisabled,
                          shape: .circle,
                        ),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: Icon(
                            LucideIcons.cat,
                            size: 32,
                            color: EcoColors.inkPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            profile.displayName,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: EcoTypography.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${profile.email ?? 'без email'} · ${profile.authProvider.displayNameRu}',
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: EcoTypography.labelSmall,
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: onCopyFriendCode,
                            borderRadius: const .all(.circular(999)),
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: EcoColors.surfacePrimary,
                                borderRadius: .all(.circular(999)),
                                border: .fromBorderSide(
                                  BorderSide(
                                    color: EcoColors.borderMuted,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const .symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Код друга: ${profile.friendCode}',
                                  style: EcoTypography.labelSmall.copyWith(
                                    color: EcoColors.inkPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onEditName,
                      tooltip: 'Изменить имя',
                      icon: const Icon(
                        LucideIcons.squarePen,
                        color: EcoColors.inkPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => context.push('/profile/badges'),
              borderRadius: const .all(.circular(16)),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: EcoColors.surfaceSubtle,
                  borderRadius: .all(.circular(16)),
                ),
                child: Padding(
                  padding: const .symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        Icon(
                          badgeIcons[i],
                          size: 24,
                          color:
                              (i < previewItems.length &&
                                  previewItems[i].isUnlocked)
                              ? EcoColors.inkPrimary
                              : EcoColors.fillDisabled,
                        ),
                        if (i < 3) const SizedBox(width: 16),
                      ],
                      const Spacer(),
                      const Text('Гардероб', style: EcoTypography.labelSmall),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: EcoColors.inkPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _BentoShortcutsRow({required final UserProfile profile})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vehicleLabel = profile.personalVehicle?.vehicleName ?? 'Не выбран';
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BentoTile(
                icon: LucideIcons.users,
                title: 'Друзья',
                subtitle: 'QR и пинг зверька',
                onTap: () => context.push('/profile/friends'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BentoTile(
                icon: LucideIcons.car,
                title: 'Мой авто',
                subtitle: vehicleLabel,
                onTap: () => context.push('/profile/vehicle'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _BentoTile(
          icon: LucideIcons.recycle,
          title: 'Карта пунктов РСО',
          subtitle: 'Быстрый переход к пунктам приёма вторсырья',
          onTap: () => context.go('/map?mode=rso'),
        ),
      ],
    );
  }
}

final class const _BentoTile({
  required final IconData icon,
  required final String title,
  required final String subtitle,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: const .all(.circular(20)),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceSubtle,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: EcoColors.inkPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(title, style: EcoTypography.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: EcoTypography.labelSmall,
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: EcoColors.inkPrimary,
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _GoalsSectionCard({required final UserProfile profile})
    extends StatefulWidget {
  @override
  State<_GoalsSectionCard> createState() => _GoalsSectionCardState();
}

final class _GoalsSectionCardState() extends State<_GoalsSectionCard> {
  late int _stepsGoal;
  late int _co2Goal;

  @override
  void initState() {
    super.initState();
    _stepsGoal = widget.profile.dailyStepGoal.clamp(3000, 20000);
    _co2Goal = widget.profile.dailyCo2GoalGrams.clamp(500, 5000);
  }

  @override
  void didUpdateWidget(covariant _GoalsSectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.dailyStepGoal != widget.profile.dailyStepGoal) {
      _stepsGoal = widget.profile.dailyStepGoal.clamp(3000, 20000);
    }
    if (oldWidget.profile.dailyCo2GoalGrams !=
        widget.profile.dailyCo2GoalGrams) {
      _co2Goal = widget.profile.dailyCo2GoalGrams.clamp(500, 5000);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProfileSettingsCubit>();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceCard,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            const Text('Мои дневные цели', style: EcoTypography.titleMedium),
            const SizedBox(height: 10),
            Text('Цель по шагам: $_stepsGoal', style: EcoTypography.bodyMedium),
            Slider(
              value: _stepsGoal.toDouble(),
              min: 3000,
              max: 20000,
              divisions: 34,
              activeColor: EcoColors.inkPrimary,
              inactiveColor: EcoColors.surfacePrimary,
              onChanged: (v) => setState(() => _stepsGoal = v.round()),
              onChangeEnd: (v) =>
                  unawaited(cubit.updateGoals(dailyStepGoal: v.round())),
            ),
            Text(
              'Цель экономии CO₂: $_co2Goal г',
              style: EcoTypography.bodyMedium,
            ),
            Slider(
              value: _co2Goal.toDouble(),
              min: 500,
              max: 5000,
              divisions: 45,
              activeColor: EcoColors.inkPrimary,
              inactiveColor: EcoColors.surfacePrimary,
              onChanged: (v) => setState(() => _co2Goal = v.round()),
              onChangeEnd: (v) =>
                  unawaited(cubit.updateGoals(dailyCo2GoalGrams: v.round())),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _GpsAndPrivacyCard({
  required final UserProfile profile,
  required final bool pushEnabled,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProfileSettingsCubit>();
    const intervals = [5, 15, 30, 60];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceCard,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            const Text(
              'Настройки трекинга и приватности',
              style: EcoTypography.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Записывать маршрут GPS для разметки транспорта',
                style: EcoTypography.bodyMedium,
              ),
              value: profile.isGpsTrackingEnabled,
              onChanged: (v) => unawaited(cubit.updateGpsPrefs(enabled: v)),
            ),
            const SizedBox(height: 6),
            const Text('Интервал записи GPS', style: EcoTypography.labelSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: intervals
                  .map(
                    (sec) => ChoiceChip(
                      label: Text('$sec сек'),
                      selected: profile.gpsIntervalSeconds == sec,
                      onSelected: (_) =>
                          unawaited(cubit.updateGpsPrefs(intervalSeconds: sec)),
                    ),
                  )
                  .toList(),
            ),
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Делиться эко-статистикой с друзьями',
                style: EcoTypography.bodyMedium,
              ),
              value: profile.isStatsVisibleToFriends,
              onChanged: (v) =>
                  unawaited(cubit.updatePrivacy(isStatsVisibleToFriends: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Push-уведомления (напоминания и «разбудить зверька»)',
                style: EcoTypography.bodyMedium,
              ),
              value: pushEnabled,
              onChanged: (v) => unawaited(cubit.togglePushNotifications(v)),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _Legal152FzSectionCard({
  required final VoidCallback onOpenConsents,
  required final VoidCallback onRevokeConsent,
  required final VoidCallback onDeleteAccount,
  required final VoidCallback onLogout,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfaceCard,
      borderRadius: .all(.circular(20)),
      border: .fromBorderSide(
        BorderSide(color: EcoColors.borderMuted, width: 1.5),
      ),
    ),
    child: Column(
      children: [
        _SettingsMenuRow(
          icon: LucideIcons.shieldCheck,
          label: 'Политика и журнал согласий 152-ФЗ',
          onTap: onOpenConsents,
        ),
        _SettingsMenuRow(
          icon: LucideIcons.rotateCcw,
          label: 'Отозвать согласие на обработку ПДн (152-ФЗ)',
          onTap: onRevokeConsent,
        ),
        _SettingsMenuRow(
          icon: LucideIcons.logOut,
          label: 'Выйти из аккаунта',
          onTap: onLogout,
        ),
        _SettingsMenuRow(
          icon: LucideIcons.trash2,
          label: 'Удалить аккаунт и данные (ст. 21 152-ФЗ)',
          onTap: onDeleteAccount,
        ),
      ],
    ),
  );
}

final class const _SettingsMenuRow({
  required final IconData icon,
  required final String label,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: const .all(.circular(16)),
    child: Padding(
      padding: const .symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: EcoColors.surfaceSubtle,
              shape: .circle,
            ),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 18, color: EcoColors.inkPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: EcoTypography.bodyMedium)),
          const Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: EcoColors.inkPrimary,
          ),
        ],
      ),
    ),
  );
}

final class const _ConsentJournalSheet({
  required final ConsentHistoryListResponse consents,
  final Future<void> Function(BuildContext context)? onReadPolicy,
}) extends StatelessWidget {
  Future<void> _showFallbackPolicySheet(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: EcoColors.surfacePrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: .vertical(top: .circular(28)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const .fromLTRB(20, 16, 20, 24),
            children: [
              const Text(
                'Политика конфиденциальности (152-ФЗ)',
                style: EcoTypography.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Версия политики: 1.0.0-2026',
                style: EcoTypography.labelSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Первичная обработка и хранение ПДн осуществляются на территории РФ в соответствии со 152-ФЗ.',
                style: EcoTypography.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const .fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          const Text(
            'Журнал согласий 152-ФЗ (Политика 1.0.0-2026)',
            style: EcoTypography.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            consents.is152fzConsentActive
                ? 'Текущий статус: Согласие активно'
                : 'Текущий статус: Согласие отозвано',
            style: EcoTypography.bodyMedium,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: .centerLeft,
            child: TextButton(
              onPressed: () => unawaited(
                onReadPolicy?.call(context) ??
                    _showFallbackPolicySheet(context),
              ),
              child: const Text('Читать полный текст согласия 152-ФЗ'),
            ),
          ),
          const SizedBox(height: 8),
          if (consents.entries.isEmpty)
            const Text(
              'Записей в журнале пока нет.',
              style: EcoTypography.labelSmall,
            )
          else
            SizedBox(
              height: 220,
              child: ListView.separated(
                itemCount: consents.entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, idx) {
                  final entry = consents.entries[idx];
                  return DecoratedBox(
                    decoration: const BoxDecoration(
                      color: EcoColors.surfaceSubtle,
                      borderRadius: .all(.circular(14)),
                    ),
                    child: Padding(
                      padding: const .all(12),
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            '${entry.action.displayNameRu} · v${entry.policyVersion}',
                            style: EcoTypography.bodyMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.recordedAt,
                            style: EcoTypography.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    ),
  );
}

final class const _DeleteAccountSheet() extends StatefulWidget {
  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

final class _DeleteAccountSheetState() extends State<_DeleteAccountSheet> {
  static const String _requiredPhrase = 'DELETE_MY_DATA_152FZ';
  static const String _defaultReason =
      'Отзыв согласия и удаление по ст. 21 152-ФЗ';

  final TextEditingController _reasonController = TextEditingController(
    text: _defaultReason,
  );
  final TextEditingController _phraseController = TextEditingController();
  bool _confirmedStepOne = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _phraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ProfileSettingsCubit, ProfileSettingsState>(
    builder: (context, state) {
      final loaded = state is ProfileSettingsLoaded ? state : null;
      final receipt = loaded?.deletionReceipt;
      final isSaving = loaded?.isSaving ?? false;
      final trimmedReason = _reasonController.text.trim();
      final isReasonValid =
          trimmedReason.length >= 3 && trimmedReason.length <= 128;

      if (receipt != null) {
        return SafeArea(
          child: Padding(
            padding: const .fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                const Text(
                  'Квитанция удаления данных (152-ФЗ)',
                  style: EcoTypography.titleMedium,
                ),
                const SizedBox(height: 12),
                _ReceiptField(label: 'ID квитанции', value: receipt.receiptId),
                _ReceiptField(
                  label: 'Обезличенный хэш',
                  value: receipt.anonymizedUserHash,
                ),
                _ReceiptField(
                  label: 'Подпись проверки',
                  value: receipt.verificationSignature,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(
                      context
                          .read<ProfileSettingsCubit>()
                          .finishAccountDeletionLogout(),
                    );
                  },
                  child: const Text('Завершить и выйти'),
                ),
              ],
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              const Text(
                'Удаление аккаунта (ст. 21 152-ФЗ)',
                style: EcoTypography.titleMedium,
              ),
              const SizedBox(height: 8),
              if (!_confirmedStepOne) ...[
                const Text(
                  'Все персональные данные, история шагов, маршруты и баланс баллов будут необратимо удалены и затёрты в локальной БД SQLite.',
                  style: EcoTypography.bodyMedium,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() => _confirmedStepOne = true),
                  child: const Text('Перейти к подтверждению'),
                ),
              ] else ...[
                TextField(
                  controller: _reasonController,
                  maxLength: 128,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Причина удаления',
                    helperText: 'Минимум 3 символа',
                    errorText: trimmedReason.length < 3
                        ? 'Минимум 3 символа'
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phraseController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Введите $_requiredPhrase',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed:
                      isReasonValid &&
                          _phraseController.text.trim() == _requiredPhrase &&
                          !isSaving
                      ? () => unawaited(
                          context.read<ProfileSettingsCubit>().deleteAccount(
                            trimmedReason,
                            _requiredPhrase,
                          ),
                        )
                      : null,
                  child: const Text('Удалить навсегда'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

final class const _ReceiptField({
  required final String label,
  required final String value,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(bottom: 8),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceSubtle,
        borderRadius: .all(.circular(12)),
      ),
      child: Padding(
        padding: const .all(10),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(label, style: EcoTypography.labelSmall),
            const SizedBox(height: 2),
            SelectableText(value, style: EcoTypography.bodyMedium),
          ],
        ),
      ),
    ),
  );
}

final class const _ProfileErrorView({
  required final String message,
  required final VoidCallback onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const .all(24),
      child: Column(
        mainAxisSize: .min,
        children: [
          const Icon(
            LucideIcons.triangleAlert,
            size: 40,
            color: EcoColors.inkPrimary,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: .center, style: EcoTypography.bodyMedium),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    ),
  );
}
