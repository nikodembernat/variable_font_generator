import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/font/binary_reader.dart';
import 'package:variable_font_generator/src/font/tables/gvar_table.dart';
import 'package:variable_font_generator/src/geometry/outline.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';
import 'package:variable_font_generator/src/variations/font_axis.dart';
import 'package:variable_font_generator/src/variations/variation_model.dart';

/// Thrown when a font file cannot be parsed.
final class FontParseException implements Exception {
  /// Creates an exception describing what went wrong.
  const FontParseException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'FontParseException: $message';
}

/// Where a table sits inside a font file.
typedef TableRecord = ({int offset, int length, int checkSum});

/// One master's contribution to one glyph, as read back out of `gvar`.
typedef ParsedTuple = ({
  MasterSupport support,
  List<int>? pointNumbers,
  List<PointDelta> deltas,
});

/// Reads a TrueType font back out of its bytes.
///
/// This exists so that the package can check its own work without depending on
/// anything else: a test builds a font, parses it with this reader, applies the
/// variations at a chosen point in the design space and compares the result
/// against the outlines that went in. A mistake in the writer would have to be
/// mirrored by exactly the same mistake here to go unnoticed, and the two are
/// written from opposite ends of the format.
@immutable
final class ParsedFont {
  const ParsedFont._({
    required this.bytes,
    required this.tables,
    required this.unitsPerEm,
    required this.indexToLocFormat,
    required this.numGlyphs,
    required this.ascender,
    required this.descender,
    required this.lineGap,
    required this.advanceWidths,
    required this.leftSideBearings,
    required this.characterMap,
    required this.axes,
    required this.glyphNames,
    required this.glyphOutlines,
    required this.glyphVariations,
  });

  /// Parses [bytes] as a font file.
  factory ParsedFont.parse(Uint8List bytes) {
    final reader = BinaryReader(bytes);
    final version = reader.uint32();
    if (version != 0x00010000 && version != 0x74727565) {
      throw FontParseException(
        'Not a TrueType font: version 0x${version.toRadixString(16)}',
      );
    }
    final tableCount = reader.uint16();
    reader.offset += 6; // searchRange, entrySelector, rangeShift
    final tables = <String, TableRecord>{};
    for (var index = 0; index < tableCount; index++) {
      final tag = reader.tag();
      final checkSum = reader.uint32();
      final offset = reader.uint32();
      final length = reader.uint32();
      tables[tag] = (offset: offset, length: length, checkSum: checkSum);
    }

    BinaryReader at(String tag, [int extra = 0]) {
      final record = tables[tag];
      if (record == null) {
        throw FontParseException('The font has no $tag table');
      }
      return BinaryReader(bytes, record.offset + extra);
    }

    final unitsPerEm = at('head', 18).uint16();
    final indexToLocFormat = at('head', 50).int16();
    final numGlyphs = at('maxp', 4).uint16();
    final hhea = at('hhea', 4);
    final ascender = hhea.int16();
    final descender = hhea.int16();
    final lineGap = hhea.int16();
    final numberOfHMetrics = at('hhea', 34).uint16();

    final advanceWidths = <int>[];
    final leftSideBearings = <int>[];
    final hmtx = at('hmtx');
    var lastAdvance = 0;
    for (var index = 0; index < numGlyphs; index++) {
      if (index < numberOfHMetrics) {
        lastAdvance = hmtx.uint16();
        advanceWidths.add(lastAdvance);
        leftSideBearings.add(hmtx.int16());
      } else {
        advanceWidths.add(lastAdvance);
        leftSideBearings.add(hmtx.int16());
      }
    }

    final locations = _readLoca(
      at('loca'),
      numGlyphs: numGlyphs,
      long: indexToLocFormat == 1,
    );
    final glyfStart = tables['glyf']!.offset;
    final glyphOutlines = [
      for (var index = 0; index < numGlyphs; index++)
        if (locations[index] == locations[index + 1])
          Outline.empty
        else
          _readGlyph(BinaryReader(bytes, glyfStart + locations[index])),
    ];

    final axes = tables.containsKey('fvar')
        ? _readFvar(at('fvar'), tables['fvar']!.offset)
        : const <FontAxis>[];

    return ParsedFont._(
      bytes: bytes,
      tables: tables,
      unitsPerEm: unitsPerEm,
      indexToLocFormat: indexToLocFormat,
      numGlyphs: numGlyphs,
      ascender: ascender,
      descender: descender,
      lineGap: lineGap,
      advanceWidths: advanceWidths,
      leftSideBearings: leftSideBearings,
      characterMap: _readCmap(at('cmap'), tables['cmap']!.offset),
      axes: axes,
      glyphNames: tables.containsKey('post')
          ? _readPostNames(at('post'), numGlyphs)
          : [for (var index = 0; index < numGlyphs; index++) 'glyph$index'],
      glyphOutlines: glyphOutlines,
      glyphVariations: tables.containsKey('gvar')
          ? _readGvar(bytes, tables['gvar']!.offset, axes, numGlyphs)
          : [for (var index = 0; index < numGlyphs; index++) const []],
    );
  }

