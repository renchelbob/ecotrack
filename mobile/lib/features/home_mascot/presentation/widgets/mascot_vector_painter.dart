import 'dart:math' as math;

import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:material_ui/material_ui.dart';

final class const MascotVectorPainter({
  required final MascotMoodState mood,
  required final double breathingPhase,
  final String? equippedAccessoryCode,
  final bool isPointerSquinting = false,
}) extends CustomPainter {
  static const Offset headAnchor = Offset(120, 42);
  static const Offset neckAnchor = Offset(120, 138);
  static const Offset eyesAnchor = Offset(120, 96);
  static const Offset auraCenter = Offset(120, 120);

  @override
  void paint(Canvas canvas, Size size) {
    final effectiveMood = isPointerSquinting ? MascotMoodState.squinting : mood;
    final sx = size.width / 240.0;
    final sy = size.height / 240.0;
    final breathScaleY =
        0.985 + (0.030 * math.sin(math.pi * breathingPhase.clamp(0.0, 1.0)));

    canvas
      ..save()
      ..scale(sx, sy);

    if (effectiveMood == .thriving || equippedAccessoryCode == 'firefly_aura') {
      _paintAura(
        canvas,
        breathingPhase: breathingPhase,
        isFireflyAccessory: equippedAccessoryCode == 'firefly_aura',
        isThriving: effectiveMood == .thriving,
      );
    }

    canvas
      ..save()
      ..translate(120, 206)
      ..scale(1.0, breathScaleY)
      ..translate(-120, -206);

    _paintTail(canvas, mood: effectiveMood, breathingPhase: breathingPhase);
    _paintBodyAndHead(
      canvas,
      mood: effectiveMood,
      isSquinting: effectiveMood == .squinting,
    );
    _paintFace(canvas, mood: effectiveMood);

    if (equippedAccessoryCode case final String code
        when code != 'firefly_aura') {
      _paintAccessory(canvas, code: code, breathingPhase: breathingPhase);
    }

    canvas.restore();

    if (effectiveMood == .sleepy) {
      _paintSleepyZzz(canvas, breathingPhase);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MascotVectorPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.breathingPhase != breathingPhase ||
      oldDelegate.equippedAccessoryCode != equippedAccessoryCode ||
      oldDelegate.isPointerSquinting != isPointerSquinting;
}

final Paint _fillLight = Paint()
  ..color = const Color(0xFFF6F6F6)
  ..style = .fill;

final Paint _fillWhite = Paint()
  ..color = EcoColors.surfacePrimary
  ..style = .fill;

final Paint _strokeInk = Paint()
  ..color = EcoColors.inkPrimary
  ..style = .stroke
  ..strokeWidth = 1.8
  ..strokeCap = .round
  ..strokeJoin = .round;

final Paint _strokeMuted = Paint()
  ..color = EcoColors.inkSecondary
  ..style = .stroke
  ..strokeWidth = 1.5
  ..strokeCap = .round;

void _paintTail(
  Canvas canvas, {
  required MascotMoodState mood,
  required double breathingPhase,
}) {
  final speed = mood == .happy || mood == .thriving ? 1.5 : 1.0;
  final angleDeg = mood == .sleepy
      ? -2.0
      : 4.5 * math.sin(breathingPhase * math.pi * 2 * speed);
  final angleRad = angleDeg * math.pi / 180.0;

  canvas
    ..save()
    ..translate(92, 198)
    ..rotate(angleRad)
    ..translate(-92, -198);

  final tailBody = Path()
    ..moveTo(92, 142)
    ..lineTo(68, 142)
    ..arcToPoint(
      const Offset(68, 206),
      radius: const Radius.circular(32),
      clockwise: false,
    )
    ..lineTo(92, 206)
    ..close();

  canvas
    ..drawPath(tailBody, _fillLight)
    ..drawPath(tailBody, _strokeInk)
    ..drawLine(const Offset(68, 142), const Offset(68, 206), _strokeInk)
    ..drawLine(const Offset(80, 142), const Offset(80, 206), _strokeInk)
    ..restore();
}

void _paintBodyAndHead(
  Canvas canvas, {
  required MascotMoodState mood,
  required bool isSquinting,
}) {
  final earFlatten = isSquinting ? 9.0 : 0.0;
  final earPeakY = (mood == .sleepy ? 44.0 : 34.0) + earFlatten;
  final silhouette = Path()
    ..moveTo(92, 206)
    ..cubicTo(92, 118, 108, 62, 146, 36)
    ..lineTo(148, earPeakY + 12)
    ..lineTo(192, 92)
    ..lineTo(164, 118)
    ..lineTo(164, 206);

  final filled = Path.from(silhouette)
    ..lineTo(92, 206)
    ..close();

  canvas
    ..drawPath(filled, _fillWhite)
    ..drawPath(silhouette, _strokeInk)
    ..drawLine(const Offset(92, 206), const Offset(132, 206), _strokeInk)
    ..drawLine(const Offset(122, 174), const Offset(132, 206), _strokeInk)
    ..drawLine(const Offset(146, 166), const Offset(146, 206), _strokeInk);
}

void _paintFace(Canvas canvas, {required MascotMoodState mood}) {
  const leftCenter = Offset(136, 86);
  const rightCenter = Offset(154, 86);
  final eyePaint = Paint()
    ..color = EcoColors.inkPrimary
    ..style = .fill;

  switch (mood) {
    case .sleepy:
      _drawLineEye(canvas, leftCenter);
      _drawLineEye(canvas, rightCenter);
    case .neutral:
      canvas
        ..drawCircle(leftCenter, 3.6, eyePaint)
        ..drawCircle(rightCenter, 3.6, eyePaint);
    case .happy:
      canvas
        ..drawCircle(leftCenter, 4.0, eyePaint)
        ..drawCircle(rightCenter, 4.0, eyePaint);
      _drawSmile(canvas);
    case .thriving:
      _drawChevronUp(canvas, leftCenter);
      _drawChevronUp(canvas, rightCenter);
      _drawSmile(canvas);
    case .squinting:
      _drawSquintChevronLeft(canvas, leftCenter);
      _drawSquintChevronRight(canvas, rightCenter);
  }
}

void _drawLineEye(Canvas canvas, Offset c) {
  canvas.drawLine(
    Offset(c.dx - 4.5, c.dy),
    Offset(c.dx + 4.5, c.dy),
    _strokeInk,
  );
}

void _drawChevronUp(Canvas canvas, Offset c) {
  final path = Path()
    ..moveTo(c.dx - 5, c.dy + 2)
    ..lineTo(c.dx, c.dy - 3)
    ..lineTo(c.dx + 5, c.dy + 2);
  canvas.drawPath(path, _strokeInk);
}

void _drawSquintChevronLeft(Canvas canvas, Offset c) {
  final path = Path()
    ..moveTo(c.dx - 4, c.dy - 3.5)
    ..lineTo(c.dx + 3, c.dy)
    ..lineTo(c.dx - 4, c.dy + 3.5);
  canvas.drawPath(path, _strokeInk);
}

void _drawSquintChevronRight(Canvas canvas, Offset c) {
  final path = Path()
    ..moveTo(c.dx + 4, c.dy - 3.5)
    ..lineTo(c.dx - 3, c.dy)
    ..lineTo(c.dx + 4, c.dy + 3.5);
  canvas.drawPath(path, _strokeInk);
}

void _drawSmile(Canvas canvas) {
  final smile = Path()
    ..moveTo(154, 102)
    ..quadraticBezierTo(160, 107, 166, 102);
  canvas.drawPath(smile, _strokeInk);
}

void _paintSleepyZzz(Canvas canvas, double phase) {
  final dy = -6.0 * math.sin(phase * math.pi);
  final z1 = Path()
    ..moveTo(176, 56 + dy)
    ..lineTo(186, 56 + dy)
    ..lineTo(176, 66 + dy)
    ..lineTo(186, 66 + dy);
  final z2 = Path()
    ..moveTo(190, 40 + dy)
    ..lineTo(202, 40 + dy)
    ..lineTo(190, 52 + dy)
    ..lineTo(202, 52 + dy);
  canvas
    ..drawPath(z1, _strokeMuted)
    ..drawPath(z2, _strokeMuted);
}

void _paintAura(
  Canvas canvas, {
  required double breathingPhase,
  required bool isFireflyAccessory,
  required bool isThriving,
}) {
  const center = MascotVectorPainter.auraCenter;
  if (isThriving) {
    final ring = Paint()
      ..color = EcoColors.borderMuted
      ..style = .stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, 88 + (breathingPhase * 4), ring);
  }
  final count = isFireflyAccessory ? 6 : 4;
  final radius = isFireflyAccessory ? 94.0 : 88.0;
  for (var i = 0; i < count; i++) {
    final angle = (i * 2 * math.pi / count) + (breathingPhase * math.pi * 0.5);
    final pos = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * (radius * 0.78),
    );
    _drawSparkle(canvas, pos, isFireflyAccessory ? 5.0 : 4.0);
  }
}

