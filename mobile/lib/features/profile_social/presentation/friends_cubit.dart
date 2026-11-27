import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class const FriendsState();

final class const FriendsLoading() extends FriendsState;

final class const FriendsLoaded({
  required final FriendsOverviewResponse overview,
  final bool isSendingRequest = false,
  final Set<String> nudgingUserIds = const {},
  final AppError? activeError,
  final String? inlineErrorText,
  final String? feedbackMessage,
}) extends FriendsState {
  FriendsLoaded copyWith({
    FriendsOverviewResponse? overview,
    bool? isSendingRequest,
    Set<String>? nudgingUserIds,
    AppError? activeError,
    String? inlineErrorText,
    String? feedbackMessage,
    bool clearErrors = false,
    bool clearFeedback = false,
  }) => FriendsLoaded(
    overview: overview ?? this.overview,
    isSendingRequest: isSendingRequest ?? this.isSendingRequest,
    nudgingUserIds: nudgingUserIds ?? this.nudgingUserIds,
    activeError: clearErrors ? null : (activeError ?? this.activeError),
    inlineErrorText: clearErrors
        ? null
        : (inlineErrorText ?? this.inlineErrorText),
    feedbackMessage: clearFeedback
        ? null
        : (feedbackMessage ?? this.feedbackMessage),
  );
}

final class const FriendsFailure(final AppError error) extends FriendsState;

final class FriendsCubit(final FriendsRepository _friendsRepo)
    extends Cubit<FriendsState> {
  this : super(const FriendsLoading());

  Future<void> load() async {
    if (state is! FriendsLoaded) {
      emit(const FriendsLoading());
    }
    final result = await _friendsRepo.getFriendsOverview();
    if (isClosed) {
      return;
    }
    switch (result) {
      case Ok(:final value):
        emit(FriendsLoaded(overview: value));
      case Err(:final error):
        if (state case final FriendsLoaded loaded) {
          emit(loaded.copyWith(activeError: error));
        } else {
          emit(FriendsFailure(error));
        }
    }
  }

  Future<bool> sendRequest(String code) async {
    final current = state;
    if (current is FriendsLoaded) {
      emit(
        current.copyWith(
          isSendingRequest: true,
          clearErrors: true,
          clearFeedback: true,
        ),
      );
    }
    final result = await _friendsRepo.sendFriendRequest(code);
    if (isClosed) {
      return false;
    }
    switch (result) {
      case Ok():
        final overviewRes = await _friendsRepo.getFriendsOverview();
        if (!isClosed) {
          switch (overviewRes) {
            case Ok(:final value):
              emit(
                FriendsLoaded(
                  overview: value,
                  feedbackMessage: 'Заявка в друзья отправлена',
                ),
              );
            case Err(:final error):
              if (state case final FriendsLoaded loaded) {
                emit(
                  loaded.copyWith(isSendingRequest: false, activeError: error),
                );
              }
          }
        }
        return true;
      case Err(:final error):
        if (state case final FriendsLoaded loaded) {
          emit(
            loaded.copyWith(
              isSendingRequest: false,
              activeError: error,
              inlineErrorText: error.clientAction == .showInline
                  ? error.uiMessageRu
                  : null,
            ),
          );
        }
        return false;
    }
  }

  Future<void> respond(String friendshipId, String action) async {
    final result = await _friendsRepo.respondToRequest(friendshipId, action);
    if (isClosed) {
      return;
    }
    switch (result) {
      case Ok():
        await load();
      case Err(:final error):
        if (state case final FriendsLoaded loaded) {
          emit(loaded.copyWith(activeError: error));
        }
    }
  }

  Future<void> removeFriend(String userId) async {
    final result = await _friendsRepo.removeFriend(userId);
    if (isClosed) {
      return;
    }
    switch (result) {
      case Ok():
        await load();
      case Err(:final error):
        if (state case final FriendsLoaded loaded) {
          emit(loaded.copyWith(activeError: error));
        }
    }
  }

  Future<void> sendNudge(String userId) async {
    final current = state;
    if (current is! FriendsLoaded) {
      return;
    }
    final nextNudging = {...current.nudgingUserIds, userId};
    emit(
      current.copyWith(
        nudgingUserIds: nextNudging,
        clearErrors: true,
        clearFeedback: true,
      ),
    );

    final result = await _friendsRepo.sendWakeupNudge(userId);
    if (isClosed) {
      return;
    }
    final updatedNudging = {...nextNudging}..remove(userId);
    switch (result) {
      case Ok():
        final updatedFriends = current.overview.friends
            .map(
              (f) => f.userId == userId
                  ? FriendProfileSummary(
                      friendshipId: f.friendshipId,
                      userId: f.userId,
                      displayName: f.displayName,
                      avatarUrl: f.avatarUrl,
                      friendCode: f.friendCode,
                      status: f.status,
                      currentStreakDays: f.currentStreakDays,
                      equippedAccessoryCode: f.equippedAccessoryCode,
                      isStatsVisibleToFriends: f.isStatsVisibleToFriends,
                      weeklyCo2SavedGrams: f.weeklyCo2SavedGrams,
                      weeklySteps: f.weeklySteps,
                      canSendWakeupNudgeToday: false,
                    )
                  : f,
            )
            .toList();
        emit(
          current.copyWith(
            overview: FriendsOverviewResponse(
              myFriendCode: current.overview.myFriendCode,
              friends: updatedFriends,
              incomingRequests: current.overview.incomingRequests,
              outgoingRequests: current.overview.outgoingRequests,
            ),
            nudgingUserIds: updatedNudging,
            feedbackMessage: 'Уведомление «Разбудить зверька» отправлено!',
          ),
        );
      case Err(:final error):
        emit(
          current.copyWith(nudgingUserIds: updatedNudging, activeError: error),
        );
    }
  }

  void clearError() {
    if (state case final FriendsLoaded loaded) {
      emit(loaded.copyWith(clearErrors: true, clearFeedback: true));
    }
  }
}
