import 'dart:async';

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/sensors/step_sensor_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@immutable
final class const SyncStatusState({
  final int pendingOutboxCount = 0,
  final bool isOnline = true,
  final bool isSyncingSensors = false,
  final int? lastSyncedEpochMs,
}) {
  SyncStatusState copyWith({
    int? pendingOutboxCount,
    bool? isOnline,
    bool? isSyncingSensors,
    int? lastSyncedEpochMs,
  }) => SyncStatusState(
    pendingOutboxCount: pendingOutboxCount ?? this.pendingOutboxCount,
    isOnline: isOnline ?? this.isOnline,
    isSyncingSensors: isSyncingSensors ?? this.isSyncingSensors,
    lastSyncedEpochMs: lastSyncedEpochMs ?? this.lastSyncedEpochMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncStatusState &&
          pendingOutboxCount == other.pendingOutboxCount &&
          isOnline == other.isOnline &&
          isSyncingSensors == other.isSyncingSensors &&
          lastSyncedEpochMs == other.lastSyncedEpochMs;

  @override
  int get hashCode => Object.hash(
    pendingOutboxCount,
    isOnline,
    isSyncingSensors,
    lastSyncedEpochMs,
  );
}

final class SyncStatusCubit(
  final OutboxDispatcher _outboxDispatcher,
  final StepSensorBridge _stepSensorBridge,
) extends Cubit<SyncStatusState> {
  this : super(const SyncStatusState()) {
    _pendingSub = _outboxDispatcher.pendingCountStream.listen(_onPendingCount);
    _stepsSub = _stepSensorBridge.liveStepsStream.listen(_onLiveSteps);
    unawaited(_loadInitialPending());
  }

  StreamSubscription<int>? _pendingSub;
  StreamSubscription<int>? _stepsSub;

  Future<void> _loadInitialPending() async {
    final pending = await _outboxDispatcher.countPending();
    if (!isClosed) {
      emit(state.copyWith(pendingOutboxCount: pending));
    }
  }

  void _onPendingCount(int count) {
    if (isClosed) {
      return;
    }
    final syncedAt = count < state.pendingOutboxCount
        ? DateTime.now().millisecondsSinceEpoch
        : state.lastSyncedEpochMs;
    emit(
      state.copyWith(
        pendingOutboxCount: count,
        isOnline:
            count == 0 || count < state.pendingOutboxCount || state.isOnline,
        lastSyncedEpochMs: syncedAt,
      ),
    );
  }

  void _onLiveSteps(int _) {
    if (!isClosed && state.isSyncingSensors) {
      emit(
        state.copyWith(
          isSyncingSensors: false,
          lastSyncedEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> refresh() async {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(isSyncingSensors: true));
    await _outboxDispatcher.flush();
    final pending = await _outboxDispatcher.countPending();
    if (!isClosed) {
      emit(
        state.copyWith(
          pendingOutboxCount: pending,
          isSyncingSensors: false,
          lastSyncedEpochMs: pending == 0
              ? DateTime.now().millisecondsSinceEpoch
              : state.lastSyncedEpochMs,
        ),
      );
    }
  }

  void setOnline(bool isOnline) {
    if (!isClosed && state.isOnline != isOnline) {
      emit(state.copyWith(isOnline: isOnline));
    }
  }

  void setSyncingSensors(bool isSyncing) {
    if (!isClosed) {
      emit(
        state.copyWith(
          isSyncingSensors: isSyncing,
          lastSyncedEpochMs: isSyncing
              ? state.lastSyncedEpochMs
              : DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  void markSyncedNow() {
    if (!isClosed) {
      emit(
        state.copyWith(
          isOnline: true,
          isSyncingSensors: false,
          lastSyncedEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _pendingSub?.cancel();
    await _stepsSub?.cancel();
    await super.close();
  }
}
