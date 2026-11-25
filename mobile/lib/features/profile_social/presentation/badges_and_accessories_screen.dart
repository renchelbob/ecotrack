import 'dart:async';

import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/profile_settings_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

typedef MascotPreviewBuilder = Widget Function(
  String moodWire, {
  String? accessoryCode,
});

final class const BadgesAndAccessoriesScreen({
  final MascotPreviewBuilder? mascotBuilder,
  super.key,
}) extends StatefulWidget {
  @override
  State<BadgesAndAccessoriesScreen> createState() =>
      _BadgesAndAccessoriesScreenState();
}

final class _BadgesAndAccessoriesScreenState()
    extends State<BadgesAndAccessoriesScreen> {
  @override
  void initState() {
    super.initState();
    final cubit = context.read<ProfileSettingsCubit>();
    if (cubit.state is ProfileSettingsLoading) {
      unawaited(cubit.load());
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: BlocConsumer<ProfileSettingsCubit, ProfileSettingsState>(
      listener: (context, state) {
        if (state case ProfileSettingsLoaded(:final activeError?)) {
          EcoErrorBannerPresenter.show(context, activeError);
          context.read<ProfileSettingsCubit>().clearError();
        }
      },
      builder: (context, state) => Scaffold(
        backgroundColor: EcoColors.surfacePrimary,
        appBar: AppBar(
          title: const Text('Достижения и гардероб'),
          bottom: const TabBar(
            labelColor: EcoColors.inkPrimary,
            unselectedLabelColor: EcoColors.inkSecondary,
            indicatorColor: EcoColors.inkPrimary,
            tabs: [
              Tab(text: 'Достижения'),
              Tab(text: 'Гардероб зверька'),
            ],
          ),
        ),
        body: switch (state) {
          ProfileSettingsLoading() => const Center(
            child: CircularProgressIndicator(color: EcoColors.inkPrimary),
          ),
          ProfileSettingsFailure(:final error) => Center(
            child: Padding(
              padding: const .all(24),
              child: Text(error.uiMessageRu, textAlign: .center),
            ),
          ),
          ProfileSettingsLoaded() => TabBarView(
            children: [
              _BadgesTab(badges: state.badges),
              _WardrobeTab(
                profile: state.profile,
                inventory: state.accessories,
                isSaving: state.isSaving,
                mascotBuilder: widget.mascotBuilder,
              ),
            ],
          ),
        },
      ),
    ),
  );
}

final class const _BadgesTab({required final BadgesListResponse badges})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (badges.badges.isEmpty) {
      return const Center(
        child: Text(
          'Достижения пока загружаются...',
          style: EcoTypography.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      padding: const .all(16),
      itemCount: badges.badges.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, idx) {
        final item = badges.badges[idx];
        final ratio = item.thresholdValue <= 0
            ? 0.0
            : (item.currentValue / item.thresholdValue).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: item.isUnlocked
                ? EcoColors.surfaceCard
                : EcoColors.surfaceSubtle,
            borderRadius: const .all(.circular(20)),
            border: .fromBorderSide(
              BorderSide(
                color: item.isUnlocked
                    ? EcoColors.inkPrimary
                    : EcoColors.borderMuted,
                width: 1.5,
              ),
            ),
          ),
          child: Padding(
            padding: const .all(14),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Row(
                  children: [
                    Icon(
                      item.isUnlocked ? LucideIcons.award : LucideIcons.lock,
                      size: 20,
                      color: item.isUnlocked
                          ? EcoColors.inkPrimary
                          : EcoColors.inkSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item.titleRu, style: EcoTypography.bodyLarge),
                    ),
                    Text(
                      '+${item.rewardPoints} ★',
                      style: EcoTypography.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.descriptionRu, style: EcoTypography.labelSmall),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  borderRadius: const .all(.circular(999)),
                  backgroundColor: EcoColors.surfacePrimary,
                  valueColor: const AlwaysStoppedAnimation(
                    EcoColors.inkPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.currentValue} / ${item.thresholdValue}',
                  style: EcoTypography.labelSmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class const _WardrobeTab({
  required final UserProfile profile,
  required final MascotInventoryResponse inventory,
  required final bool isSaving,
  required final MascotPreviewBuilder? mascotBuilder,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final equipped = profile.mascot.equippedAccessoryCode;
    return ListView(
      padding: const .all(16),
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: EcoColors.surfaceSubtle,
            borderRadius: .all(.circular(24)),
            border: .fromBorderSide(
              BorderSide(color: EcoColors.borderMuted, width: 1.5),
            ),
          ),
          child: SizedBox(
            height: 200,
            child: Center(
              child:
                  mascotBuilder?.call(
                    profile.mascot.mood.wireName,
                    accessoryCode: equipped,
                  ) ??
                  const Icon(
                    LucideIcons.sparkles,
                    size: 64,
                    color: EcoColors.inkPrimary,
                  ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final item in inventory.accessories) ...[
          _AccessoryRow(
            item: item,
            isEquipped: equipped == item.code,
            isSaving: isSaving,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

final class const _AccessoryRow({
  required final MascotAccessoryItem item,
  required final bool isEquipped,
  required final bool isSaving,
}) extends StatelessWidget {
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
        child: Row(
          children: [
            Icon(
              item.isUnlocked ? LucideIcons.sparkles : LucideIcons.lock,
              size: 20,
              color: EcoColors.inkPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(item.nameRu, style: EcoTypography.bodyLarge),
                  Text('Слот: ${item.slot}', style: EcoTypography.labelSmall),
                ],
              ),
            ),
            if (item.isUnlocked)
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () => unawaited(
                        cubit.equipAccessory(isEquipped ? null : item.code),
                      ),
                child: Text(isEquipped ? 'Снять' : 'Надеть'),
              )
            else
              const Text('Закрыто', style: EcoTypography.labelSmall),
          ],
        ),
      ),
    );
  }
}
