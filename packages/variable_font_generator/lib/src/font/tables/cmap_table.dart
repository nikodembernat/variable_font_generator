import 'dart:math' as math;
import 'dart:typed_data';

import 'package:variable_font_generator/src/font/binary_writer.dart';

/// A run of consecutive code points mapping to consecutive glyph IDs.
typedef _Range = ({int startCode, int endCode, int startGlyph});

/// Builds the `cmap` table for [mapping], which maps code point to glyph ID.
///
/// Four encoding records are written, all pointing at one of two subtables: a
/// format 4 subtable covering the Basic Multilingual Plane and a format 12
/// subtable covering everything. Between them they satisfy every text stack in
/// use, including ones that only look for a Windows record and ones that only
/// look for a Unicode record.
Uint8List buildCmapTable(Map<int, int> mapping) {
  final ranges = _rangesOf(mapping);
  final basicPlane = [
    for (final range in ranges)
      if (range.startCode <= 0xFFFF)
        (
          startCode: range.startCode,
          endCode: math.min(range.endCode, 0xFFFF),
          startGlyph: range.startGlyph,
        ),
  ];

  // A format 4 subtable records its own length in sixteen bits, so a font with
  // an extraordinary number of separate ranges has to do without it. Format 12
  // then carries everything on its own.
  final format4 = _format4Length(basicPlane) > 0xFFFF
      ? null
      : _buildFormat4(basicPlane);
  final format12 = _buildFormat12(ranges);

  // Platform 0 is Unicode, platform 3 is Windows; encodings 1 and 10 on Windows
  // are the BMP and the full range, and 3 and 4 on Unicode mean the same.
  final encodings = [
    if (format4 != null) (platform: 0, encoding: 3, useFormat12: false),
    (platform: 0, encoding: 4, useFormat12: true),
    if (format4 != null) (platform: 3, encoding: 1, useFormat12: false),
    (platform: 3, encoding: 10, useFormat12: true),
  ];

  final headerLength = 4 + encodings.length * 8;
  final format4Offset = headerLength;
  final format12Offset = headerLength + (format4?.length ?? 0);

  final writer = BinaryWriter(format12Offset + format12.length)
    ..uint16(0) // version
    ..uint16(encodings.length);
  for (final record in encodings) {
    writer
      ..uint16(record.platform)
      ..uint16(record.encoding)
      ..uint32(record.useFormat12 ? format12Offset : format4Offset);
  }
  if (format4 != null) {
    writer.bytes(format4);
  }
  writer.bytes(format12);
  return writer.toBytes();
}

/// Groups [mapping] into runs where both the code point and the glyph ID
/// advance by one, which is the shape both subtable formats compress well.
List<_Range> _rangesOf(Map<int, int> mapping) {
  final codePoints = mapping.keys.toList()..sort();
  final ranges = <_Range>[];
  for (final codePoint in codePoints) {
    final glyph = mapping[codePoint]!;
    if (ranges.isNotEmpty) {
      final last = ranges.last;
      if (codePoint == last.endCode + 1 &&
          glyph == last.startGlyph + (last.endCode - last.startCode) + 1) {
        ranges[ranges.length - 1] = (
          startCode: last.startCode,
          endCode: codePoint,
          startGlyph: last.startGlyph,
        );
        continue;
      }
    }
    ranges.add((startCode: codePoint, endCode: codePoint, startGlyph: glyph));
  }
  return ranges;
}

/// How long a format 4 subtable covering [ranges] would be.
int _format4Length(List<_Range> ranges) => 16 + (ranges.length + 1) * 8;

/// Builds a format 4 subtable, the segmented mapping every Windows text stack
/// still expects to find.
Uint8List _buildFormat4(List<_Range> ranges) {
  // The final segment mapping 0xFFFF to nothing is mandatory.
  final segments = [
    ...ranges,
    (startCode: 0xFFFF, endCode: 0xFFFF, startGlyph: 0),
  ];
  final segCount = segments.length;
  final searchRange = 2 * _largestPowerOfTwoNotExceeding(segCount);
  final entrySelector = _log2(searchRange ~/ 2);

  final writer = BinaryWriter(16 + segCount * 8)
    ..uint16(4)
    ..uint16(0) // length, patched below
    ..uint16(0) // language
    ..uint16(segCount * 2)
    ..uint16(searchRange)
    ..uint16(entrySelector)
    ..uint16(segCount * 2 - searchRange);
  for (final segment in segments) {
    writer.uint16(segment.endCode);
  }
  writer.uint16(0); // reservedPad
  for (final segment in segments) {
    writer.uint16(segment.startCode);
  }
  for (final segment in segments) {
    if (segment.startCode == 0xFFFF) {
      writer.int16(1);
    } else {
      // The delta is added to the code point modulo 65536 to give the glyph ID.
      final delta = (segment.startGlyph - segment.startCode) % 65536;
      writer.uint16(delta);
    }
  }
  for (var index = 0; index < segCount; index++) {
    // Zero means "use idDelta"; the glyph ID array stays empty because every
    // segment maps consecutively by construction.
    writer.uint16(0);
  }
  writer.patchUint16(2, writer.length);
  return writer.toBytes();
}

/// Builds a format 12 subtable, which unlike format 4 can reach beyond the
/// Basic Multilingual Plane.
Uint8List _buildFormat12(List<_Range> ranges) {
  final writer = BinaryWriter(16 + ranges.length * 12)
    ..uint16(12)
    ..uint16(0) // reserved
    ..uint32(16 + ranges.length * 12) // length
    ..uint32(0) // language
    ..uint32(ranges.length);
  for (final range in ranges) {
    writer
      ..uint32(range.startCode)
      ..uint32(range.endCode)
      ..uint32(range.startGlyph);
  }
  return writer.toBytes();
}

int _largestPowerOfTwoNotExceeding(int value) {
  var result = 1;
  while (result * 2 <= value) {
    result *= 2;
  }
  return result;
}

int _log2(int value) {
  var result = 0;
  var remaining = value;
  while (remaining > 1) {
    remaining ~/= 2;
    result++;
  }
  return result;
}
