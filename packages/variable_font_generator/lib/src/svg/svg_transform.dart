import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// A 2D affine transform stored as the six values of an SVG `matrix(...)`.
///
/// Maps a point `(x, y)` to `(a * x + c * y + e, b * x + d * y + f)`.
@immutable
final class AffineTransform {
  /// Creates a transform from its six coefficients.
  const AffineTransform(this.a, this.b, this.c, this.d, this.e, this.f);

  /// A transform that moves points by ([dx], [dy]).
  factory AffineTransform.translate(double dx, double dy) =>
      AffineTransform(1, 0, 0, 1, dx, dy);

  /// A transform that scales by [sx] horizontally and [sy] vertically.
  factory AffineTransform.scale(double sx, double sy) =>
      AffineTransform(sx, 0, 0, sy, 0, 0);

  /// A transform that rotates by [degrees] around the origin.
  factory AffineTransform.rotate(double degrees) {
    final radians = degrees * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return AffineTransform(cos, sin, -sin, cos, 0, 0);
  }

  /// A transform that skews the X axis by [degrees].
  factory AffineTransform.skewX(double degrees) =>
      AffineTransform(1, 0, math.tan(degrees * math.pi / 180), 1, 0, 0);

  /// A transform that skews the Y axis by [degrees].
  factory AffineTransform.skewY(double degrees) =>
      AffineTransform(1, math.tan(degrees * math.pi / 180), 0, 1, 0, 0);

  /// The transform that leaves every point where it is.
  static const identity = AffineTransform(1, 0, 0, 1, 0, 0);

  /// The horizontal scale coefficient.
  final double a;

  /// The vertical shear coefficient.
  final double b;

  /// The horizontal shear coefficient.
  final double c;

  /// The vertical scale coefficient.
  final double d;

  /// The horizontal translation.
  final double e;

  /// The vertical translation.
  final double f;

  /// The transform that applies [other] first and then this one.
  AffineTransform multiply(AffineTransform other) => AffineTransform(
    a * other.a + c * other.b,
    b * other.a + d * other.b,
    a * other.c + c * other.d,
    b * other.c + d * other.d,
    a * other.e + c * other.f + e,
    b * other.e + d * other.f + f,
  );

  /// Applies this transform to [point].
  Vec2 apply(Vec2 point) =>
      Vec2(a * point.x + c * point.y + e, b * point.x + d * point.y + f);

  /// The determinant, which is the factor by which areas are scaled.
  double get determinant => a * d - b * c;

  /// How much a stroke width is scaled by this transform.
  ///
  /// SVG strokes a path in its local coordinate system and then transforms the
  /// result, so an anisotropic transform makes the stroke thicker in one
  /// direction than the other. Approximating that with the geometric mean of
  /// the two scale factors keeps uniform scales, rotations and translations
  /// exact, which covers everything icon sets use in practice.
  double get strokeScale => math.sqrt(determinant.abs());

  /// Whether this transform leaves every point where it is.
  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  @override
  String toString() => 'AffineTransform($a, $b, $c, $d, $e, $f)';
}

/// Parses the value of an SVG `transform` attribute.
///
/// Supports `matrix`, `translate`, `scale`, `rotate`, `skewX` and `skewY`, in
/// any number and order. Unknown function names are skipped rather than
/// rejected, so an unexpected attribute degrades to a missing transform instead
/// of failing the whole icon.
AffineTransform parseSvgTransform(String value) {
  final pattern = RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)');
  var result = AffineTransform.identity;
  for (final match in pattern.allMatches(value)) {
    final name = match.group(1)!;
    final numbers = _parseNumberList(match.group(2)!);
    final transform = switch (name) {
      'matrix' when numbers.length >= 6 => AffineTransform(
        numbers[0],
        numbers[1],
        numbers[2],
        numbers[3],
        numbers[4],
        numbers[5],
      ),
      'translate' when numbers.isNotEmpty => AffineTransform.translate(
        numbers[0],
        numbers.length > 1 ? numbers[1] : 0,
      ),
      'scale' when numbers.isNotEmpty => AffineTransform.scale(
        numbers[0],
        numbers.length > 1 ? numbers[1] : numbers[0],
      ),
      'rotate' when numbers.length >= 3 =>
        AffineTransform.translate(numbers[1], numbers[2]).multiply(
          AffineTransform.rotate(numbers[0])
              .multiply(AffineTransform.translate(-numbers[1], -numbers[2])),
        ),
      'rotate' when numbers.isNotEmpty => AffineTransform.rotate(numbers[0]),
      'skewX' when numbers.isNotEmpty => AffineTransform.skewX(numbers[0]),
      'skewY' when numbers.isNotEmpty => AffineTransform.skewY(numbers[0]),
      _ => AffineTransform.identity,
    };
    result = result.multiply(transform);
  }
  return result;
}

/// Parses a whitespace or comma separated list of numbers.
List<double> _parseNumberList(String value) => [
  for (final match in RegExp(
    r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
  ).allMatches(value))
    double.parse(match.group(0)!),
];
