import 'dart:typed_data';

import 'package:variable_font_generator/src/font/binary_writer.dart';
import 'package:variable_font_generator/src/geometry/outline.dart';

/// Flag bits of a simple glyph's point records.
abstract final class GlyphFlag {
  /// The point lies on the curve rather than being a control point.
  static const onCurve = 0x01;

  /// The X delta is stored as one unsigned byte.
  static const xShort = 0x02;

  /// The Y delta is stored as one unsigned byte.
  static const yShort = 0x04;

  /// The next byte says how many more times this flag repeats.
  static const repeat = 0x08;

  /// With [xShort], the X delta is positive; without it, the X delta is zero.
  static const xSameOrPositive = 0x10;

  /// With [yShort], the Y delta is positive; without it, the Y delta is zero.
  static const ySameOrPositive = 0x20;

  /// The glyph's contours overlap each other.
  ///
  /// Stroking an icon almost always produces overlapping contours, and some
  /// rasterisers need to be told so before they will merge them instead of
  /// letting the fill rule cancel them out.
  static const overlapSimple = 0x40;
}

/// The `glyf` and `loca` tables, which are built together because `loca` is an
/// index into `glyf`.
typedef GlyfAndLoca = ({Uint8List glyf, Uint8List loca, bool longFormat});

/// Encodes [outlines] into a `glyf` table and its matching `loca` index.
///
/// Coordinates are rounded on the way in, so callers should pass outlines that
/// have already been rounded if they also need the exact values elsewhere, as
/// variation deltas do.
GlyfAndLoca buildGlyfAndLoca(List<Outline> outlines) {
  final glyf = BinaryWriter(outlines.length * 256);
  final offsets = <int>[0];
  for (final outline in outlines) {
    if (!outline.isEmpty) {
      glyf
        ..bytes(_encodeGlyph(outline))
        // Every glyph starts on a four byte boundary. That is stricter than the
        // two bytes the short `loca` format needs, and it keeps the table
        // aligned whichever format is chosen.
        ..align(4);
    }
    offsets.add(glyf.length);
  }

  final longFormat = offsets.last > 0x1FFFE;
  final loca = BinaryWriter(offsets.length * (longFormat ? 4 : 2));
  for (final offset in offsets) {
    if (longFormat) {
      loca.uint32(offset);
    } else {
      loca.uint16(offset ~/ 2);
    }
  }
  return (glyf: glyf.toBytes(), loca: loca.toBytes(), longFormat: longFormat);
}

Uint8List _encodeGlyph(Outline outline) {
  final bounds = outline.bounds!;
  final writer = BinaryWriter()
    ..int16(outline.contours.length)
    ..int16(bounds.minX.round())
    ..int16(bounds.minY.round())
    ..int16(bounds.maxX.round())
    ..int16(bounds.maxY.round());

  var pointIndex = 0;
  for (final contour in outline.contours) {
    pointIndex += contour.points.length;
    writer.uint16(pointIndex - 1);
  }
  writer.uint16(0); // instructionLength: the font carries no hinting

  final points = outline.allPoints;
  final xDeltas = <int>[];
  final yDeltas = <int>[];
  var previousX = 0;
  var previousY = 0;
  for (final point in points) {
    final x = point.position.x.round();
    final y = point.position.y.round();
    xDeltas.add(x - previousX);
    yDeltas.add(y - previousY);
    previousX = x;
    previousY = y;
  }

  // Flags, run-length encoded: a flag that repeats is written once followed by
  // a count.
  final flags = <int>[];
  for (var index = 0; index < points.length; index++) {
    var flag = points[index].onCurve ? GlyphFlag.onCurve : 0;
    final dx = xDeltas[index];
    final dy = yDeltas[index];
    if (dx == 0) {
      flag |= GlyphFlag.xSameOrPositive;
    } else if (dx >= -255 && dx <= 255) {
      flag |= GlyphFlag.xShort;
      if (dx > 0) {
        flag |= GlyphFlag.xSameOrPositive;
      }
    }
    if (dy == 0) {
      flag |= GlyphFlag.ySameOrPositive;
    } else if (dy >= -255 && dy <= 255) {
      flag |= GlyphFlag.yShort;
      if (dy > 0) {
        flag |= GlyphFlag.ySameOrPositive;
      }
    }
    if (index == 0) {
      flag |= GlyphFlag.overlapSimple;
    }
    flags.add(flag);
  }

  var index = 0;
  while (index < flags.length) {
    final flag = flags[index];
    var repeats = 0;
    while (index + repeats + 1 < flags.length &&
        flags[index + repeats + 1] == flag &&
        repeats < 255) {
      repeats++;
    }
    if (repeats > 0) {
      writer
        ..uint8(flag | GlyphFlag.repeat)
        ..uint8(repeats);
      index += repeats + 1;
    } else {
      writer.uint8(flag);
      index++;
    }
  }

  for (var i = 0; i < points.length; i++) {
    final dx = xDeltas[i];
    if (dx == 0) {
      continue;
    }
    if (dx >= -255 && dx <= 255) {
      writer.uint8(dx.abs());
    } else {
      writer.int16(dx);
    }
  }
  for (var i = 0; i < points.length; i++) {
    final dy = yDeltas[i];
    if (dy == 0) {
      continue;
    }
    if (dy >= -255 && dy <= 255) {
      writer.uint8(dy.abs());
    } else {
      writer.int16(dy);
    }
  }
  return writer.toBytes();
}
