import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_cubit.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/fox_mascot_widget.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

final class const HomeScreen({super.key}) extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState() extends State<HomeScreen> {
  bool _activityExpanded = false;
  bool _co2Expanded = false;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<HomeCubit>();
    if (cubit.state is HomeLoading) {
      cubit.loadHome();
    }
  }

  void _openLedger(BuildContext context, UserProfile profile) {
    final router = GoRouter.maybeOf(context);
    final hasLedgerRoute =
        router?.configuration.routes.any(
          (route) => route is GoRoute && route.path == '/ledger',
        ) ??
        false;
    if (hasLedgerRoute && router != null) {
      router.push('/ledger');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EcoColors.surfacePrimary,
      builder: (_) => _PointsSummarySheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) => BlocListener<HomeCubit, HomeState>(
    listenWhen: (previous, current) {
      if (current is! HomeReady || current.bannerError == null) {
        return false;
      }
      if (previous is HomeReady) {
        return previous.bannerError != current.bannerError;
      }
      return true;
    },
    listener: (context, state) {
      if (state case HomeReady(:final bannerError?)) {
        EcoErrorBannerPresenter.show(context, bannerError);
      }
    },
    child: Scaffold(
      backgroundColor: EcoColors.surfacePrimary,
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) => switch (state) {
          HomeLoading() => const _HomeSkeletonView(),
          HomeReady() => _HomeReadyBody(
            ready: state,
            activityExpanded: _activityExpanded,
            co2Expanded: _co2Expanded,
            onToggleActivity: () =>
                setState(() => _activityExpanded = !_activityExpanded),
            onToggleCo2: () => setState(() => _co2Expanded = !_co2Expanded),
            onOpenLedger: () => _openLedger(context, state.profile),
          ),
        },
      ),
    ),
  );
}