void _drawSparkle(Canvas canvas, Offset center, double r) {
  if (r >= 5.0) {
    canvas
      ..drawCircle(center, r, _fillLight)
      ..drawCircle(center, r, _strokeInk);
    return;
  }
  canvas
    ..drawLine(
      Offset(center.dx - r, center.dy),
      Offset(center.dx + r, center.dy),
      _strokeInk,
    )
    ..drawLine(
      Offset(center.dx, center.dy - r),
      Offset(center.dx, center.dy + r),
      _strokeInk,
    );
}

void _paintAccessory(
  Canvas canvas, {
  required String code,
  required double breathingPhase,
}) {
  switch (code) {
    case 'leaf_sprout_hat':
      _paintLeafSprout(canvas, breathingPhase);
    case 'knit_green_scarf':
      _paintKnitScarf(canvas);
    case 'solar_shades':
      _paintSolarShades(canvas);
    case 'moss_crown':
      _paintMossCrown(canvas);
  }
}

void _paintLeafSprout(Canvas canvas, double phase) {
  final sway = (phase - 0.5) * 4.0;
  const base = Offset(136, 42);
  final stem = Path()
    ..moveTo(base.dx, base.dy)
    ..quadraticBezierTo(
      base.dx + sway,
      base.dy - 12,
      base.dx + sway,
      base.dy - 18,
    );
  final leftLeaf = Path()
    ..moveTo(base.dx + sway, base.dy - 16)
    ..quadraticBezierTo(
      base.dx - 16 + sway,
      base.dy - 26,
      base.dx - 14 + sway,
      base.dy - 14,
    )
    ..close();
  final rightLeaf = Path()
    ..moveTo(base.dx + sway, base.dy - 16)
    ..quadraticBezierTo(
      base.dx + 16 + sway,
      base.dy - 26,
      base.dx + 14 + sway,
      base.dy - 14,
    )
    ..close();
  final leafFill = Paint()
    ..color = EcoColors.eqForestBg
    ..style = .fill;
  canvas
    ..drawPath(stem, _strokeInk)
    ..drawPath(leftLeaf, leafFill)
    ..drawPath(leftLeaf, _strokeInk)
    ..drawPath(rightLeaf, leafFill)
    ..drawPath(rightLeaf, _strokeInk);
}