  /// The bytes the font was parsed from.
  final Uint8List bytes;

  /// Where each table sits, keyed by tag.
  final Map<String, TableRecord> tables;

  /// The design grid resolution.
  final int unitsPerEm;

  /// Zero when `loca` stores halved 16 bit offsets, one when it stores 32 bit
  /// ones.
  final int indexToLocFormat;

  /// How many glyphs the font has.
  final int numGlyphs;

  /// The ascender from `hhea`.
  final int ascender;

  /// The descender from `hhea`, as a negative number.
  final int descender;

  /// The line gap from `hhea`.
  final int lineGap;

  /// Each glyph's advance width.
  final List<int> advanceWidths;

  /// Each glyph's left side bearing.
  final List<int> leftSideBearings;

  /// Which glyph each code point maps to.
  final Map<int, int> characterMap;

  /// The variation axes, in font order.
  final List<FontAxis> axes;

  /// Each glyph's name from the `post` table.
  final List<String> glyphNames;

  /// Each glyph's outline at the default instance.
  final List<Outline> glyphOutlines;

  /// Each glyph's variation tuples.
  final List<List<ParsedTuple>> glyphVariations;

  /// Whether the font carries variations.
  bool get isVariable => axes.isNotEmpty && tables.containsKey('gvar');

  /// The glyph a code point maps to, or zero when it maps to nothing.
  int glyphIdFor(int codePoint) => characterMap[codePoint] ?? 0;

  /// The outline of [glyphId] at the design-space position [axisValues], which
  /// is given in user coordinates keyed by axis tag.
  ///
  /// Axes left out sit at their default. This walks the same path a rasteriser
  /// does: work out how strongly each tuple applies, scale its deltas by that,
  /// fill in the points it does not mention by interpolation, and add the lot
  /// to the default outline.
  Outline glyphOutlineAt(
    int glyphId, {
    Map<String, double> axisValues = const {},
  }) {
    final outline = glyphOutlines[glyphId];
    final tuples = glyphVariations[glyphId];
    if (tuples.isEmpty || outline.isEmpty) {
      return outline;
    }
    final location = <String, double>{
      for (final axis in axes)
        axis.tag: axis.normalize(axisValues[axis.tag] ?? axis.defaultValue),
    };

    final points = outline.allPoints;
    final total = points.length + phantomPointCount;
    final accumulated = List.filled(total, const (x: 0.0, y: 0.0));
    final contourEnds = <int>[];
    var running = 0;
    for (final contour in outline.contours) {
      running += contour.points.length;
      contourEnds.add(running - 1);
    }
    final originals = <({double x, double y})>[
      for (final point in points) (x: point.position.x, y: point.position.y),
      for (var index = 0; index < phantomPointCount; index++) (x: 0.0, y: 0.0),
    ];

    for (final tuple in tuples) {
      final scalar = VariationModel.supportScalar(location, tuple.support);
      if (scalar == 0) {
        continue;
      }
      final scaled = List<({double x, double y})?>.filled(total, null);
      final listed = tuple.pointNumbers;
      if (listed == null) {
        for (
          var index = 0;
          index < total && index < tuple.deltas.length;
          index++
        ) {
          scaled[index] = (
            x: tuple.deltas[index].x * scalar,
            y: tuple.deltas[index].y * scalar,
          );
        }
      } else {
        for (var slot = 0; slot < listed.length; slot++) {
          final index = listed[slot];
          if (index < total) {
            scaled[index] = (
              x: tuple.deltas[slot].x * scalar,
              y: tuple.deltas[slot].y * scalar,
            );
          }
        }
      }
      final resolved = _interpolateUntouched(
        scaled,
        originals,
        contourEnds,
        total,
      );
      for (var index = 0; index < total; index++) {
        accumulated[index] = (
          x: accumulated[index].x + resolved[index].x,
          y: accumulated[index].y + resolved[index].y,
        );
      }
    }

    var index = 0;
    return Outline([
      for (final contour in outline.contours)
        Contour([
          for (final point in contour.points)
            OutlinePoint(
              Vec2(
                point.position.x + accumulated[index].x,
                point.position.y + accumulated[index++].y,
              ),
              onCurve: point.onCurve,
            ),
        ]),
    ]);
  }

