import 'dart:math' as math;

import 'package:variable_font_generator/src/geometry/path.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// Converts an SVG elliptical arc in endpoint parameterisation into a list of
/// cubic Bézier segments.
///
/// Implements the conversion from appendix F.6 of the SVG 1.1 specification,
/// including the out-of-range radii correction of F.6.6. The returned segments
/// start at [start] and the last one ends exactly at [end].
///
/// Degenerate arcs are handled the way the specification requires: an arc whose
/// end point equals its start point produces no segments at all, and an arc
/// with a zero radius degenerates into a straight line.
List<PathSegment> arcToCubics({
  required Vec2 start,
  required Vec2 end,
  required double radiusX,
  required double radiusY,
  required double rotationDegrees,
  required bool largeArc,
  required bool sweep,
}) {
  if (start.isCloseTo(end)) {
    return const [];
  }

  var rx = radiusX.abs();
  var ry = radiusY.abs();
  if (rx == 0 || ry == 0) {
    return [LineSegment(end)];
  }

  final phi = rotationDegrees * math.pi / 180;
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);

  // Step 1: compute (x1', y1'), the midpoint offset in the rotated frame.
  final dx = (start.x - end.x) / 2;
  final dy = (start.y - end.y) / 2;
  final x1p = cosPhi * dx + sinPhi * dy;
  final y1p = -sinPhi * dx + cosPhi * dy;

  // Step 1.5 (F.6.6): scale up the radii if they are too small to span the
  // chord.
  final lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lambda > 1) {
    final scale = math.sqrt(lambda);
    rx *= scale;
    ry *= scale;
  }

  // Step 2: compute (cx', cy'), the centre in the rotated frame.
  final rxSq = rx * rx;
  final rySq = ry * ry;
  final x1pSq = x1p * x1p;
  final y1pSq = y1p * y1p;
  final denominator = rxSq * y1pSq + rySq * x1pSq;
  final rawNumerator = rxSq * rySq - denominator;
  final numerator = rawNumerator < 0 ? 0 : rawNumerator;
  final coefficient =
      (largeArc == sweep ? -1.0 : 1.0) *
      (denominator == 0 ? 0.0 : math.sqrt(numerator / denominator));
  final cxp = coefficient * rx * y1p / ry;
  final cyp = -coefficient * ry * x1p / rx;

  // Step 3: rotate the centre back into user space.
  final centre = Vec2(
    cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2,
    sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2,
  );

  // Step 4: compute the start angle and the sweep angle.
  final startVector = Vec2((x1p - cxp) / rx, (y1p - cyp) / ry);
  final endVector = Vec2((-x1p - cxp) / rx, (-y1p - cyp) / ry);
  final theta1 = _angleBetween(const Vec2(1, 0), startVector);
  var deltaTheta = _angleBetween(startVector, endVector) % (2 * math.pi);
  if (!sweep && deltaTheta > 0) {
    deltaTheta -= 2 * math.pi;
  } else if (sweep && deltaTheta < 0) {
    deltaTheta += 2 * math.pi;
  }

  // Step 5: split into segments spanning at most 90 degrees each and turn every
  // one of them into a cubic.
  final segmentCount = math.max(1, (deltaTheta.abs() / (math.pi / 2)).ceil());
  final segmentAngle = deltaTheta / segmentCount;
  // The magic constant that makes a cubic match a circular arc at its ends and
  // at its midpoint.
  final controlScale = 4 / 3 * math.tan(segmentAngle / 4);

  Vec2 pointAt(double angle) {
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);
    return Vec2(
      centre.x + rx * cosAngle * cosPhi - ry * sinAngle * sinPhi,
      centre.y + rx * cosAngle * sinPhi + ry * sinAngle * cosPhi,
    );
  }

  Vec2 derivativeAt(double angle) {
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);
    return Vec2(
      -rx * sinAngle * cosPhi - ry * cosAngle * sinPhi,
      -rx * sinAngle * sinPhi + ry * cosAngle * cosPhi,
    );
  }

  final segments = <PathSegment>[];
  for (var index = 0; index < segmentCount; index++) {
    final angleStart = theta1 + index * segmentAngle;
    final angleEnd = angleStart + segmentAngle;
    final segmentStart = index == 0 ? start : pointAt(angleStart);
    final segmentEnd = index == segmentCount - 1 ? end : pointAt(angleEnd);
    segments.add(
      CubicSegment(
        segmentStart + derivativeAt(angleStart) * controlScale,
        segmentEnd - derivativeAt(angleEnd) * controlScale,
        segmentEnd,
      ),
    );
  }
  return segments;
}

/// The signed angle from [from] to [to], in radians, in the range `(-pi, pi]`.
double _angleBetween(Vec2 from, Vec2 to) {
  final dot = from.dot(to);
  final magnitude = from.length * to.length;
  if (magnitude == 0) {
    return 0;
  }
  final cosine = (dot / magnitude).clamp(-1.0, 1.0);
  final angle = math.acos(cosine);
  return from.cross(to) < 0 ? -angle : angle;
}
