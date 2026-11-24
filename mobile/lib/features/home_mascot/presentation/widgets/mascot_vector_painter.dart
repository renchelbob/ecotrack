import 'dart:math' as math;

import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:flutter/material.dart';

/// Fox Mascot vector painter drawing expressive Canvas geometry with 4 mood states:
/// sleepy, happy, thriving, squinting.
class MascotVectorPainter extends CustomPainter {
  const MascotVectorPainter({
    required this.mood,
    required this.breathProgress,
    required this.tailProgress,
  });

  final MascotMood mood;
  final double breathProgress; // 0.0 to 1.0 (sine breathing)
  final double tailProgress; // 0.0 to 1.0 (tail swaying)

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = 1.0 + (breathProgress * 0.04);

    canvas
      ..save()
      ..translate(cx, cy)
      ..scale(scale, scale);

    // 1. Aura (Thriving mood only)
    if (mood == MascotMood.thriving) {
      final auraPaint = Paint()
        ..color = const Color(0x4081C784)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawCircle(Offset.zero, 85, auraPaint);

      // Eco leaf over head
      final leafPaint = Paint()..color = const Color(0xFF4CAF50);
      final leafPath = Path()
        ..moveTo(0, -95)
        ..quadraticBezierTo(15, -110, 0, -125)
        ..quadraticBezierTo(-15, -110, 0, -95);
      canvas.drawPath(leafPath, leafPaint);
    }

    // 2. Tail (swaying)
    final tailAngle = math.sin(tailProgress * math.pi * 2) * 0.15;
    canvas
      ..save()
      ..translate(45, 45)
      ..rotate(tailAngle);
    final tailPaint = Paint()..color = const Color(0xFFE65100);
    final tailPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(20, -10, 40, 10, 50, 40)
      ..cubicTo(50, 60, 20, 70, 0, 45)
      ..close();
    canvas.drawPath(tailPath, tailPaint);

    // White tail tip
    final tailTipPaint = Paint()..color = const Color(0xFFFFF8E1);
    final tailTipPath = Path()
      ..moveTo(35, 30)
      ..cubicTo(45, 35, 50, 45, 50, 55)
      ..cubicTo(40, 65, 30, 60, 20, 48)
      ..close();
    canvas
      ..drawPath(tailTipPath, tailTipPaint)
      ..restore();

