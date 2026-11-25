import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/mascot_vector_painter.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:material_ui/material_ui.dart';

final class const FoxMascotWidget({
  required final MascotMoodState mood,
  final Size size = const Size(240, 240),
  final String? equippedAccessoryCode,
  final bool isPointerSquinting = false,
  final ValueChanged<bool>? onSquintingChanged,
  final VoidCallback? onTap,
  super.key,
}) extends StatefulWidget {
  @override
  State<FoxMascotWidget> createState() => _FoxMascotWidgetState();
}

final class _FoxMascotWidgetState()
    extends State<FoxMascotWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;
  bool _localPressing = false;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _breathController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  void _setSquinting(bool active) {
    if (_localPressing != active) {
      setState(() => _localPressing = active);
    }
    widget.onSquintingChanged?.call(active);
  }

  @override
  Widget build(BuildContext context) {
    final squinting = widget.isPointerSquinting || _localPressing;
    return GestureDetector(
      behavior: .opaque,
      onTapDown: (_) => _setSquinting(true),
      onTapUp: (_) {
        _setSquinting(false);
        widget.onTap?.call();
      },
      onTapCancel: () => _setSquinting(false),
      onLongPressStart: (_) => _setSquinting(true),
      onLongPressEnd: (_) => _setSquinting(false),
      child: Stack(
        alignment: .topCenter,
        clipBehavior: .none,
        children: [
          AnimatedBuilder(
            animation: _breathController,
            builder: (context, child) => RepaintBoundary(
              child: CustomPaint(
                size: widget.size,
                painter: MascotVectorPainter(
                  mood: widget.mood,
                  breathingPhase: _breathController.value,
                  equippedAccessoryCode: widget.equippedAccessoryCode,
                  isPointerSquinting: squinting,
                ),
              ),
            ),
          ),
          if (squinting) const Positioned(top: 0, child: _TickleSpeechBubble()),
        ],
      ),
    );
  }
}

final class const _TickleSpeechBubble() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: EcoColors.surfacePrimary,
      borderRadius: const .all(.circular(999)),
      border: .all(color: EcoColors.inkPrimary, width: 1.5),
    ),
    child: Padding(
      padding: const .symmetric(horizontal: 14, vertical: 6),
      child: Text(
        'Щекотно! Пойдём гулять?',
        style: EcoTypography.labelSmall.copyWith(color: EcoColors.inkPrimary),
      ),
    ),
  );
}
