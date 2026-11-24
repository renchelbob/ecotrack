import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';
import 'package:ecotrack_mobile/features/stats/presentation/stats_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Статистика и эко-след',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    body: BlocBuilder<StatsCubit, StatsState>(
      builder: (context, state) => switch (state) {
        StatsLoading() => const Center(
          child: CircularProgressIndicator(color: EcoColors.primaryGreen),
        ),
        StatsFailure(error: final err) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: EcoColors.errorRed,
              ),
              const SizedBox(height: 16),
              Text(err.uiMessageRu),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.read<StatsCubit>().loadStats(),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        StatsLoaded(stats: final s, leaderboard: final board) => _buildContent(
          context,
          s,
          board,
        ),
      },
    ),
  );

  Widget _buildContent(
    BuildContext context,
    EmissionsStats stats,
    List<LeaderboardEntry> board,
  ) => SingleChildScrollView(
    padding: const EdgeInsets.all(20.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Total CO2 saved card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Сэкономлено выбросов CO₂',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                '${stats.totalCo2SavedKg.toStringAsFixed(1)} кг',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSubMetric(
                    '🌳 ${stats.treesEquivalent.toStringAsFixed(2)}',
                    'эквивалент деревьев',
                  ),
                  _buildSubMetric(
                    '⛽ ${stats.gasolineSavedLiters.toStringAsFixed(1)} л',
                    'бензина спасено',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Transport mode breakdown
        const Text(
          'Доли замещенного транспорта',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: stats.shares
                  .map(
                    (share) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                share.mode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${share.percentage.toStringAsFixed(0)}% (${share.co2SavedKg.toStringAsFixed(1)} кг)',
                                style: const TextStyle(
                                  color: EcoColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (share.percentage / 100).clamp(0.0, 1.0),
                              minHeight: 8,
                              backgroundColor: EcoColors.surfaceVariant,
                              valueColor: AlwaysStoppedAnimation(
                                share.mode == 'Пешком'
                                    ? EcoColors.primaryGreen
                                    : share.mode == 'Метро'
                                    ? EcoColors.accentBlue
                                    : EcoColors.accentOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Friends Leaderboard
        const Text(
          'Эко-рейтинг друзей',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: board.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: EcoColors.divider),
            itemBuilder: (context, index) {
              final entry = board[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: entry.isCurrentUser
                      ? EcoColors.primaryGreen
                      : EcoColors.surfaceVariant,
                  foregroundColor: Colors.white,
                  child: Text('${entry.rank}'),
                ),
                title: Text(
                  entry.displayName,
                  style: TextStyle(
                    fontWeight: entry.isCurrentUser
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: entry.isCurrentUser
                        ? EcoColors.primaryGreenLight
                        : EcoColors.textPrimary,
                  ),
                ),
                subtitle: Text('🔥 ${entry.streakDays} дн подряд'),
                trailing: Text(
                  '${(entry.totalCo2SavedGrams / 1000).toStringAsFixed(1)} кг CO₂',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildSubMetric(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ],
  );
}
