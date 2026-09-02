import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// How many points each curved segment contributes when a produced outline is
/// checked against the shape it is meant to approximate.
const _samplesPerSegment = 8;

void main() {
  group('parseSvgPath, moves and lines', () {
    test('returns an empty path for data that is empty or only whitespace', () {
      expect(parseSvgPath('').subPaths, isEmpty);
      expect(parseSvgPath(' \t\r\n\f , ').subPaths, isEmpty);
    });

    test('produces no sub path for a moveto that draws nothing', () {
      expect(parseSvgPath('M5 5').subPaths, isEmpty);
    });

    test('keeps a zero-length line so a round cap can draw it as a dot', () {
      final path = parseSvgPath('M5 5 L5 5');
      expect(path.subPaths, hasLength(1));
      final subPath = path.subPaths.single;
      expect(subPath.start, const Vec2(5, 5));
      expect(subPath.segments, [const LineSegment(Vec2(5, 5))]);
    });

    test('measures an initial relative moveto from the origin', () {
      final subPath = parseSvgPath('m5 5 l1 0').subPaths.single;
      expect(subPath.start, const Vec2(5, 5));
      expect(subPath.segments, [const LineSegment(Vec2(6, 5))]);
    });

    test(
      'continues the pairs after an absolute moveto as absolute linetos',
      () {
        final subPath = parseSvgPath('M0 0 10 0 10 10').subPaths.single;
        expect(subPath.start, Vec2.zero);
        expect(subPath.segments, [
          const LineSegment(Vec2(10, 0)),
          const LineSegment(Vec2(10, 10)),
        ]);
      },
    );

    test('continues the pairs after a relative moveto as relative linetos', () {
      final subPath = parseSvgPath('m1 1 2 0 2 0').subPaths.single;
      expect(subPath.start, const Vec2(1, 1));
      expect(subPath.segments, [
        const LineSegment(Vec2(3, 1)),
        const LineSegment(Vec2(5, 1)),
      ]);
    });

    test('repeats an explicit lineto for every extra coordinate pair', () {
      final subPath = parseSvgPath('M0 0 L1 0 2 0 l0 1 0 1').subPaths.single;
      expect(subPath.segments, [
        const LineSegment(Vec2(1, 0)),
        const LineSegment(Vec2(2, 0)),
        const LineSegment(Vec2(2, 1)),
        const LineSegment(Vec2(2, 2)),
      ]);
    });

    test('walks a rectangle with absolute and relative H and V linetos', () {
      final subPath = parseSvgPath('M0 0 H10 V10 h-5 v-5').subPaths.single;
      expect(subPath.segments, [
        const LineSegment(Vec2(10, 0)),
        const LineSegment(Vec2(10, 10)),
        const LineSegment(Vec2(5, 10)),
        const LineSegment(Vec2(5, 5)),
      ]);
    });
  });

  group('parseSvgPath, sub paths and closing', () {
    test('begins a new sub path at every moveto', () {
      final path = parseSvgPath('M0 0 L1 0 M5 5 L6 5 m0 0 l1 0');
      expect(path.subPaths, hasLength(3));
      expect(path.subPaths.map((subPath) => subPath.start), [
        Vec2.zero,
        const Vec2(5, 5),
        const Vec2(6, 5),
      ]);
      expect(
        path.subPaths.every((subPath) => !subPath.closed),
        isTrue,
        reason: 'no Z appears in the data',
      );
    });

    test('marks only the sub path that a Z ends as closed', () {
      final path = parseSvgPath('M0 0 L10 0 L10 10 Z M20 20 L30 20');
      expect(path.subPaths.map((subPath) => subPath.closed), [true, false]);
      expect(path.subPaths.first.segments, hasLength(2));
    });

    test('does not add a segment back to the start point for Z', () {
      // Closing is recorded as a flag; the loop is implied, not materialised.
      final subPath = parseSvgPath('M0 0 L10 0 L10 10 z').subPaths.single;
      expect(subPath.closed, isTrue);
      expect(subPath.segments.last.end, const Vec2(10, 10));
    });

    test('starts a sub path at the previous start when drawing after Z', () {
      final path = parseSvgPath('M1 1 L10 1 Z L20 20');
      expect(path.subPaths, hasLength(2));
      expect(path.subPaths[1].start, const Vec2(1, 1));
      expect(path.subPaths[1].segments, [const LineSegment(Vec2(20, 20))]);
      expect(path.subPaths[1].closed, isFalse);
    });

    test('moves the current point back to the sub path start on Z', () {
      // The relative lineto after `z` is measured from (10, 10), not (15, 10).
      final path = parseSvgPath('M10 10 l5 0 z l0 5');
      expect(path.subPaths[1].segments, [const LineSegment(Vec2(10, 15))]);
    });
  });

  group('parseSvgPath, curves', () {
    test('reads relative cubic control points against the current point', () {
      final subPath = parseSvgPath('M10 10 c1 1 2 2 3 3').subPaths.single;
      expect(subPath.segments, [
        const CubicSegment(Vec2(11, 11), Vec2(12, 12), Vec2(13, 13)),
      ]);
    });

    test('repeats a cubic command for every extra run of three points', () {
      final subPath = parseSvgPath('M0 0 C1 1 2 2 3 3 4 4 5 5 6 6')
          .subPaths
          .single;
      expect(subPath.segments, [
        const CubicSegment(Vec2(1, 1), Vec2(2, 2), Vec2(3, 3)),
        const CubicSegment(Vec2(4, 4), Vec2(5, 5), Vec2(6, 6)),
      ]);
    });

    test('reflects the previous cubic control point for S', () {
      final subPath = parseSvgPath('M0 0 C0 10 10 10 10 0 S20 -10 20 0')
          .subPaths
          .single;
      // The reflection of (10, 10) about the current point (10, 0).
      expect(
        (subPath.segments[1] as CubicSegment).control1,
        const Vec2(10, -10),
      );
    });

    test(
      'uses the current point for S when the previous segment is a line',
      () {
        final subPath = parseSvgPath('M0 0 L10 0 S20 10 30 0').subPaths.single;
        expect(
          (subPath.segments[1] as CubicSegment).control1,
          const Vec2(10, 0),
        );
      },
    );

    test(
      'uses the current point for S when the previous curve is quadratic',
      () {
        final subPath = parseSvgPath('M0 0 Q5 10 10 0 S20 10 30 0')
            .subPaths
            .single;
        expect(
          (subPath.segments[1] as CubicSegment).control1,
          const Vec2(10, 0),
        );
      },
    );

    test('reflects again for a second S, chaining the shorthand', () {
      final subPath = parseSvgPath('M0 0 C0 5 5 5 5 0 S10 -5 10 0 s5 5 5 0')
          .subPaths
          .single;
      // The second S reflected (5, 5) to (5, -5); the `s` reflects that again
      // about the current point (10, 0).
      expect((subPath.segments[2] as CubicSegment).control1, const Vec2(10, 5));
      // The relative `s` measures its own control and end from (10, 0).
      expect((subPath.segments[2] as CubicSegment).control2, const Vec2(15, 5));
      expect(subPath.segments[2].end, const Vec2(15, 0));
    });

    test('reads absolute and relative quadratic control points', () {
      final subPath = parseSvgPath('M0 0 Q1 2 2 0 q1 -2 2 0').subPaths.single;
      expect(subPath.segments, [
        const QuadraticSegment(Vec2(1, 2), Vec2(2, 0)),
        const QuadraticSegment(Vec2(3, -2), Vec2(4, 0)),
      ]);
    });

    test('reflects the previous quadratic control point for T', () {
      final subPath = parseSvgPath('M0 0 Q1 2 2 0 T4 0 t2 0').subPaths.single;
      // (1, 2) reflected about (2, 0), then (3, -2) reflected about (4, 0).
      expect(
        (subPath.segments[1] as QuadraticSegment).control,
        const Vec2(3, -2),
      );
      expect(
        (subPath.segments[2] as QuadraticSegment).control,
        const Vec2(5, 2),
      );
      expect(subPath.segments[2].end, const Vec2(6, 0));
    });

    test('uses the current point for T when the previous curve is cubic', () {
      final subPath = parseSvgPath('M0 0 C0 5 5 5 5 0 T10 0').subPaths.single;
      expect(
        (subPath.segments[1] as QuadraticSegment).control,
        const Vec2(5, 0),
      );
    });

    test('forgets the reflected control point across an arc', () {
      final subPath = parseSvgPath('M0 0 C0 5 5 5 5 0 A1 1 0 0 1 7 0 S9 5 9 0')
          .subPaths
          .single;
      final smooth = subPath.segments.last as CubicSegment;
      expect(smooth.control1, const Vec2(7, 0));
    });
  });

  group('parseSvgPath, number scanning', () {
    test('accepts explicit plus and minus signs', () {
      final subPath = parseSvgPath('M+1+2 L-3-4').subPaths.single;
      expect(subPath.start, const Vec2(1, 2));
      expect(subPath.segments, [const LineSegment(Vec2(-3, -4))]);
    });

    test('accepts numbers written with a bare leading dot', () {
      final subPath = parseSvgPath('M.5.5 L1.5.25').subPaths.single;
      expect(subPath.start, const Vec2(0.5, 0.5));
      expect(subPath.segments, [const LineSegment(Vec2(1.5, 0.25))]);
    });

    test('splits numbers that are run together by a sign', () {
      final subPath = parseSvgPath('M0 0 L1-2 3-4').subPaths.single;
      expect(subPath.segments, [
        const LineSegment(Vec2(1, -2)),
        const LineSegment(Vec2(3, -4)),
      ]);
    });

    test('reads exponents in either case and with a signed exponent', () {
      final subPath = parseSvgPath('M1e3 1.5E-2 L-2E+1 3e0').subPaths.single;
      expect(subPath.start, const Vec2(1000, 0.015));
      expect(subPath.segments, [const LineSegment(Vec2(-20, 3))]);
    });

    test('accepts commas and any whitespace run as separators', () {
      final subPath = parseSvgPath('M 0,0 , L\t1 ,\n2\r\n,3 ,, 4')
          .subPaths
          .single;
      expect(subPath.segments, [
        const LineSegment(Vec2(1, 2)),
        const LineSegment(Vec2(3, 4)),
      ]);
    });
  });

  group('parseSvgPath, arcs', () {
    test('reads arc flags that are jammed against the following number', () {
      // `0 011 1` is largeArc 0, sweep 1, then the pair (1, 1).
      final open = parseSvgPath('M0 0 a1 1 0 011 1').subPaths.single;
      expect(open.segments.last.end, const Vec2(1, 1));

      // The same data with a large-arc flag of 1 must take the long way round.
      final large = parseSvgPath('M0 0 a1 1 0 111 1').subPaths.single;
      expect(large.segments.last.end, const Vec2(1, 1));
      expect(
        large.segments.length,
        greaterThan(open.segments.length),
        reason: 'the large arc spans more than 90 degrees more',
      );
    });

    test('reads the jammed arc flags of the Lucide command icon', () {
      final source = File('$fixtureDirectory/command.svg').readAsStringSync();
      final data = _pathDataIn(source).single;
      expect(
        data,
        contains('0 1 0-3 3'),
        reason: 'this fixture is the one with a flag jammed to its number',
      );

      final subPath = parseSvgPath(data).subPaths.single;
      expect(subPath.start, const Vec2(15, 6));
      // Four linetos plus four 270 degree arcs of three cubics each.
      expect(subPath.segments, hasLength(16));
      expect(subPath.segments[0].end, const Vec2(15, 18));
      expect(subPath.segments[3].end, const Vec2(18, 15));
      expect(
        subPath.segments.last.end,
        subPath.start,
        reason: 'the command icon is a closed loop',
      );
      for (final point in subPath.onCurvePoints) {
        expect(point.x, inInclusiveRange(0, 24));
        expect(point.y, inInclusiveRange(0, 24));
      }
    });

    test('parses the path data of every fixture icon without complaint', () {
      final files = Directory(fixtureDirectory)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.svg'));
      var pathCount = 0;
      for (final file in files) {
        for (final data in _pathDataIn(file.readAsStringSync())) {
          pathCount++;
          final path = parseSvgPath(data);
          expect(path.isEmpty, isFalse, reason: '${file.path}: "$data"');
        }
      }
      expect(pathCount, greaterThan(10));
    });

    test('turns an arc command into cubics that land on the end point', () {
      final subPath = parseSvgPath('M0 0 A5 5 0 0 1 10 0').subPaths.single;
      expect(subPath.segments, hasLength(2));
      expect(subPath.segments.every((s) => s is CubicSegment), isTrue);
      expect(subPath.segments.last.end, const Vec2(10, 0));
      _expectOnEllipse(
        _samplePoints(subPath.start, subPath.segments),
        centre: const Vec2(5, 0),
        radiusX: 5,
        radiusY: 5,
        rotationDegrees: 0,
        what: 'the semicircle of A5 5 0 0 1 10 0',
      );
    });
  });

  group('parseSvgPath, malformed data', () {
    test('rejects path data that starts with a number', () {
      expect(
        () => parseSvgPath('10 10 L20 20'),
        throwsA(
          isA<PathParseException>()
              .having((e) => e.message, 'message', contains('must start'))
              .having((e) => e.offset, 'offset', 0)
              .having((e) => e.source, 'source', '10 10 L20 20'),
        ),
      );
    });

    test('rejects a lineto that runs out of numbers', () {
      expect(
        () => parseSvgPath('M10'),
        throwsA(
          isA<PathParseException>().having(
            (e) => e.message,
            'message',
            contains('Expected a number'),
          ),
        ),
      );
    });

    test('rejects a cubic with only two of its three points', () {
      expect(
        () => parseSvgPath('M0 0 C1 1 2 2'),
        throwsA(isA<PathParseException>()),
      );
    });

    test('rejects an arc flag that is neither 0 nor 1', () {
      expect(
        () => parseSvgPath('M0 0 A1 1 0 2 0 5 5'),
        throwsA(
          isA<PathParseException>().having(
            (e) => e.message,
            'message',
            contains('Expected "0" or "1"'),
          ),
        ),
      );
    });

    test('rejects an arc that ends before its flags', () {
      expect(
        () => parseSvgPath('M0 0 A1 1 0'),
        throwsA(
          isA<PathParseException>().having(
            (e) => e.message,
            'message',
            contains('Expected a flag'),
          ),
        ),
      );
    });
  });

  group('arcToCubics', () {
    test('produces a single cubic with exact ends for a quarter circle', () {
      final segments = arcToCubics(
        start: const Vec2(1, 0),
        end: const Vec2(0, 1),
        radiusX: 1,
        radiusY: 1,
        rotationDegrees: 0,
        largeArc: false,
        sweep: true,
      );
      expect(segments, hasLength(1));
      expect(segments.single.end, const Vec2(0, 1));
      _expectOnEllipse(
        _samplePoints(const Vec2(1, 0), segments),
        centre: Vec2.zero,
        radiusX: 1,
        radiusY: 1,
        rotationDegrees: 0,
        what: 'the quarter circle',
      );
    });

    test('splits a half circle into two cubics that stay on the circle', () {
      final segments = arcToCubics(
        start: const Vec2(1, 0),
        end: const Vec2(-1, 0),
        radiusX: 1,
        radiusY: 1,
        rotationDegrees: 0,
        largeArc: false,
        sweep: true,
      );
      expect(segments, hasLength(2));
      expect(segments.last.end, const Vec2(-1, 0));
      _expectOnEllipse(
        _samplePoints(const Vec2(1, 0), segments),
        centre: Vec2.zero,
        radiusX: 1,
        radiusY: 1,
        rotationDegrees: 0,
        what: 'the half circle',
      );
    });

    test('splits a 270 degree arc into three cubics', () {
      final segments = arcToCubics(
        start: const Vec2(1, 0),
        end: const Vec2(0, -1),
        radiusX: 1,
        radiusY: 1,
        rotationDegrees: 0,
        largeArc: true,
        sweep: true,
      );
      expect(segments, hasLength(3));
      expect(segments.last.end, const Vec2(0, -1));
      _expectOnEllipse(
        _samplePoints(const Vec2(1, 0), segments),
        centre: Vec2.zero,
        radiusX: 1,
        radiusY: 1,
        rotationDegrees: 0,
        what: 'the three quarter circle',
      );
    });

    test('scales radii up when they cannot span the chord', () {
      // F.6.6: rx = ry = 1 cannot reach from (0, 0) to (10, 0), so both are
      // multiplied until the arc is exactly a half circle of radius 5.
      const start = Vec2.zero;
      const end = Vec2(10, 0);
      final segments = arcToCubics(
        start: start,
        end: end,
        radiusX: 1,
        radiusY: 1,
        rotationDegrees: 0,
        largeArc: false,
        sweep: true,
      );
      expect(segments.last.end, end);
      _expectOnEllipse(
        _samplePoints(start, segments),
        centre: const Vec2(5, 0),
        radiusX: 5,
        radiusY: 5,
        rotationDegrees: 0,
        what: 'the corrected arc',
      );
    });

    test('degenerates to a straight line when a radius is zero', () {
      const end = Vec2(4, 7);
      expect(
        arcToCubics(
          start: Vec2.zero,
          end: end,
          radiusX: 0,
          radiusY: 3,
          rotationDegrees: 0,
          largeArc: true,
          sweep: true,
        ),
        [const LineSegment(end)],
      );
      expect(
        arcToCubics(
          start: Vec2.zero,
          end: end,
          radiusX: 3,
          radiusY: 0,
          rotationDegrees: 45,
          largeArc: false,
          sweep: false,
        ),
        [const LineSegment(end)],
      );
    });

    test('produces nothing when the end point coincides with the start', () {
      expect(
        arcToCubics(
          start: const Vec2(3, 4),
          end: const Vec2(3, 4),
          radiusX: 5,
          radiusY: 5,
          rotationDegrees: 0,
          largeArc: true,
          sweep: true,
        ),
        isEmpty,
      );
    });

    test('ignores the sign of the radii', () {
      List<PathSegment> arcWith(double radiusX, double radiusY) => arcToCubics(
        start: const Vec2(1, 0),
        end: const Vec2(0, 1),
        radiusX: radiusX,
        radiusY: radiusY,
        rotationDegrees: 0,
        largeArc: false,
        sweep: true,
      );
      expect(arcWith(-1, -1), arcWith(1, 1));
    });

    test('picks four different arcs from the largeArc and sweep flags', () {
      const start = Vec2.zero;
      const end = Vec2(10, 0);
      List<PathSegment> arcWith({
        required bool largeArc,
        required bool sweep,
      }) => arcToCubics(
        start: start,
        end: end,
        radiusX: 10,
        radiusY: 10,
        rotationDegrees: 0,
        largeArc: largeArc,
        sweep: sweep,
      );

      final smallLeft = arcWith(largeArc: false, sweep: false);
      final smallRight = arcWith(largeArc: false, sweep: true);
      final largeLeft = arcWith(largeArc: true, sweep: false);
      final largeRight = arcWith(largeArc: true, sweep: true);

      // A 60 degree arc fits in one cubic; the 300 degree one needs four.
      expect(smallLeft, hasLength(1));
      expect(smallRight, hasLength(1));
      expect(largeLeft, hasLength(4));
      expect(largeRight, hasLength(4));

      // The chord runs along y = 0, so the side each arc bulges towards is the
      // sign of its midpoint's y, and the small arcs stay nearer the chord.
      expect(_midpointOf(start, smallLeft).y, inExclusiveRange(0, 10));
      expect(_midpointOf(start, smallRight).y, inExclusiveRange(-10, 0));
      expect(_midpointOf(start, largeLeft).y, greaterThan(10));
      expect(_midpointOf(start, largeRight).y, lessThan(-10));

      for (final arc in [smallLeft, smallRight, largeLeft, largeRight]) {
        expect(arc.last.end, end);
      }
    });

    test(
      'follows an ellipse whose axes are rotated off the coordinate axes',
      () {
        // Rotating a 2 by 1 ellipse a quarter turn maps (rx, 0) to (0, rx).
        const start = Vec2(0, 2);
        const end = Vec2(-1, 0);
        final segments = arcToCubics(
          start: start,
          end: end,
          radiusX: 2,
          radiusY: 1,
          rotationDegrees: 90,
          largeArc: false,
          sweep: true,
        );
        expect(segments, hasLength(1));
        expect(segments.single.end, end);
        _expectOnEllipse(
          _samplePoints(start, segments),
          centre: Vec2.zero,
          radiusX: 2,
          radiusY: 1,
          rotationDegrees: 90,
          what: 'the rotated ellipse',
        );
      },
    );

    test('keeps a long thin elliptical arc on its ellipse', () {
      const start = Vec2(20, 5);
      const end = Vec2(4, 5);
      final segments = arcToCubics(
        start: start,
        end: end,
        radiusX: 8,
        radiusY: 2,
        rotationDegrees: 0,
        largeArc: true,
        sweep: false,
      );
      expect(segments.last.end, end);
      _expectOnEllipse(
        _samplePoints(start, segments),
        centre: const Vec2(12, 5),
        radiusX: 8,
        radiusY: 2,
        rotationDegrees: 0,
        what: 'the flattened ellipse',
      );
    });
  });
}

