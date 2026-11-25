import 'dart:async';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';
import 'package:ecotrack_mobile/features/stats/presentation/stats_cubit.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

final class const StatsScreen({super.key}) extends StatefulWidget {
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

final class _StatsScreenState() extends State<StatsScreen> {
  @override
  void initState() {
    super.initState();
    final cubit = context.read<StatsCubit>();
    if (cubit.state is StatsLoading) {
      unawaited(cubit.loadStats());
    }
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<StatsCubit, StatsState>(
    listenWhen: (prev, curr) {
      if (curr is! StatsLoaded || curr.bannerError == null) return false;
      if (prev is StatsLoaded) return prev.bannerError != curr.bannerError;
      return true;
    },
    listener: (context, state) {
      if (state case StatsLoaded(:final bannerError?)) {
        EcoErrorBannerPresenter.show(context, bannerError);
        context.read<StatsCubit>().clearBannerError();
      }
    },
    builder: (context, state) => Scaffold(
      backgroundColor: EcoColors.surfacePrimary,
      body: SafeArea(
        child: switch (state) {
          StatsLoading() => const _StatsSkeletonView(),
          StatsFailure(:final error) => Center(
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
                  Text(
                    error.uiMessageRu,
                    textAlign: .center,
                    style: EcoTypography.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        unawaited(context.read<StatsCubit>().loadStats()),
                    child: const Text('Повторить загрузку'),
                  ),
                ],
              ),
            ),
          ),
          StatsLoaded() => _StatsLoadedBody(loaded: state),
        },
      ),
    ),
  );
}