final class const _HomeReadyBody({
  required final HomeReady ready,
  required final bool activityExpanded,
  required final bool co2Expanded,
  required final VoidCallback onToggleActivity,
  required final VoidCallback onToggleCo2,
  required final VoidCallback onOpenLedger,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final snapshot = ready.mascotSnapshot;
    final metrics = ready.todayMetrics;
    return RefreshIndicator(
      color: EcoColors.inkPrimary,
      backgroundColor: EcoColors.surfacePrimary,
      onRefresh: () => context.read<HomeCubit>().refreshSensors(),
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _MascotHeroStage(
            profile: ready.profile,
            snapshot: snapshot,
            onOpenLedger: onOpenLedger,
          ),
          Padding(
            padding: const .symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                if (metrics.isEmptyDay) ...[
                  _EmptyDayPromptCard(
                    isRefreshing: ready.isRefreshing,
                    onRefresh: () => context.read<HomeCubit>().refreshSensors(),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Сегодня', style: EcoTypography.headlineLarge),
                const SizedBox(height: 12),
                _ActivityTodayCard(
                  metrics: metrics,
                  expanded: activityExpanded,
                  onToggle: onToggleActivity,
                ),
                const SizedBox(height: 12),
                _Co2TodayCard(
                  metrics: metrics,
                  expanded: co2Expanded,
                  onToggle: onToggleCo2,
                ),
                const SizedBox(height: 20),
                const _AddRouteCtaButton(),
                const SizedBox(height: 112),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class const _MascotHeroStage({
  required final UserProfile profile,
  required final MascotVisualSnapshot snapshot,
  required final VoidCallback onOpenLedger,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: .topCenter,
        end: .bottomCenter,
        colors: [
          Color(0xFFB5B5B5),
          Color(0xFFEAEAEA),
          EcoColors.surfacePrimary,
        ],
        stops: [0.0, 0.62, 1.0],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const .fromLTRB(16, 10, 16, 14),
        child: Column(
          children: [
            _HomeTopBar(profile: profile, onOpenLedger: onOpenLedger),
            const SizedBox(height: 8),
            FoxMascotWidget(
              mood: snapshot.mood,
              size: const Size(216, 216),
              equippedAccessoryCode: snapshot.equippedAccessoryCode,
              isPointerSquinting: snapshot.isPointerSquinting,
              onSquintingChanged: (down) =>
                  context.read<HomeCubit>().setPointerSquinting(down),
            ),
            const SizedBox(height: 4),
            Text(
              snapshot.statusCaptionRu,
              textAlign: .center,
              style: EcoTypography.bodyMedium.copyWith(
                color: EcoColors.inkPrimary,
                fontWeight: .w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _HomeTopBar({
  required final UserProfile profile,
  required final VoidCallback onOpenLedger,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: .spaceBetween,
    children: [
      _BalancePill(pointsBalance: profile.pointsBalance, onTap: onOpenLedger),
      _StreakPill(
        streakDays: profile.currentStreakDays,
        freezeCount: profile.streakFreezeCount,
      ),
      _ProfileAvatarButton(onTap: () => context.go('/profile')),
    ],
  );
}

final class const _BalancePill({
  required final int pointsBalance,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    child: Material(
      color: EcoColors.surfaceCard,
      borderRadius: const .all(.circular(999)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const .all(.circular(999)),
        child: Padding(
          padding: const .fromLTRB(6, 6, 14, 6),
          child: Row(
            mainAxisSize: .min,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: EcoColors.borderMuted,
                  shape: .circle,
                ),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: Icon(
                      LucideIcons.star,
                      size: 18,
                      color: EcoColors.surfacePrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '★ $pointsBalance',
                style: EcoTypography.titleMedium.copyWith(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class const _StreakPill({
  required final int streakDays,
  required final int freezeCount,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: EcoColors.surfaceSubtle,
      borderRadius: const .all(.circular(999)),
      border: .all(color: EcoColors.borderMuted, width: 1.5),
    ),
    child: Padding(
      padding: const .symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: .min,
        children: [
          Text(
            '🔥 $streakDays дн.',
            style: EcoTypography.bodyMedium.copyWith(fontWeight: .w700),
          ),
          if (freezeCount > 0) ...[
            const SizedBox(width: 8),
            Text(
              '❄ $freezeCount',
              style: EcoTypography.bodyMedium.copyWith(fontWeight: .w700),
            ),
          ],
        ],
      ),
    ),
  );
}

final class const _ProfileAvatarButton({required final VoidCallback onTap})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Профиль',
    child: SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: EcoColors.surfaceCard,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const Center(
            child: Icon(
              LucideIcons.user,
              size: 22,
              color: EcoColors.inkSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

final class const _EmptyDayPromptCard({
  required final bool isRefreshing,
  required final VoidCallback onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _DashedRoundedRectPainter(
      color: EcoColors.borderMuted,
      radius: 20,
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceSubtle,
        borderRadius: .all(.circular(20)),
      ),
      child: Padding(
        padding: const .all(16),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            const Text(
              'Сегодня шагов пока нет',
              style: EcoTypography.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Прогуляйтесь со смартфоном в кармане. Шаги синхронизируются автоматически с датчиков устройства.',
              style: EcoTypography.bodyMedium.copyWith(
                color: EcoColors.inkSecondary,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isRefreshing ? null : onRefresh,
              icon: isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EcoColors.inkPrimary,
                      ),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Обновить датчики сейчас'),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _DashedRoundedRectPainter({
  required final Color color,
  required final double radius,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashLen = 7.0;
    const gapLen = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

final class const _ActivityTodayCard({
  required final TodayCardMetrics metrics,
  required final bool expanded,
  required final VoidCallback onToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _CollapsibleWireframeCard(
    expanded: expanded,
    onToggle: onToggle,
    header: _ActivityCardHeader(metrics: metrics, expanded: expanded),
    expandedBody: _ActivityCardExpanded(metrics: metrics),
  );
}

final class const _ActivityCardHeader({
  required final TodayCardMetrics metrics,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    children: [
      Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          const Expanded(
            child: Text('Активность сегодня', style: EcoTypography.titleMedium),
          ),
          _ExpandCornerBadge(expanded: expanded),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: .end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Row(
                  crossAxisAlignment: .baseline,
                  textBaseline: .alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        '${metrics.validatedSteps}',
                        style: EcoTypography.displayHero,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '/ ${metrics.dailyStepGoal} шагов',
                      style: EcoTypography.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '+${metrics.pointsAwardedForDay} ★',
                  style: EcoTypography.labelSmall.copyWith(
                    color: EcoColors.inkPrimary,
                  ),
                ),
              ],
            ),
          ),
          const _WireframeMetricPillIcon(icon: LucideIcons.footprints),
        ],
      ),
    ],
  );
}

final class const _ActivityCardExpanded({
  required final TodayCardMetrics metrics,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      const SizedBox(height: 14),
      ClipRRect(
        borderRadius: const .all(.circular(999)),
        child: LinearProgressIndicator(
          value: metrics.stepGoalProgress,
          minHeight: 8,
          backgroundColor: EcoColors.surfaceSubtle,
          valueColor: const AlwaysStoppedAnimation<Color>(EcoColors.inkPrimary),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _SmallMetricCol(
              label: 'Дистанция',
              value: '${metrics.totalStepDistanceKm.toStringAsFixed(2)} км',
            ),
          ),
          Expanded(
            child: _SmallMetricCol(
              label: 'Калории',
              value: '${metrics.estimatedKcal} ккал',
            ),
          ),
          Expanded(
            child: _SmallMetricCol(
              label: 'Длина шага',
              value: '${metrics.strideLengthCm} см',
            ),
          ),
        ],
      ),
    ],
  );
}

final class const _Co2TodayCard({
  required final TodayCardMetrics metrics,
  required final bool expanded,
  required final VoidCallback onToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _CollapsibleWireframeCard(
    expanded: expanded,
    onToggle: onToggle,
    header: _Co2CardHeader(metrics: metrics, expanded: expanded),
    expandedBody: _Co2CardExpanded(metrics: metrics),
  );
}

final class const _Co2CardHeader({
  required final TodayCardMetrics metrics,
  required final bool expanded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    children: [
      Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'Экономия CO₂ сегодня',
              style: EcoTypography.titleMedium,
            ),
          ),
          _ExpandCornerBadge(expanded: expanded),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: .end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Row(
                  crossAxisAlignment: .baseline,
                  textBaseline: .alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        '${metrics.totalCo2SavedGrams}',
                        style: EcoTypography.displayHero,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '/ ${metrics.dailyCo2GoalGrams} г CO₂',
                      style: EcoTypography.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CalculationModeBadge(
                  isAutoCalculated: metrics.isAutoCalculated,
                ),
              ],
            ),
          ),
          const _WireframeMetricPillIcon(icon: LucideIcons.leaf),
        ],
      ),
    ],
  );
}

final class const _Co2CardExpanded({required final TodayCardMetrics metrics})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      const SizedBox(height: 14),
      Text(
        'Размечено по маршруту GPS: ${metrics.allocatedCo2SavedGrams} г (${metrics.allocatedGpsDistanceM.round()} м)',
        style: EcoTypography.bodyMedium,
      ),
      const SizedBox(height: 6),
      Text(
        'Базовый авторасчёт по остатку шагов: ${metrics.autoDefaultCo2SavedGrams} г (${metrics.unallocatedStepDistanceM.round()} м)',
        style: EcoTypography.bodyMedium.copyWith(color: EcoColors.inkSecondary),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => context.go('/map?mode=routes&date=today'),
        child: const Text('Уточнить транспорт на карте →'),
      ),
    ],
  );
}

final class const _CalculationModeBadge({required final bool isAutoCalculated})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: isAutoCalculated ? EcoColors.surfaceSubtle : EcoColors.inkPrimary,
      borderRadius: const .all(.circular(999)),
      border: .all(color: EcoColors.inkPrimary, width: 1.5),
    ),
    child: Padding(
      padding: const .symmetric(horizontal: 10, vertical: 4),
      child: Text(
        isAutoCalculated
            ? 'Авторасчёт (80% × 0.7)'
            : 'Подтверждено по GPS (100%)',
        style: EcoTypography.labelSmall.copyWith(
          color: isAutoCalculated
              ? EcoColors.inkPrimary
              : EcoColors.surfacePrimary,
        ),
      ),
    ),
  );
}

final class const _CollapsibleWireframeCard({
  required final bool expanded,
  required final VoidCallback onToggle,
  required final Widget header,
  required final Widget expandedBody,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: EcoColors.surfaceCard,
      borderRadius: const .all(.circular(20)),
      border: .all(color: EcoColors.borderMuted, width: 1.5),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: const .all(.circular(20)),
        child: Padding(
          padding: const .all(16),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              header,
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: expanded ? expandedBody : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class const _ExpandCornerBadge({required final bool expanded})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.borderMuted,
      shape: .circle,
    ),
    child: SizedBox(
      width: 30,
      height: 30,
      child: Center(
        child: Icon(
          expanded ? LucideIcons.chevronUp : LucideIcons.arrowUpRight,
          size: 16,
          color: EcoColors.inkPrimary,
        ),
      ),
    ),
  );
}

final class const _WireframeMetricPillIcon({required final IconData icon})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: EcoColors.surfaceSubtle,
      borderRadius: .all(.circular(999)),
    ),
    child: SizedBox(
      width: 82,
      height: 36,
      child: Align(
        alignment: .centerRight,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: EcoColors.borderMuted,
            borderRadius: .all(.circular(999)),
          ),
          child: SizedBox(
            width: 48,
            height: 36,
            child: Center(
              child: Icon(icon, size: 18, color: EcoColors.inkPrimary),
            ),
          ),
        ),
      ),
    ),
  );
}

final class const _SmallMetricCol({
  required final String label,
  required final String value,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    children: [
      Text(label, style: EcoTypography.labelSmall),
      const SizedBox(height: 2),
      Text(value, style: EcoTypography.bodyMedium.copyWith(fontWeight: .w700)),
    ],
  );
}

final class const _AddRouteCtaButton() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Tooltip(
      message: 'Открыть калькулятор активности',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 76, minHeight: 48),
        child: Material(
          color: const Color(0xFFB8B8B8),
          borderRadius: const .all(.circular(28)),
          child: InkWell(
            onTap: () => context.go('/map'),
            borderRadius: const .all(.circular(28)),
            child: const Padding(
              padding: .symmetric(horizontal: 24, vertical: 10),
              child: Icon(
                LucideIcons.plus,
                size: 26,
                color: EcoColors.inkPrimary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class const _PointsSummarySheet({required final UserProfile profile})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const .fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          const Text('История эко-баллов', style: EcoTypography.titleMedium),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: EcoColors.surfaceCard,
              borderRadius: const .all(.circular(20)),
              border: .all(color: EcoColors.borderMuted, width: 1.5),
            ),
            child: Padding(
              padding: const .all(16),
              child: Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: .start,
                    children: [
                      const Text(
                        'Текущий баланс',
                        style: EcoTypography.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '★ ${profile.pointsBalance}',
                        style: EcoTypography.headlineLarge,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: .end,
                    children: [
                      const Text(
                        'Всего заработано',
                        style: EcoTypography.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${profile.lifetimePointsEarned} ★',
                        style: EcoTypography.titleMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/shop');
            },
            child: const Text('Перейти в магазин наград'),
          ),
        ],
      ),
    ),
  );
}

final class const _HomeSkeletonView() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const .all(16),
      children: const [
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            _SkeletonBox(width: 96, height: 40, radius: 999),
            _SkeletonBox(width: 84, height: 36, radius: 999),
            _SkeletonBox(width: 48, height: 48, radius: 999),
          ],
        ),
        SizedBox(height: 24),
        Center(child: _SkeletonBox(width: 200, height: 200, radius: 100)),
        SizedBox(height: 24),
        _SkeletonBox(width: 120, height: 28, radius: 8),
        SizedBox(height: 12),
        _SkeletonBox(width: double.infinity, height: 112, radius: 20),
        SizedBox(height: 12),
        _SkeletonBox(width: double.infinity, height: 112, radius: 20),
      ],
    ),
  );
}

final class const _SkeletonBox({
  required final double width,
  required final double height,
  required final double radius,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: EcoColors.surfaceSubtle,
      borderRadius: .all(.circular(radius)),
    ),
    child: SizedBox(width: width, height: height),
  );
}