/// The `d` attribute of every `path` element in [svgSource].
List<String> _pathDataIn(String svgSource) => [
  for (final match in RegExp(r'\sd="([^"]*)"').allMatches(svgSource))
    match.group(1)!,
];

/// Walks [segments] from [start], sampling every curve so the result traces the
/// shape the segments draw.
List<Vec2> _samplePoints(Vec2 start, List<PathSegment> segments) {
  final points = <Vec2>[start];
  var current = start;
  for (final segment in segments) {
    switch (segment) {
      case LineSegment(:final end):
        points.add(end);
      case QuadraticSegment(:final control, :final end):
        for (var index = 1; index <= _samplesPerSegment; index++) {
          points.add(
            evaluateQuadratic((
              start: current,
              control: control,
              end: end,
            ), index / _samplesPerSegment),
          );
        }
      case CubicSegment(:final control1, :final control2, :final end):
        for (var index = 1; index <= _samplesPerSegment; index++) {
          points.add(
            evaluateCubic((
              start: current,
              control1: control1,
              control2: control2,
              end: end,
            ), index / _samplesPerSegment),
          );
        }
    }
    current = segment.end;
  }
  return points;
}

/// The point halfway along the sampled outline of [segments].
Vec2 _midpointOf(Vec2 start, List<PathSegment> segments) {
  final points = _samplePoints(start, segments);
  return points[points.length ~/ 2];
}

/// Fails unless every point of [points] lies on the given ellipse.
///
/// The tolerance is on the normalised radius, so it reads as a fraction of the
/// ellipse's own size rather than in absolute units.
void _expectOnEllipse(
  List<Vec2> points, {
  required Vec2 centre,
  required double radiusX,
  required double radiusY,
  required double rotationDegrees,
  required String what,
}) {
  final phi = rotationDegrees * math.pi / 180;
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);
  for (final point in points) {
    final offset = point - centre;
    final x = (cosPhi * offset.x + sinPhi * offset.y) / radiusX;
    final y = (-sinPhi * offset.x + cosPhi * offset.y) / radiusY;
    expect(
      math.sqrt(x * x + y * y),
      closeTo(1, 1e-3),
      reason: '$what: $point is off the ellipse',
    );
  }
}
