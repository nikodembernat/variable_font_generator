import 'dart:math' as math;
import 'dart:typed_data';

import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/generator/icon_axes.dart';
import 'package:variable_font_generator/src/generator/icon_outline_builder.dart';
import 'package:variable_font_generator/src/raster/coverage_bitmap.dart';
import 'package:variable_font_generator/src/raster/png.dart';
import 'package:variable_font_generator/src/raster/rasterizer.dart';
import 'package:variable_font_generator/src/svg/svg_icon.dart';
import 'package:variable_font_generator/src/variations/variation_model.dart';

/// One column of a preview sheet: a name and the design-space position it draws
/// the icons at.
typedef PreviewColumn = ({String label, AxisLocation location});

/// Renders a contact sheet showing a sample of [icons] at several points in the
/// design space.
///
/// Reading numbers out of a font tells you the tables are right; looking at the
/// icons tells you the artwork is. The sheet puts one icon per row and one
/// design-space position per column, so a weight that has gone wrong or a fill
/// that has not closed shows up at a glance.
Uint8List renderPreviewSheet({
  required List<SvgIcon> icons,
  required IconAxisSet axisSet,
  FontMetrics metrics = const FontMetrics(),
  double curveTolerance = 1,
  int cellSize = 96,
  int maxRows = 24,
  List<PreviewColumn>? columns,
}) {
  final builder = IconOutlineBuilder(
    metrics: metrics,
    curveTolerance: curveTolerance,
  );
  final positions = columns ?? defaultPreviewColumns(axisSet);
  final rows = math.min(icons.length, maxRows);
  final step = icons.length <= maxRows ? 1 : (icons.length / maxRows).floor();

  final width = cellSize * positions.length;
  final height = cellSize * rows;
  final sheet = CoverageBitmap.empty(width, height);
  const rasterizer = Rasterizer();
  final transform = Rasterizer.transformFor(
    minX: 0,
    minY: metrics.descender.toDouble(),
    maxX: metrics.unitsPerEm.toDouble(),
    maxY: metrics.ascender.toDouble(),
    width: cellSize,
    height: cellSize,
  );

  for (var row = 0; row < rows; row++) {
    final template = builder.build(icons[row * step]);
    for (var column = 0; column < positions.length; column++) {
      final resolved = axisSet.resolve(positions[column].location);
      final cell = rasterizer.rasterize(
        template.evaluate(
          strokeScale: resolved.strokeScale,
          fill: resolved.fill,
          widthScale: resolved.widthScale,
          horizontalCentre: metrics.unitsPerEm / 2,
        ),
        width: cellSize,
        height: cellSize,
        transform: transform,
      );
      for (var y = 0; y < cellSize; y++) {
        final source = y * cellSize;
        final target = (row * cellSize + y) * width + column * cellSize;
        sheet.pixels.setRange(target, target + cellSize, cell.pixels, source);
      }
    }
  }
  return encodeCoverageAsPng(sheet);
}

/// The design-space positions a preview shows by default: the extremes of every
/// axis, plus the default.
List<PreviewColumn> defaultPreviewColumns(IconAxisSet axisSet) => [
  (label: 'default', location: const {}),
  for (final axis in axisSet.axes) ...[
    if (axis.axis.minimum < axis.axis.defaultValue)
      (label: '${axis.axis.tag} min', location: {axis.axis.tag: -1.0}),
    if (axis.axis.maximum > axis.axis.defaultValue)
      (label: '${axis.axis.tag} max', location: {axis.axis.tag: 1.0}),
  ],
];
