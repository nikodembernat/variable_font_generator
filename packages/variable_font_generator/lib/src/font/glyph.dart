import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/geometry/outline.dart';

/// One glyph of a variable font: the same outline drawn once per master.
///
/// Every master must have identical structure — the same number of contours,
/// each with the same number of points in the same on- and off-curve pattern —
/// because `gvar` can only move existing points, never add or remove them.
/// [validate] checks that.
@immutable
final class VariableGlyph {
  /// Creates a glyph.
  const VariableGlyph({
    required this.name,
    required this.codePoint,
    required this.advanceWidth,
    required this.masters,
  });

  /// The glyph's name, used for the `post` table and for diagnostics.
  final String name;

  /// The code point this glyph is reached by, or `null` for glyphs that are not
  /// mapped, such as `.notdef`.
  final int? codePoint;

  /// The advance width in design units.
  final int advanceWidth;

  /// The outline at each master location, starting with the default.
  final List<Outline> masters;

  /// The outline written into `glyf`, which every delta is measured against.
  Outline get defaultOutline => masters.first;

  /// The number of points in the outline, which is the same for every master.
  int get pointCount => defaultOutline.pointCount;

  /// Throws a [StateError] when the masters do not line up.
  void validate() {
    final reference = defaultOutline;
    for (var index = 1; index < masters.length; index++) {
      final master = masters[index];
      if (master.contours.length != reference.contours.length) {
        throw StateError(
          'Glyph "$name" master $index has ${master.contours.length} contours '
          'but the default has ${reference.contours.length}',
        );
      }
      for (var c = 0; c < reference.contours.length; c++) {
        if (master.contours[c].points.length !=
            reference.contours[c].points.length) {
          throw StateError(
            'Glyph "$name" master $index contour $c has '
            '${master.contours[c].points.length} points but the default has '
            '${reference.contours[c].points.length}',
          );
        }
        for (var p = 0; p < reference.contours[c].points.length; p++) {
          if (master.contours[c].points[p].onCurve !=
              reference.contours[c].points[p].onCurve) {
            throw StateError(
              'Glyph "$name" master $index contour $c point $p is on the curve '
              'in one master and off it in another',
            );
          }
        }
      }
    }
  }

  @override
  String toString() =>
      'VariableGlyph($name, ${masters.length} masters, $pointCount points)';
}
