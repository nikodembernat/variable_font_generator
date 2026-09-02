import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// A sub path made of straight lines through [points].
SubPath _polyline(List<Vec2> points, {bool closed = false}) => SubPath(
  start: points.first,
  segments: [for (final point in points.skip(1)) LineSegment(point)],
  closed: closed,
);

/// A closed circular sub path of [radius] around [centre], drawn as the four
/// cubic quarter arcs an SVG `circle` element becomes.
SubPath _circle(Vec2 centre, double radius) {
  const kappa = 0.5522847498307936;
  final handle = radius * kappa;
  return SubPath(
    start: Vec2(centre.x + radius, centre.y),
    segments: [
      CubicSegment(
        Vec2(centre.x + radius, centre.y + handle),
        Vec2(centre.x + handle, centre.y + radius),
        Vec2(centre.x, centre.y + radius),
      ),
      CubicSegment(
        Vec2(centre.x - handle, centre.y + radius),
        Vec2(centre.x - radius, centre.y + handle),
        Vec2(centre.x - radius, centre.y),
      ),
      CubicSegment(
        Vec2(centre.x - radius, centre.y - handle),
        Vec2(centre.x - handle, centre.y - radius),
        Vec2(centre.x, centre.y - radius),
      ),
      CubicSegment(
        Vec2(centre.x + handle, centre.y - radius),
        Vec2(centre.x + radius, centre.y - handle),
        Vec2(centre.x + radius, centre.y),
      ),
    ],
    closed: true,
  );
}

/// Whether any point of [outline] sits within [tolerance] of [target].
bool _hasPointNear(Outline outline, Vec2 target, [double tolerance = 1e-9]) =>
    outline.contours.any(
      (contour) =>
          contour.points.any((p) => p.position.isCloseTo(target, tolerance)),
    );

/// How many points of [outline] are control points.
int _offCurveCount(Outline outline) =>
    outline.allPoints.where((point) => !point.onCurve).length;

/// Renders a glyph outline into a square bitmap covering the whole em box.
CoverageBitmap _render(Outline outline, int size) =>
    const Rasterizer().rasterize(
      outline,
      width: size,
      height: size,
      transform: Rasterizer.transformFor(
        minX: 0,
        minY: -200,
        maxX: 1000,
        maxY: 800,
        width: size,
        height: size,
      ),
    );

/// The fraction of the bitmap that is inked, from 0 to 1.
double _inkFraction(CoverageBitmap bitmap) =>
    bitmap.totalCoverage / (255 * bitmap.width * bitmap.height);

/// A stroked, unfilled SVG shape wrapping a single [subPath].
SvgShape _strokedShape(
  SubPath subPath, {
  double strokeWidth = 2,
  StrokeCap cap = StrokeCap.butt,
}) => SvgShape(
  path: Path([subPath]),
  filled: false,
  stroked: true,
  strokeWidth: strokeWidth,
  cap: cap,
  join: StrokeJoin.miter,
  miterLimit: 4,
);

/// An icon made of [shapes] in the given view box.
SvgIcon _icon(
  List<SvgShape> shapes, {
  double x = 0,
  double y = 0,
  double width = 24,
  double height = 24,
}) => SvgIcon(
  name: 'probe',
  viewBoxX: x,
  viewBoxY: y,
  viewBoxWidth: width,
  viewBoxHeight: height,
  shapes: shapes,
);