  @override
  String toString() =>
      'ParsedFont($numGlyphs glyphs, ${axes.length} axes, '
      '${tables.length} tables)';
}

/// Fills in the deltas of points a tuple did not mention.
///
/// A point between two moved points follows them, in proportion to where it sat
/// between them to begin with; a point beyond the last moved one simply moves
/// with it. A contour where nothing moved stays put. This is the rule
/// rasterisers apply, and it is why a tuple that moves part of a contour must
/// list the whole of it.
List<({double x, double y})> _interpolateUntouched(
  List<({double x, double y})?> deltas,
  List<({double x, double y})> originals,
  List<int> contourEnds,
  int total,
) {
  final result = List<({double x, double y})>.filled(total, const (
    x: 0.0,
    y: 0.0,
  ));
  final groups = <({int start, int end})>[
    for (var index = 0; index < contourEnds.length; index++)
      (
        start: index == 0 ? 0 : contourEnds[index - 1] + 1,
        end: contourEnds[index],
      ),
    if (contourEnds.isNotEmpty && contourEnds.last < total - 1)
      (start: contourEnds.last + 1, end: total - 1),
  ];

  for (final group in groups) {
    final touched = <int>[
      for (var index = group.start; index <= group.end; index++)
        if (deltas[index] != null) index,
    ];
    if (touched.isEmpty) {
      continue;
    }
    if (touched.length == 1) {
      final delta = deltas[touched.single]!;
      for (var index = group.start; index <= group.end; index++) {
        result[index] = delta;
      }
      continue;
    }
    for (final index in touched) {
      result[index] = deltas[index]!;
    }
    final count = group.end - group.start + 1;
    for (var slot = 0; slot < touched.length; slot++) {
      final before = touched[slot];
      final after = touched[(slot + 1) % touched.length];
      var index = before + 1;
      if (index > group.end) {
        index = group.start;
      }
      while (index != after) {
        result[index] = (
          x: _interpolateOne(
            originals[index].x,
            originals[before].x,
            originals[after].x,
            deltas[before]!.x,
            deltas[after]!.x,
          ),
          y: _interpolateOne(
            originals[index].y,
            originals[before].y,
            originals[after].y,
            deltas[before]!.y,
            deltas[after]!.y,
          ),
        );
        index++;
        if (index > group.end) {
          index = group.start;
        }
      }
      if (count == touched.length) {
        break;
      }
    }
  }
  return result;
}

double _interpolateOne(
  double value,
  double beforeValue,
  double afterValue,
  double beforeDelta,
  double afterDelta,
) {
  var lowValue = beforeValue;
  var highValue = afterValue;
  var lowDelta = beforeDelta;
  var highDelta = afterDelta;
  if (lowValue > highValue) {
    lowValue = afterValue;
    highValue = beforeValue;
    lowDelta = afterDelta;
    highDelta = beforeDelta;
  }
  if (value <= lowValue) {
    return lowDelta;
  }
  if (value >= highValue) {
    return highDelta;
  }
  if (highValue == lowValue) {
    return lowDelta;
  }
  final t = (value - lowValue) / (highValue - lowValue);
  return lowDelta + t * (highDelta - lowDelta);
}

List<int> _readLoca(
  BinaryReader reader, {
  required int numGlyphs,
  required bool long,
}) => [
  for (var index = 0; index <= numGlyphs; index++)
    if (long) reader.uint32() else reader.uint16() * 2,
];

