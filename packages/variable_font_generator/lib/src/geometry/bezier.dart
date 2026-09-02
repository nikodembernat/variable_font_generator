import 'dart:math' as math;

import 'package:variable_font_generator/src/geometry/vec2.dart';

/// A quadratic Bézier curve given by its three defining points.
typedef Quadratic = ({Vec2 start, Vec2 control, Vec2 end});

/// A cubic Bézier curve given by its four defining points.
typedef Cubic = ({Vec2 start, Vec2 control1, Vec2 control2, Vec2 end});

/// Evaluates the quadratic Bézier [curve] at [t].
Vec2 evaluateQuadratic(Quadratic curve, double t) {
  final inverse = 1 - t;
  return curve.start * (inverse * inverse) +
      curve.control * (2 * inverse * t) +
      curve.end * (t * t);
}

/// Evaluates the cubic Bézier [curve] at [t].
Vec2 evaluateCubic(Cubic curve, double t) {
  final inverse = 1 - t;
  return curve.start * (inverse * inverse * inverse) +
      curve.control1 * (3 * inverse * inverse * t) +
      curve.control2 * (3 * inverse * t * t) +
      curve.end * (t * t * t);
}

/// Splits [curve] at [t] into two quadratics that together trace the same path.
(Quadratic, Quadratic) splitQuadratic(Quadratic curve, double t) {
  final a = curve.start.lerp(curve.control, t);
  final b = curve.control.lerp(curve.end, t);
  final middle = a.lerp(b, t);
  return (
    (start: curve.start, control: a, end: middle),
    (start: middle, control: b, end: curve.end),
  );
}

/// Splits [curve] at [t] into two cubics that together trace the same path.
(Cubic, Cubic) splitCubic(Cubic curve, double t) {
  final a = curve.start.lerp(curve.control1, t);
  final b = curve.control1.lerp(curve.control2, t);
  final c = curve.control2.lerp(curve.end, t);
  final d = a.lerp(b, t);
  final e = b.lerp(c, t);
  final middle = d.lerp(e, t);
  return (
    (start: curve.start, control1: a, control2: d, end: middle),
    (start: middle, control1: e, control2: c, end: curve.end),
  );
}

/// The quadratic that shares both end points and both end tangents with the
/// cubic [curve], or `null` when no such quadratic exists.
///
/// Matching the tangents matters more here than minimising the deviation: the
/// stroker decides where to put a corner by comparing the tangents of adjacent
/// segments, so an approximation that bent the tangents would invent corners
/// that are not in the source artwork.
///
/// There is no answer when the two end tangents are parallel, or when they only
/// meet behind one of the end points, which is what happens around an
/// inflection. Both cases mean the curve has to be split before it can be
/// approximated at all, so they are reported as `null` rather than papered over
/// with a straight line.
Quadratic? tangentPreservingQuadratic(Cubic curve) {
  final startTangent = _startTangent(curve);
  final endTangent = _endTangent(curve);
  final denominator = startTangent.cross(endTangent);
  if (denominator.abs() < 1e-9) {
    return null;
  }
  final chord = curve.end - curve.start;
  final fromStart = chord.cross(endTangent) / denominator;
  final fromEnd = -chord.cross(startTangent) / denominator;
  if (fromStart <= 0 || fromEnd <= 0) {
    return null;
  }
  return (
    start: curve.start,
    control: curve.start + startTangent * fromStart,
    end: curve.end,
  );
}

Vec2 _startTangent(Cubic curve) {
  for (final candidate in [
    curve.control1 - curve.start,
    curve.control2 - curve.start,
    curve.end - curve.start,
  ]) {
    if (candidate.lengthSquared > 1e-24) {
      return candidate.normalized;
    }
  }
  return const Vec2(1, 0);
}

Vec2 _endTangent(Cubic curve) {
  for (final candidate in [
    curve.end - curve.control2,
    curve.end - curve.control1,
    curve.end - curve.start,
  ]) {
    if (candidate.lengthSquared > 1e-24) {
      return candidate.normalized;
    }
  }
  return const Vec2(1, 0);
}

/// The angle, in radians, by which the tangent of the cubic [curve] turns from
/// its start to its end.
double cubicTurnAngle(Cubic curve) {
  final cosine = _startTangent(curve).dot(_endTangent(curve)).clamp(-1.0, 1.0);
  return math.acos(cosine);
}

/// Whether every control point of [curve] lies within [tolerance] of its chord.
bool isCubicDegenerate(Cubic curve, double tolerance) {
  final chord = curve.end - curve.start;
  final chordLength = chord.length;
  if (chordLength < tolerance) {
    return (curve.control1 - curve.start).length <= tolerance &&
        (curve.control2 - curve.start).length <= tolerance;
  }
  return chord.cross(curve.control1 - curve.start).abs() / chordLength <=
          tolerance &&
      chord.cross(curve.control2 - curve.start).abs() / chordLength <=
          tolerance;
}

