import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class StatsState {
  const StatsState();
}

final class StatsLoading extends StatsState {
  const StatsLoading();
}

final class StatsLoaded extends StatsState {
  const StatsLoaded({required this.stats, required this.leaderboard});

  final EmissionsStats stats;
  final List<LeaderboardEntry> leaderboard;
}

final class StatsFailure extends StatsState {
  const StatsFailure(this.error);
  final AppError error;
}

final class StatsCubit extends Cubit<StatsState> {
  StatsCubit(this._repository) : super(const StatsLoading());

  final StatsRepository _repository;

  Future<void> loadStats() async {
    emit(const StatsLoading());

    final statsRes = await _repository.getEmissionsStats();
    final boardRes = await _repository.getLeaderboard();

    if (statsRes is Ok<EmissionsStats, AppError> &&
        boardRes is Ok<List<LeaderboardEntry>, AppError>) {
      emit(StatsLoaded(stats: statsRes.value, leaderboard: boardRes.value));
    } else {
      final err =
          statsRes.errOrNull ??
          boardRes.errOrNull ??
          AppError.fromCode('VALIDATION_ERROR');
      emit(StatsFailure(err));
    }
  }
}
