import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/geometry/path.dart';
import 'package:variable_font_generator/src/geometry/polygon.dart';
import 'package:variable_font_generator/src/geometry/stroke_template.dart';
import 'package:variable_font_generator/src/geometry/stroker.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';
import 'package:variable_font_generator/src/svg/svg_icon.dart';

/// Turns a parsed [SvgIcon] into a [StrokeTemplate] in font design units.
///
/// The template's half width argument is dimensionless here: passing one
/// reproduces the stroke widths the SVG asks for, and the variable axes simply
/// scale that number. Shapes that specify different stroke widths therefore
/// keep their relative thickness at every weight.
@immutable
final class IconOutlineBuilder {
  /// Creates a builder.
  const IconOutlineBuilder({
    this.metrics = const FontMetrics(),
    this.maxTurnAngle = Stroker.defaultMaxTurnAngle,
    this.maxArcAngle = Stroker.defaultMaxArcAngle,
    this.curveTolerance = 1,
    this.innerJoinLimit = Stroker.defaultInnerJoinLimit,
  });

  /// The metrics the icon is fitted to.
  final FontMetrics metrics;

  /// See [Stroker.maxTurnAngle].
  final double maxTurnAngle;

  /// See [Stroker.maxArcAngle].
  final double maxArcAngle;

  /// See [Stroker.innerJoinLimit].
  final double innerJoinLimit;

  /// How far, in font design units, a curve may deviate from the artwork.
  ///
  /// Cubic Bézier curves have to become quadratics for TrueType, and this is
  /// the budget for that approximation. One design unit out of a thousand is
  /// about a fortieth of a pixel when an icon is drawn at 24 logical pixels.
  final double curveTolerance;

  /// The advance width every glyph gets, which is one em.
  int get advanceWidth => metrics.unitsPerEm;

  /// Builds the outline template for [icon].
  StrokeTemplate build(SvgIcon icon) {
    // Fit the view box into the em square, keeping the aspect ratio and
    // centring whichever dimension is smaller.
    final scale =
        metrics.unitsPerEm /
        (icon.viewBoxWidth > icon.viewBoxHeight
            ? icon.viewBoxWidth
            : icon.viewBoxHeight);
    final offsetX = (metrics.unitsPerEm - icon.viewBoxWidth * scale) / 2;
    final offsetY = (metrics.unitsPerEm - icon.viewBoxHeight * scale) / 2;

    // SVG's Y axis points down and the font's points up, so the vertical scale
    // is negated and the top of the view box lands on the ascender.
    Vec2 linear(Vec2 vector) => Vec2(vector.x * scale, -vector.y * scale);
    final translation = Vec2(
      offsetX - icon.viewBoxX * scale,
      metrics.ascender.toDouble() - offsetY + icon.viewBoxY * scale,
    );

    // The tolerance is quoted in design units but the artwork is stroked in
    // its own user units, so convert before handing it to the stroker.
    final userTolerance = curveTolerance / scale;

    // A detail stroke sitting inside a shape the fill axis will make solid
    // gets special treatment, so work out which sub paths those are before
    // stroking anything.
    final knockedOut = _knockedOutSubPaths(icon);

    var template = StrokeTemplate.empty;
    for (final shape in icon.shapes) {
      if (!shape.stroked) {
        // Painted but not stroked: a zero-width stroke leaves exactly the
        // shape's own boundary, which is the fill.
        if (shape.filled) {
          template += _scaleDirections(
            Stroker(
              cap: shape.cap,
              join: shape.join,
              miterLimit: shape.miterLimit,
              maxTurnAngle: maxTurnAngle,
              maxArcAngle: maxArcAngle,
              cubicTolerance: userTolerance,
              innerJoinLimit: innerJoinLimit,
            ).strokePath(shape.path, filled: true),
            0,
          );
        }
        continue;
      }
      final stroker = Stroker(
        cap: shape.cap,
        join: shape.join,
        miterLimit: shape.miterLimit,
        maxTurnAngle: maxTurnAngle,
        maxArcAngle: maxArcAngle,
        cubicTolerance: userTolerance,
        innerJoinLimit: innerJoinLimit,
      );
      for (final subPath in shape.path.subPaths) {
        template += _scaleDirections(
          stroker.strokeSubPath(
            subPath,
            filled: shape.filled,
            knockedOutWhenFilled: knockedOut.contains(subPath),
          ),
          shape.strokeWidth / 2,
        );
      }
    }

    return template.transformed(transform: linear, translation: translation);
  }

  /// The open sub paths of [icon] that sit inside a shape the fill axis will
  /// make solid.
  ///
  /// Only open sub paths qualify. A closed one has an inside of its own and
  /// filling it is meaningful in its own right, whereas an open one is a detail
  /// — a tick, a cross, a pair of battery terminals — that exists to be read
  /// against the shape around it.
  static Set<SubPath> _knockedOutSubPaths(SvgIcon icon) {
    final containers = <({SubPath subPath, List<Vec2> polygon})>[];
    for (final shape in icon.shapes) {
      if (!shape.stroked || shape.filled) {
        continue;
      }
      for (final subPath in shape.path.subPaths) {
        if (subPath.closed) {
          containers.add((subPath: subPath, polygon: flattenSubPath(subPath)));
        }
      }
    }
    if (containers.isEmpty) {
      return const {};
    }

    final result = <SubPath>{};
    for (final shape in icon.shapes) {
      if (!shape.stroked) {
        continue;
      }
      for (final subPath in shape.path.subPaths) {
        final polygon = flattenSubPath(subPath);
        for (final container in containers) {
          if (identical(container.subPath, subPath)) {
            continue;
          }
          if (isPolygonInside(
            polygon,
            container.polygon,
            // A detail stroke commonly meets the outline it sits within, so a
            // point that far outside is still counted as contained.
            boundaryTolerance: shape.strokeWidth / 2,
          )) {
            result.add(subPath);
            break;
          }
        }
      }
    }
    return result;
  }

  /// Rescales a template built with a half width of one so that a half width of
  /// one now means [halfWidth] source units.
  static StrokeTemplate _scaleDirections(
    StrokeTemplate template,
    double halfWidth,
  ) => StrokeTemplate([
    for (final contour in template.contours)
      StrokeContourTemplate(
        points: [for (final point in contour.points) point.scaled(halfWidth)],
        behaviour: contour.behaviour,
        collapseTarget: contour.collapseTarget,
        // The width a hole closes at is measured in the same units as the half
        // width, so it moves the opposite way to the directions.
        emptyAtHalfWidth: switch (contour.emptyAtHalfWidth) {
          final width? when halfWidth != 0 => width / halfWidth,
          _ => null,
        },
      ),
  ]);
}
