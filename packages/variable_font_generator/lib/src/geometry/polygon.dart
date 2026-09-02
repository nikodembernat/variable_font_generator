import 'package:variable_font_generator/src/geometry/bezier.dart';
import 'package:variable_font_generator/src/geometry/path.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// Samples [subPath]'s centre line into a polygon.
///
/// Curves are flattened to within [tolerance] of the real curve. The result is
/// closed implicitly: the last point joins back to the first, whether or not
/// the sub path itself was closed, which is what makes it usable as a region to
/// test points against.
List<Vec2> flattenSubPath(SubPath subPath, {double tolerance = 0.1}) {
  final points = <Vec2>[subPath.start];
  var current = subPath.start;
  for (final segment in subPath.segments) {
    switch (segment) {
      case LineSegment():
        points.add(segment.end);
      case QuadraticSegment():
        points.addAll(
          flattenQuadratic((
            start: current,
            control: segment.control,
            end: segment.end,
          ), tolerance: tolerance),
        );
      case CubicSegment():
        for (final quadratic in cubicToQuadratics((
          start: current,
          control1: segment.control1,
          control2: segment.control2,
          end: segment.end,
        ), tolerance: tolerance)) {
          points.addAll(flattenQuadratic(quadratic, tolerance: tolerance));
        }
    }
    current = segment.end;
  }
  return points;
}

/// Whether [point] lies inside [polygon].
///
/// Uses the even-odd rule: a ray cast to the right crosses the boundary an odd
/// number of times exactly when the point is inside. A point on the boundary
/// may come out either way, which is fine for the only thing this is used
/// for — deciding whether one part of an icon sits inside another.
bool isPointInPolygon(Vec2 point, List<Vec2> polygon) {
  if (polygon.length < 3) {
    return false;
  }
  var inside = false;
  for (
    var current = 0, previous = polygon.length - 1;
    current < polygon.length;
    previous = current++
  ) {
    final a = polygon[current];
    final b = polygon[previous];
    if ((a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// The distance from [point] to the nearest edge of [polygon].
double distanceToPolygon(Vec2 point, List<Vec2> polygon) {
  var best = double.infinity;
  for (
    var current = 0, previous = polygon.length - 1;
    current < polygon.length;
    previous = current++
  ) {
    final distance = _distanceToSegment(
      point,
      polygon[previous],
      polygon[current],
    );
    if (distance < best) {
      best = distance;
    }
  }
  return best;
}

double _distanceToSegment(Vec2 point, Vec2 start, Vec2 end) {
  final along = end - start;
  final lengthSquared = along.lengthSquared;
  if (lengthSquared == 0) {
    return point.distanceTo(start);
  }
  final t = ((point - start).dot(along) / lengthSquared).clamp(0.0, 1.0);
  return point.distanceTo(start + along * t);
}

/// Whether [inner] lies inside [outer].
///
/// Every point of [inner] must be inside, or within [boundaryTolerance] of the
/// boundary, and at least one must be strictly inside. The tolerance matters
/// because a detail stroke very often starts or ends exactly on the outline it
/// sits within — the door of a house icon meets the wall it is drawn in — and a
/// test that took those end points for "outside" would decide the whole detail
/// was not contained.
///
/// Requiring the rest to be inside rather than taking a majority is deliberate:
/// a shape that genuinely straddles a boundary is not inside anything, and
/// treating it as if it were would change how it is drawn on a guess.
bool isPolygonInside(
  List<Vec2> inner,
  List<Vec2> outer, {
  double boundaryTolerance = 0,
}) {
  if (inner.isEmpty) {
    return false;
  }
  var anyStrictlyInside = false;
  for (final point in inner) {
    if (isPointInPolygon(point, outer)) {
      anyStrictlyInside = true;
      continue;
    }
    if (boundaryTolerance <= 0 ||
        distanceToPolygon(point, outer) > boundaryTolerance) {
      return false;
    }
  }
  return anyStrictlyInside;
}
