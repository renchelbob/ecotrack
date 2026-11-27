import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

final class const PolylineSimplifier() {
  static const double _earthRadiusM = 6371000.0;
  static const double _degToRad = math.pi / 180.0;

  List<LatLng> call(List<LatLng> points, {double epsilonMeters = 1.5}) =>
      simplifyRdp(points, epsilonMeters: epsilonMeters);

  static List<LatLng> simplifyRdp(
    List<LatLng> points, {
    double epsilonMeters = 1.5,
  }) => simplifyIndexed<LatLng>(
    points,
    latOf: (p) => p.latitude,
    lonOf: (p) => p.longitude,
    epsilonMeters: epsilonMeters,
  );

  static List<T> simplifyIndexed<T>(
    List<T> points, {
    required double Function(T point) latOf,
    required double Function(T point) lonOf,
    double epsilonMeters = 1.5,
  }) {
    if (points.length <= 2 || epsilonMeters <= 0.0) {
      return List<T>.of(points);
    }

    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;

    final stack = <(int start, int end)>[(0, points.length - 1)];

    while (stack.isNotEmpty) {
      final (start, end) = stack.removeLast();
      if (end - start <= 1) {
        continue;
      }

      var maxDistance = 0.0;
      var maxIndex = -1;
      final startLat = latOf(points[start]);
      final startLon = lonOf(points[start]);
      final endLat = latOf(points[end]);
      final endLon = lonOf(points[end]);

      for (var i = start + 1; i < end; i++) {
        final d = _perpendicularDistanceMeters(
          pointLat: latOf(points[i]),
          pointLon: lonOf(points[i]),
          lineStartLat: startLat,
          lineStartLon: startLon,
          lineEndLat: endLat,
          lineEndLon: endLon,
        );
        if (d > maxDistance) {
          maxDistance = d;
          maxIndex = i;
        }
      }

      if (maxDistance > epsilonMeters && maxIndex != -1) {
        keep[maxIndex] = true;
        stack
          ..add((start, maxIndex))
          ..add((maxIndex, end));
      }
    }

    final result = <T>[];
    for (var i = 0; i < points.length; i++) {
      if (keep[i]) {
        result.add(points[i]);
      }
    }
    return result;
  }

  static double _perpendicularDistanceMeters({
    required double pointLat,
    required double pointLon,
    required double lineStartLat,
    required double lineStartLon,
    required double lineEndLat,
    required double lineEndLon,
  }) {
    final meanLatRad = ((lineStartLat + lineEndLat) * 0.5) * _degToRad;
    final cosLat = math.cos(meanLatRad);

    final px = (pointLon - lineStartLon) * _degToRad * _earthRadiusM * cosLat;
    final py = (pointLat - lineStartLat) * _degToRad * _earthRadiusM;
    final bx = (lineEndLon - lineStartLon) * _degToRad * _earthRadiusM * cosLat;
    final by = (lineEndLat - lineStartLat) * _degToRad * _earthRadiusM;

    final lenSq = bx * bx + by * by;
    if (lenSq == 0.0) {
      return math.sqrt(px * px + py * py);
    }

    final t = ((px * bx + py * by) / lenSq).clamp(0.0, 1.0);
    final projX = t * bx;
    final projY = t * by;
    final dx = px - projX;
    final dy = py - projY;
    return math.sqrt(dx * dx + dy * dy);
  }
}