/// Approximates [curve] with quadratic Bézier segments no further than
/// [tolerance] from it.
///
/// TrueType outlines can only express quadratic curves, so every cubic coming
/// out of the SVG parser has to go through this conversion. The curve is halved
/// until each piece has a [tangentPreservingQuadratic] that stays within
/// [tolerance] of it and turns by no more than a quarter turn. Halving a cubic
/// leaves the tangent at the split point untouched, so the resulting chain of
/// quadratics is exactly as smooth as the cubic it replaces.
List<Quadratic> cubicToQuadratics(Cubic curve, {double tolerance = 0.01}) {
  final result = <Quadratic>[];
  _appendQuadratics(curve, tolerance, 0, result);
  return result;
}

void _appendQuadratics(
  Cubic curve,
  double tolerance,
  int depth,
  List<Quadratic> result,
) {
  const maxDepth = 14;
  final straight = (
    start: curve.start,
    control: curve.start.lerp(curve.end, 0.5),
    end: curve.end,
  );
  if (isCubicDegenerate(curve, tolerance)) {
    result.add(straight);
    return;
  }
  final approximation = tangentPreservingQuadratic(curve);
  if (approximation != null &&
      cubicTurnAngle(curve) <= math.pi / 2 &&
      evaluateCubic(
            curve,
            0.5,
          ).distanceTo(evaluateQuadratic(approximation, 0.5)) <=
          tolerance) {
    result.add(approximation);
    return;
  }
  if (depth >= maxDepth) {
    // Sixteen thousand times smaller than the original curve: whatever shape it
    // still has is far below the tolerance, so its chord will do.
    result.add(approximation ?? straight);
    return;
  }
  final (first, second) = splitCubic(curve, 0.5);
  _appendQuadratics(first, tolerance, depth + 1, result);
  _appendQuadratics(second, tolerance, depth + 1, result);
}

/// The angle, in radians, by which the tangent of [curve] turns from its start
/// to its end.
///
/// Returns zero for a degenerate curve whose control point coincides with an
/// end point.
double quadraticTurnAngle(Quadratic curve) {
  final incoming = curve.control - curve.start;
  final outgoing = curve.end - curve.control;
  if (incoming.lengthSquared == 0 || outgoing.lengthSquared == 0) {
    return 0;
  }
  final cosine = (incoming.dot(outgoing) / (incoming.length * outgoing.length))
      .clamp(-1.0, 1.0);
  return math.acos(cosine);
}

/// Whether [curve] is straight enough to be treated as a line segment.
///
/// A quadratic is a line when its control point lies on the segment joining its
/// end points; [tolerance] is the largest perpendicular distance still counted
/// as straight.
bool isQuadraticDegenerate(Quadratic curve, {double tolerance = 1e-9}) {
  final chord = curve.end - curve.start;
  final chordLength = chord.length;
  if (chordLength < tolerance) {
    // A curve whose ends coincide is only degenerate if the control point is
    // there too, otherwise it is a spike that still has direction.
    return (curve.control - curve.start).length < tolerance;
  }
  final area = chord.cross(curve.control - curve.start).abs();
  return area / chordLength <= tolerance;
}

/// Splits [curve] until every piece turns by at most [maxTurnAngle] radians.
///
/// The stroker relies on this: offsetting a quadratic by moving its control
/// point is only accurate while the curve stays gently bent, and the number of
/// pieces produced here depends solely on the centre line, never on the stroke
/// width, which is what keeps every master topologically identical.
List<Quadratic> limitQuadraticTurn(Quadratic curve, double maxTurnAngle) {
  final result = <Quadratic>[];
  _appendTurnLimited(curve, maxTurnAngle, 0, result);
  return result;
}

void _appendTurnLimited(
  Quadratic curve,
  double maxTurnAngle,
  int depth,
  List<Quadratic> result,
) {
  const maxDepth = 8;
  if (depth >= maxDepth || quadraticTurnAngle(curve) <= maxTurnAngle) {
    result.add(curve);
    return;
  }
  final (first, second) = splitQuadratic(curve, 0.5);
  _appendTurnLimited(first, maxTurnAngle, depth + 1, result);
  _appendTurnLimited(second, maxTurnAngle, depth + 1, result);
}

/// Samples [curve] into a polyline whose deviation stays under [tolerance].
///
/// The returned list excludes the start point and ends with the curve's end
/// point, which makes it convenient for appending to an existing polyline.
List<Vec2> flattenQuadratic(Quadratic curve, {double tolerance = 0.05}) {
  // The distance between a quadratic and its chord is at most a quarter of the
  // distance from the control point to the chord midpoint, and halving the
  // curve divides that error by four.
  final deviation = curve.control * 2 - curve.start - curve.end;
  final steps = math.max(
    1,
    math.sqrt(deviation.length / (4 * tolerance)).ceil(),
  );
  return [
    for (var step = 1; step <= steps; step++)
      evaluateQuadratic(curve, step / steps),
  ];
}