Outline _readGlyph(BinaryReader reader) {
  final contourCount = reader.int16();
  reader.offset += 8; // The bounding box, which we recompute anyway.
  if (contourCount < 0) {
    throw const FontParseException(
      'Composite glyphs are not supported; this package never writes them',
    );
  }
  final endPoints = [
    for (var index = 0; index < contourCount; index++) reader.uint16(),
  ];
  final pointCount = endPoints.isEmpty ? 0 : endPoints.last + 1;
  // Reading the length has to happen before the skip: a compound assignment
  // captures the left-hand side first, so combining the two would rewind over
  // the length field itself.
  final instructionLength = reader.uint16();
  reader.offset += instructionLength;

  final flags = <int>[];
  while (flags.length < pointCount) {
    final flag = reader.uint8();
    flags.add(flag);
    if (flag & 0x08 != 0) {
      final repeats = reader.uint8();
      for (var index = 0; index < repeats; index++) {
        flags.add(flag);
      }
    }
  }

  final xs = <int>[];
  var x = 0;
  for (final flag in flags) {
    if (flag & 0x02 != 0) {
      final value = reader.uint8();
      x += flag & 0x10 != 0 ? value : -value;
    } else if (flag & 0x10 == 0) {
      x += reader.int16();
    }
    xs.add(x);
  }
  final ys = <int>[];
  var y = 0;
  for (final flag in flags) {
    if (flag & 0x04 != 0) {
      final value = reader.uint8();
      y += flag & 0x20 != 0 ? value : -value;
    } else if (flag & 0x20 == 0) {
      y += reader.int16();
    }
    ys.add(y);
  }

  final contours = <Contour>[];
  var start = 0;
  for (final end in endPoints) {
    contours.add(
      Contour([
        for (var index = start; index <= end; index++)
          OutlinePoint(
            Vec2(xs[index].toDouble(), ys[index].toDouble()),
            onCurve: flags[index] & 0x01 != 0,
          ),
      ]),
    );
    start = end + 1;
  }
  return Outline(contours);
}

Map<int, int> _readCmap(BinaryReader reader, int tableStart) {
  reader.offset += 2; // version
  final recordCount = reader.uint16();
  var best = -1;
  var bestScore = -1;
  for (var index = 0; index < recordCount; index++) {
    final platform = reader.uint16();
    final encoding = reader.uint16();
    final offset = reader.uint32();
    // Prefer the subtable that can reach beyond the Basic Multilingual Plane.
    final score = switch ((platform, encoding)) {
      (3, 10) => 4,
      (0, 4) => 3,
      (3, 1) => 2,
      (0, 3) => 1,
      _ => 0,
    };
    if (score > bestScore) {
      bestScore = score;
      best = tableStart + offset;
    }
  }
  if (best < 0) {
    throw const FontParseException('The cmap table has no usable subtable');
  }

  final subtable = BinaryReader(reader.data, best);
  final format = subtable.uint16();
  final result = <int, int>{};
  switch (format) {
    case 4:
      subtable.offset += 4; // length, language
      final segCount = subtable.uint16() ~/ 2;
      subtable.offset += 6; // searchRange, entrySelector, rangeShift
      final endCodes = [
        for (var index = 0; index < segCount; index++) subtable.uint16(),
      ];
      subtable.offset += 2; // reservedPad
      final startCodes = [
        for (var index = 0; index < segCount; index++) subtable.uint16(),
      ];
      final deltas = [
        for (var index = 0; index < segCount; index++) subtable.uint16(),
      ];
      final rangeOffsetsAt = subtable.offset;
      final rangeOffsets = [
        for (var index = 0; index < segCount; index++) subtable.uint16(),
      ];
      for (var segment = 0; segment < segCount; segment++) {
        if (startCodes[segment] == 0xFFFF) {
          continue;
        }
        for (
          var code = startCodes[segment];
          code <= endCodes[segment];
          code++
        ) {
          final int glyph;
          if (rangeOffsets[segment] == 0) {
            glyph = (code + deltas[segment]) % 65536;
          } else {
            final at =
                rangeOffsetsAt +
                segment * 2 +
                rangeOffsets[segment] +
                (code - startCodes[segment]) * 2;
            final raw = BinaryReader(subtable.data, at).uint16();
            glyph = raw == 0 ? 0 : (raw + deltas[segment]) % 65536;
          }
          if (glyph != 0) {
            result[code] = glyph;
          }
        }
      }
    case 12:
      subtable.offset += 10; // reserved, length, language
      final groupCount = subtable.uint32();
      for (var index = 0; index < groupCount; index++) {
        final startCode = subtable.uint32();
        final endCode = subtable.uint32();
        final startGlyph = subtable.uint32();
        for (var code = startCode; code <= endCode; code++) {
          result[code] = startGlyph + (code - startCode);
        }
      }
    default:
      throw FontParseException('Unsupported cmap subtable format $format');
  }
  return result;
}

