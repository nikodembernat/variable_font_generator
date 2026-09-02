import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// Parses [body] wrapped in an `<svg>` root carrying [rootAttributes].
SvgIcon _parse(String body, {String rootAttributes = 'viewBox="0 0 24 24"'}) =>
    parseSvgIcon('<svg $rootAttributes>$body</svg>', name: 'test');

/// The single shape [body] produces, failing when it produces any other count.
SvgShape _onlyShape(
  String body, {
  String rootAttributes = 'viewBox="0 0 24 24"',
}) {
  final icon = _parse(body, rootAttributes: rootAttributes);
  expect(icon.shapes, hasLength(1), reason: 'expected exactly one shape');
  return icon.shapes.single;
}

/// The single sub path of the single shape [body] produces.
SubPath _onlySubPath(String body) {
  final shape = _onlyShape(body);
  expect(shape.path.subPaths, hasLength(1));
  return shape.path.subPaths.single;
}

/// How closely the helpers below follow a curve when they sample one.
///
/// Much finer than the default, so that a measured area is dominated by the
/// geometry under test rather than by the chords standing in for its curves.
const _samplingTolerance = 0.001;

/// Samples every sub path of [path] into polygons.
List<Vec2> _sample(Path path) => [
  for (final subPath in path.subPaths)
    ...flattenSubPath(subPath, tolerance: _samplingTolerance),
];

