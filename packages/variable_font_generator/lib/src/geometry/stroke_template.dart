import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/geometry/outline.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// A single outline point expressed as an affine function of the stroke's
/// width.
///
/// The position of the point is `base + direction * strokeScale`. Keeping every
/// point in this form is what lets a single icon be re-stroked at any weight
/// while producing outlines that are point-for-point identical in structure,
/// which is the precondition for storing the difference between them as `gvar`
/// deltas.
@immutable
final class StrokePointTemplate {
  /// Creates a template point.
  const StrokePointTemplate({
    required this.base,
    required this.direction,
    required this.onCurve,
  });

  /// The position the point takes at a half width of zero, which is a point on
  /// the stroke's centre line.
  final Vec2 base;

  /// How far the point moves per unit of half width.
  final Vec2 direction;

  /// Whether the point lies on the curve. See [OutlinePoint.onCurve].
  final bool onCurve;

  /// The position of this point at [strokeScale].
  Vec2 at(double strokeScale) => base + direction * strokeScale;

  @override
  String toString() => 'StrokePointTemplate($base + $direction * w)';
}

/// A contour of a [StrokeTemplate].
@immutable
final class StrokeContourTemplate {
  /// Creates a contour template.
  const StrokeContourTemplate({required this.points, this.collapseTarget});

  /// The points of the contour, in traversal order.
  final List<StrokePointTemplate> points;

  /// Where this contour shrinks to as the fill amount goes to one, or `null`
  /// for contours that are unaffected by filling.
  ///
  /// Only the inner contour of a closed, unfilled sub path collapses: pulling
  /// it onto a single point removes the hole, turning an outlined shape into a
  /// solid one. The target never depends on the stroke width, so the collapse
  /// stays well defined at every weight.
  final Vec2? collapseTarget;

  /// Whether filling closes this contour's hole.
  bool get collapsesWhenFilled => collapseTarget != null;

  /// Evaluates this contour at [strokeScale] and [fill].
  Contour evaluate({required double strokeScale, required double fill}) {
    final target = collapseTarget;
    return Contour([
      for (final point in points)
        OutlinePoint(
          target == null || fill == 0
              ? point.at(strokeScale)
              : point.at(strokeScale).lerp(target, fill),
          onCurve: point.onCurve,
        ),
    ]);
  }

  /// Returns this contour with its traversal order reversed.
  StrokeContourTemplate get reversed => StrokeContourTemplate(
    points: points.reversed.toList(),
    collapseTarget: collapseTarget,
  );

  @override
  String toString() =>
      'StrokeContourTemplate(${points.length} points, '
      'collapses: $collapsesWhenFilled)';
}

/// A glyph outline parameterised by stroke half width and fill amount.
///
/// A template is built once per icon from its centre lines. Evaluating it is
/// cheap and, crucially, always yields the same contours with the same number
/// of points in the same order, whatever arguments it is given.
@immutable
final class StrokeTemplate {
  /// Creates a template from [contours].
  const StrokeTemplate(this.contours);

  /// A template that draws nothing.
  static const empty = StrokeTemplate([]);

  /// The contours of the outline.
  final List<StrokeContourTemplate> contours;

  /// The total number of points, which is invariant across evaluations.
  int get pointCount =>
      contours.fold(0, (total, contour) => total + contour.points.length);

  /// Whether this template draws nothing.
  bool get isEmpty => contours.isEmpty;

  /// Builds the outline for the given [strokeScale] and [fill].
  ///
  /// What a stroke scale of one means depends on who built the template: a
  /// [StrokeTemplate] straight out of the stroker measures it in source units
  /// of half width, while one from an icon builder has been rescaled so that
  /// one reproduces the artwork's own stroke widths.
  ///
  /// [fill] runs from zero (holes fully open) to one (holes fully closed).
  Outline evaluate({required double strokeScale, double fill = 0}) => Outline([
    for (final contour in contours)
      contour.evaluate(strokeScale: strokeScale, fill: fill),
  ]);

  /// Returns a copy with [transform] applied to every base point, collapse
  /// target and offset direction.
  ///
  /// [transform] must be linear for the result to stay meaningful, so the
  /// translation is passed separately as [translation]. This is used to map an
  /// icon from SVG user space into font design units.
  StrokeTemplate transformed({
    required Vec2 Function(Vec2 vector) transform,
    Vec2 translation = Vec2.zero,
  }) => StrokeTemplate([
    for (final contour in contours)
      StrokeContourTemplate(
        points: [
          for (final point in contour.points)
            StrokePointTemplate(
              base: transform(point.base) + translation,
              direction: transform(point.direction),
              onCurve: point.onCurve,
            ),
        ],
        collapseTarget: switch (contour.collapseTarget) {
          final target? => transform(target) + translation,
          null => null,
        },
      ),
  ]);

  /// Returns a copy with [other]'s contours appended.
  StrokeTemplate operator +(StrokeTemplate other) =>
      StrokeTemplate([...contours, ...other.contours]);

  @override
  String toString() =>
      'StrokeTemplate(${contours.length} contours, $pointCount points)';
}