void _paintKnitScarf(Canvas canvas) {
  final collar = RRect.fromRectAndRadius(
    const Rect.fromLTWH(112, 126, 54, 14),
    const Radius.circular(7),
  );
  final tail = Path()
    ..moveTo(118, 138)
    ..lineTo(106, 166)
    ..lineTo(120, 166)
    ..lineTo(128, 138)
    ..close();
  final scarfFill = Paint()
    ..color = EcoColors.surfaceCard
    ..style = .fill;
  canvas
    ..drawPath(tail, scarfFill)
    ..drawPath(tail, _strokeInk)
    ..drawRRect(collar, scarfFill)
    ..drawRRect(collar, _strokeInk)
    ..drawLine(const Offset(128, 127), const Offset(128, 139), _strokeInk)
    ..drawLine(const Offset(142, 127), const Offset(142, 139), _strokeInk);
}

void _paintSolarShades(Canvas canvas) {
  final lensFill = Paint()
    ..color = EcoColors.inkPrimary
    ..style = .fill;
  final reflection = Paint()
    ..color = EcoColors.surfacePrimary
    ..style = .stroke
    ..strokeWidth = 1.3;
  const leftLens = Rect.fromLTWH(126, 78, 18, 13);
  const rightLens = Rect.fromLTWH(148, 78, 18, 13);
  canvas
    ..drawRRect(RRect.fromRectAndRadius(leftLens, const .circular(4)), lensFill)
    ..drawRRect(
      RRect.fromRectAndRadius(rightLens, const .circular(4)),
      lensFill,
    )
    ..drawLine(const Offset(144, 83), const Offset(148, 83), _strokeInk)
    ..drawLine(const Offset(112, 84), const Offset(126, 83), _strokeInk)
    ..drawLine(const Offset(130, 88), const Offset(136, 81), reflection)
    ..drawLine(const Offset(152, 88), const Offset(158, 81), reflection);
}

void _paintMossCrown(Canvas canvas) {
  final crown = Path()
    ..moveTo(118, 52)
    ..lineTo(124, 34)
    ..lineTo(134, 44)
    ..lineTo(142, 30)
    ..lineTo(152, 46)
    ..lineTo(118, 52);
  final fill = Paint()
    ..color = EcoColors.eqForestBg
    ..style = .fill;
  canvas
    ..drawPath(crown, fill)
    ..drawPath(crown, _strokeInk)
    ..drawCircle(const Offset(124, 34), 2.5, _strokeInk)
    ..drawCircle(const Offset(142, 30), 2.5, _strokeInk);
}