/// The bounding box of [path], measured on a flattened sampling of it.
({double left, double top, double right, double bottom}) _bounds(Path path) {
  final points = _sample(path);
  var left = points.first.x;
  var right = points.first.x;
  var top = points.first.y;
  var bottom = points.first.y;
  for (final point in points) {
    left = math.min(left, point.x);
    right = math.max(right, point.x);
    top = math.min(top, point.y);
    bottom = math.max(bottom, point.y);
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

/// The enclosed area of [path], measured on a flattened sampling of it.
double _area(Path path) {
  var total = 0.0;
  for (final subPath in path.subPaths) {
    final points = flattenSubPath(subPath, tolerance: _samplingTolerance);
    for (var index = 0; index < points.length; index++) {
      final a = points[index];
      final b = points[(index + 1) % points.length];
      total += a.x * b.y - b.x * a.y;
    }
  }
  return total.abs() / 2;
}

/// Fails unless [actual] and [expected] have the same on-curve points.
void _expectSamePoints(Path actual, Path expected) {
  expect(actual.subPaths, hasLength(expected.subPaths.length));
  for (var index = 0; index < expected.subPaths.length; index++) {
    final actualPoints = actual.subPaths[index].onCurvePoints;
    final expectedPoints = expected.subPaths[index].onCurvePoints;
    expect(actualPoints, hasLength(expectedPoints.length));
    for (var point = 0; point < expectedPoints.length; point++) {
      expect(actualPoints[point].x, closeTo(expectedPoints[point].x, 1e-9));
      expect(actualPoints[point].y, closeTo(expectedPoints[point].y, 1e-9));
    }
  }
}

void main() {
  group('shape elements', () {
    test('turns a path element into the geometry its d attribute names', () {
      final subPath = _onlySubPath('<path d="M1 2 L11 2 L11 12 Z" />');

      expect(subPath.start, const Vec2(1, 2));
      expect(subPath.onCurvePoints, [
        const Vec2(1, 2),
        const Vec2(11, 2),
        const Vec2(11, 12),
      ]);
      expect(subPath.closed, isTrue);
    });

    test('drops a path whose d attribute is blank', () {
      expect(_parse('<path d="   " />').shapes, isEmpty);
      expect(_parse('<path />').shapes, isEmpty);
    });

    test('turns a circle into a closed loop touching its radius', () {
      final subPath = _onlySubPath('<circle cx="10" cy="20" r="4" />');

      expect(subPath.closed, isTrue);
      expect(subPath.segments.every((s) => s is CubicSegment), isTrue);
      final bounds = _bounds(Path([subPath]));
      expect(bounds.left, closeTo(6, 1e-9));
      expect(bounds.right, closeTo(14, 1e-9));
      expect(bounds.top, closeTo(16, 1e-9));
      expect(bounds.bottom, closeTo(24, 1e-9));
    });

    test('gives an ellipse independent horizontal and vertical radii', () {
      final subPath = _onlySubPath('<ellipse cx="10" cy="10" rx="8" ry="2" />');

      final bounds = _bounds(Path([subPath]));
      expect(bounds.right - bounds.left, closeTo(16, 1e-9));
      expect(bounds.bottom - bounds.top, closeTo(4, 1e-9));
    });

    test('drops a circle or an ellipse with a non positive radius', () {
      expect(_parse('<circle cx="5" cy="5" r="0" />').shapes, isEmpty);
      expect(_parse('<circle cx="5" cy="5" r="-3" />').shapes, isEmpty);
      expect(_parse('<ellipse cx="5" cy="5" rx="4" />').shapes, isEmpty);
    });

    test('turns a plain rect into its four corners in order', () {
      final subPath = _onlySubPath(
        '<rect x="2" y="3" width="10" height="6" />',
      );

      expect(subPath.closed, isTrue);
      expect(subPath.onCurvePoints, [
        const Vec2(2, 3),
        const Vec2(12, 3),
        const Vec2(12, 9),
        const Vec2(2, 9),
      ]);
    });

    test('drops a rect with a non positive width or height', () {
      expect(_parse('<rect width="0" height="6" />').shapes, isEmpty);
      expect(_parse('<rect width="10" height="-6" />').shapes, isEmpty);
      expect(_parse('<rect />').shapes, isEmpty);
    });

    test('keeps a line open so its caps are drawn', () {
      final subPath = _onlySubPath('<line x1="1" y1="2" x2="9" y2="8" />');

      expect(subPath.closed, isFalse);
      expect(subPath.start, const Vec2(1, 2));
      expect(subPath.segments, const [LineSegment(Vec2(9, 8))]);
    });

    test('keeps a zero length line, which a round cap draws as a dot', () {
      final subPath = _onlySubPath('<line x1="5" y1="5" x2="5" y2="5" />');

      expect(subPath.segments, hasLength(1));
      expect(subPath.segments.single.end, subPath.start);
    });

    test('leaves a polyline open and closes a polygon', () {
      const points = 'points="0,0 10,0 10,10"';
      final polyline = _onlySubPath('<polyline $points />');
      final polygon = _onlySubPath('<polygon $points />');

      expect(polyline.closed, isFalse);
      expect(polygon.closed, isTrue);
      expect(polyline.onCurvePoints, polygon.onCurvePoints);
      expect(polyline.onCurvePoints, [
        Vec2.zero,
        const Vec2(10, 0),
        const Vec2(10, 10),
      ]);
    });

    test('needs two whole points and ignores a trailing odd one', () {
      expect(_parse('<polygon points="1,2" />').shapes, isEmpty);
      expect(_parse('<polygon points="1,2 3" />').shapes, isEmpty);
      expect(_parse('<polyline />').shapes, isEmpty);
      expect(
        _onlySubPath('<polygon points="0 0 4 0 4 4 7" />').onCurvePoints,
        hasLength(3),
      );
    });
  });

  group('rect corner radii', () {
    test('takes ry from rx when only rx is given', () {
      final onlyRx = _onlySubPath('<rect width="20" height="12" rx="3" />');
      final both = _onlySubPath(
        '<rect width="20" height="12" rx="3" ry="3" />',
      );

      _expectSamePoints(Path([onlyRx]), Path([both]));
    });

    test('takes rx from ry when only ry is given', () {
      final onlyRy = _onlySubPath('<rect width="20" height="12" ry="3" />');
      final both = _onlySubPath(
        '<rect width="20" height="12" rx="3" ry="3" />',
      );

      _expectSamePoints(Path([onlyRy]), Path([both]));
    });

    test('clamps each radius to half of the side it rounds', () {
      final oversized = _onlySubPath(
        '<rect width="20" height="12" rx="50" ry="90" />',
      );
      final clamped = _onlySubPath(
        '<rect width="20" height="12" rx="10" ry="6" />',
      );

      _expectSamePoints(Path([oversized]), Path([clamped]));
    });

    test('squares the corners when either radius resolves to zero', () {
      final zeroRx = _onlySubPath(
        '<rect width="20" height="12" rx="0" ry="4" />',
      );
      final plain = _onlySubPath('<rect width="20" height="12" />');

      expect(zeroRx.onCurvePoints, plain.onCurvePoints);
    });

    test('makes a stadium when rx is exactly half the width', () {
      final subPath = _onlySubPath('<rect width="10" height="30" rx="5" />');

      // The straight top and bottom edges collapse to a point, so the ends are
      // pure semicircles.
      expect(subPath.segments.first.end, subPath.start);
      final bounds = _bounds(Path([subPath]));
      expect(bounds.left, closeTo(0, 1e-9));
      expect(bounds.right, closeTo(10, 1e-9));
      expect(bounds.top, closeTo(0, 1e-9));
      expect(bounds.bottom, closeTo(30, 1e-9));
      // A 10 by 20 rectangle plus a circle of radius 5.
      expect(_area(Path([subPath])), closeTo(200 + math.pi * 25, 0.5));
    });

    test('draws a circle when rx is half of both sides', () {
      final rect = _onlySubPath(
        '<rect width="20" height="20" rx="10" ry="10" />',
      );
      final circle = _onlySubPath('<circle cx="10" cy="10" r="10" />');

      final rectBounds = _bounds(Path([rect]));
      final circleBounds = _bounds(Path([circle]));
      expect(rectBounds.left, closeTo(circleBounds.left, 1e-6));
      expect(rectBounds.right, closeTo(circleBounds.right, 1e-6));
      expect(rectBounds.top, closeTo(circleBounds.top, 1e-6));
      expect(rectBounds.bottom, closeTo(circleBounds.bottom, 1e-6));
      expect(_area(Path([rect])), closeTo(_area(Path([circle])), 0.5));
      expect(_area(Path([rect])), closeTo(math.pi * 100, 0.5));
    });
  });

  group('presentation attributes', () {
    test('inherits paint from the svg root down to a shape', () {
      final shape = _onlyShape(
        '<rect width="4" height="4" />',
        rootAttributes:
            'viewBox="0 0 24 24" fill="none" stroke="black" '
            'stroke-width="2px" stroke-linecap="round" '
            'stroke-linejoin="round" stroke-miterlimit="8"',
      );

      expect(shape.filled, isFalse);
      expect(shape.stroked, isTrue);
      expect(shape.strokeWidth, 2);
      expect(shape.cap, StrokeCap.round);
      expect(shape.join, StrokeJoin.round);
      expect(shape.miterLimit, 8);
    });

    test('uses the SVG initial values when the root says nothing', () {
      final shape = _onlyShape('<rect width="4" height="4" />');

      expect(shape.filled, isTrue);
      expect(shape.stroked, isFalse);
      expect(shape.strokeWidth, 1);
      expect(shape.cap, StrokeCap.butt);
      expect(shape.join, StrokeJoin.miter);
      expect(shape.miterLimit, 4);
    });

    test('inherits through nested g elements', () {
      final shape = _onlyShape(
        '<g stroke="red" stroke-width="3">'
        '<g stroke-linecap="square"><rect width="4" height="4" /></g>'
        '</g>',
      );

      expect(shape.stroked, isTrue);
      expect(shape.strokeWidth, 3);
      expect(shape.cap, StrokeCap.square);
    });

    test('lets a child override what its parent set', () {
      final icon = _parse(
        '<g fill="red" stroke-width="3">'
        '<rect width="4" height="4" />'
        '<rect width="4" height="4" fill="none" stroke="blue" '
        'stroke-width="7" />'
        '</g>',
      );

      expect(icon.shapes, hasLength(2));
      expect(icon.shapes[0].filled, isTrue);
      expect(icon.shapes[0].strokeWidth, 3);
      expect(icon.shapes[1].filled, isFalse);
      expect(icon.shapes[1].stroked, isTrue);
      expect(icon.shapes[1].strokeWidth, 7);
    });

    test('treats any paint value other than none as filling', () {
      for (final value in ['red', '#ff0000', 'currentColor', 'url(#g)']) {
        expect(
          _onlyShape('<rect width="4" height="4" fill="$value" />').filled,
          isTrue,
          reason: 'fill="$value"',
        );
      }
    });

    test('treats none as not painting, whatever its case or padding', () {
      for (final value in ['none', 'NONE', '  none  ', 'transparent']) {
        expect(
          _onlyShape(
            '<rect width="4" height="4" fill="$value" stroke="black" />',
          ).filled,
          isFalse,
          reason: 'fill="$value"',
        );
      }
    });

    test('drops a shape that is neither filled nor stroked', () {
      expect(
        _parse('<rect width="4" height="4" fill="none" stroke="none" />')
            .shapes,
        isEmpty,
      );
    });

    test('lets a style declaration beat the matching attribute', () {
      final shape = _onlyShape(
        '<rect width="4" height="4" fill="red" stroke="black" '
        'stroke-width="2" style="fill: none; stroke-width: 9" />',
      );

      expect(shape.filled, isFalse);
      expect(shape.stroked, isTrue);
      expect(shape.strokeWidth, 9);
      // A declaration with no colon is not a declaration at all.
      expect(
        _onlyShape('<rect width="4" height="4" fill="red" style="fill" />')
            .filled,
        isTrue,
      );
    });

    test('falls back to butt and miter for keywords it does not know', () {
      final shape = _onlyShape(
        '<rect width="4" height="4" stroke="black" '
        'stroke-linecap="triangle" stroke-linejoin="arcs" />',
      );

      expect(shape.cap, StrokeCap.butt);
      expect(shape.join, StrokeJoin.miter);
    });
  });

  group('transform', () {
    test('moves geometry by a translate', () {
      final subPath = _onlySubPath(
        '<rect width="10" height="10" transform="translate(5, 7)" />',
      );

      expect(subPath.onCurvePoints.first, const Vec2(5, 7));
      expect(subPath.onCurvePoints[2], const Vec2(15, 17));
      // A one argument translate only moves horizontally.
      expect(
        parseSvgTransform('translate(5)').apply(Vec2.zero),
        const Vec2(5, 0),
      );
    });

    test('scales geometry and the stroke width together', () {
      final shape = _onlyShape(
        '<rect width="10" height="10" stroke="black" stroke-width="2" '
        'transform="scale(3)" />',
      );

      expect(shape.path.subPaths.single.onCurvePoints[2], const Vec2(30, 30));
      expect(shape.strokeWidth, closeTo(6, 1e-9));
    });

    test('rotates around the origin', () {
      final subPath = _onlySubPath(
        '<line x1="10" y1="0" x2="10" y2="0" transform="rotate(90)" />',
      );

      expect(subPath.start.x, closeTo(0, 1e-9));
      expect(subPath.start.y, closeTo(10, 1e-9));
    });

    test('rotates around the centre a rotate is given', () {
      final subPath = _onlySubPath(
        '<line x1="5" y1="0" x2="5" y2="0" transform="rotate(90 5 5)" />',
      );

      expect(subPath.start.x, closeTo(10, 1e-9));
      expect(subPath.start.y, closeTo(5, 1e-9));
    });

    test('applies the six numbers of a matrix', () {
      final subPath = _onlySubPath(
        '<line x1="1" y1="1" x2="1" y2="1" '
        'transform="matrix(2 0 0 3 4 5)" />',
      );

      expect(subPath.start.x, closeTo(6, 1e-9));
      expect(subPath.start.y, closeTo(8, 1e-9));
    });

    test('shears x with skewX and y with skewY', () {
      final skewX = parseSvgTransform('skewX(45)').apply(const Vec2(0, 10));
      final skewY = parseSvgTransform('skewY(45)').apply(const Vec2(10, 0));

      expect(skewX.x, closeTo(10, 1e-9));
      expect(skewX.y, closeTo(10, 1e-9));
      expect(skewY.x, closeTo(10, 1e-9));
      expect(skewY.y, closeTo(10, 1e-9));
    });

    test('applies chained functions right to left', () {
      final chained = parseSvgTransform('translate(10 0) scale(2)');

      expect(chained.apply(const Vec2(1, 1)).x, closeTo(12, 1e-9));
      expect(chained.apply(const Vec2(1, 1)).y, closeTo(2, 1e-9));
    });

    test('composes a parent transform with a child transform', () {
      final subPath = _onlySubPath(
        '<g transform="translate(1, 2)">'
        '<g transform="scale(2)">'
        '<line x1="3" y1="4" x2="3" y2="4" />'
        '</g></g>',
      );

      expect(subPath.start.x, closeTo(7, 1e-9));
      expect(subPath.start.y, closeTo(10, 1e-9));
    });

    test('scales the stroke width by the root of the determinant', () {
      final anisotropic = _onlyShape(
        '<rect width="4" height="4" stroke="black" stroke-width="2" '
        'transform="scale(3, 1)" />',
      );
      final mirrored = _onlyShape(
        '<rect width="4" height="4" stroke="black" stroke-width="2" '
        'transform="scale(-2, 2)" />',
      );
      final rotated = _onlyShape(
        '<rect width="4" height="4" stroke="black" stroke-width="2" '
        'transform="rotate(37)" />',
      );

      expect(anisotropic.strokeWidth, closeTo(2 * math.sqrt(3), 1e-9));
      expect(mirrored.strokeWidth, closeTo(4, 1e-9));
      expect(rotated.strokeWidth, closeTo(2, 1e-9));
    });

    test('skips a transform function it does not recognise', () {
      final subPath = _onlySubPath(
        '<line x1="0" y1="0" x2="0" y2="0" '
        'transform="frobnicate(9) translate(4, 6)" />',
      );

      expect(subPath.start, const Vec2(4, 6));
    });

    test('reads an empty or absent transform as the identity', () {
      expect(parseSvgTransform('').isIdentity, isTrue);
      expect(parseSvgTransform('   ').isIdentity, isTrue);
      expect(parseSvgTransform('translate(0 0)').isIdentity, isTrue);
    });

    test('multiplies so that the argument transform is applied first', () {
      final composed = AffineTransform.translate(
        1,
        0,
      ).multiply(AffineTransform.scale(2, 2));

      expect(composed.apply(const Vec2(3, 3)), const Vec2(7, 6));
    });

    test('reports the determinant and the stroke scale of a transform', () {
      const transform = AffineTransform(0, 2, -3, 0, 5, 5);

      expect(transform.determinant, 6);
      expect(transform.strokeScale, closeTo(math.sqrt(6), 1e-12));
      expect(AffineTransform.scale(-1, 1).strokeScale, 1);
    });
  });

  group('the view box', () {
    test('reads the four numbers of a viewBox, origin included', () {
      final icon = _parse(
        '<rect width="1" height="1" />',
        rootAttributes: 'viewBox="-4 -8 32 16"',
      );

      expect(icon.viewBoxX, -4);
      expect(icon.viewBoxY, -8);
      expect(icon.viewBoxWidth, 32);
      expect(icon.viewBoxHeight, 16);

      final commas = _parse(
        '<rect width="1" height="1" />',
        rootAttributes: 'viewBox="0,0,48,24"',
      );
      expect(commas.viewBoxWidth, 48);
      expect(commas.viewBoxHeight, 24);
    });

    test('falls back to width and height when there is no viewBox', () {
      final icon = _parse(
        '<rect width="1" height="1" />',
        rootAttributes: 'width="48px" height="32px"',
      );

      expect(icon.viewBoxX, 0);
      expect(icon.viewBoxY, 0);
      expect(icon.viewBoxWidth, 48);
      expect(icon.viewBoxHeight, 32);
    });

    test('falls back when the viewBox has a non positive size', () {
      final icon = _parse(
        '<rect width="1" height="1" />',
        rootAttributes: 'viewBox="0 0 0 24" width="10" height="20"',
      );

      expect(icon.viewBoxWidth, 10);
      expect(icon.viewBoxHeight, 20);
    });

    test('throws when neither a viewBox nor a size is usable', () {
      expect(
        () => parseSvgIcon('<svg />', name: 'sizeless'),
        throwsA(isA<SvgParseException>()),
      );
      expect(
        () => parseSvgIcon('<svg width="0" height="0" />', name: 'sizeless'),
        throwsA(isA<SvgParseException>()),
      );
      expect(
        () => parseSvgIcon('<svg viewBox="0 0 24" />', name: 'sizeless'),
        throwsA(isA<SvgParseException>()),
      );
    });
  });

  group('documents the parser cannot use', () {
    test('throws for malformed XML rather than letting it escape', () {
      expect(
        () => parseSvgIcon('<svg><rect></svg>', name: 'broken'),
        throwsA(
          isA<SvgParseException>()
              .having((e) => e.source, 'source', 'broken')
              .having((e) => e.message, 'message', contains('Malformed XML')),
        ),
      );
      expect(
        () => parseSvgIcon('not xml at all', name: 'broken'),
        throwsA(isA<SvgParseException>()),
      );
    });

    test('throws when the root element is not svg', () {
      expect(
        () => parseSvgIcon('<html><svg /></html>', name: 'page'),
        throwsA(
          isA<SvgParseException>().having(
            (e) => e.message,
            'message',
            contains('html'),
          ),
        ),
      );
    });
  });

  group('elements the parser does not understand', () {
    test('ignores text, titles, gradients and metadata', () {
      final icon = _parse(
        '<title>An icon</title>'
        '<desc>Something</desc>'
        '<linearGradient id="g"><stop offset="0" /></linearGradient>'
        '<text x="1" y="2">hello</text>'
        '<rect width="4" height="4" />',
      );

      expect(icon.shapes, hasLength(1));
      expect(icon.isEmpty, isFalse);
    });

    test('still walks the children of an element it does not understand', () {
      final icon = _parse(
        '<defs><rect width="4" height="4" /></defs>'
        '<switch><circle cx="2" cy="2" r="1" /></switch>',
      );

      expect(icon.shapes, hasLength(2));
    });

    test('reports an icon with nothing drawable as empty', () {
      final icon = _parse('<text x="1" y="2">hello</text>');

      expect(icon.shapes, isEmpty);
      expect(icon.isEmpty, isTrue);
    });
  });

  group('loadSvgIcons', () {
    test('reads every SVG in the directory and skips anything else', () {
      final icons = loadSvgIcons(Directory(fixtureDirectory));

      expect(icons, hasLength(45));
      expect(icons.map((icon) => icon.name), isNot(contains('LICENSE')));
    });

    test('sorts icons by name so a build is reproducible', () {
      final names = [
        for (final icon in loadSvgIcons(Directory(fixtureDirectory))) icon.name,
      ];
      final sorted = [...names]..sort();

      expect(names, sorted);
      expect(names.toSet(), hasLength(names.length));
    });

    test('names an icon after its file without the extension', () {
      final names = [for (final icon in fixtureIcons) icon.name];

      expect(names, containsAll(['circle', 'plus', 'square', 'toggle-left']));
      expect(names.any((name) => name.endsWith('.svg')), isFalse);
    });

    test('throws for a directory that does not exist', () {
      expect(
        () => loadSvgIcons(Directory('test/fixtures/definitely-not-here')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('parses every fixture icon into at least one drawable shape', () {
      for (final icon in fixtureIcons) {
        expect(icon.shapes, isNotEmpty, reason: icon.name);
        expect(icon.isEmpty, isFalse, reason: icon.name);
        expect(icon.viewBoxWidth, 24, reason: icon.name);
        expect(icon.viewBoxHeight, 24, reason: icon.name);
        for (final shape in icon.shapes) {
          // Every Lucide icon paints from the root's attributes alone.
          expect(shape.stroked, isTrue, reason: icon.name);
          expect(shape.strokeWidth, 2, reason: icon.name);
          expect(shape.cap, StrokeCap.round, reason: icon.name);
          expect(shape.join, StrokeJoin.round, reason: icon.name);
        }
      }
    });

    test('lets a fixture shape override the root fill it inherits', () {
      final scatter = fixtureIcons.singleWhere(
        (i) => i.name == 'chart-scatter',
      );

      // Five dots painted with an explicit fill, plus one stroked axis path.
      expect(scatter.shapes.where((shape) => shape.filled), hasLength(5));
      expect(scatter.shapes.where((shape) => !shape.filled), hasLength(1));
    });
  });
}
