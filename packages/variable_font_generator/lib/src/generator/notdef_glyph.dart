import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/geometry/outline.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// Builds the outline of glyph zero, the one shown when a code point has no
/// glyph of its own.
///
/// Drawing a hollow rectangle rather than leaving it blank is what makes a
/// missing icon visible instead of silently absent, which is worth a great deal
/// when a code point in an application has drifted out of step with the font.
Outline buildNotdefOutline(FontMetrics metrics) {
  final em = metrics.unitsPerEm.toDouble();
  final left = em * 0.1;
  final right = em * 0.9;
  final bottom = metrics.descender + em * 0.08;
  final top = metrics.ascender - em * 0.08;
  final inset = em * 0.06;

  Contour rectangle(
    double x0,
    double y0,
    double x1,
    double y1, {
    required bool clockwise,
  }) {
    final corners = [Vec2(x0, y0), Vec2(x0, y1), Vec2(x1, y1), Vec2(x1, y0)];
    return Contour([
      for (final corner in clockwise ? corners.reversed : corners)
        OutlinePoint(corner, onCurve: true),
    ]);
  }

  return Outline([
    rectangle(left, bottom, right, top, clockwise: false),
    rectangle(
      left + inset,
      bottom + inset,
      right - inset,
      top - inset,
      clockwise: true,
    ),
  ]);
}
