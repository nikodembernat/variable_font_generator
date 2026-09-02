import 'dart:math' as math;

import 'package:meta/meta.dart';

/// An immutable two dimensional point (or vector).
///
/// Used throughout the package both for SVG user space coordinates and for
/// font design units. Which space a particular value lives in is documented at
/// the API that produces it.
@immutable
final class Vec2 {
  /// Creates a vector from its [x] and [y] components.
  const Vec2(this.x, this.y);

  /// The vector `(0, 0)`.
  static const zero = Vec2(0, 0);

  /// The horizontal component.
  final double x;

  /// The vertical component.
  final double y;

  /// Component-wise addition.
  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);

  /// Component-wise subtraction.
  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);

  /// Scales both components by [factor].
  Vec2 operator *(double factor) => Vec2(x * factor, y * factor);

  /// Divides both components by [divisor].
  Vec2 operator /(double divisor) => Vec2(x / divisor, y / divisor);

  /// Negates both components.
  Vec2 operator -() => Vec2(-x, -y);

  /// The Euclidean length of this vector.
  double get length => math.sqrt(x * x + y * y);

  /// The squared Euclidean length, avoiding the square root.
  double get lengthSquared => x * x + y * y;

  /// This vector scaled to unit length.
  ///
  /// Returns [zero] when this vector is degenerate, so callers never have to
  /// guard against division by zero.
  Vec2 get normalized {
    final len = length;
    if (len == 0) {
      return zero;
    }
    return Vec2(x / len, y / len);
  }

  /// This vector rotated by 90 degrees counter-clockwise in a Y-up space.
  Vec2 get perpendicular => Vec2(-y, x);

  /// The dot product of this vector and [other].
  double dot(Vec2 other) => x * other.x + y * other.y;

  /// The 2D cross product (the Z component of the 3D cross product).
  ///
  /// Positive when [other] lies counter-clockwise from this vector in a Y-up
  /// space.
  double cross(Vec2 other) => x * other.y - y * other.x;

  /// Linearly interpolates towards [other] by [t].
  Vec2 lerp(Vec2 other, double t) =>
      Vec2(x + (other.x - x) * t, y + (other.y - y) * t);

  /// The distance between this point and [other].
  double distanceTo(Vec2 other) => (this - other).length;

  /// The angle of this vector in radians, measured from the positive X axis.
  double get angle => math.atan2(y, x);

  /// Whether this point is within [epsilon] of [other] in both components.
  bool isCloseTo(Vec2 other, [double epsilon = 1e-9]) =>
      (x - other.x).abs() <= epsilon && (y - other.y).abs() <= epsilon;

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}