final class const _StatsLoadedBody({required final StatsLoaded loaded})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<StatsCubit>();
    final cachedMs = loaded.offlineCachedAtMs;
    return RefreshIndicator(
      color: EcoColors.inkPrimary,
      onRefresh: cubit.refresh,
      child: ListView(
        padding: const .fromLTRB(16, 12, 16, 112),
        children: [
          const Center(
            child: Text('Статистика', style: EcoTypography.titleMedium),
          ),
          if (cachedMs != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Кэш от ${_formatTime(cachedMs)}',
                style: EcoTypography.labelSmall,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _EmissionsOverviewCard(emissions: loaded.emissions),
          const SizedBox(height: 12),
          _HistoryPreviewCard(history: loaded.history),
          const SizedBox(height: 12),
          _EquivalentsBentoGrid(metrics: loaded.equivalents.lifetime),
          const SizedBox(height: 12),
          _LeaderboardCard(leaderboard: loaded.leaderboard),
          if (loaded.sharedForest case final forest?) ...[
            const SizedBox(height: 12),
            _SharedForestCard(challenge: forest),
          ],
        ],
      ),
    );
  }

  static String _formatTime(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

final class const _EmissionsOverviewCard({
  required final EmissionsStatisticsResponse emissions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final buckets = emissions.buckets;
    final hasAnyData = buckets.any((b) => b.totalCo2SavedGrams > 0);
    return InkWell(
      onTap: () => context.push('/stats/emissions'),
      borderRadius: const .all(.circular(20)),
      child: DecoratedBox(
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
            crossAxisAlignment: .start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        const Text(
                          'Сэкономлено CO₂ за 7 дней',
                          style: EcoTypography.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${emissions.periodTotalCo2SavedGrams} г CO₂',
                          style: EcoTypography.headlineLarge,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 20,
                    color: EcoColors.inkPrimary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!hasAnyData)
                const SizedBox(
                  height: 100,
                  child: Center(
                    child: Text(
                      'Начните шагать, чтобы увидеть графики CO₂',
                      textAlign: .center,
                      style: EcoTypography.bodyMedium,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 140,
                  child: _StackedEmissionsBarChart(buckets: buckets),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class const _StackedEmissionsBarChart({
  required final List<EmissionsBucketItem> buckets,
  final bool interactive = false,
  final double? averageY,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final baseMaxY = buckets.fold<double>(
      100.0,
      (acc, b) => math.max(acc, b.totalCo2SavedGrams.toDouble() * 1.15),
    );
    final avg = averageY;
    final maxY = avg != null ? math.max(baseMaxY, avg * 1.15) : baseMaxY;
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        extraLinesData: avg == null
            ? const ExtraLinesData()
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: avg,
                    color: EcoColors.inkPrimary,
                    strokeWidth: 1.5,
                    dashArray: const [4, 4],
                  ),
                ],
              ),
        barTouchData: BarTouchData(
          enabled: interactive,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= buckets.length) return null;
              final b = buckets[groupIndex];
              return BarTooltipItem(
                '${b.bucketLabel}: ${b.totalCo2SavedGrams} г CO₂\n(${b.validatedSteps} шагов)',
                EcoTypography.labelSmall.copyWith(
                  color: EcoColors.surfacePrimary,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= buckets.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const .only(top: 6),
                  child: Text(
                    buckets[idx].bucketLabel,
                    style: EcoTypography.labelSmall.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].totalCo2SavedGrams.toDouble(),
                  width: 16,
                  borderRadius: const .all(.circular(8)),
                  rodStackItems: [
                    BarChartRodStackItem(
                      0,
                      buckets[i].allocatedCo2SavedGrams.toDouble(),
                      EcoColors.inkPrimary,
                    ),
                    BarChartRodStackItem(
                      buckets[i].allocatedCo2SavedGrams.toDouble(),
                      buckets[i].totalCo2SavedGrams.toDouble(),
                      EcoColors.borderMuted,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

final class const _HistoryPreviewCard({
  required final PaginatedActivityHistoryResponse history,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final preview = history.items.take(3).toList();
    return DecoratedBox(
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
            InkWell(
              onTap: () => context.push('/stats/history'),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'История активности',
                      style: EcoTypography.titleMedium,
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 20,
                    color: EcoColors.inkPrimary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (preview.isEmpty)
              const Text(
                'Пока нет записей активности.',
                style: EcoTypography.bodyMedium,
              )
            else
              for (final item in preview) ...[
                _ActivityRowTile(item: item),
                const SizedBox(height: 8),
              ],
            Align(
              alignment: .centerLeft,
              child: TextButton(
                onPressed: () => context.push('/stats/history'),
                child: const Text('Вся история активности →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _ActivityRowTile({required final DailyActivitySummary item})
    extends StatelessWidget {
  bool get _isEditable {
    final now = DateTime.now();
    final today = _fmt(now);
    final yesterday = _fmt(now.subtract(const Duration(days: 1)));
    return item.activityDate == today || item.activityDate == yesterday;
  }

  static String _fmt(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final km = (item.totalStepDistanceM / 1000.0).toStringAsFixed(1);
    return InkWell(
      onTap: _isEditable
          ? () => context.go('/map?mode=routes&date=${item.activityDate}')
          : null,
      borderRadius: const .all(.circular(14)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: EcoColors.surfaceSubtle,
          borderRadius: .all(.circular(14)),
        ),
        child: Padding(
          padding: const .symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                _isEditable ? LucideIcons.squarePen : LucideIcons.footprints,
                size: 18,
                color: EcoColors.inkPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      '${item.activityDate} · $km км',
                      style: EcoTypography.bodyMedium,
                    ),
                    Text(
                      item.isAutoCalculated
                          ? 'Авторасчёт 80% × 0.7'
                          : 'Подтверждено по GPS',
                      style: EcoTypography.labelSmall,
                    ),
                  ],
                ),
              ),
              Text(
                '+${item.pointsAwardedForDay} ★',
                style: EcoTypography.tabularMetric,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class const _EquivalentsBentoGrid({
  required final EcoEquivalentsMetrics metrics,
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
    child: Padding(
      padding: const .all(14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(
              child: _EquivalentCardTile(
                title: 'Лес',
                metricText:
                    '${metrics.treesPlantedEquivalent.toStringAsFixed(2)} дерева',
                subtitle: 'Поглощают столько же CO₂ в год',
                bgColor: EcoColors.eqForestBg,
                inkColor: EcoColors.eqForestInk,
                icon: LucideIcons.trees,
                onTap: () => context.push('/stats/equivalents/forest'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  Expanded(
                    child: _EquivalentCardTile(
                      title: 'Бензин',
                      metricText:
                          '${metrics.gasolineLitersSaved.toStringAsFixed(2)} л',
                      subtitle:
                          'Избежано ${metrics.carKmAvoided.toStringAsFixed(1)} км на авто',
                      bgColor: EcoColors.eqFuelBg,
                      inkColor: EcoColors.eqFuelInk,
                      icon: LucideIcons.fuel,
                      onTap: () => context.push('/stats/equivalents/gasoline'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _EquivalentCardTile(
                      title: 'Воздух',
                      metricText:
                          '${metrics.smartphoneChargesEquivalent} зарядок',
                      subtitle: 'Или ${metrics.ledBulbHoursEquivalent} ч LED',
                      bgColor: EcoColors.eqAirBg,
                      inkColor: EcoColors.eqAirInk,
                      icon: LucideIcons.wind,
                      onTap: () => context.push('/stats/equivalents/air'),
                    ),
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

final class const _EquivalentCardTile({
  required final String title,
  required final String metricText,
  required final String subtitle,
  required final Color bgColor,
  required final Color inkColor,
  required final IconData icon,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: const .all(.circular(16)),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const .all(.circular(16)),
      ),
      child: Padding(
        padding: const .all(14),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: inkColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: EcoTypography.titleMedium.copyWith(color: inkColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              metricText,
              style: EcoTypography.headlineLarge.copyWith(
                fontSize: 18,
                color: inkColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: EcoTypography.labelSmall.copyWith(color: inkColor),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _LeaderboardCard({
  required final FriendsLeaderboardResponse leaderboard,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final maxGrams = leaderboard.entries.fold<int>(
      1,
      (acc, e) => math.max(acc, e.weeklyCo2SavedGrams),
    );
    return DecoratedBox(
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
          crossAxisAlignment: .start,
          children: [
            const Text(
              'Рейтинг друзей за неделю (CO₂)',
              style: EcoTypography.titleMedium,
            ),
            const SizedBox(height: 10),
            if (leaderboard.entries.isEmpty)
              const Text(
                'Добавьте друзей в профиле, чтобы соревноваться по эковкладу.',
                style: EcoTypography.bodyMedium,
              )
            else
              for (final entry in leaderboard.entries) ...[
                _LeaderboardRow(entry: entry, maxGrams: maxGrams),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

final class const _LeaderboardRow({
  required final LeaderboardEntry entry,
  required final int maxGrams,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ratio = entry.isStatsVisible
        ? (entry.weeklyCo2SavedGrams / math.max(1, maxGrams)).clamp(0.0, 1.0)
        : 0.0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceSubtle,
        borderRadius: .all(.circular(14)),
      ),
      child: Padding(
        padding: const .all(10),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Row(
              children: [
                Text('#${entry.rank}', style: EcoTypography.tabularMetric),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: EcoTypography.bodyLarge,
                  ),
                ),
                if (entry.rank == 1)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: EcoColors.eqFuelBg,
                      borderRadius: .all(.circular(999)),
                    ),
                    child: Padding(
                      padding: const .symmetric(horizontal: 8, vertical: 2),
                      child: Text(
                        '👑 Лидер недели',
                        style: EcoTypography.labelSmall.copyWith(
                          color: EcoColors.eqFuelInk,
                          fontWeight: .w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (!entry.isStatsVisible)
              const Text(
                'Статистика скрыта настройками приватности',
                style: EcoTypography.labelSmall,
              )
            else ...[
              LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                borderRadius: const .all(.circular(999)),
                backgroundColor: EcoColors.surfacePrimary,
                valueColor: const AlwaysStoppedAnimation(EcoColors.inkPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.weeklyCo2SavedGrams} г CO₂ · стрик ${entry.currentStreakDays} дн.',
                style: EcoTypography.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class const _SharedForestCard({
  required final SharedForestChallengeResponse challenge,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final progress = challenge.progressRatio.clamp(0.0, 1.0);
    return DecoratedBox(
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
          crossAxisAlignment: .start,
          children: [
            const Text(
              'Кооперативный челлендж: «Общий лес»',
              style: EcoTypography.titleMedium,
            ),
            const SizedBox(height: 6),
            const Chip(label: Text('+50 ★ каждому участнику при выполнении')),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: const .all(.circular(999)),
              backgroundColor: EcoColors.surfacePrimary,
              valueColor: const AlwaysStoppedAnimation(EcoColors.inkPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              '${challenge.currentCo2SavedGrams} / ${challenge.targetCo2SavedGrams} г CO₂',
              style: EcoTypography.tabularMetric,
            ),
            const SizedBox(height: 4),
            Text(
              'Высажено виртуальных деревьев: ${challenge.treesEquivalentPlanted} · Ваш вклад: ${challenge.myContributedCo2Grams} г',
              style: EcoTypography.labelSmall,
            ),
            if (challenge.topFriendsContributors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: challenge.topFriendsContributors
                    .take(3)
                    .map(
                      (c) => Chip(
                        label: Text(
                          '${c.displayName}: ${c.contributedCo2Grams} г',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class const _PeriodSwitcherRow({
  required final String selectedPeriod,
  required final ValueChanged<String> onSelected,
}) extends StatelessWidget {
  static const List<(String, String)> _periods = [
    ('days', 'Дни'),
    ('weeks', 'Недели'),
    ('months', 'Месяцы'),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (code, label) in _periods) ...[
        Expanded(
          child: ChoiceChip(
            label: Center(child: Text(label)),
            selected: selectedPeriod == code,
            onSelected: (_) => onSelected(code),
          ),
        ),
        if (code != 'months') const SizedBox(width: 8),
      ],
    ],
  );
}

final class const _StatsDrilldownErrorView({
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

final class const EmissionsDrilldownScreen({super.key}) extends StatefulWidget {
  @override
  State<EmissionsDrilldownScreen> createState() =>
      _EmissionsDrilldownScreenState();
}

final class _EmissionsDrilldownScreenState()
    extends State<EmissionsDrilldownScreen> {
  @override
  void initState() {
    super.initState();
    final cubit = context.read<StatsCubit>();
    if (cubit.state is StatsLoading) {
      unawaited(cubit.loadStats());
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<StatsCubit, StatsState>(
    builder: (context, state) {
      final cubit = context.read<StatsCubit>();
      return Scaffold(
        backgroundColor: EcoColors.surfacePrimary,
        appBar: AppBar(title: const Text('Снижение выбросов')),
        body: SafeArea(
          top: false,
          child: switch (state) {
            StatsLoading() => const Center(
              child: CircularProgressIndicator(color: EcoColors.inkPrimary),
            ),
            StatsFailure(:final error) => _StatsDrilldownErrorView(
              message: error.uiMessageRu,
              onRetry: () => unawaited(cubit.loadStats()),
            ),
            StatsLoaded() => _EmissionsDrilldownBody(loaded: state),
          },
        ),
      );
    },
  );
}

final class const _EmissionsDrilldownBody({required final StatsLoaded loaded})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<StatsCubit>();
    final buckets = loaded.emissions.buckets;
    final averageGrams = buckets.isEmpty
        ? 0
        : (buckets.fold<int>(0, (sum, b) => sum + b.totalCo2SavedGrams) /
                  buckets.length)
              .round();
    final dateRangeText = buckets.isEmpty
        ? null
        : '${buckets.first.startDate} – ${buckets.last.endDate}';

    return ListView(
      padding: const .all(16),
      children: [
        _PeriodSwitcherRow(
          selectedPeriod: loaded.selectedPeriod,
          onSelected: (code) => unawaited(cubit.changePeriod(code)),
        ),
        const SizedBox(height: 16),
        Text(
          'Итого: ${loaded.emissions.periodTotalCo2SavedGrams} г CO₂ · ${loaded.emissions.periodTotalSteps} шагов',
          style: EcoTypography.titleMedium,
        ),
        const SizedBox(height: 12),
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
              crossAxisAlignment: .start,
              children: [
                if (dateRangeText != null) ...[
                  Text(dateRangeText, style: EcoTypography.labelSmall),
                  const SizedBox(height: 10),
                ],
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const .all(.circular(999)),
                    border: .all(color: EcoColors.inkPrimary, width: 1.2),
                  ),
                  child: Padding(
                    padding: const .symmetric(horizontal: 10, vertical: 3),
                    child: Text(
                      'Среднее',
                      style: EcoTypography.labelSmall.copyWith(
                        color: EcoColors.inkPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('$averageGrams г CO₂', style: EcoTypography.displayHero),
                const SizedBox(height: 12),
                SizedBox(
                  height: 210,
                  child: _StackedEmissionsBarChart(
                    buckets: buckets,
                    interactive: true,
                    averageY: averageGrams.toDouble(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (loaded.emissions.transportShares.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Доли замещённого транспорта',
            style: EcoTypography.titleMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 36,
                sections: [
                  for (
                    var i = 0;
                    i < loaded.emissions.transportShares.length;
                    i++
                  )
                    PieChartSectionData(
                      value: math.max(
                        1.0,
                        loaded.emissions.transportShares[i].percentage,
                      ),
                      title:
                          '${loaded.emissions.transportShares[i].percentage.round()}%',
                      radius: 52,
                      color: i.isEven
                          ? EcoColors.inkPrimary
                          : EcoColors.borderMuted,
                      titleStyle: EcoTypography.labelSmall.copyWith(
                        color: EcoColors.surfacePrimary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final share in loaded.emissions.transportShares)
            ListTile(
              dense: true,
              title: Text(share.labelRu),
              trailing: Text(
                '${share.co2SavedGrams} г (${share.percentage.toStringAsFixed(0)}%)',
                style: EcoTypography.tabularMetric,
              ),
            ),
        ],
      ],
    );
  }
}

final class const ActivityHistoryDrilldownScreen({super.key})
    extends StatefulWidget {
  @override
  State<ActivityHistoryDrilldownScreen> createState() =>
      _ActivityHistoryDrilldownScreenState();
}

final class _ActivityHistoryDrilldownScreenState()
    extends State<ActivityHistoryDrilldownScreen> {
  @override
  void initState() {
    super.initState();
    final cubit = context.read<StatsCubit>();
    if (cubit.state is StatsLoading) {
      unawaited(cubit.loadStats());
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<StatsCubit, StatsState>(
    builder: (context, state) {
      final cubit = context.read<StatsCubit>();
      return Scaffold(
        backgroundColor: EcoColors.surfacePrimary,
        appBar: AppBar(title: const Text('История активности')),
        body: SafeArea(
          top: false,
          child: switch (state) {
            StatsLoading() => const Center(
              child: CircularProgressIndicator(color: EcoColors.inkPrimary),
            ),
            StatsFailure(:final error) => _StatsDrilldownErrorView(
              message: error.uiMessageRu,
              onRetry: () => unawaited(cubit.loadStats()),
            ),
            StatsLoaded() => Column(
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const .fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      _PeriodSwitcherRow(
                        selectedPeriod: state.selectedPeriod,
                        onSelected: (code) =>
                            unawaited(cubit.changePeriod(code)),
                      ),
                      if (state.emissions.buckets.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${state.emissions.buckets.first.startDate} – ${state.emissions.buckets.last.endDate}',
                          style: EcoTypography.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: state.history.items.isEmpty
                      ? const Center(
                          child: Text(
                            'Пока нет записей активности.',
                            style: EcoTypography.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          padding: const .all(16),
                          itemCount: state.history.items.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            if (idx < state.history.items.length) {
                              return _ActivityRowTile(
                                item: state.history.items[idx],
                              );
                            }
                            if (state.history.items.length <
                                state.history.totalCount) {
                              return OutlinedButton(
                                onPressed: state.isLoadingMoreHistory
                                    ? null
                                    : () => unawaited(cubit.loadMoreHistory()),
                                child: const Text('Загрузить ещё'),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                ),
              ],
            ),
          },
        ),
      );
    },
  );
}

final class const EquivalentsDrilldownScreen({
  required final String kind,
  super.key,
}) extends StatefulWidget {
  @override
  State<EquivalentsDrilldownScreen> createState() =>
      _EquivalentsDrilldownScreenState();
}

final class _EquivalentsDrilldownScreenState()
    extends State<EquivalentsDrilldownScreen> {
  @override
  void initState() {
    super.initState();
    final cubit = context.read<StatsCubit>();
    if (cubit.state is StatsLoading) {
      unawaited(cubit.loadStats());
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<StatsCubit, StatsState>(
    builder: (context, state) {
      final cubit = context.read<StatsCubit>();
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: EcoColors.surfacePrimary,
          appBar: AppBar(
            title: Text(_titleForKind(widget.kind)),
            bottom: const TabBar(
              labelColor: EcoColors.inkPrimary,
              indicatorColor: EcoColors.inkPrimary,
              tabs: [
                Tab(text: 'За всё время'),
                Tab(text: 'Эта неделя'),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: switch (state) {
              StatsLoading() => const Center(
                child: CircularProgressIndicator(color: EcoColors.inkPrimary),
              ),
              StatsFailure(:final error) => _StatsDrilldownErrorView(
                message: error.uiMessageRu,
                onRetry: () => unawaited(cubit.loadStats()),
              ),
              StatsLoaded() => TabBarView(
                children: [
                  _EquivalentsMetricsView(metrics: state.equivalents.lifetime),
                  _EquivalentsMetricsView(
                    metrics: state.equivalents.currentWeek,
                  ),
                ],
              ),
            },
          ),
        ),
      );
    },
  );

  static String _titleForKind(String k) => switch (k) {
    'forest' => 'Эко-эквивалент: Лес',
    'gasoline' || 'fuel' => 'Эко-эквивалент: Бензин и Авто',
    _ => 'Эко-эквивалент: Воздух и Энергия',
  };
}

final class const _EquivalentsMetricsView({
  required final EcoEquivalentsMetrics metrics,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const .all(16),
    children: [
      _MetricLineCard(
        label: 'Всего сэкономлено CO₂',
        value: '${metrics.totalCo2SavedGrams} г',
      ),
      const SizedBox(height: 10),
      _MetricLineCard(
        label: 'Деревьев (эквивалент за год)',
        value: metrics.treesPlantedEquivalent.toStringAsFixed(2),
      ),
      const SizedBox(height: 10),
      _MetricLineCard(
        label: 'Пройдено вместо автомобиля',
        value: '${metrics.carKmAvoided.toStringAsFixed(1)} км',
      ),
      const SizedBox(height: 10),
      _MetricLineCard(
        label: 'Зарядок смартфона',
        value: '${metrics.smartphoneChargesEquivalent}',
      ),
      const SizedBox(height: 10),
      _MetricLineCard(
        label: 'Часов работы LED-лампы',
        value: '${metrics.ledBulbHoursEquivalent} ч',
      ),
    ],
  );
}

final class const _MetricLineCard({
  required final String label,
  required final String value,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfaceCard,
      borderRadius: .all(.circular(16)),
      border: .fromBorderSide(
        BorderSide(color: EcoColors.borderMuted, width: 1.5),
      ),
    ),
    child: Padding(
      padding: const .all(14),
      child: Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          Expanded(child: Text(label, style: EcoTypography.bodyMedium)),
          Text(value, style: EcoTypography.titleMedium),
        ],
      ),
    ),
  );
}

final class const _StatsSkeletonView() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const .all(16),
    children: const [
      SizedBox(height: 36),
      _StatsSkeletonBox(height: 200),
      SizedBox(height: 12),
      _StatsSkeletonBox(height: 150),
      SizedBox(height: 12),
      _StatsSkeletonBox(height: 180),
    ],
  );
}

final class const _StatsSkeletonBox({required final double height})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfaceSubtle,
      borderRadius: .all(.circular(20)),
    ),
    child: SizedBox(height: height, width: double.infinity),
  );
}
