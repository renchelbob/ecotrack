import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:material_ui/material_ui.dart';

final class EcoTopBannerOverlay._() {
  static final EcoTopBannerOverlay instance = EcoTopBannerOverlay._();

  final ValueNotifier<AppError?> currentBannerError = ValueNotifier<AppError?>(
    null,
  );
  VoidCallback? _currentOnRetry;

  VoidCallback? get currentOnRetry => _currentOnRetry;

  void show(AppError error, {VoidCallback? onRetry}) {
    _currentOnRetry = onRetry;
    if (currentBannerError.value == error) {
      currentBannerError.value = null;
    }
    currentBannerError.value = error;
  }

  void showMessage(String message) => show(
    AppError(
      code: 'INFO_BANNER',
      httpStatus: 200,
      domain: 'ui',
      retryable: false,
      clientAction: .showBanner,
      uiMessageRu: message,
    ),
  );

  void dismiss() {
    _currentOnRetry = null;
    currentBannerError.value = null;
  }
}

final class const EcoInlineErrorScope({
  required final ValueChanged<AppError> onInlineError,
  required super.child,
  super.key,
}) extends InheritedWidget {
  static ValueChanged<AppError>? maybeHandlerOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<EcoInlineErrorScope>()
      ?.onInlineError;

  @override
  bool updateShouldNotify(covariant EcoInlineErrorScope oldWidget) =>
      oldWidget.onInlineError != onInlineError;
}

