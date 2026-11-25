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

  void show(AppError error) {
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
      clientAction: ClientErrorAction.showBanner,
      uiMessageRu: message,
    ),
  );

  void dismiss() {
    currentBannerError.value = null;
  }
}

final class EcoErrorBannerPresenter({
  required final BuildContext context,
  required final AppError error,
  final VoidCallback? onForceLogout,
  final VoidCallback? onOpenPhoneModal,
  final VoidCallback? onOpenConsentScreen,
  final VoidCallback? onRetry,
}) {
  static const String offlineQueuedMessageRu =
      'Сохранено офлайн · Синхронизируем при появлении сети';

  void present() {
    switch (error.clientAction) {
      case ClientErrorAction.none:
      case ClientErrorAction.refreshToken:
        return;
      case ClientErrorAction.forceLogout:
        onForceLogout?.call();
        EcoTopBannerOverlay.instance.show(error);
      case ClientErrorAction.showInline:
      case ClientErrorAction.showBanner:
        EcoTopBannerOverlay.instance.show(error);
      case ClientErrorAction.queueRetry:
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
        );
      case ClientErrorAction.openPhoneModal:
        onOpenPhoneModal?.call();
      case ClientErrorAction.openConsentScreen:
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
  }) => EcoErrorBannerPresenter(
    context: context,
    error: error,
    onForceLogout: onForceLogout,
    onOpenPhoneModal: onOpenPhoneModal,
    onOpenConsentScreen: onOpenConsentScreen,
    onRetry: onRetry,
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
  static const Duration _bannerDuration = Duration(milliseconds: 4000);

  Timer? _dismissTimer;
  AppError? _activeError;

  EcoTopBannerOverlay get _overlay =>
      widget.overlay ?? EcoTopBannerOverlay.instance;

  @override
  void initState() {
    super.initState();
    _overlay.currentBannerError.addListener(_handleBannerChanged);
    _activeError = _overlay.currentBannerError.value;
    if (_activeError != null) {
      _scheduleDismiss();
    }
  }

  @override
  void didUpdateWidget(covariant EcoTopBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldOverlay = oldWidget.overlay ?? EcoTopBannerOverlay.instance;
    if (!identical(oldOverlay, _overlay)) {
      oldOverlay.currentBannerError.removeListener(_handleBannerChanged);
      _overlay.currentBannerError.addListener(_handleBannerChanged);
      _handleBannerChanged();
    }
  }

  void _handleBannerChanged() {
    final nextError = _overlay.currentBannerError.value;
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
    _overlay.currentBannerError.removeListener(_handleBannerChanged);
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
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: EcoColors.inkPrimary, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