    // 3. Body
    final bodyPaint = Paint()..color = const Color(0xFFF57C00);
    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-40, 0, 80, 70),
      const Radius.circular(35),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    // White chest fluff
    final chestPaint = Paint()..color = const Color(0xFFFFF8E1);
    final chestPath = Path()
      ..moveTo(-25, 10)
      ..quadraticBezierTo(0, 40, 25, 10)
      ..quadraticBezierTo(15, 55, 0, 60)
      ..quadraticBezierTo(-15, 55, -25, 10);
    canvas.drawPath(chestPath, chestPaint);

    // 4. Ears
    final earOuterPaint = Paint()..color = const Color(0xFFE65100);
    final earInnerPaint = Paint()..color = const Color(0xFFFFF8E1);
    final earTipPaint = Paint()..color = const Color(0xFF212121);

    // Left Ear
    final leftEarPath = Path()
      ..moveTo(-50, -45)
      ..lineTo(-35, -95)
      ..lineTo(-10, -55)
      ..close();
    canvas.drawPath(leftEarPath, earOuterPaint);

    final leftEarTip = Path()
      ..moveTo(-45, -75)
      ..lineTo(-35, -95)
      ..lineTo(-22, -75)
      ..close();
    canvas.drawPath(leftEarTip, earTipPaint);

    final leftEarInner = Path()
      ..moveTo(-42, -50)
      ..lineTo(-34, -80)
      ..lineTo(-18, -58)
      ..close();
    canvas.drawPath(leftEarInner, earInnerPaint);

    // Right Ear
    final rightEarPath = Path()
      ..moveTo(10, -55)
      ..lineTo(35, -95)
      ..lineTo(50, -45)
      ..close();
    canvas.drawPath(rightEarPath, earOuterPaint);

    final rightEarTip = Path()
      ..moveTo(22, -75)
      ..lineTo(35, -95)
      ..lineTo(45, -75)
      ..close();
    canvas.drawPath(rightEarTip, earTipPaint);

    final rightEarInner = Path()
      ..moveTo(18, -58)
      ..lineTo(34, -80)
      ..lineTo(42, -50)
      ..close();
    canvas.drawPath(rightEarInner, earInnerPaint);

    // 5. Head
    final headPaint = Paint()..color = const Color(0xFFF57C00);
    final headRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-55, -65, 110, 80),
      const Radius.circular(42),
    );
    canvas.drawRRect(headRect, headPaint);

    // White Cheeks
    final cheekPaint = Paint()..color = const Color(0xFFFFF8E1);
    final leftCheek = Path()
      ..moveTo(-55, -20)
      ..quadraticBezierTo(-30, 15, 0, 0)
      ..quadraticBezierTo(-20, -40, -55, -20);
    canvas.drawPath(leftCheek, cheekPaint);

    final rightCheek = Path()
      ..moveTo(55, -20)
      ..quadraticBezierTo(30, 15, 0, 0)
      ..quadraticBezierTo(20, -40, 55, -20);
    canvas.drawPath(rightCheek, cheekPaint);

    // 6. Nose
    final nosePaint = Paint()..color = const Color(0xFF212121);
    final nosePath = Path()
      ..moveTo(-7, -8)
      ..lineTo(7, -8)
      ..lineTo(0, -1)
      ..close();
    canvas.drawPath(nosePath, nosePaint);

    // Mouth
    final mouthPaint = Paint()
      ..color = const Color(0xFF212121)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final mouthPath = Path()
      ..moveTo(0, -1)
      ..lineTo(0, 5);

    if (mood == MascotMood.thriving) {
      // Joyful open mouth
      final openMouth = Path()
        ..moveTo(-8, 5)
        ..quadraticBezierTo(0, 18, 8, 5)
        ..close();
      final tonguePaint = Paint()..color = const Color(0xFFE57373);
      canvas
        ..drawPath(openMouth, tonguePaint)
        ..drawPath(openMouth, mouthPaint);
    } else if (mood == MascotMood.sleepy) {
      // Tiny relaxed line
      mouthPath
        ..moveTo(-4, 6)
        ..lineTo(4, 6);
      canvas.drawPath(mouthPath, mouthPaint);
    } else {
      // Happy / Squinting curved smile
      mouthPath
        ..moveTo(-8, 5)
        ..quadraticBezierTo(0, 12, 8, 5);
      canvas.drawPath(mouthPath, mouthPaint);
    }

    // 7. Eyes based on Mood
    _drawEyes(canvas);

    // 8. Sleepy Zzz indicator
    if (mood == MascotMood.sleepy) {
      _drawZzz(canvas);
    }

    canvas.restore();
  }

  void _drawEyes(Canvas canvas) {
    final eyePaint = Paint()..color = const Color(0xFF212121);
    final shinePaint = Paint()..color = Colors.white;

    switch (mood) {
      case MascotMood.sleepy:
        // Closed sleepy curved lines (^ ^ inverted)
        final strokePaint = Paint()
          ..color = const Color(0xFF212121)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        final leftEye = Path()
          ..moveTo(-28, -25)
          ..quadraticBezierTo(-20, -18, -12, -25);
        final rightEye = Path()
          ..moveTo(12, -25)
          ..quadraticBezierTo(20, -18, 28, -25);
        canvas
          ..drawPath(leftEye, strokePaint)
          ..drawPath(rightEye, strokePaint);

      case MascotMood.squinting:
        // One winking eye, one curved squint (> <)
        final strokePaint = Paint()
          ..color = const Color(0xFF212121)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        final leftEye = Path()
          ..moveTo(-28, -24)
          ..lineTo(-18, -20)
          ..lineTo(-28, -16);
        final rightEye = Path()
          ..moveTo(28, -24)
          ..lineTo(18, -20)
          ..lineTo(28, -16);
        canvas
          ..drawPath(leftEye, strokePaint)
          ..drawPath(rightEye, strokePaint);

      case MascotMood.thriving:
        // Sparkly joyful round eyes
        canvas
          ..drawCircle(const Offset(-20, -22), 8, eyePaint)
          ..drawCircle(const Offset(20, -22), 8, eyePaint)
          // Double highlights
          ..drawCircle(const Offset(-18, -25), 3, shinePaint)
          ..drawCircle(const Offset(-22, -20), 1.5, shinePaint)
          ..drawCircle(const Offset(22, -25), 3, shinePaint)
          ..drawCircle(const Offset(18, -20), 1.5, shinePaint);

      case MascotMood.happy:
        // Standard friendly alert eyes
        canvas
          ..drawOval(const Rect.fromLTWH(-25, -28, 10, 14), eyePaint)
          ..drawOval(const Rect.fromLTWH(15, -28, 10, 14), eyePaint)
          ..drawCircle(const Offset(-22, -24), 2.5, shinePaint)
          ..drawCircle(const Offset(18, -24), 2.5, shinePaint);
    }
  }

  void _drawZzz(Canvas canvas) {
    final zPaint = Paint()
      ..color = const Color(0xFF90CAF9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final z1 = Path()
      ..moveTo(40, -50)
      ..lineTo(52, -50)
      ..lineTo(40, -38)
      ..lineTo(52, -38);
    canvas.drawPath(z1, zPaint);

    final z2 = Path()
      ..moveTo(55, -70)
      ..lineTo(70, -70)
      ..lineTo(55, -55)
      ..lineTo(70, -55);
    canvas.drawPath(z2, zPaint);
  }

  @override
  bool shouldRepaint(covariant MascotVectorPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.breathProgress != breathProgress ||
      oldDelegate.tailProgress != tailProgress;
}

/// Interactive Mascot Widget supporting breathing, tail sway, and tap-squint.
class FoxMascotWidget extends StatefulWidget {
  const FoxMascotWidget({
    super.key,
    required this.mood,
    this.size = const Size(220, 220),
    this.onTap,
  });

  final MascotMood mood;
  final Size size;
  final VoidCallback? onTap;

  @override
  State<FoxMascotWidget> createState() => _FoxMascotWidgetState();
}

class _FoxMascotWidgetState extends State<FoxMascotWidget>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _tailController;
  bool _isSquintingTemporary = false;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _tailController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathController.dispose();
    _tailController.dispose();
    super.dispose();
  }

  void _handleTap() {
    setState(() => _isSquintingTemporary = true);
    widget.onTap?.call();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _isSquintingTemporary = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeMood = _isSquintingTemporary
        ? MascotMood.squinting
        : widget.mood;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_breathController, _tailController]),
        builder: (context, child) => RepaintBoundary(
          child: CustomPaint(
            size: widget.size,
            painter: MascotVectorPainter(
              mood: activeMood,
              breathProgress: _breathController.value,
              tailProgress: _tailController.value,
            ),
          ),
        ),
      ),
    );
  }
}