void main() {
  final line = _polyline(const [Vec2.zero, Vec2(10, 0)]);
  final rightAngle = _polyline(const [Vec2.zero, Vec2(10, 0), Vec2(10, 10)]);
  final sharpCorner = _polyline(const [Vec2.zero, Vec2(10, 0), Vec2(0.5, 1)]);
  final square = _polyline(const [
    Vec2.zero,
    Vec2(10, 0),
    Vec2(10, 10),
    Vec2(0, 10),
  ], closed: true);

  group('a straight line stroked with butt caps', () {
    final outline = const Stroker()
        .strokeSubPath(line)
        .evaluate(strokeScale: 1);

    test('gives a single rectangular contour of four on-curve points', () {
      expect(outline.contours, hasLength(1));
      expect(outline.contours.single.points, hasLength(4));
      expect(_offCurveCount(outline), 0);
      expect(outline.contours.single.signedArea.abs(), closeTo(20, 1e-9));
    });

    test('sits exactly half a stroke width either side of the centre line', () {
      final bounds = outline.bounds!;
      expect(bounds.minX, closeTo(0, 1e-9));
      expect(bounds.maxX, closeTo(10, 1e-9));
      expect(bounds.minY, closeTo(-1, 1e-9));
      expect(bounds.maxY, closeTo(1, 1e-9));
    });
  });

  group('the caps of an open sub path', () {
    test('square caps lengthen the rectangle by half a width at each end', () {
      final outline = const Stroker(cap: StrokeCap.square)
          .strokeSubPath(line)
          .evaluate(strokeScale: 1);
      final bounds = outline.bounds!;
      expect(bounds.minX, closeTo(-1, 1e-9));
      expect(bounds.maxX, closeTo(11, 1e-9));
      expect(bounds.minY, closeTo(-1, 1e-9));
      expect(bounds.maxY, closeTo(1, 1e-9));
      expect(_offCurveCount(outline), 0);
      // Two square caps of one by two units on top of the ten by two body.
      expect(outline.contours.single.signedArea.abs(), closeTo(24, 1e-9));
    });

    test('round caps replace each end with an arc of off-curve points', () {
      final butt = const Stroker().strokeSubPath(line).evaluate(strokeScale: 1);
      final round = const Stroker(cap: StrokeCap.round)
          .strokeSubPath(line)
          .evaluate(strokeScale: 1);
      expect(round.contours, hasLength(1));
      expect(round.pointCount, greaterThan(butt.pointCount));
      // A half turn at 45 degrees a piece is four control points per cap.
      expect(_offCurveCount(round), 8);
    });

    test('round caps reach exactly half a width beyond each end', () {
      final outline = const Stroker(cap: StrokeCap.round)
          .strokeSubPath(line)
          .evaluate(strokeScale: 1);
      final points = outline.contours.single.points;
      // The tip of the arc is the on-curve point TrueType implies between the
      // two control points that straddle it.
      final tips = [
        for (var index = 0; index < points.length; index++)
          if (!points[index].onCurve &&
              !points[(index + 1) % points.length].onCurve)
            points[index].position.lerp(
              points[(index + 1) % points.length].position,
              0.5,
            ),
      ];
      expect(tips.any((tip) => tip.isCloseTo(const Vec2(11, 0))), isTrue);
      expect(tips.any((tip) => tip.isCloseTo(const Vec2(-1, 0))), isTrue);
    });
  });

  group('a zero-length sub path', () {
    final dot = _polyline(const [Vec2(3, 4), Vec2(3, 4)]);

    test('draws nothing when the cap is butt', () {
      expect(const Stroker().strokeSubPath(dot).isEmpty, isTrue);
    });

    test('draws a square of the full stroke width when the cap is square', () {
      final outline = const Stroker(cap: StrokeCap.square)
          .strokeSubPath(dot)
          .evaluate(strokeScale: 1);
      expect(outline.contours, hasLength(1));
      expect(outline.contours.single.points, hasLength(4));
      expect(_offCurveCount(outline), 0);
      for (final corner in const [
        Vec2(2, 3),
        Vec2(4, 3),
        Vec2(4, 5),
        Vec2(2, 5),
      ]) {
        expect(_hasPointNear(outline, corner), isTrue, reason: '$corner');
      }
    });

    test('draws a dot of the half width radius when the cap is round', () {
      final outline = const Stroker(cap: StrokeCap.round)
          .strokeSubPath(dot)
          .evaluate(strokeScale: 1);
      expect(outline.contours, hasLength(1));
      final points = outline.contours.single.points;
      // A full turn made only of control points, so every on-curve point of
      // the circle is the implied midpoint of a neighbouring pair.
      expect(points.every((point) => !point.onCurve), isTrue);
      for (var index = 0; index < points.length; index++) {
        final implied = points[index].position.lerp(
          points[(index + 1) % points.length].position,
          0.5,
        );
        expect(
          implied.distanceTo(const Vec2(3, 4)),
          closeTo(1, 1e-9),
          reason: 'point $index',
        );
      }
    });

    test('draws nothing when the sub path has no segments at all', () {
      const bare = SubPath(start: Vec2(1, 2), segments: [], closed: false);
      expect(
        const Stroker(cap: StrokeCap.round).strokeSubPath(bare).isEmpty,
        isTrue,
      );
    });
  });

  group('joins', () {
    test('a miter join puts a point at the miter distance on the outside', () {
      final outline = const Stroker()
          .strokeSubPath(rightAngle)
          .evaluate(strokeScale: 1);
      // A right angle miters to half a width times the square root of two.
      expect(_hasPointNear(outline, const Vec2(11, -1)), isTrue);
      const vertex = Vec2(10, 0);
      // Nothing sticks out further from the corner than the miter tip does.
      final aroundCorner = outline.allPoints
          .map((point) => point.position.distanceTo(vertex))
          .where((distance) => distance < 2);
      expect(aroundCorner.reduce(math.max), closeTo(math.sqrt2, 1e-9));
    });

    test('a bevel join leaves the outer corner point out', () {
      final miter = const Stroker()
          .strokeSubPath(rightAngle)
          .evaluate(strokeScale: 1);
      final bevel = const Stroker(join: StrokeJoin.bevel)
          .strokeSubPath(rightAngle)
          .evaluate(strokeScale: 1);
      expect(bevel.pointCount, miter.pointCount - 1);
      expect(_hasPointNear(bevel, const Vec2(11, -1), 1e-6), isFalse);
    });

    test('a corner sharper than the miter limit falls back to bevel', () {
      final miter = const Stroker().strokeSubPath(sharpCorner);
      final bevel = const Stroker(join: StrokeJoin.bevel)
          .strokeSubPath(sharpCorner);
      expect(miter.pointCount, bevel.pointCount);
    });

    test('raising the miter limit keeps the miter on that same corner', () {
      final generous = const Stroker(miterLimit: 20).strokeSubPath(sharpCorner);
      final bevel = const Stroker(join: StrokeJoin.bevel)
          .strokeSubPath(sharpCorner);
      expect(generous.pointCount, bevel.pointCount + 1);
    });

    test('a round join fills the corner with off-curve arc points', () {
      final round = const Stroker(join: StrokeJoin.round)
          .strokeSubPath(rightAngle)
          .evaluate(strokeScale: 1);
      final bevel = const Stroker(join: StrokeJoin.bevel)
          .strokeSubPath(rightAngle)
          .evaluate(strokeScale: 1);
      // A quarter turn at 45 degrees a piece is two control points.
      expect(round.pointCount, bevel.pointCount + 2);
      expect(_offCurveCount(round), 2);
      expect(_offCurveCount(bevel), 0);
    });

    test('a smooth continuation adds no corner point and repeats none', () {
      final split = _polyline(const [Vec2.zero, Vec2(5, 0), Vec2(10, 0)]);
      final outline = const Stroker()
          .strokeSubPath(split)
          .evaluate(strokeScale: 1);
      // One extra on-curve point per side, and no repeat of it: a corner would
      // have emitted two points per side instead.
      expect(outline.contours.single.points, hasLength(6));
      expect(outline.contours.single.signedArea.abs(), closeTo(20, 1e-9));
    });

    test('the inside of a turn is closed at the crossing of the offsets', () {
      final outline = const Stroker()
          .strokeSubPath(rightAngle)
          .evaluate(strokeScale: 1);
      // The two inner offset lines, one unit inside each leg, cross at (9, 1).
      expect(_hasPointNear(outline, const Vec2(9, 1)), isTrue);
    });
  });

  group('a closed sub path', () {
    test('produces an outer boundary and a hole of opposite winding', () {
      final outline = const Stroker()
          .strokeSubPath(square)
          .evaluate(strokeScale: 1);
      expect(outline.contours, hasLength(2));
      final outer = outline.contours.first.signedArea;
      final hole = outline.contours.last.signedArea;
      expect(outer.abs(), closeTo(144, 1e-9));
      expect(hole.abs(), closeTo(64, 1e-9));
      expect(hole.sign, -outer.sign);
    });

    test('produces a single solid contour when the shape is filled', () {
      final outline = const Stroker()
          .strokeSubPath(square, filled: true)
          .evaluate(strokeScale: 1);
      expect(outline.contours, hasLength(1));
      expect(outline.contours.single.signedArea.abs(), closeTo(144, 1e-9));
    });

    test('is closed implicitly when its last point returns to its first', () {
      final implicit = _polyline(const [
        Vec2.zero,
        Vec2(10, 0),
        Vec2(10, 10),
        Vec2(0, 10),
        Vec2.zero,
      ]);
      expectSameOutline(
        const Stroker().strokeSubPath(implicit).evaluate(strokeScale: 1),
        const Stroker().strokeSubPath(square).evaluate(strokeScale: 1),
        'an implicitly closed square',
      );
    });

    test('collapses its hole onto the centroid of the centre line', () {
      final template = const Stroker().strokeSubPath(square);
      expect(
        template.contours.first.behaviour,
        ContourFillBehaviour.unaffected,
      );
      expect(template.contours.last.behaviour, ContourFillBehaviour.collapse);
      expect(template.contours.last.collapseTarget, const Vec2(5, 5));
    });
  });

  group('the fill axis', () {
    final template = const Stroker().strokeSubPath(square);

    test('brings every point of the hole together at fill one', () {
      final closed = template.evaluate(strokeScale: 1, fill: 1);
      final hole = closed.contours.last;
      expect(hole.points, hasLength(template.contours.last.points.length));
      expect(hole.points.map((point) => point.position).toSet(), {
        const Vec2(5, 5),
      });
      expect(hole.signedArea, 0);
    });

    test('leaves the outer boundary untouched at every fill', () {
      final open = template.evaluate(strokeScale: 1);
      for (final fill in const [0.25, 0.5, 1.0]) {
        final closed = template.evaluate(strokeScale: 1, fill: fill);
        expect(
          closed.contours.first.points,
          open.contours.first.points,
          reason: 'fill $fill',
        );
      }
    });

    test('narrows a knocked-out open detail away and widens a reversed copy', () {
      final detail = const Stroker().strokeSubPath(
        line,
        knockedOutWhenFilled: true,
      );
      expect(detail.contours.map((contour) => contour.behaviour), const [
        ContourFillBehaviour.fadeOut,
        ContourFillBehaviour.knockOut,
      ]);
      expect(
        detail.contours[1].points.map((point) => point.base),
        detail.contours[0].points.reversed.map((point) => point.base),
      );

      final open = detail.evaluate(strokeScale: 1);
      final closed = detail.evaluate(strokeScale: 1, fill: 1);
      // The drawn stroke has narrowed onto its own centre line, which encloses
      // nothing, and the copy that took its place winds the other way.
      expect(closed.contours[0].signedArea, closeTo(0, 1e-9));
      expect(
        closed.contours[1].signedArea.abs(),
        closeTo(open.contours[0].signedArea.abs(), 1e-9),
      );
      expect(
        closed.contours[1].signedArea.sign,
        -open.contours[0].signedArea.sign,
      );
    });

    test('shrinks a knocked-out closed detail away and grows a filled copy', () {
      // A closed shape still encloses area once its stroke has no width left,
      // so narrowing it is not enough to make it disappear; it is pulled onto a
      // point instead, and what replaces it is the shape filled rather than
      // merely outlined.
      final detail = const Stroker().strokeSubPath(
        square,
        knockedOutWhenFilled: true,
      );
      expect(detail.contours.map((contour) => contour.behaviour), const [
        ContourFillBehaviour.collapse,
        ContourFillBehaviour.collapse,
        ContourFillBehaviour.grow,
      ]);

      final open = detail.evaluate(strokeScale: 1);
      final closed = detail.evaluate(strokeScale: 1, fill: 1);
      // At no fill the detail is drawn and its replacement is a point.
      expect(open.contours[2].signedArea, closeTo(0, 1e-9));
      expect(open.contours[0].signedArea.abs(), greaterThan(100));
      // At full fill the detail has gone and its replacement is the whole
      // shape, winding against what it cuts into.
      expect(closed.contours[0].signedArea, closeTo(0, 1e-9));
      expect(closed.contours[1].signedArea, closeTo(0, 1e-9));
      expect(
        closed.contours[2].signedArea.abs(),
        closeTo(open.contours[0].signedArea.abs(), 1e-9),
      );
      expect(
        closed.contours[2].signedArea.sign,
        -open.contours[0].signedArea.sign,
      );
    });
  });

  group('a stroke wider than the shape it outlines', () {
    // Half the stroke width is one unit, so this circle is narrower than the
    // stroke drawn around it and its inner boundary turns itself inside out.
    final tiny = _circle(Vec2.zero, 0.5);

    test('still covers the whole disc the stroke sweeps out', () {
      final outline = const Stroker()
          .strokeSubPath(tiny)
          .evaluate(strokeScale: 1);
      expect(
        outline.contours.first.signedArea.abs(),
        closeTo(math.pi * 1.5 * 1.5, 0.2),
      );
    });

    test('leaves a single solid contour with no inverted hole', () {
      final outline = const Stroker()
          .strokeSubPath(tiny)
          .evaluate(strokeScale: 1);
      expect(outline.contours, hasLength(1));
    });

    test('keeps the hole of a shape with room to spare', () {
      // Four times the half width across, so there is plenty of room inside for
      // a hole and the shape must keep it.
      final outline = const Stroker()
          .strokeSubPath(_circle(Vec2.zero, 4))
          .evaluate(strokeScale: 1);
      expect(outline.contours, hasLength(2));
      // `signedArea` measures the control polygon, which sits slightly outside
      // a circle, so the hole comes out a fraction larger than pi times three
      // squared.
      expect(
        outline.contours.last.signedArea.abs(),
        closeTo(math.pi * 3 * 3, 0.5),
      );
    });
  });

  group('centre lines that cross themselves', () {
    const crossing = ['infinity', 'command', 'ampersands'];

    test('are cut into several contours instead of one', () {
      for (final name in crossing) {
        expect(
          fixtureTemplates[name]!.contours.length,
          greaterThan(1),
          reason: name,
        );
      }
    });

    test('give every piece the same winding', () {
      for (final name in crossing) {
        final outline = fixtureTemplates[name]!.evaluate(strokeScale: 1);
        final signs = outline.contours
            .map((contour) => contour.signedArea.sign)
            .toSet();
        expect(signs, hasLength(1), reason: name);
        expect(signs.single, isNot(0), reason: name);
      }
    });

    test('leave the lobes of infinity hollow while the band is inked', () {
      final bitmap = _render(
        fixtureTemplates['infinity']!.evaluate(strokeScale: 1),
        64,
      );
      // The two lobes of the eight are circles of radius four about (6, 12)
      // and (18, 12) in the icon's own 24 unit view box.
      expect(bitmap[(16, 32)], 0, reason: 'left lobe interior');
      expect(bitmap[(48, 32)], 0, reason: 'right lobe interior');
      // The stroke band around them, and the crossing in the middle, are solid.
      expect(bitmap[(16, 21)], 255, reason: 'left lobe stroke');
      expect(bitmap[(48, 21)], 255, reason: 'right lobe stroke');
      expect(bitmap[(48, 43)], 255, reason: 'right lobe stroke below');
      expect(bitmap[(32, 32)], 255, reason: 'the crossing itself');
      expect(bitmap[(2, 2)], 0, reason: 'outside the artwork');
    });

    test('ink roughly the area their stroke should cover', () {
      const expected = {
        'infinity': (0.14, 0.23),
        'command': (0.27, 0.4),
        'ampersands': (0.19, 0.31),
      };
      for (final entry in expected.entries) {
        final ink = _inkFraction(
          _render(fixtureTemplates[entry.key]!.evaluate(strokeScale: 1), 64),
        );
        expect(
          ink,
          inInclusiveRange(entry.value.$1, entry.value.$2),
          reason: entry.key,
        );
      }
    });
  });

  group('an outline template', () {
    const scales = [0.1, 0.5, 1.0, 1.5, 2.0, 3.0];
    const fills = [0.0, 0.25, 0.5, 1.0];

    test('keeps its contours, points and flags at every scale and fill', () {
      for (final entry in fixtureTemplates.entries) {
        final reference = entry.value.evaluate(strokeScale: 1);
        for (final scale in scales) {
          for (final fill in fills) {
            final outline = entry.value.evaluate(
              strokeScale: scale,
              fill: fill,
            );
            final where = '${entry.key} at scale $scale fill $fill';
            expect(
              outline.contours.length,
              reference.contours.length,
              reason: '$where: contour count',
            );
            for (var index = 0; index < outline.contours.length; index++) {
              expect(
                outline.contours[index].points.map((p) => p.onCurve),
                reference.contours[index].points.map((p) => p.onCurve),
                reason: '$where: contour $index',
              );
            }
          }
        }
      }
    });

    test('moves every point exactly linearly with the stroke scale', () {
      for (final entry in fixtureTemplates.entries) {
        final low = entry.value.evaluate(strokeScale: 0.5).allPoints;
        final high = entry.value.evaluate(strokeScale: 2.5).allPoints;
        final middle = entry.value.evaluate(strokeScale: 1.5).allPoints;
        for (var index = 0; index < middle.length; index++) {
          final blend = low[index].position.lerp(high[index].position, 0.5);
          expect(
            middle[index].position.x,
            closeTo(blend.x, 1e-8),
            reason: '${entry.key} point $index x',
          );
          expect(
            middle[index].position.y,
            closeTo(blend.y, 1e-8),
            reason: '${entry.key} point $index y',
          );
        }
      }
    });

    test('describes every point as its base plus a scaled direction', () {
      final template = fixtureTemplates['plus']!;
      final outline = template.evaluate(strokeScale: 1.75);
      var index = 0;
      for (final contour in template.contours) {
        for (final point in contour.points) {
          final expected = point.base + point.direction * 1.75;
          expect(outline.allPoints[index].position, expected);
          index++;
        }
      }
      expect(index, template.pointCount);
    });
  });

  group('IconOutlineBuilder', () {
    const builder = IconOutlineBuilder();

    test('puts the top of the view box on the ascender and the bottom on the '
        'descender', () {
      final outline = builder
          .build(
            _icon([
              _strokedShape(_polyline(const [Vec2(12, 0), Vec2(12, 24)])),
            ]),
          )
          .evaluate(strokeScale: 1);
      final bounds = outline.bounds!;
      expect(bounds.maxY, closeTo(800, 1e-9));
      expect(bounds.minY, closeTo(-200, 1e-9));
      expect(bounds.minX, closeTo(500 - 1000 / 24, 1e-9));
      expect(bounds.maxX, closeTo(500 + 1000 / 24, 1e-9));
    });

    test('reproduces the SVG stroke width at a stroke scale of one', () {
      final outline = builder
          .build(
            _icon([
              _strokedShape(
                _polyline(const [Vec2(0, 12), Vec2(24, 12)]),
                strokeWidth: 3,
              ),
            ]),
          )
          .evaluate(strokeScale: 1);
      final bounds = outline.bounds!;
      // Three user units out of twenty-four, in a thousand unit em square.
      expect(bounds.maxY - bounds.minY, closeTo(3 * 1000 / 24, 1e-9));
      final doubled = builder
          .build(
            _icon([
              _strokedShape(
                _polyline(const [Vec2(0, 12), Vec2(24, 12)]),
                strokeWidth: 3,
              ),
            ]),
          )
          .evaluate(strokeScale: 2)
          .bounds!;
      expect(doubled.maxY - doubled.minY, closeTo(6 * 1000 / 24, 1e-9));
    });

    test('centres a view box that is not square inside the em box', () {
      final outline = builder
          .build(
            _icon([
              _strokedShape(_polyline(const [Vec2(0, 6), Vec2(24, 6)])),
            ], height: 12),
          )
          .evaluate(strokeScale: 1);
      final bounds = outline.bounds!;
      // The half height view box is scaled to the full width and centred on
      // the middle of the em box, which sits halfway from -200 to 800.
      expect((bounds.minY + bounds.maxY) / 2, closeTo(300, 1e-9));
      expect(bounds.minX, closeTo(0, 1e-9));
      expect(bounds.maxX, closeTo(1000, 1e-9));
    });

    test('shifts a view box with a non-zero origin onto the em square', () {
      final outline = builder
          .build(
            _icon(
              [
                _strokedShape(_polyline(const [Vec2(4, 4), Vec2(28, 4)])),
              ],
              x: 4,
              y: 4,
            ),
          )
          .evaluate(strokeScale: 1);
      final bounds = outline.bounds!;
      expect(bounds.minX, closeTo(0, 1e-9));
      expect(bounds.maxX, closeTo(1000, 1e-9));
      // The line runs along the top edge of the view box, so it straddles the
      // ascender.
      expect((bounds.minY + bounds.maxY) / 2, closeTo(800, 1e-9));
    });

    test('leaves a filled but unstroked shape unmoved by the stroke scale', () {
      final shape = SvgShape(
        path: Path([
          _polyline(const [
            Vec2.zero,
            Vec2(24, 0),
            Vec2(24, 24),
            Vec2(0, 24),
          ], closed: true),
        ]),
        filled: true,
        stroked: false,
        strokeWidth: 2,
        cap: StrokeCap.butt,
        join: StrokeJoin.miter,
        miterLimit: 4,
      );
      final template = builder.build(_icon([shape]));
      expect(template.contours, hasLength(1));
      for (final point in template.contours.single.points) {
        expect(point.direction, Vec2.zero);
      }
      expectSameOutline(
        template.evaluate(strokeScale: 5),
        template.evaluate(strokeScale: 1),
        'a filled but unstroked square',
      );
    });
  });
}
