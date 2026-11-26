import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MascotMood() {
  sleepy,
  neutral,
  happy,
  thriving,
  squinting,
}

/// Pure vector rendering. The parent owns the animation and pointer gestures.
final class MascotVectorPainter({
  required final MascotMood mood,
  required final double breathingPhase,
  final bool isPointerSquinting = false,
  Iterable<String> accessories = const [],
}) extends CustomPainter {
  final Set<String> accessories = Set.unmodifiable(accessories);

  static const _ink = Color(0xff1e1e1e);
  static const _outline = Color(0xff717171);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(size.width, size.height) / 240;
    final phase = breathingPhase.clamp(0.0, 1.0);
    final wave = math.sin(math.pi * phase);
    final squint = isPointerSquinting || mood == MascotMood.squinting;
    final sleepy = mood == MascotMood.sleepy;
    canvas
      ..save()
      ..translate(
        (size.width - 240 * scale) / 2,
        (size.height - 240 * scale) / 2,
      )
      ..scale(scale)
      ..translate(0, 196)
      ..scale(1, .985 + .025 * wave)
      ..translate(0, -196);
    if (sleepy) canvas.translate(0, 7);
    _tail(canvas, phase);
    final profile = Path()
      ..moveTo(99, 195)
      ..lineTo(68, 195)
      ..cubicTo(68, 145, 71, 107, 87, 78)
      ..quadraticBezierTo(104, 47, 145, 42)
      ..lineTo(151, 60)
      ..lineTo(194, 97)
      ..lineTo(169, 116)
      ..lineTo(168, 195);
    final legs = Path()
      ..moveTo(108, 166)
      ..lineTo(117, 195)
      ..lineTo(99, 195)
      ..moveTo(147, 156)
      ..lineTo(147, 195);
    final outline = _stroke(_outline, 1.8);
    canvas
      ..drawPath(profile, outline)
      ..drawPath(legs, outline);
    _eye(canvas, const Offset(123, 88), squint);
    _eye(canvas, const Offset(145, 88), squint);
    if (sleepy) {
      for (var i = 0; i < 3; i++) {
        final x = 175.0 + i * 10;
        final y = 57.0 - i * 9 - wave * 5;
        canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..relativeLineTo(8, 0)
            ..relativeLineTo(-8, 8)
            ..relativeLineTo(8, 0),
          _stroke(_ink, 1.5),
        );
      }
    } else if (mood == MascotMood.thriving) {
      for (var i = 0; i < 4; i++) {
        final angle = i * math.pi / 2 + phase * .3;
        _sparkle(
          canvas,
          Offset(120 + 96 * math.cos(angle), 108 + 64 * math.sin(angle)),
          7,
        );
      }
    }
    for (final accessory in accessories) {
      _accessory(canvas, accessory, phase);
    }
    canvas.restore();
  }

  static Paint _fill(Color color) => Paint()..color = color;

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  void _tail(Canvas canvas, double phase) {
    final wag = mood == MascotMood.happy || mood == MascotMood.thriving
        ? 4 * math.sin(phase * math.pi * 2)
        : 0.0;
    final tail = Path()
      ..moveTo(69, 142)
      ..lineTo(54, 142)
      ..cubicTo(12, 142 + wag, 12, 195, 54, 195)
      ..lineTo(68, 195)
      ..moveTo(54, 143)
      ..lineTo(54, 195);
    canvas.drawPath(tail, _stroke(_outline, 1.8));
  }

  void _eye(Canvas canvas, Offset center, bool squint) {
    final x = center.dx;
    final y = center.dy;
    final stroke = _stroke(_ink, 3);
    if (squint || mood == MascotMood.thriving) {
      canvas.drawPath(
        Path()
          ..moveTo(x - 7, y + 3)
          ..lineTo(x, y - 4)
          ..lineTo(x + 7, y + 3),
        stroke,
      );
    } else if (mood == MascotMood.happy) {
      canvas.drawArc(
        Rect.fromCenter(center: center, width: 14, height: 12),
        math.pi,
        math.pi,
        false,
        stroke,
      );
    } else if (mood == MascotMood.sleepy) {
      canvas.drawLine(center.translate(-6, 0), center.translate(6, 0), stroke);
    } else {
      canvas.drawCircle(center, 3.4, _fill(_ink));
    }
  }

  void _sparkle(Canvas canvas, Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final r = i.isEven ? radius : radius * .27;
      final point = center.translate(r * math.cos(angle), r * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path..close(), _fill(_ink));
  }

  void _accessory(Canvas canvas, String code, double phase) {
    switch (code) {
      case 'leaf_sprout_hat':
        final sway = math.sin(math.pi * phase) * 5;
        canvas
          ..drawPath(
            Path()
              ..moveTo(120, 49)
              ..quadraticBezierTo(117, 37, 120 + sway, 26),
            _stroke(_outline, 3),
          )
          ..drawOval(Rect.fromLTWH(104 + sway, 24, 17, 8), _fill(_outline))
          ..drawOval(Rect.fromLTWH(120 + sway, 19, 17, 8), _fill(_outline));
      case 'knit_green_scarf':
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(68, 120, 101, 13),
              const Radius.circular(6),
            ),
            _fill(_outline),
          )
          ..drawRect(const Rect.fromLTWH(150, 129, 13, 24), _fill(_outline));
        for (final x in [152.0, 156.0, 160.0]) {
          canvas.drawLine(Offset(x, 149), Offset(x, 158), _stroke(_outline, 2));
        }
      case 'solar_shades':
        for (final x in [123.0, 145.0]) {
          canvas
            ..drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x - 10, 80, 20, 17),
                const Radius.circular(5),
              ),
              _stroke(_ink, 3),
            )
            ..drawLine(
              Offset(x - 4, 93),
              Offset(x + 5, 84),
              _stroke(_outline, 2),
            );
        }
        canvas.drawLine(
          const Offset(133, 87),
          const Offset(135, 87),
          _stroke(_ink, 2),
        );
      case 'moss_crown':
        canvas.drawArc(
          const Rect.fromLTWH(89, 36, 62, 29),
          math.pi,
          math.pi,
          false,
          _stroke(_outline, 5),
        );
        for (var i = 0; i < 5; i++) {
          final angle = math.pi + i * math.pi / 4;
          canvas.drawCircle(
            Offset(120 + 31 * math.cos(angle), 50 + 14 * math.sin(angle)),
            4,
            _fill(_outline),
          );
        }
      case 'firefly_aura':
        for (var i = 0; i < 6; i++) {
          final angle = i * math.pi / 3 + 2 * math.pi * phase;
          canvas.drawCircle(
            Offset(120 + 104 * math.cos(angle), 120 + 80 * math.sin(angle)),
            3,
            _stroke(_outline, 1.7),
          );
        }
    }
  }

  @override
  bool shouldRepaint(covariant MascotVectorPainter oldDelegate) =>
      mood != oldDelegate.mood ||
      breathingPhase != oldDelegate.breathingPhase ||
      isPointerSquinting != oldDelegate.isPointerSquinting ||
      accessories.length != oldDelegate.accessories.length ||
      !accessories.containsAll(oldDelegate.accessories);
}
