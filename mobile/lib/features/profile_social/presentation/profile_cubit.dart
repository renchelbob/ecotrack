import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class ProfileState {
  const ProfileState();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileLoaded extends ProfileState {
  const ProfileLoaded(this.profile);
  final UserProfile profile;
}

final class ProfileFailure extends ProfileState {
  const ProfileFailure(this.error);
  final AppError error;
}

final class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit(this._repository) : super(const ProfileLoading());

  final ProfileRepository _repository;

  Future<void> loadProfile() async {
    emit(const ProfileLoading());
    final result = await _repository.getProfile();
    switch (result) {
      case Ok(value: final profile):
        emit(ProfileLoaded(profile));
      case Err(error: final appError):
        emit(ProfileFailure(appError));
    }
  }

  Future<Result<void, AppError>> exportData() =>
      _repository.exportPersonalData152Fz();

  Future<Result<void, AppError>> deleteAccount() =>
      _repository.deleteAccount152Fz();
}
