import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/geometry/path.dart';
import 'package:variable_font_generator/src/geometry/stroke_style.dart';

/// One drawable shape of an [SvgIcon], with the painting properties that apply
/// to it already resolved from its ancestors.
@immutable
final class SvgShape {
  /// Creates a shape.
  const SvgShape({
    required this.path,
    required this.filled,
    required this.stroked,
    required this.strokeWidth,
    required this.cap,
    required this.join,
    required this.miterLimit,
  });

  /// The geometry, in the icon's user space.
  final Path path;

  /// Whether the shape's interior is painted.
  final bool filled;

  /// Whether the shape's outline is painted.
  final bool stroked;

  /// The stroke width in user space units.
  final double strokeWidth;

  /// How the ends of open sub paths are drawn.
  final StrokeCap cap;

  /// How corners are drawn.
  final StrokeJoin join;

  /// The miter limit, as a ratio of miter length to stroke width.
  final double miterLimit;

  @override
  String toString() =>
      'SvgShape(${path.subPaths.length} sub paths, filled: $filled, '
      'stroked: $stroked, strokeWidth: $strokeWidth)';
}

/// A parsed SVG icon: its view box and the shapes that make it up.
@immutable
final class SvgIcon {
  /// Creates an icon.
  const SvgIcon({
    required this.name,
    required this.viewBoxX,
    required this.viewBoxY,
    required this.viewBoxWidth,
    required this.viewBoxHeight,
    required this.shapes,
  });

  /// The icon's name, normally the file name without its extension.
  final String name;

  /// The left edge of the view box.
  final double viewBoxX;

  /// The top edge of the view box.
  final double viewBoxY;

  /// The width of the view box.
  final double viewBoxWidth;

  /// The height of the view box.
  final double viewBoxHeight;

  /// The shapes making up the icon, in painting order.
  final List<SvgShape> shapes;

  /// Whether the icon draws nothing at all.
  bool get isEmpty => shapes.every((shape) => shape.path.isEmpty);

  @override
  String toString() =>
      'SvgIcon($name, viewBox: $viewBoxX $viewBoxY $viewBoxWidth '
      '$viewBoxHeight, ${shapes.length} shapes)';
}
