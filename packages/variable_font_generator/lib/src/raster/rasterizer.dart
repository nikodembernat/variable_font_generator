import 'dart:math' as math;
import 'dart:typed_data';

import 'package:variable_font_generator/src/geometry/bezier.dart';
import 'package:variable_font_generator/src/geometry/outline.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';
import 'package:variable_font_generator/src/raster/coverage_bitmap.dart';

/// An edge of a flattened outline, kept in the sample space the scanline walk
/// runs in.
typedef _Edge = ({
  double minY,
  double maxY,
  double x0,
  double y0,
  double slope,
  int winding,
});

/// Renders glyph outlines into anti-aliased coverage bitmaps.
///
/// Fills with the non-zero winding rule, the rule TrueType outlines are defined
/// with. Coverage is exact horizontally — a span contributes the fraction of
/// each pixel it actually covers — and sampled [samplesPerPixel] times
/// vertically, which is accurate enough that two renderers of the same shape
/// agree to within a few percent.
final class Rasterizer {
  /// Creates a rasterizer.
  const Rasterizer({this.samplesPerPixel = 8, this.curveTolerance = 0.05});

  /// How many scanlines are sampled per pixel row.
  final int samplesPerPixel;

  /// How far, in output pixels, a flattened curve may deviate from the real
  /// one.
  final double curveTolerance;

  /// Renders [outline] into a [width] by [height] bitmap.
  ///
  /// [transform] maps outline coordinates to pixel coordinates, where Y grows
  /// downwards. Use [transformFor] to build one that fits a glyph's design
  /// space into the bitmap.
  CoverageBitmap rasterize(
    Outline outline, {
    required int width,
    required int height,
    required Vec2 Function(Vec2 point) transform,
  }) {
    final bitmap = CoverageBitmap.empty(width, height);
    final edges = _collectEdges(outline, transform);
    if (edges.isEmpty) {
      return bitmap;
    }

    final coverage = Float64List(width);
    final crossings = <({double x, int winding})>[];
    final sampleWeight = 255 / samplesPerPixel;

    for (var row = 0; row < height; row++) {
      coverage.fillRange(0, width, 0);
      var rowHasInk = false;
      for (var sample = 0; sample < samplesPerPixel; sample++) {
        final y = row + (sample + 0.5) / samplesPerPixel;
        crossings.clear();
        for (final edge in edges) {
          if (y < edge.minY || y >= edge.maxY) {
            continue;
          }
          crossings.add((
            x: edge.x0 + (y - edge.y0) * edge.slope,
            winding: edge.winding,
          ));
        }
        if (crossings.length < 2) {
          continue;
        }
        crossings.sort((a, b) => a.x.compareTo(b.x));

        var winding = 0;
        var spanStart = 0.0;
        for (final crossing in crossings) {
          final wasInside = winding != 0;
          winding += crossing.winding;
          final isInside = winding != 0;
          if (!wasInside && isInside) {
            spanStart = crossing.x;
          } else if (wasInside && !isInside) {
            rowHasInk = true;
            _accumulateSpan(coverage, spanStart, crossing.x, sampleWeight);
          }
        }
      }
      if (!rowHasInk) {
        continue;
      }
      final rowOffset = row * width;
      for (var column = 0; column < width; column++) {
        final value = coverage[column];
        if (value > 0) {
          bitmap.pixels[rowOffset + column] = value >= 255
              ? 255
              : value.round();
        }
      }
    }
    return bitmap;
  }

  /// Adds the coverage of the horizontal span from [startX] to [endX].
  static void _accumulateSpan(
    Float64List coverage,
    double startX,
    double endX,
    double weight,
  ) {
    final width = coverage.length;
    var left = startX;
    var right = endX;
    if (right <= 0 || left >= width || right <= left) {
      return;
    }
    if (left < 0) {
      left = 0;
    }
    if (right > width) {
      right = width.toDouble();
    }

    final firstColumn = left.floor();
    final lastColumn = (right.ceil() - 1).clamp(0, width - 1);
    if (firstColumn == lastColumn) {
      coverage[firstColumn] += (right - left) * weight;
      return;
    }
    coverage[firstColumn] += (firstColumn + 1 - left) * weight;
    for (var column = firstColumn + 1; column < lastColumn; column++) {
      coverage[column] += weight;
    }
    coverage[lastColumn] += (right - lastColumn) * weight;
  }

  List<_Edge> _collectEdges(
    Outline outline,
    Vec2 Function(Vec2 point) transform,
  ) {
    final edges = <_Edge>[];

    void addLine(Vec2 from, Vec2 to) {
      if (from.y == to.y) {
        return;
      }
      final winding = from.y < to.y ? 1 : -1;
      final top = winding == 1 ? from : to;
      final bottom = winding == 1 ? to : from;
      edges.add((
        minY: top.y,
        maxY: bottom.y,
        x0: top.x,
        y0: top.y,
        slope: (bottom.x - top.x) / (bottom.y - top.y),
        winding: winding,
      ));
    }

    for (final contour in outline.contours) {
      for (final segment in contour.segments) {
        final start = transform(segment.start);
        final end = transform(segment.end);
        final control = segment.control;
        if (control == null) {
          addLine(start, end);
          continue;
        }
        final curve = (start: start, control: transform(control), end: end);
        var previous = start;
        for (final point in flattenQuadratic(
          curve,
          tolerance: curveTolerance,
        )) {
          addLine(previous, point);
          previous = point;
        }
      }
    }
    return edges;
  }

  /// A transform that maps the box from ([minX], [minY]) to ([maxX], [maxY]) in
  /// a Y-up design space onto a [width] by [height] bitmap, flipping the Y axis
  /// and preserving the aspect ratio.
  static Vec2 Function(Vec2 point) transformFor({
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
    required int width,
    required int height,
  }) {
    final scale = math.min(width / (maxX - minX), height / (maxY - minY));
    final offsetX = (width - (maxX - minX) * scale) / 2;
    final offsetY = (height - (maxY - minY) * scale) / 2;
    return (point) => Vec2(
      offsetX + (point.x - minX) * scale,
      height - offsetY - (point.y - minY) * scale,
    );
  }
}