List<FontAxis> _readFvar(BinaryReader reader, int tableStart) {
  reader.offset += 4; // major and minor version
  final axesOffset = reader.uint16();
  reader.offset += 2; // reserved
  final axisCount = reader.uint16();
  final axisSize = reader.uint16();
  final axes = <FontAxis>[];
  for (var index = 0; index < axisCount; index++) {
    final axis = BinaryReader(
      reader.data,
      tableStart + axesOffset + index * axisSize,
    );
    final tag = axis.tag();
    final minimum = axis.fixed();
    final defaultValue = axis.fixed();
    final maximum = axis.fixed();
    final flags = axis.uint16();
    axis.offset += 2; // axisNameID
    axes.add(
      FontAxis(
        tag: tag,
        name: tag,
        minimum: minimum,
        defaultValue: defaultValue,
        maximum: maximum,
        hidden: flags & 0x0001 != 0,
      ),
    );
  }
  return axes;
}

List<String> _readPostNames(BinaryReader reader, int numGlyphs) {
  final version = reader.uint32();
  if (version != 0x00020000) {
    return [for (var index = 0; index < numGlyphs; index++) 'glyph$index'];
  }
  reader.offset += 28; // The rest of the version 1.0 header.
  final count = reader.uint16();
  final indices = [for (var index = 0; index < count; index++) reader.uint16()];
  final names = <String>[];
  while (!reader.isAtEnd) {
    final length = reader.uint8();
    if (reader.remaining < length) {
      break;
    }
    names.add(ascii.decode(reader.take(length)));
  }
  return [
    for (final index in indices)
      if (index >= 258 && index - 258 < names.length)
        names[index - 258]
      else
        '.glyph$index',
  ];
}

List<List<ParsedTuple>> _readGvar(
  Uint8List bytes,
  int tableStart,
  List<FontAxis> axes,
  int numGlyphs,
) {
  final reader = BinaryReader(bytes, tableStart)
    ..offset += 4; // major and minor version
  final axisCount = reader.uint16();
  final sharedTupleCount = reader.uint16();
  final sharedTuplesOffset = reader.uint32();
  final glyphCount = reader.uint16();
  final flags = reader.uint16();
  final dataArrayOffset = reader.uint32();
  final longOffsets = flags & 0x0001 != 0;
  final offsets = [
    for (var index = 0; index <= glyphCount; index++)
      if (longOffsets) reader.uint32() else reader.uint16() * 2,
  ];

  final sharedTuples = <List<double>>[];
  final shared = BinaryReader(bytes, tableStart + sharedTuplesOffset);
  for (var index = 0; index < sharedTupleCount; index++) {
    sharedTuples.add([
      for (var axis = 0; axis < axisCount; axis++) shared.f2dot14(),
    ]);
  }

  final result = <List<ParsedTuple>>[];
  for (var glyph = 0; glyph < numGlyphs; glyph++) {
    if (glyph >= glyphCount || offsets[glyph] == offsets[glyph + 1]) {
      result.add(const []);
      continue;
    }
    result.add(
      _readGlyphVariationData(
        BinaryReader(bytes, tableStart + dataArrayOffset + offsets[glyph]),
        axes,
        sharedTuples,
        axisCount,
      ),
    );
  }
  return result;
}

/// A tuple variation header, with its region already resolved.
typedef _TupleHeader = ({
  int size,
  List<double> peak,
  List<double> start,
  List<double> end,
  bool private,
});

