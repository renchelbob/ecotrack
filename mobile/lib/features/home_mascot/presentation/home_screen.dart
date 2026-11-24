import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/home_cubit.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/mascot_vector_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'EcoTrack',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        BlocBuilder<HomeCubit, HomeState>(
          builder: (context, state) {
            final streak = switch (state) {
              HomeLoaded(summary: final s) => s.streakDays,
              _ => 1,
            };
            final balance = switch (state) {
              HomeLoaded(summary: final s) => s.pointsBalance,
              _ => 0,
            };
            return Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: EcoColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          color: EcoColors.accentOrange,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$streak дн',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: EcoColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: EcoColors.primaryGreen),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.eco,
                          color: EcoColors.primaryGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$balance',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    ),
    body: BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) => switch (state) {
        HomeLoading() => const Center(
          child: CircularProgressIndicator(color: EcoColors.primaryGreen),
        ),
        HomeFailure(error: final err) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off,
                  size: 48,
                  color: EcoColors.accentOrange,
                ),
                const SizedBox(height: 16),
                Text(err.uiMessageRu, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.read<HomeCubit>().loadTodaySummary(),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        HomeLoaded(summary: final s) => _buildContent(context, s),
      },
    ),
  );

  Widget _buildContent(BuildContext context, DailyActivitySummary summary) {
    final progress = (summary.validatedSteps / 10000).clamp(0.0, 1.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Speech Bubble
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: EcoColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EcoColors.divider),
              ),
              child: Text(
                switch (summary.mascotMood) {
                  MascotMood.sleepy => '«Давай сделаем первые шаги сегодня!»',
                  MascotMood.thriving =>
                    '«Ура! Дневная эко-цель выполнена на 100%!»',
                  MascotMood.squinting =>
                    '«Привет! Я лисенок Эко, рад тебя видеть!»',
                  MascotMood.happy =>
                    '«Отличный темп! Продолжаем беречь природу!»',
                },
                style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: EcoColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Interactive Fox Mascot
          Center(
            child: FoxMascotWidget(
              mood: summary.mascotMood,
              onTap: () => context.read<HomeCubit>().tapMascot(),
            ),
          ),
          const SizedBox(height: 20),

          // Today Progress Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Активность за сегодня',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${summary.validatedSteps} / 10 000',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: EcoColors.primaryGreenLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: EcoColors.surfaceVariant,
                      valueColor: const AlwaysStoppedAnimation(
                        EcoColors.primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetric(
                        Icons.directions_walk,
                        '${(summary.totalStepDistanceM / 1000).toStringAsFixed(1)} км',
                        'Дистанция',
                      ),
                      _buildMetric(
                        Icons.cloud_done_outlined,
                        '${summary.totalCo2SavedGrams} г',
                        'CO₂ сберегли',
                      ),
                      _buildMetric(
                        Icons.stars_outlined,
                        '+${summary.pointsBalance}',
                        'Эко-баллы',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Quick Action Cards
          const Text(
            'Быстрые действия',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  context,
                  icon: Icons.map_outlined,
                  title: 'Маршруты',
                  subtitle: 'Записать поездку',
                  color: EcoColors.accentBlue,
                  onTap: () => context.go('/map'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  context,
                  icon: Icons.recycling,
                  title: 'Пункты РСО',
                  subtitle: 'Сдать вторсырье',
                  color: EcoColors.primaryGreen,
                  onTap: () => context.go('/map'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(IconData icon, String value, String label) => Column(
    children: [
      Icon(icon, color: EcoColors.primaryGreenLight, size: 22),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      Text(
        label,
        style: const TextStyle(color: EcoColors.textSecondary, fontSize: 11),
      ),
    ],
  );

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EcoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: EcoColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}