final class const EcoInlineErrorCallout({
  required final AppError error,
  final VoidCallback? onRetry,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: .start,
    children: [
      const Padding(
        padding: .only(top: 2),
        child: Icon(
          Icons.warning_amber_rounded,
          size: 16,
          color: EcoColors.inkPrimary,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          error.uiMessageRu,
          style: EcoTypography.labelSmall.copyWith(
            fontSize: 12,
            fontWeight: .w700,
            color: EcoColors.inkPrimary,
          ),
        ),
      ),
      if (onRetry case final retry?) ...[
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: TextButton(
            onPressed: retry,
            child: Text(
              'Повторить',
              style: EcoTypography.labelSmall.copyWith(
                color: EcoColors.inkPrimary,
                fontWeight: .w700,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

final class EcoErrorBannerPresenter({
  required final BuildContext context,
  required final AppError error,
  final VoidCallback? onForceLogout,
  final VoidCallback? onOpenPhoneModal,
  final VoidCallback? onOpenConsentScreen,
  final VoidCallback? onRetry,
  final ValueChanged<AppError>? onShowInline,
}) {
  static const String offlineQueuedMessageRu =
      'Сохранено офлайн · Синхронизируем при появлении сети';

  void present() {
    switch (error.clientAction) {
      case .none:
      case .refreshToken:
        return;
      case .forceLogout:
        onForceLogout?.call();
        EcoTopBannerOverlay.instance.show(error);
      case .showInline:
        final inlineHandler =
            onShowInline ?? EcoInlineErrorScope.maybeHandlerOf(context);
        if (inlineHandler != null) {
          inlineHandler(error);
          return;
        }
        EcoTopBannerOverlay.instance.show(error, onRetry: onRetry);
      case .showBanner:
        EcoTopBannerOverlay.instance.show(error, onRetry: onRetry);
      case .queueRetry:
        EcoTopBannerOverlay.instance.show(
          AppError(
            code: error.code,
            httpStatus: error.httpStatus,
            domain: error.domain,
            retryable: error.retryable,
            clientAction: error.clientAction,
            uiMessageRu: offlineQueuedMessageRu,
            traceId: error.traceId,
            details: error.details,
          ),
          onRetry: onRetry,
        );
      case .openPhoneModal:
        onOpenPhoneModal?.call();
      case .openConsentScreen:
        onOpenConsentScreen?.call();
    }
  }

  static void show(
    BuildContext context,
    AppError error, {
    VoidCallback? onForceLogout,
    VoidCallback? onOpenPhoneModal,
    VoidCallback? onOpenConsentScreen,
    VoidCallback? onRetry,
    ValueChanged<AppError>? onShowInline,
  }) => EcoErrorBannerPresenter(
    context: context,
    error: error,
    onForceLogout: onForceLogout,
    onOpenPhoneModal: onOpenPhoneModal,
    onOpenConsentScreen: onOpenConsentScreen,
    onRetry: onRetry,
    onShowInline: onShowInline,
  ).present();
}

final class const EcoTopBannerHost({
  required final Widget child,
  final EcoTopBannerOverlay? overlay,
  super.key,
}) extends StatefulWidget {
  @override
  State<EcoTopBannerHost> createState() => _EcoTopBannerHostState();
}

final class _EcoTopBannerHostState() extends State<EcoTopBannerHost> {
  static const Duration _bannerDuration = .new(milliseconds: 4000);

  Timer? _dismissTimer;
  AppError? _activeError;
  late ValueNotifier<AppError?> _listenedNotifier;

  EcoTopBannerOverlay get _overlay =>
      widget.overlay ?? EcoTopBannerOverlay.instance;

  @override
  void initState() {
    super.initState();
    _listenedNotifier = _overlay.currentBannerError;
    _listenedNotifier.addListener(_handleBannerChanged);
    _activeError = _listenedNotifier.value;
    if (_activeError != null) {
      _scheduleDismiss();
    }
  }

  @override
  void didUpdateWidget(covariant EcoTopBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextNotifier = _overlay.currentBannerError;
    if (!identical(_listenedNotifier, nextNotifier)) {
      _listenedNotifier.removeListener(_handleBannerChanged);
      _listenedNotifier = nextNotifier;
      _listenedNotifier.addListener(_handleBannerChanged);
      _dismissTimer?.cancel();
      _activeError = _listenedNotifier.value;
      if (_activeError != null) {
        _scheduleDismiss();
      }
    }
  }

  void _handleBannerChanged() {
    final nextError = _listenedNotifier.value;
    _dismissTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _activeError = nextError);
    if (nextError != null) {
      _scheduleDismiss();
    }
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(_bannerDuration, _overlay.dismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _listenedNotifier.removeListener(_handleBannerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeError = _activeError;
    return Stack(
      children: [
        widget.child,
        if (activeError != null)
          Positioned(
            top: 0,
            left: 16,
            right: 16,
            child: SafeArea(
              bottom: false,
              child: _EcoTopBannerCard(
                error: activeError,
                onDismiss: _overlay.dismiss,
                onRetry: _overlay.currentOnRetry,
              ),
            ),
          ),
      ],
    );
  }
}

final class const _EcoTopBannerCard({
  required final AppError error,
  required final VoidCallback onDismiss,
  final VoidCallback? onRetry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isOfflinePill = error.clientAction == ClientErrorAction.queueRetry;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isOfflinePill
              ? EcoColors.surfaceSubtle
              : EcoColors.surfacePrimary,
          borderRadius: const .all(.circular(20)),
          border: const .fromBorderSide(
            BorderSide(color: EcoColors.inkPrimary, width: 1.5),
          ),
        ),
        child: Padding(
          padding: const .symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isOfflinePill ? Icons.cloud_off : Icons.error_outline,
                color: EcoColors.inkPrimary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  error.uiMessageRu,
                  style: EcoTypography.bodyMedium.copyWith(
                    color: EcoColors.inkPrimary,
                    fontWeight: .w600,
                  ),
                ),
              ),
              if (onRetry case final retry?) ...[
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: TextButton(
                    onPressed: () {
                      onDismiss();
                      retry();
                    },
                    child: Text(
                      'Повторить',
                      style: EcoTypography.labelSmall.copyWith(
                        color: EcoColors.inkPrimary,
                        fontWeight: .w700,
                      ),
                    ),
                  ),
                ),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(
                    Icons.close,
                    color: EcoColors.inkPrimary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
