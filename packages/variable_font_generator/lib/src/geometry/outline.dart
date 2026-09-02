import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// A single point of a glyph [Contour].
@immutable
final class OutlinePoint {
  /// Creates a point at [position].
  const OutlinePoint(this.position, {required this.onCurve});

  /// Where the point sits.
  final Vec2 position;

  /// Whether the curve passes through this point.
  ///
  /// Off-curve points are quadratic Bézier control points. Two consecutive
  /// off-curve points imply an on-curve point at their midpoint, which is how
  /// TrueType stores circular arcs compactly.
  final bool onCurve;

  /// Returns a copy of this point moved to [newPosition].
  OutlinePoint withPosition(Vec2 newPosition) =>
      OutlinePoint(newPosition, onCurve: onCurve);

  @override
  bool operator ==(Object other) =>
      other is OutlinePoint &&
      other.position == position &&
      other.onCurve == onCurve;

  @override
  int get hashCode => Object.hash(position, onCurve);

  @override
  String toString() =>
      'OutlinePoint($position, ${onCurve ? 'on' : 'off'}-curve)';
}

/// A closed loop of [points] making up part of a glyph outline.
@immutable
final class Contour {
  /// Creates a contour from [points].
  const Contour(this.points);

  /// The points of the loop, in traversal order. The loop is implicitly closed
  /// from the last point back to the first.
  final List<OutlinePoint> points;

  /// Twice the signed area enclosed by the control polygon.
  ///
  /// Positive for a counter-clockwise loop in a Y-up space. Off-curve points
  /// are treated as if they were on the curve, which is accurate enough to
  /// decide a contour's orientation.
  double get signedArea {
    var total = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index].position;
      final next = points[(index + 1) % points.length].position;
      total += current.cross(next);
    }
    return total / 2;
  }

  /// Expands this contour into explicit line and quadratic segments.
  ///
  /// Resolves the two TrueType storage shorthands: an on-curve point implied at
  /// the midpoint of two consecutive off-curve points, and a contour that
  /// stores no on-curve point at all, whose starting point is then implied at
  /// the midpoint of the last and first control points.
  List<ContourSegment> get segments {
    if (points.length < 2) {
      return const [];
    }

    final firstOnCurve = points.indexWhere((point) => point.onCurve);
    final Vec2 start;
    final int startIndex;
    if (firstOnCurve == -1) {
      // Every point is a control point, so the curve starts halfway between the
      // last and the first of them.
      start = points.last.position.lerp(points.first.position, 0.5);
      startIndex = 0;
    } else {
      start = points[firstOnCurve].position;
      startIndex = firstOnCurve + 1;
    }

    final result = <ContourSegment>[];
    var current = start;
    Vec2? pending;
    for (var step = 0; step < points.length; step++) {
      final point = points[(startIndex + step) % points.length];
      if (point.onCurve) {
        result.add((start: current, control: pending, end: point.position));
        current = point.position;
        pending = null;
      } else if (pending == null) {
        pending = point.position;
      } else {
        final implied = pending.lerp(point.position, 0.5);
        result.add((start: current, control: pending, end: implied));
        current = implied;
        pending = point.position;
      }
    }
    if (!current.isCloseTo(start) || pending != null) {
      result.add((start: current, control: pending, end: start));
    }
    return result;
  }

  /// Returns this contour with its traversal order reversed, which flips its
  /// winding direction.
  Contour get reversed => Contour(points.reversed.toList());

  /// Returns a copy with [transform] applied to every point.
  Contour transformed(Vec2 Function(Vec2 point) transform) => Contour([
    for (final point in points) point.withPosition(transform(point.position)),
  ]);

  @override
  String toString() => 'Contour(${points.length} points)';
}

/// A single drawn piece of a [Contour]: a straight line when its `control` is
/// `null`, and a quadratic Bézier otherwise.
typedef ContourSegment = ({Vec2 start, Vec2? control, Vec2 end});

/// The complete outline of a single glyph.
@immutable
final class Outline {
  /// Creates an outline from [contours].
  const Outline(this.contours);

  /// An outline with no contours, used for blank glyphs such as the space.
  static const empty = Outline([]);

  /// The contours making up the glyph.
  final List<Contour> contours;

  /// The total number of points across every contour.
  int get pointCount =>
      contours.fold(0, (total, contour) => total + contour.points.length);

  /// Whether this outline draws nothing.
  bool get isEmpty => contours.isEmpty;

  /// Every point of every contour, in the order a `glyf` table stores them.
  List<OutlinePoint> get allPoints => [
    for (final contour in contours) ...contour.points,
  ];

  /// Returns a copy with [transform] applied to every point.
  Outline transformed(Vec2 Function(Vec2 point) transform) =>
      Outline([for (final contour in contours) contour.transformed(transform)]);

  /// Returns a copy with every coordinate rounded to a whole design unit.
  ///
  /// Rounding has to happen before variation deltas are computed, not after:
  /// `glyf` stores whole units and `gvar` stores whole-unit differences, so the
  /// default outline plus its deltas can only reproduce a master exactly if
  /// that master was rounded first.
  Outline get rounded => transformed(
    (point) => Vec2(point.x.roundToDouble(), point.y.roundToDouble()),
  );

  /// The tightest axis-aligned box containing every point, or `null` when this
  /// outline is empty.
  ///
  /// Control points are included, so the box can be slightly larger than the
  /// rendered glyph. That is what the OpenType specification asks for in the
  /// common case and never causes clipping.
  ({double minX, double minY, double maxX, double maxY})? get bounds {
    if (isEmpty) {
      return null;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final contour in contours) {
      for (final point in contour.points) {
        minX = minX < point.position.x ? minX : point.position.x;
        minY = minY < point.position.y ? minY : point.position.y;
        maxX = maxX > point.position.x ? maxX : point.position.x;
        maxY = maxY > point.position.y ? maxY : point.position.y;
      }
    }
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  @override
  String toString() =>
      'Outline(${contours.length} contours, $pointCount points)';
}
