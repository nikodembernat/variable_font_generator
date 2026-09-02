import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

/// The straight square used as the outer region in the polygon tests.
const _square = [Vec2.zero, Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)];

/// An L shape whose notch is the top right quadrant.
const _lShape = [
  Vec2.zero,
  Vec2(10, 0),
  Vec2(10, 4),
  Vec2(4, 4),
  Vec2(4, 10),
  Vec2(0, 10),
];

double _distanceToSegment(Vec2 point, Vec2 start, Vec2 end) {
  final along = end - start;
  final lengthSquared = along.lengthSquared;
  if (lengthSquared == 0) {
    return point.distanceTo(start);
  }
  final t = ((point - start).dot(along) / lengthSquared).clamp(0.0, 1.0);
  return point.distanceTo(start + along * t);
}

double _distanceToPolyline(Vec2 point, List<Vec2> polyline) {
  var best = double.infinity;
  for (var index = 1; index < polyline.length; index++) {
    final distance = _distanceToSegment(
      point,
      polyline[index - 1],
      polyline[index],
    );
    if (distance < best) {
      best = distance;
    }
  }
  return best;
}

List<Vec2> _sampleCubic(Cubic curve, int steps) => [
  for (var step = 0; step <= steps; step++) evaluateCubic(curve, step / steps),
];

List<Vec2> _sampleQuadratic(Quadratic curve, int steps) => [
  for (var step = 0; step <= steps; step++)
    evaluateQuadratic(curve, step / steps),
];

List<Vec2> _sampleChain(List<Quadratic> chain, int stepsPerPiece) => [
  for (final piece in chain) ..._sampleQuadratic(piece, stepsPerPiece),
];

/// The largest distance from any sample of [chain] to the polyline [reference].
double _maximumDeviation(List<Quadratic> chain, List<Vec2> reference) {
  var worst = 0.0;
  for (final sample in _sampleChain(chain, 8)) {
    final distance = _distanceToPolyline(sample, reference);
    if (distance > worst) {
      worst = distance;
    }
  }
  return worst;
}

