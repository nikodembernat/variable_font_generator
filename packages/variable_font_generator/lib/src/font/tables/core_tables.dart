import 'dart:typed_data';

import 'package:variable_font_generator/src/font/binary_writer.dart';
import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/font/glyph.dart';

/// The magic number every `head` table has to carry.
const headMagicNumber = 0x5F0F3CF5;

/// Seconds between the Macintosh epoch of 1904-01-01 and the Unix epoch.
const _macEpochOffset = 2082844800;

/// Builds the `head` table.
///
/// The `checkSumAdjustment` field is written as zero here and patched
/// afterwards, once the checksum of the whole file is known. See
/// [headCheckSumAdjustmentOffset].
Uint8List buildHeadTable({
  required FontMetrics metrics,
  required double fontRevision,
  required int xMin,
  required int yMin,
  required int xMax,
  required int yMax,
  required bool longLocaFormat,
  required DateTime created,
  required DateTime modified,
}) {
  final writer = BinaryWriter(54)
    ..uint16(1) // majorVersion
    ..uint16(0) // minorVersion
    ..fixed(fontRevision)
    ..uint32(0) // checkSumAdjustment, patched later
    ..uint32(headMagicNumber)
    // Bit 0: the baseline sits at y = 0. Bit 1: the left side bearing point
    // sits at x = 0. Both hold for this generator's glyphs.
    ..uint16(0x0003)
    ..uint16(metrics.unitsPerEm)
    ..int64(created.millisecondsSinceEpoch ~/ 1000 + _macEpochOffset)
    ..int64(modified.millisecondsSinceEpoch ~/ 1000 + _macEpochOffset)
    ..int16(xMin)
    ..int16(yMin)
    ..int16(xMax)
    ..int16(yMax)
    ..uint16(0) // macStyle: neither bold nor italic
    ..uint16(8) // lowestRecPPEM
    ..int16(2) // fontDirectionHint, deprecated but conventionally 2
    ..int16(longLocaFormat ? 1 : 0)
    ..int16(0); // glyphDataFormat
  return writer.toBytes();
}

/// The offset of `checkSumAdjustment` inside the `head` table.
const headCheckSumAdjustmentOffset = 8;

/// Builds the `hhea` table.
Uint8List buildHheaTable({
  required FontMetrics metrics,
  required int advanceWidthMax,
  required int minLeftSideBearing,
  required int minRightSideBearing,
  required int xMaxExtent,
  required int numberOfHMetrics,
}) =>
    (BinaryWriter(36)
          ..uint16(1) // majorVersion
          ..uint16(0) // minorVersion
          ..int16(metrics.ascender)
          ..int16(metrics.descender)
          ..int16(metrics.lineGap)
          ..uint16(advanceWidthMax)
          ..int16(minLeftSideBearing)
          ..int16(minRightSideBearing)
          ..int16(xMaxExtent)
          ..int16(1) // caretSlopeRise, upright
          ..int16(0) // caretSlopeRun
          ..int16(0) // caretOffset
          ..int16(0) // reserved
          ..int16(0) // reserved
          ..int16(0) // reserved
          ..int16(0) // reserved
          ..int16(0) // metricDataFormat
          ..uint16(numberOfHMetrics))
        .toBytes();

/// Builds the `hmtx` table with one full metric per glyph.
Uint8List buildHmtxTable(List<VariableGlyph> glyphs) {
  final writer = BinaryWriter(glyphs.length * 4);
  for (final glyph in glyphs) {
    final bounds = glyph.defaultOutline.bounds;
    writer
      ..uint16(glyph.advanceWidth)
      ..int16(bounds == null ? 0 : bounds.minX.round());
  }
  return writer.toBytes();
}

/// Builds the `maxp` table for a font with TrueType outlines.
Uint8List buildMaxpTable({
  required int numGlyphs,
  required int maxPoints,
  required int maxContours,
}) =>
    (BinaryWriter(32)
          ..uint32(0x00010000) // version 1.0
          ..uint16(numGlyphs)
          ..uint16(maxPoints)
          ..uint16(maxContours)
          ..uint16(0) // maxCompositePoints
          ..uint16(0) // maxCompositeContours
          ..uint16(2) // maxZones
          ..uint16(0) // maxTwilightPoints
          ..uint16(0) // maxStorage
          ..uint16(0) // maxFunctionDefs
          ..uint16(0) // maxInstructionDefs
          ..uint16(0) // maxStackElements
          ..uint16(0) // maxSizeOfInstructions
          ..uint16(0) // maxComponentElements
          ..uint16(0)) // maxComponentDepth
        .toBytes();

/// Builds the `post` table, version 2.0, which carries glyph names.
///
/// Names make a generated font far easier to inspect: `ttx` and every other
/// tool can then say `house` instead of `glyph00123`. The 258 standard
/// Macintosh names are not used, so every glyph gets its own Pascal string.
Uint8List buildPostTable({
  required List<VariableGlyph> glyphs,
  required int underlinePosition,
  required int underlineThickness,
}) {
  final writer = BinaryWriter(1024)
    ..uint32(0x00020000) // version 2.0
    ..fixed(0) // italicAngle
    ..int16(underlinePosition)
    ..int16(underlineThickness)
    ..uint32(0) // isFixedPitch
    ..uint32(0) // minMemType42
    ..uint32(0) // maxMemType42
    ..uint32(0) // minMemType1
    ..uint32(0) // maxMemType1
    ..uint16(glyphs.length);

  final names = <String>[];
  final used = <String>{};
  for (final glyph in glyphs) {
    var name = _postScriptGlyphName(glyph.name);
    if (!used.add(name)) {
      var suffix = 1;
      while (!used.add('$name.$suffix')) {
        suffix++;
      }
      name = '$name.$suffix';
    }
    writer.uint16(258 + names.length);
    names.add(name);
  }
  for (final name in names) {
    writer
      ..uint8(name.length)
      ..bytes(name.codeUnits);
  }
  return writer.toBytes();
}

/// Reduces [name] to the characters a PostScript glyph name may contain.
String _postScriptGlyphName(String name) {
  final buffer = StringBuffer();
  for (final unit in name.codeUnits) {
    final isLetter =
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isAllowed = unit == 0x2E || unit == 0x5F; // '.' and '_'
    if (isLetter || isDigit || isAllowed) {
      buffer.writeCharCode(unit);
    } else {
      buffer.write('_');
    }
  }
  var result = buffer.toString();
  if (result.isEmpty) {
    result = 'glyph';
  }
  // A name may not start with a digit, and is limited to 63 characters.
  if (result.codeUnitAt(0) >= 0x30 && result.codeUnitAt(0) <= 0x39) {
    result = '_$result';
  }
  return result.length <= 63 ? result : result.substring(0, 63);
}
