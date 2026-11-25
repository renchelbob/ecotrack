import 'dart:async';

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:ecotrack_mobile/features/profile_social/data/friends_sqlite_dao.dart';
import 'package:ecotrack_mobile/features/profile_social/data/profile_sqlite_dao.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';

final class FriendsRepositoryImpl(
  final DioClient _dioClient,
  final SqliteDatabase _db,
  final OutboxDispatcher _outbox,
) implements FriendsRepository {
  static final RegExp _friendCodePattern = RegExp(
    r'^ECO-[A-Z0-9]{4}-[A-Z0-9]{4}$',
  );

  late final FriendsSqliteDao _friendsDao = FriendsSqliteDao(_db);
  late final ProfileSqliteDao _profileDao = ProfileSqliteDao(_db);

  @override
  Future<Result<FriendsOverviewResponse, AppError>> getFriendsOverview() async {
    final result = await _dioClient.get<FriendsOverviewResponse>(
      '/api/v1/friends',
      parser: (data) => _parseOrThrow(data, FriendsOverviewResponse.fromJson),
    );

    switch (result) {
      case Ok(:final value):
        await _friendsDao.replaceCachedFriends(value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final profile = await _profileDao.getCachedProfile();
          final cached = await _friendsDao.getCachedOverview(
            profile?.friendCode ?? 'ECO-0000-0000',
          );
          if (cached != null) {
            return Ok(cached);
          }
          if (profile != null) {
            return Ok(
              FriendsOverviewResponse(
                myFriendCode: profile.friendCode,
                friends: const [],
                incomingRequests: const [],
                outgoingRequests: const [],
              ),
            );
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<FriendshipRecord, AppError>> sendFriendRequest(
    String friendCode,
  ) async {
    final normalized = friendCode.trim().toUpperCase();
    if (!_friendCodePattern.hasMatch(normalized)) {
      return Err(AppError.fromCode('FRIEND_CODE_NOT_FOUND'));
    }

    return await _dioClient.post<FriendshipRecord>(
      '/api/v1/friends/requests',
      data: {'friend_code': normalized},
      parser: (data) => _parseOrThrow(data, FriendshipRecord.fromJson),
    );
  }

  @override
  Future<Result<FriendshipRecord, AppError>> respondToRequest(
    String friendshipId,
    String action,
  ) => _dioClient.patch<FriendshipRecord>(
    '/api/v1/friends/requests/$friendshipId',
    data: {'action': action},
    parser: (data) => _parseOrThrow(data, FriendshipRecord.fromJson),
  );

  @override
  Future<Result<void, AppError>> removeFriend(String friendUserId) async {
    final result = await _dioClient.delete<void>(
      '/api/v1/friends/$friendUserId',
      parser: (_) {},
    );
    if (result case Ok()) {
      await _friendsDao.removeCachedFriend(friendUserId);
    }
    return result;
  }

  @override
  Future<Result<WakeupNudgeResponse, AppError>> sendWakeupNudge(
    String friendUserId,
  ) async {
    final result = await _dioClient.post<WakeupNudgeResponse>(
      '/api/v1/friends/$friendUserId/nudge',
      parser: (data) => _parseOrThrow(data, WakeupNudgeResponse.fromJson),
    );

    switch (result) {
      case Ok(:final value):
        await _friendsDao.markNudgedToday(friendUserId, value.nudgeDate);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          await _friendsDao.enqueueWakeupNudgeOutbox(
            friendUserId: friendUserId,
            idempotencyKey: UuidV7.generate(),
          );
          unawaited(_outbox.flush());
        }
        return Err(error);
    }
  }

  bool _isOfflineError(AppError error) =>
      error.clientAction == ClientErrorAction.queueRetry ||
      error.httpStatus == 0 ||
      error.httpStatus == 503;

  T _parseOrThrow<T>(
    Object? data,
    Result<T, AppError> Function(Map<String, Object?>) parser,
  ) {
    if (data is Map<String, Object?>) {
      return switch (parser(data)) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };
    }
    throw AppError.fromCode('VALIDATION_ERROR');
  }
}