List<ParsedTuple> _readGlyphVariationData(
  BinaryReader reader,
  List<FontAxis> axes,
  List<List<double>> sharedTuples,
  int axisCount,
) {
  final start = reader.offset;
  final tupleCount = reader.uint16();
  final dataOffset = reader.uint16();
  final count = tupleCount & 0x0FFF;
  final hasSharedPoints = tupleCount & 0x8000 != 0;

  final headers = <_TupleHeader>[];
  for (var index = 0; index < count; index++) {
    final size = reader.uint16();
    final tupleIndex = reader.uint16();
    final embedded = tupleIndex & 0x8000 != 0;
    final intermediate = tupleIndex & 0x4000 != 0;
    final private = tupleIndex & 0x2000 != 0;
    final peak = embedded
        ? [for (var axis = 0; axis < axisCount; axis++) reader.f2dot14()]
        : sharedTuples[tupleIndex & 0x0FFF];
    List<double>? regionStart;
    List<double>? regionEnd;
    if (intermediate) {
      regionStart = [
        for (var axis = 0; axis < axisCount; axis++) reader.f2dot14(),
      ];
      regionEnd = [
        for (var axis = 0; axis < axisCount; axis++) reader.f2dot14(),
      ];
    }
    headers.add((
      size: size,
      peak: peak,
      // Without an explicit region, a tuple applies from the default out to its
      // peak and no further, which is the shape the specification implies.
      start:
          regionStart ??
          [
            for (final value in peak)
              if (value < 0) value else 0.0,
          ],
      end:
          regionEnd ??
          [
            for (final value in peak)
              if (value > 0) value else 0.0,
          ],
      private: private,
    ));
  }

  var cursor = start + dataOffset;
  List<int>? sharedPoints;
  if (hasSharedPoints) {
    final points = _readPointNumbers(BinaryReader(reader.data, cursor));
    sharedPoints = points.numbers;
    cursor = points.next;
  }

  final tuples = <ParsedTuple>[];
  for (final header in headers) {
    final body = BinaryReader(reader.data, cursor);
    var pointNumbers = sharedPoints;
    if (header.private) {
      final points = _readPointNumbers(body);
      pointNumbers = points.numbers;
      body.offset = points.next;
    }
    final deltaCount = pointNumbers?.length;
    final xs = _readPackedDeltas(body, deltaCount);
    final ys = _readPackedDeltas(body, deltaCount ?? xs.length);
    cursor += header.size;

    tuples.add((
      support: {
        for (var axis = 0; axis < axes.length && axis < axisCount; axis++)
          if (header.peak[axis] != 0 ||
              header.start[axis] != 0 ||
              header.end[axis] != 0)
            axes[axis].tag: (
              start: header.start[axis],
              peak: header.peak[axis],
              end: header.end[axis],
            ),
      },
      pointNumbers: pointNumbers,
      deltas: [
        for (var index = 0; index < xs.length && index < ys.length; index++)
          (x: xs[index], y: ys[index]),
      ],
    ));
  }
  return tuples;
}

({List<int>? numbers, int next}) _readPointNumbers(BinaryReader reader) {
  var count = reader.uint8();
  if (count & 0x80 != 0) {
    count = ((count & 0x7F) << 8) | reader.uint8();
  }
  if (count == 0) {
    // Zero means every point in the glyph, which is stored as no list at all.
    return (numbers: null, next: reader.offset);
  }
  final numbers = <int>[];
  var value = 0;
  while (numbers.length < count) {
    final control = reader.uint8();
    final runLength = (control & 0x7F) + 1;
    final asWords = control & 0x80 != 0;
    for (var index = 0; index < runLength && numbers.length < count; index++) {
      value += asWords ? reader.uint16() : reader.uint8();
      numbers.add(value);
    }
  }
  return (numbers: numbers, next: reader.offset);
}

List<int> _readPackedDeltas(BinaryReader reader, int? count) {
  final deltas = <int>[];
  while (count == null ? !reader.isAtEnd : deltas.length < count) {
    final control = reader.uint8();
    final runLength = (control & 0x3F) + 1;
    if (control & 0x80 != 0) {
      for (var index = 0; index < runLength; index++) {
        deltas.add(0);
      }
    } else if (control & 0x40 != 0) {
      for (var index = 0; index < runLength; index++) {
        deltas.add(reader.int16());
      }
    } else {
      for (var index = 0; index < runLength; index++) {
        deltas.add(reader.int8());
      }
    }
    if (count == null) {
      break;
    }
  }
  return deltas;
}
