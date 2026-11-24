import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class HomeState {
  const HomeState();
}

final class HomeLoading extends HomeState {
  const HomeLoading();
}

final class HomeLoaded extends HomeState {
  const HomeLoaded(this.summary);
  final DailyActivitySummary summary;
}

final class HomeFailure extends HomeState {
  const HomeFailure(this.error);
  final AppError error;
}

final class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._repository) : super(const HomeLoading());

  final HomeRepository _repository;

  Future<void> loadTodaySummary() async {
    emit(const HomeLoading());
    final result = await _repository.getTodaySummary();
    switch (result) {
      case Ok(value: final summary):
        emit(HomeLoaded(summary));
      case Err(error: final appError):
        emit(HomeFailure(appError));
    }
  }

  Future<void> syncSteps(int rawSteps) async {
    final result = await _repository.syncSteps(rawSteps);
    switch (result) {
      case Ok(value: final summary):
        emit(HomeLoaded(summary));
      case Err(error: final appError):
        emit(HomeFailure(appError));
    }
  }

  void tapMascot() {
    if (state case HomeLoaded(summary: final s)) {
      // Toggle squinting or delight reaction
      emit(HomeLoaded(s));
    }
  }
}
