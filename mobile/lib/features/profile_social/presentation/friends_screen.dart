import 'dart:async';

import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/friends_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

final class const FriendsScreen({final String? initialInviteCode, super.key})
    extends StatefulWidget {
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

final class _FriendsScreenState() extends State<FriendsScreen> {
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: widget.initialInviteCode ?? '',
    );
    final cubit = context.read<FriendsCubit>();
    if (cubit.state is FriendsLoading) {
      unawaited(cubit.load());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _showMyQrSheet(String friendCode) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: EcoColors.surfacePrimary,
    shape: const RoundedRectangleBorder(
      borderRadius: .vertical(top: .circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const .all(24),
        child: Column(
          mainAxisSize: .min,
          children: [
            const Text('Мой QR-код друга', style: EcoTypography.titleMedium),
            const SizedBox(height: 16),
            QrImageView(data: friendCode, size: 200),
            const SizedBox(height: 12),
            SelectableText(friendCode, style: EcoTypography.headlineLarge),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _openQrScanner() async {
    final scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EcoColors.surfacePrimary,
      builder: (_) => const _QrScannerSheet(),
    );
    if (scanned != null && scanned.isNotEmpty && mounted) {
      _codeController.text = scanned;
      await context.read<FriendsCubit>().sendRequest(scanned);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FriendsCubit, FriendsState>(
        listener: (context, state) {
          if (state case FriendsLoaded(
            :final activeError,
            :final feedbackMessage,
          )) {
            if (activeError != null) {
              EcoErrorBannerPresenter.show(context, activeError);
              context.read<FriendsCubit>().clearError();
            } else if (feedbackMessage != null) {
              EcoTopBannerOverlay.instance.showMessage(feedbackMessage);
              context.read<FriendsCubit>().clearError();
            }
          }
        },
        builder: (context, state) => Scaffold(
          backgroundColor: EcoColors.surfacePrimary,
          appBar: AppBar(title: const Text('Друзья')),
          body: switch (state) {
            FriendsLoading() => const Center(
              child: CircularProgressIndicator(color: EcoColors.inkPrimary),
            ),
            FriendsFailure(:final error) => Center(
              child: Padding(
                padding: const .all(24),
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    Text(error.uiMessageRu, textAlign: .center),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: () =>
                          unawaited(context.read<FriendsCubit>().load()),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
            FriendsLoaded() => RefreshIndicator(
              color: EcoColors.inkPrimary,
              onRefresh: context.read<FriendsCubit>().load,
              child: ListView(
                padding: const .all(16),
                children: [
                  _AddFriendCard(
                    overview: state.overview,
                    controller: _codeController,
                    isSending: state.isSendingRequest,
                    inlineError: state.inlineErrorText,
                    onShowQr: () =>
                        unawaited(_showMyQrSheet(state.overview.myFriendCode)),
                    onScanQr: () => unawaited(_openQrScanner()),
                    onSubmitCode: () => unawaited(
                      context.read<FriendsCubit>().sendRequest(
                        _codeController.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (state.overview.incomingRequests.isNotEmpty) ...[
                    const Text(
                      'Входящие заявки',
                      style: EcoTypography.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final req in state.overview.incomingRequests) ...[
                      _IncomingRequestCard(friend: req),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 10),
                  ],
                  const Text('Мои друзья', style: EcoTypography.titleMedium),
                  const SizedBox(height: 8),
                  if (state.overview.friends.isEmpty)
                    const Text(
                      'Пока нет добавленных друзей. Поделитесь своим кодом ECO-XXXX-XXXX.',
                      style: EcoTypography.bodyMedium,
                    )
                  else
                    for (final friend in state.overview.friends) ...[
                      _AcceptedFriendCard(
                        friend: friend,
                        isNudging: state.nudgingUserIds.contains(friend.userId),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          },
        ),
      );
}

final class const _AddFriendCard({
  required final FriendsOverviewResponse overview,
  required final TextEditingController controller,
  required final bool isSending,
  required final String? inlineError,
  required final VoidCallback onShowQr,
  required final VoidCallback onScanQr,
  required final VoidCallback onSubmitCode,
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
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            'Мой код друга: ${overview.myFriendCode}',
            style: EcoTypography.titleMedium,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShowQr,
                  icon: const Icon(LucideIcons.qrCode, size: 18),
                  label: const Text('Показать мой QR'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onScanQr,
                  icon: const Icon(LucideIcons.scanLine, size: 18),
                  label: const Text('Сканировать QR'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            textCapitalization: .characters,
            decoration: const InputDecoration(
              labelText: 'Код друга ECO-XXXX-XXXX',
              hintText: 'ECO-AB12-CD34',
            ),
          ),
          if (inlineError case final err?) ...[
            const SizedBox(height: 6),
            Text(err, style: EcoTypography.labelSmall),
          ],
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: isSending ? null : onSubmitCode,
            child: const Text('Отправить заявку'),
          ),
        ],
      ),
    ),
  );
}

final class const _IncomingRequestCard({
  required final FriendProfileSummary friend,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FriendsCubit>();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceSubtle,
        borderRadius: .all(.circular(16)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(friend.displayName, style: EcoTypography.bodyLarge),
                  Text(friend.friendCode, style: EcoTypography.labelSmall),
                ],
              ),
            ),
            TextButton(
              onPressed: () =>
                  unawaited(cubit.respond(friend.friendshipId, 'decline')),
              child: const Text('Отклонить'),
            ),
            ElevatedButton(
              onPressed: () =>
                  unawaited(cubit.respond(friend.friendshipId, 'accept')),
              child: const Text('Принять'),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _AcceptedFriendCard({
  required final FriendProfileSummary friend,
  required final bool isNudging,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FriendsCubit>();
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceCard,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: EcoColors.surfaceSubtle,
                  child: Icon(LucideIcons.user, color: EcoColors.inkPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(friend.displayName, style: EcoTypography.bodyLarge),
                      Text(
                        'Стрик ${friend.currentStreakDays} дн · Неделя: ${friend.weeklyCo2SavedGrams} г CO₂',
                        style: EcoTypography.labelSmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => unawaited(cubit.removeFriend(friend.userId)),
                  tooltip: 'Удалить из друзей',
                  icon: const Icon(
                    LucideIcons.userMinus,
                    size: 18,
                    color: EcoColors.inkSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: friend.canSendWakeupNudgeToday && !isNudging
                  ? () => unawaited(cubit.sendNudge(friend.userId))
                  : null,
              icon: const Icon(LucideIcons.bell, size: 16),
              label: Text(
                friend.canSendWakeupNudgeToday
                    ? 'Разбудить зверька'
                    : 'Зверёк уже разбужен сегодня',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class const _QrScannerSheet() extends StatefulWidget {
  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

final class _QrScannerSheetState() extends State<_QrScannerSheet> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: 420,
      child: Column(
        children: [
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Наведите камеру на QR-код друга',
                    style: EcoTypography.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                if (_handled) return;
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value != null && value.isNotEmpty) {
                  _handled = true;
                  Navigator.of(context).pop(value);
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}
