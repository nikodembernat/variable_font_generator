import 'package:meta/meta.dart';

import 'package:variable_font_generator/src/geometry/vec2.dart';

/// A single segment of a [SubPath], starting at the previous segment's end
/// point (or at [SubPath.start] for the first segment).
@immutable
sealed class PathSegment {
  /// Creates a segment ending at [end].
  const PathSegment(this.end);

  /// The point the segment ends at.
  final Vec2 end;

  /// Returns a copy of this segment with [transform] applied to every point.
  PathSegment transformed(Vec2 Function(Vec2 point) transform);
}

/// A straight line segment.
final class LineSegment extends PathSegment {
  /// Creates a line ending at [end].
  const LineSegment(super.end);

  @override
  LineSegment transformed(Vec2 Function(Vec2 point) transform) =>
      LineSegment(transform(end));

  @override
  bool operator ==(Object other) => other is LineSegment && other.end == end;

  @override
  int get hashCode => Object.hash(LineSegment, end);

  @override
  String toString() => 'LineSegment($end)';
}

/// A quadratic Bézier segment with a single [control] point.
final class QuadraticSegment extends PathSegment {
  /// Creates a quadratic Bézier through [control] ending at [end].
  const QuadraticSegment(this.control, super.end);

  /// The off-curve control point.
  final Vec2 control;

  @override
  QuadraticSegment transformed(Vec2 Function(Vec2 point) transform) =>
      QuadraticSegment(transform(control), transform(end));

  @override
  bool operator ==(Object other) =>
      other is QuadraticSegment && other.control == control && other.end == end;

  @override
  int get hashCode => Object.hash(QuadraticSegment, control, end);

  @override
  String toString() => 'QuadraticSegment($control, $end)';
}

/// A cubic Bézier segment with two control points.
final class CubicSegment extends PathSegment {
  /// Creates a cubic Bézier through [control1] and [control2] ending at [end].
  const CubicSegment(this.control1, this.control2, super.end);

  /// The off-curve control point associated with the start point.
  final Vec2 control1;

  /// The off-curve control point associated with [end].
  final Vec2 control2;

  @override
  CubicSegment transformed(Vec2 Function(Vec2 point) transform) =>
      CubicSegment(transform(control1), transform(control2), transform(end));

  @override
  bool operator ==(Object other) =>
      other is CubicSegment &&
      other.control1 == control1 &&
      other.control2 == control2 &&
      other.end == end;

  @override
  int get hashCode => Object.hash(CubicSegment, control1, control2, end);

  @override
  String toString() => 'CubicSegment($control1, $control2, $end)';
}

/// A contiguous run of segments starting at [start].
///
/// A sub path is the result of a single `M` command in SVG path data, together
/// with every segment that follows it up to the next `M` or the end of the
/// path.
@immutable
final class SubPath {
  /// Creates a sub path starting at [start] and made of [segments].
  const SubPath({
    required this.start,
    required this.segments,
    required this.closed,
  });

  /// The point the first segment starts from.
  final Vec2 start;

  /// The segments making up this sub path, in order.
  final List<PathSegment> segments;

  /// Whether the sub path was explicitly closed with a `Z` command.
  ///
  /// A closed sub path is filled and stroked as a loop: the last segment's end
  /// point is joined back to [start] rather than capped.
  final bool closed;

  /// Whether this sub path carries no drawable geometry.
  bool get isEmpty => segments.isEmpty;

  /// Every on-curve point of this sub path, starting with [start].
  List<Vec2> get onCurvePoints => [start, ...segments.map((s) => s.end)];

  /// Returns a copy with [transform] applied to every point.
  SubPath transformed(Vec2 Function(Vec2 point) transform) => SubPath(
    start: transform(start),
    segments: [for (final segment in segments) segment.transformed(transform)],
    closed: closed,
  );

  @override
  String toString() =>
      'SubPath(start: $start, segments: ${segments.length}, closed: $closed)';
}

/// An immutable outline made of independent [subPaths].
@immutable
final class Path {
  /// Creates a path from [subPaths].
  const Path(this.subPaths);

  /// A path with no sub paths.
  static const empty = Path([]);

  /// The sub paths, in drawing order.
  final List<SubPath> subPaths;

  /// Whether this path contains no drawable geometry.
  bool get isEmpty => subPaths.every((s) => s.isEmpty);

  /// Returns a copy with [transform] applied to every point.
  Path transformed(Vec2 Function(Vec2 point) transform) =>
      Path([for (final subPath in subPaths) subPath.transformed(transform)]);

  /// Returns a copy of this path with [other]'s sub paths appended.
  Path operator +(Path other) => Path([...subPaths, ...other.subPaths]);

  @override
  String toString() => 'Path(${subPaths.length} sub paths)';
}