void main() {
  group('Vec2', () {
    test('normalizes the zero vector to zero rather than to NaN', () {
      const degenerate = Vec2.zero;
      expect(degenerate.normalized, Vec2.zero);
      expect(degenerate.normalized.x.isNaN, isFalse);
      expect(degenerate.normalized.y.isNaN, isFalse);
    });

    test(
      'normalizes a vector to unit length without changing its direction',
      () {
        const vector = Vec2(3, 4);
        final unit = vector.normalized;
        expect(unit.length, closeTo(1, 1e-12));
        expect(unit.cross(vector).abs(), closeTo(0, 1e-12));
        expect(unit.dot(vector), greaterThan(0));
      },
    );

    test('rotates a quarter turn counter-clockwise for perpendicular', () {
      expect(const Vec2(1, 0).perpendicular, const Vec2(0, 1));
      expect(const Vec2(0, 1).perpendicular, const Vec2(-1, 0));
      expect(const Vec2(3, 4).perpendicular.dot(const Vec2(3, 4)), 0);
      // Four quarter turns are a full turn, back where it started.
      const vector = Vec2(2, -7);
      expect(
        vector.perpendicular.perpendicular.perpendicular.perpendicular,
        vector,
      );
    });

    test('reports which side of a vector another one lies on via cross', () {
      const base = Vec2(1, 0);
      expect(base.cross(const Vec2(1, 1)), greaterThan(0));
      expect(base.cross(const Vec2(1, -1)), lessThan(0));
    });

    test('gives a zero cross for parallel and antiparallel vectors', () {
      const base = Vec2(2, 3);
      expect(base.cross(base * 5), 0);
      expect(base.cross(-base), 0);
    });

    test('lerps exactly to each end point at t of zero and one', () {
      const from = Vec2(1, -2);
      const to = Vec2(9, 6);
      expect(from.lerp(to, 0), from);
      expect(from.lerp(to, 1), to);
      expect(from.lerp(to, 0.5), const Vec2(5, 2));
      // Nothing clamps t, so a value outside the unit range extrapolates.
      expect(Vec2.zero.lerp(const Vec2(4, 8), 2), const Vec2(8, 16));
    });
  });

  group('cubicToQuadratics', () {
    const arc = (
      start: Vec2.zero,
      control1: Vec2(0, 55),
      control2: Vec2(45, 100),
      end: Vec2(100, 100),
    );

    test('starts and ends exactly where the cubic does', () {
      final pieces = cubicToQuadratics(arc);
      expect(pieces, isNotEmpty);
      expect(pieces.first.start, arc.start);
      expect(pieces.last.end, arc.end);
    });

    test('produces pieces that join up exactly', () {
      final pieces = cubicToQuadratics(arc, tolerance: 0.001);
      expect(pieces.length, greaterThan(1));
      for (var index = 1; index < pieces.length; index++) {
        expect(pieces[index].start, pieces[index - 1].end);
      }
    });

    test('stays within the requested tolerance of the cubic', () {
      const tolerance = 0.05;
      final pieces = cubicToQuadratics(arc, tolerance: tolerance);
      expect(
        _maximumDeviation(pieces, _sampleCubic(arc, 2000)),
        lessThanOrEqualTo(tolerance),
      );
    });

    test('never produces fewer pieces as the tolerance tightens', () {
      const tolerances = [2.0, 0.5, 0.1, 0.02, 0.005, 0.001];
      var previous = 0;
      for (final tolerance in tolerances) {
        final count = cubicToQuadratics(arc, tolerance: tolerance).length;
        expect(
          count,
          greaterThanOrEqualTo(previous),
          reason: 'tolerance $tolerance produced $count pieces',
        );
        previous = count;
      }
    });

    test('returns a single piece for a cubic that is really a line', () {
      const line = (
        start: Vec2.zero,
        control1: Vec2(10, 0),
        control2: Vec2(20, 0),
        end: Vec2(30, 0),
      );
      final pieces = cubicToQuadratics(line, tolerance: 0.001);
      expect(pieces, hasLength(1));
      expect(pieces.single.start, line.start);
      expect(pieces.single.end, line.end);
      expect(isQuadraticDegenerate(pieces.single), isTrue);
    });

    test('splits a symmetric S rather than collapsing it onto its chord', () {
      // Both end tangents point along (2, -3), so no single quadratic can
      // preserve them and the curve has to be split.
      const symmetricS = (
        start: Vec2.zero,
        control1: Vec2(2, -3),
        control2: Vec2(-2, -3),
        end: Vec2(0, -6),
      );
      expect(tangentPreservingQuadratic(symmetricS), isNull);

      final pieces = cubicToQuadratics(symmetricS, tolerance: 0.001);
      expect(pieces.length, greaterThan(1));
      expect(pieces.first.start, symmetricS.start);
      expect(pieces.last.end, symmetricS.end);

      // The chord runs straight down the line x == 0. A result that had been
      // flattened onto it would have every sample there.
      final samples = _sampleChain(pieces, 8);
      final widest = samples.map((sample) => sample.x.abs()).reduce(math.max);
      expect(widest, greaterThan(0.4));

      expect(
        _maximumDeviation(pieces, _sampleCubic(symmetricS, 2000)),
        lessThanOrEqualTo(0.001),
      );
    });

    test(
      'uses one piece for a shallow cubic that is an elevated quadratic',
      () {
        // The quadratic through (0, 0), (10, 4), (20, 0), degree elevated. It
        // turns by well under a quarter turn, so it survives whole.
        const elevated = (
          start: Vec2.zero,
          control1: Vec2(20 / 3, 8 / 3),
          control2: Vec2(40 / 3, 8 / 3),
          end: Vec2(20, 0),
        );
        final pieces = cubicToQuadratics(elevated, tolerance: 0.001);
        expect(pieces, hasLength(1));
        expect(pieces.single.control.x, closeTo(10, 1e-9));
        expect(pieces.single.control.y, closeTo(4, 1e-9));
      },
    );

    test('splits a cubic that turns by more than a quarter turn anyway', () {
      // A single quadratic matches this cubic's tangents and passes exactly
      // through it, but a turn of about 2.21 radians is more than the
      // conversion is willing to put in one piece.
      const steep = (
        start: Vec2.zero,
        control1: Vec2(20 / 3, 40 / 3),
        control2: Vec2(40 / 3, 40 / 3),
        end: Vec2(20, 0),
      );
      expect(cubicTurnAngle(steep), greaterThan(math.pi / 2));
      expect(tangentPreservingQuadratic(steep), isNotNull);
      final pieces = cubicToQuadratics(steep, tolerance: 0.001);
      expect(pieces.length, greaterThan(1));
      expect(pieces.first.start, steep.start);
      expect(pieces.last.end, steep.end);
    });
  });

  group('tangentPreservingQuadratic', () {
    test('recovers the quadratic a cubic was elevated from', () {
      const elevated = (
        start: Vec2.zero,
        control1: Vec2(20 / 3, 40 / 3),
        control2: Vec2(40 / 3, 40 / 3),
        end: Vec2(20, 0),
      );
      final recovered = tangentPreservingQuadratic(elevated);
      expect(recovered, isNotNull);
      expect(recovered!.control.isCloseTo(const Vec2(10, 20)), isTrue);
    });

    test('returns null when the two end tangents are parallel', () {
      const symmetricS = (
        start: Vec2.zero,
        control1: Vec2(2, -3),
        control2: Vec2(-2, -3),
        end: Vec2(0, -6),
      );
      expect(tangentPreservingQuadratic(symmetricS), isNull);
    });

    test('returns null when the end tangents only meet behind the start', () {
      // The start tangent points along +X and the end tangent line crosses
      // y == 0 at x == -1, which is behind the start point.
      const inflected = (
        start: Vec2.zero,
        control1: Vec2(1, 0),
        control2: Vec2(-1, 0),
        end: Vec2(-1, 1),
      );
      expect(tangentPreservingQuadratic(inflected), isNull);
    });
  });

  group('splitCubic', () {
    const curve = (
      start: Vec2.zero,
      control1: Vec2(10, 40),
      control2: Vec2(70, 60),
      end: Vec2(100, 0),
    );

    test('produces halves that together trace the original curve', () {
      const t = 0.3;
      final (first, second) = splitCubic(curve, t);
      for (var step = 0; step <= 40; step++) {
        final u = step / 40;
        expect(
          evaluateCubic(first, u).isCloseTo(evaluateCubic(curve, u * t)),
          isTrue,
          reason: 'first half at $u',
        );
        expect(
          evaluateCubic(
            second,
            u,
          ).isCloseTo(evaluateCubic(curve, t + u * (1 - t))),
          isTrue,
          reason: 'second half at $u',
        );
      }
      expect(first.start, curve.start);
      expect(first.end, second.start);
      expect(second.end, curve.end);
      expect(first.end.isCloseTo(evaluateCubic(curve, t)), isTrue);
    });

    test('collapses the first half to a point when split at zero', () {
      final (first, second) = splitCubic(curve, 0);
      expect(first.start, curve.start);
      expect(first.end, curve.start);
      expect(first.control1, curve.start);
      expect(first.control2, curve.start);
      expect(second.start, curve.start);
      expect(second.end, curve.end);
    });
  });

  group('splitQuadratic', () {
    const curve = (start: Vec2.zero, control: Vec2(50, 90), end: Vec2(100, 0));

    test('produces halves that together trace the original curve', () {
      const t = 0.35;
      final (first, second) = splitQuadratic(curve, t);
      for (var step = 0; step <= 40; step++) {
        final u = step / 40;
        expect(
          evaluateQuadratic(
            first,
            u,
          ).isCloseTo(evaluateQuadratic(curve, u * t)),
          isTrue,
          reason: 'first half at $u',
        );
        expect(
          evaluateQuadratic(
            second,
            u,
          ).isCloseTo(evaluateQuadratic(curve, t + u * (1 - t))),
          isTrue,
          reason: 'second half at $u',
        );
      }
      expect(first.start, curve.start);
      expect(first.end, second.start);
      expect(second.end, curve.end);
      expect(first.end.isCloseTo(evaluateQuadratic(curve, t)), isTrue);
    });
  });

  group('limitQuadraticTurn', () {
    test('returns a straight quadratic unchanged as a single piece', () {
      const straight = (
        start: Vec2.zero,
        control: Vec2(5, 5),
        end: Vec2(10, 10),
      );
      final pieces = limitQuadraticTurn(straight, 0.1);
      expect(pieces, hasLength(1));
      expect(pieces.single, straight);
    });

    test('leaves every piece turning by at most the limit', () {
      const quarter = (
        start: Vec2.zero,
        control: Vec2(10, 0),
        end: Vec2(10, 10),
      );
      const limit = 0.2;
      final pieces = limitQuadraticTurn(quarter, limit);
      expect(pieces.length, greaterThan(1));
      for (final piece in pieces) {
        expect(quadraticTurnAngle(piece), lessThanOrEqualTo(limit + 1e-12));
      }
    });

    test('produces pieces that join up and span the original curve', () {
      const quarter = (
        start: Vec2.zero,
        control: Vec2(10, 0),
        end: Vec2(10, 10),
      );
      final pieces = limitQuadraticTurn(quarter, 0.15);
      expect(pieces.first.start, quarter.start);
      expect(pieces.last.end, quarter.end);
      for (var index = 1; index < pieces.length; index++) {
        expect(pieces[index].start, pieces[index - 1].end);
      }
      expect(
        _maximumDeviation(pieces, _sampleQuadratic(quarter, 40000)),
        lessThan(1e-8),
      );
      // Splitting redistributes the turn, it neither adds nor loses any.
      expect(
        pieces.map(quadraticTurnAngle).reduce((a, b) => a + b),
        closeTo(quadraticTurnAngle(quarter), 1e-9),
      );
    });
  });

  group('flattenQuadratic', () {
    const curve = (start: Vec2.zero, control: Vec2(50, 90), end: Vec2(100, 0));

    test('excludes the start point and ends exactly at the end point', () {
      final polyline = flattenQuadratic(curve, tolerance: 0.02);
      expect(polyline, isNotEmpty);
      expect(polyline.first, isNot(curve.start));
      expect(polyline.last, curve.end);
    });

    test('stays within the requested tolerance of the curve', () {
      const tolerance = 0.02;
      final polyline = [
        curve.start,
        ...flattenQuadratic(curve, tolerance: tolerance),
      ];
      var worst = 0.0;
      for (var step = 0; step <= 4000; step++) {
        final distance = _distanceToPolyline(
          evaluateQuadratic(curve, step / 4000),
          polyline,
        );
        if (distance > worst) {
          worst = distance;
        }
      }
      expect(worst, lessThanOrEqualTo(tolerance));
      expect(
        flattenQuadratic(curve, tolerance: 0.001).length,
        greaterThan(polyline.length),
      );
    });

    test('returns just the end point for a quadratic that is a line', () {
      const straight = (
        start: Vec2.zero,
        control: Vec2(5, 5),
        end: Vec2(10, 10),
      );
      expect(flattenQuadratic(straight, tolerance: 0.001), [straight.end]);
    });
  });

  group('Contour.segments', () {
    test(
      'implies an on-curve point between two consecutive control points',
      () {
        const contour = Contour([
          OutlinePoint(Vec2.zero, onCurve: true),
          OutlinePoint(Vec2(5, 10), onCurve: false),
          OutlinePoint(Vec2(15, 10), onCurve: false),
          OutlinePoint(Vec2(20, 0), onCurve: true),
        ]);
        final segments = contour.segments;
        expect(segments, hasLength(3));
        expect(segments[0].control, const Vec2(5, 10));
        expect(segments[0].end, const Vec2(10, 10));
        expect(segments[1].start, const Vec2(10, 10));
        expect(segments[1].control, const Vec2(15, 10));
        expect(segments[1].end, const Vec2(20, 0));
        expect(segments[2].control, isNull);
        expect(segments[2].end, Vec2.zero);
      },
    );

    test(
      'implies the start point of a contour made only of control points',
      () {
        const circle = Contour([
          OutlinePoint(Vec2(-10, -10), onCurve: false),
          OutlinePoint(Vec2(10, -10), onCurve: false),
          OutlinePoint(Vec2(10, 10), onCurve: false),
          OutlinePoint(Vec2(-10, 10), onCurve: false),
        ]);
        final segments = circle.segments;
        expect(segments, hasLength(4));
        expect(segments.first.start, const Vec2(-10, 0));
        expect(segments.last.end, const Vec2(-10, 0));
        for (final segment in segments) {
          expect(segment.control, isNotNull);
        }
      },
    );

    test('produces segments that join into a closed loop', () {
      const contours = [
        Contour([
          OutlinePoint(Vec2.zero, onCurve: true),
          OutlinePoint(Vec2(5, 10), onCurve: false),
          OutlinePoint(Vec2(15, 10), onCurve: false),
          OutlinePoint(Vec2(20, 0), onCurve: true),
        ]),
        Contour([
          OutlinePoint(Vec2(-10, -10), onCurve: false),
          OutlinePoint(Vec2(10, -10), onCurve: false),
          OutlinePoint(Vec2(10, 10), onCurve: false),
          OutlinePoint(Vec2(-10, 10), onCurve: false),
        ]),
        Contour([
          OutlinePoint(Vec2.zero, onCurve: true),
          OutlinePoint(Vec2(10, 0), onCurve: true),
          OutlinePoint(Vec2(10, 10), onCurve: true),
        ]),
      ];
      for (final contour in contours) {
        final segments = contour.segments;
        for (var index = 1; index < segments.length; index++) {
          expect(segments[index].start, segments[index - 1].end);
        }
        expect(segments.last.end, segments.first.start);
      }
    });

    test('closes a contour of straight on-curve points back to the start', () {
      const triangle = Contour([
        OutlinePoint(Vec2.zero, onCurve: true),
        OutlinePoint(Vec2(10, 0), onCurve: true),
        OutlinePoint(Vec2(10, 10), onCurve: true),
      ]);
      final segments = triangle.segments;
      expect(segments, hasLength(3));
      expect(segments.every((segment) => segment.control == null), isTrue);
    });

    test('produces nothing for a contour with fewer than two points', () {
      expect(const Contour([]).segments, isEmpty);
      expect(
        const Contour([OutlinePoint(Vec2(3, 4), onCurve: true)]).segments,
        isEmpty,
      );
    });
  });

  group('Contour.signedArea', () {
    test('flips sign but keeps magnitude when the contour is reversed', () {
      const square = Contour([
        OutlinePoint(Vec2.zero, onCurve: true),
        OutlinePoint(Vec2(10, 0), onCurve: true),
        OutlinePoint(Vec2(10, 10), onCurve: true),
        OutlinePoint(Vec2(0, 10), onCurve: true),
      ]);
      expect(square.signedArea, greaterThan(0));
      expect(square.reversed.signedArea, -square.signedArea);
      expect(square.signedArea.abs(), closeTo(100, 1e-9));
    });

    test('is zero for a contour whose points are collinear', () {
      const collinear = Contour([
        OutlinePoint(Vec2.zero, onCurve: true),
        OutlinePoint(Vec2(5, 5), onCurve: true),
        OutlinePoint(Vec2(10, 10), onCurve: true),
      ]);
      expect(collinear.signedArea, closeTo(0, 1e-9));
    });
  });

  group('Outline', () {
    test('bounds cover every point, control points included', () {
      const outline = Outline([
        Contour([
          OutlinePoint(Vec2.zero, onCurve: true),
          OutlinePoint(Vec2(50, -30), onCurve: false),
          OutlinePoint(Vec2(20, 40), onCurve: true),
        ]),
        Contour([
          OutlinePoint(Vec2(-15, 5), onCurve: true),
          OutlinePoint(Vec2(-5, 70), onCurve: true),
        ]),
      ]);
      final bounds = outline.bounds;
      expect(bounds, isNotNull);
      expect(bounds!.minX, -15);
      expect(bounds.minY, -30);
      expect(bounds.maxX, 50);
      expect(bounds.maxY, 70);
      for (final point in outline.allPoints) {
        expect(point.position.x, inInclusiveRange(bounds.minX, bounds.maxX));
        expect(point.position.y, inInclusiveRange(bounds.minY, bounds.maxY));
      }
    });

    test('has no bounds when it draws nothing', () {
      expect(Outline.empty.bounds, isNull);
      expect(Outline.empty.isEmpty, isTrue);
      expect(Outline.empty.pointCount, 0);
    });

    test('rounds every coordinate to a whole unit, halves away from zero', () {
      const outline = Outline([
        Contour([
          OutlinePoint(Vec2(1.4, -1.4), onCurve: true),
          OutlinePoint(Vec2(1.5, -1.5), onCurve: false),
          OutlinePoint(Vec2(-0.5, 2.5), onCurve: true),
        ]),
      ]);
      final positions = outline.rounded.allPoints
          .map((point) => point.position)
          .toList();
      expect(positions, [
        const Vec2(1, -1),
        const Vec2(2, -2),
        const Vec2(-1, 3),
      ]);
      for (final position in positions) {
        expect(position.x, position.x.roundToDouble());
        expect(position.y, position.y.roundToDouble());
      }
      // Rounding moves points, it does not reclassify them.
      expect(outline.rounded.allPoints.map((point) => point.onCurve), [
        true,
        false,
        true,
      ]);
    });
  });

  group('isPointInPolygon', () {
    test('accepts a point in the middle of a square', () {
      expect(isPointInPolygon(const Vec2(5, 5), _square), isTrue);
    });

    test('rejects points beyond every side of a square', () {
      expect(isPointInPolygon(const Vec2(15, 5), _square), isFalse);
      expect(isPointInPolygon(const Vec2(-1, 5), _square), isFalse);
      expect(isPointInPolygon(const Vec2(5, -1), _square), isFalse);
      expect(isPointInPolygon(const Vec2(5, 11), _square), isFalse);
    });

    test('accepts the arms of a concave L but rejects its notch', () {
      expect(isPointInPolygon(const Vec2(7, 2), _lShape), isTrue);
      expect(isPointInPolygon(const Vec2(2, 7), _lShape), isTrue);
      expect(isPointInPolygon(const Vec2(7, 7), _lShape), isFalse);
    });

    test('rejects every point for a polygon with fewer than three points', () {
      expect(isPointInPolygon(Vec2.zero, const []), isFalse);
      expect(
        isPointInPolygon(Vec2.zero, const [Vec2(-1, -1), Vec2(1, 1)]),
        isFalse,
      );
    });
  });

  group('isPolygonInside', () {
    test('accepts a polygon that lies wholly within another', () {
      const inner = [Vec2(2, 2), Vec2(3, 2), Vec2(3, 3), Vec2(2, 3)];
      expect(isPolygonInside(inner, _square), isTrue);
    });

    test('rejects a polygon that straddles the boundary or misses it', () {
      const straddling = [Vec2(8, 5), Vec2(12, 5), Vec2(12, 6), Vec2(8, 6)];
      const outside = [Vec2(20, 20), Vec2(22, 20), Vec2(22, 22)];
      expect(isPolygonInside(straddling, _square), isFalse);
      expect(isPolygonInside(outside, _square), isFalse);
    });

    test('rejects an empty inner polygon', () {
      expect(isPolygonInside(const [], _square), isFalse);
    });

    test(
      'rejects a detail touching the outline unless a tolerance allows it',
      () {
        // The first point sits exactly on the right hand edge of the square.
        const detail = [Vec2(10, 2), Vec2(9, 2), Vec2(9, 3)];
        expect(isPolygonInside(detail, _square), isFalse);
        expect(
          isPolygonInside(detail, _square, boundaryTolerance: 0.5),
          isTrue,
        );
      },
    );

    test('rejects a polygon that only grazes the boundary from outside', () {
      // Every point is within the tolerance of the outline but none is inside.
      const grazing = [Vec2(10.1, 2), Vec2(10.1, 3), Vec2(10.2, 3)];
      expect(
        isPolygonInside(grazing, _square, boundaryTolerance: 0.5),
        isFalse,
      );
    });

    test('rejects a polygon that sits inside the notch of an L shape', () {
      const inNotch = [Vec2(6, 6), Vec2(8, 6), Vec2(8, 8), Vec2(6, 8)];
      expect(isPolygonInside(inNotch, _lShape), isFalse);
      expect(isPolygonInside(inNotch, _square), isTrue);
    });
  });
}
