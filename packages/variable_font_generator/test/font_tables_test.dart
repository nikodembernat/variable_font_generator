import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:variable_font_generator/src/font/tables/core_tables.dart'
    show headCheckSumAdjustmentOffset;
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// The metrics every font built here uses.
const testMetrics = FontMetrics();

/// A fixed timestamp, so a font built twice comes out byte-identical.
final testTimestamp = DateTime.utc(2000);

/// An on-curve outline point at ([x], [y]).
OutlinePoint on(double x, double y) => OutlinePoint(Vec2(x, y), onCurve: true);

/// An off-curve outline point at ([x], [y]).
OutlinePoint off(double x, double y) =>
    OutlinePoint(Vec2(x, y), onCurve: false);

/// A four point square contour with its lower left corner at ([x], [y]).
Contour square(double x, double y, double size) => Contour([
  on(x, y),
  on(x + size, y),
  on(x + size, y + size),
  on(x, y + size),
]);

/// Assembles the smallest font [ParsedFont] will accept around [outlines].
Uint8List minimalFontBytes(
  List<Outline> outlines, {
  Map<int, int> characterMap = const {},
}) {
  final glyfAndLoca = buildGlyfAndLoca(outlines);
  final glyphs = [
    for (var index = 0; index < outlines.length; index++)
      VariableGlyph(
        name: 'glyph$index',
        codePoint: null,
        advanceWidth: 1000,
        masters: [outlines[index]],
      ),
  ];
  return assembleSfnt([
    (
      tag: 'head',
      data: buildHeadTable(
        metrics: testMetrics,
        fontRevision: 1,
        xMin: -1000,
        yMin: -1000,
        xMax: 1000,
        yMax: 1000,
        longLocaFormat: glyfAndLoca.longFormat,
        created: testTimestamp,
        modified: testTimestamp,
      ),
    ),
    (
      tag: 'hhea',
      data: buildHheaTable(
        metrics: testMetrics,
        advanceWidthMax: 1000,
        minLeftSideBearing: 0,
        minRightSideBearing: 0,
        xMaxExtent: 1000,
        numberOfHMetrics: glyphs.length,
      ),
    ),
    (
      tag: 'maxp',
      data: buildMaxpTable(
        numGlyphs: glyphs.length,
        maxPoints: 4096,
        maxContours: 256,
      ),
    ),
    (tag: 'hmtx', data: buildHmtxTable(glyphs)),
    (tag: 'cmap', data: buildCmapTable(characterMap)),
    (tag: 'loca', data: glyfAndLoca.loca),
    (tag: 'glyf', data: glyfAndLoca.glyf),
  ]);
}

/// The `loca` entries of [built] as byte offsets into `glyf`.
List<int> locaOffsets(GlyfAndLoca built, int glyphCount) {
  final reader = BinaryReader(built.loca);
  return [
    for (var index = 0; index <= glyphCount; index++)
      if (built.longFormat) reader.uint32() else reader.uint16() * 2,
  ];
}

/// The point flags of the glyph starting at [offset], with runs expanded, and
/// how many bytes the flag array took.
({List<int> flags, int byteLength}) decodeGlyphFlags(
  Uint8List glyf,
  int offset,
) {
  final reader = BinaryReader(glyf, offset);
  final contourCount = reader.int16();
  reader.offset += 8; // The bounding box.
  final endPoints = [
    for (var index = 0; index < contourCount; index++) reader.uint16(),
  ];
  final pointCount = endPoints.isEmpty ? 0 : endPoints.last + 1;
  // The length has to be read before the skip: a compound assignment would
  // capture the offset first and rewind over the length field itself.
  final instructionLength = reader.uint16();
  reader.offset += instructionLength;
  final start = reader.offset;
  final flags = <int>[];
  while (flags.length < pointCount) {
    final raw = reader.uint8();
    // The repeat bit belongs to the encoding, not to the point.
    final flag = raw & ~GlyphFlag.repeat;
    flags.add(flag);
    if (raw & GlyphFlag.repeat != 0) {
      final repeats = reader.uint8();
      for (var index = 0; index < repeats; index++) {
        flags.add(flag);
      }
    }
  }
  return (flags: flags, byteLength: reader.offset - start);
}

/// The bounding box the glyph starting at [offset] records.
({int xMin, int yMin, int xMax, int yMax}) decodeGlyphBounds(
  Uint8List glyf,
  int offset,
) {
  final reader = BinaryReader(glyf, offset + 2);
  return (
    xMin: reader.int16(),
    yMin: reader.int16(),
    xMax: reader.int16(),
    yMax: reader.int16(),
  );
}

/// The encoding records of a `cmap` table, in the order they are written.
List<({int platform, int encoding, int offset})> cmapEncodingRecords(
  Uint8List table,
) {
  final reader = BinaryReader(table);
  expect(reader.uint16(), 0, reason: 'the cmap version');
  final count = reader.uint16();
  return [
    for (var index = 0; index < count; index++)
      (
        platform: reader.uint16(),
        encoding: reader.uint16(),
        offset: reader.uint32(),
      ),
  ];
}

/// Decodes the format 4 or format 12 subtable at [offset] into the mapping it
/// describes.
Map<int, int> decodeCmapSubtable(Uint8List table, int offset) {
  final reader = BinaryReader(table, offset);
  final format = reader.uint16();
  final result = <int, int>{};
  if (format == 4) {
    reader.offset += 4; // length, language
    final segCount = reader.uint16() ~/ 2;
    reader.offset += 6; // searchRange, entrySelector, rangeShift
    final endCodes = [
      for (var index = 0; index < segCount; index++) reader.uint16(),
    ];
    reader.offset += 2; // reservedPad
    final startCodes = [
      for (var index = 0; index < segCount; index++) reader.uint16(),
    ];
    final deltas = [
      for (var index = 0; index < segCount; index++) reader.uint16(),
    ];
    final rangeOffsets = [
      for (var index = 0; index < segCount; index++) reader.uint16(),
    ];
    expect(
      rangeOffsets,
      everyElement(0),
      reason: 'every segment maps consecutively, so no glyph id array is used',
    );
    for (var segment = 0; segment < segCount; segment++) {
      if (startCodes[segment] == 0xFFFF) {
        continue;
      }
      for (var code = startCodes[segment]; code <= endCodes[segment]; code++) {
        result[code] = (code + deltas[segment]) % 65536;
      }
    }
    return result;
  }
  expect(format, 12, reason: 'the subtable format');
  reader.offset += 10; // reserved, length, language
  final groupCount = reader.uint32();
  for (var index = 0; index < groupCount; index++) {
    final startCode = reader.uint32();
    final endCode = reader.uint32();
    final startGlyph = reader.uint32();
    for (var code = startCode; code <= endCode; code++) {
      result[code] = startGlyph + (code - startCode);
    }
  }
  return result;
}

/// How many groups the format 12 subtable at [offset] holds.
int cmapFormat12GroupCount(Uint8List table, int offset) =>
    BinaryReader(table, offset + 12).uint32();

/// How many segments the format 4 subtable at [offset] holds.
int cmapFormat4SegmentCount(Uint8List table, int offset) =>
    BinaryReader(table, offset + 6).uint16() ~/ 2;

/// One decoded record of a `name` table.
typedef DecodedName = ({
  int platform,
  int encoding,
  int language,
  int nameId,
  String value,
});

/// Decodes a `name` table into its records, in the order they are stored.
List<DecodedName> decodeNameTable(Uint8List table) {
  final reader = BinaryReader(table);
  expect(reader.uint16(), 0, reason: 'the name table version');
  final count = reader.uint16();
  final storageOffset = reader.uint16();
  expect(
    storageOffset,
    6 + count * 12,
    reason: 'the storage follows the records',
  );
  return [
    for (var index = 0; index < count; index++)
      () {
        final platform = reader.uint16();
        final encoding = reader.uint16();
        final language = reader.uint16();
        final nameId = reader.uint16();
        final length = reader.uint16();
        final offset = reader.uint16();
        final bytes = Uint8List.sublistView(
          table,
          storageOffset + offset,
          storageOffset + offset + length,
        );
        return (
          platform: platform,
          encoding: encoding,
          language: language,
          nameId: nameId,
          value: platform == 3
              ? String.fromCharCodes([
                  for (var at = 0; at < bytes.length; at += 2)
                    (bytes[at] << 8) | bytes[at + 1],
                ])
              : ascii.decode(bytes),
        );
      }(),
  ];
}

/// Sums every delta, scaled by how strongly its master applies at [location].
double reconstructAt(
  VariationModel model,
  List<double> deltas,
  AxisLocation location,
) {
  var total = 0.0;
  for (var index = 0; index < model.masterCount; index++) {
    total +=
        deltas[index] *
        VariationModel.supportScalar(location, model.supports[index]);
  }
  return total;
}

/// Fails unless every master of the model over [locations] is reproduced
/// exactly by summing the deltas solved for it.
void expectMastersReconstruct(
  List<AxisLocation> locations,
  List<String> axisOrder,
) {
  final model = VariationModel(locations, axisOrder: axisOrder);
  // Arbitrary but deterministic master values, none of them equal.
  final values = [
    for (var index = 0; index < locations.length; index++)
      (index * 37 % 23) - 11 + index / 7,
  ];
  final deltas = model.solveDeltas<double>(
    values,
    subtract: (a, b) => a - b,
    scale: (value, factor) => value * factor,
  );
  for (var index = 0; index < model.masterCount; index++) {
    expect(
      reconstructAt(model, deltas, model.sortedLocations[index]),
      closeTo(values[model.originalOrder[index]], 1e-9),
      reason: 'master at ${model.sortedLocations[index]}',
    );
  }
}

void main() {
  group('the binary writer and reader', () {
    test('round trips every field type it can write', () {
      final writer = BinaryWriter()
        ..uint8(255)
        ..int8(-128)
        ..int8(127)
        ..uint16(65535)
        ..int16(-32768)
        ..uint32(0xFFFFFFFF)
        ..int32(-2147483648)
        ..int64(-1234567890123)
        ..fixed(1.5)
        ..f2dot14(0.25)
        ..tag('glyf')
        ..bytes([1, 2, 3]);

      final reader = BinaryReader(writer.toBytes());
      expect(reader.uint8(), 255);
      expect(reader.int8(), -128);
      expect(reader.int8(), 127);
      expect(reader.uint16(), 65535);
      expect(reader.int16(), -32768);
      expect(reader.uint32(), 0xFFFFFFFF);
      expect(reader.int32(), -2147483648);
      expect(reader.int64(), -1234567890123);
      expect(reader.fixed(), 1.5);
      expect(reader.f2dot14(), 0.25);
      expect(reader.tag(), 'glyf');
      expect(reader.take(3), [1, 2, 3]);
      expect(reader.isAtEnd, isTrue);
    });

    test('writes integers most significant byte first', () {
      final writer = BinaryWriter()
        ..uint16(0x1234)
        ..int16(-2)
        ..uint32(0xDEADBEEF)
        ..int32(-1);
      expect(writer.toBytes(), [
        0x12,
        0x34,
        0xFF,
        0xFE,
        0xDE,
        0xAD,
        0xBE,
        0xEF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
      ]);
    });

    test('encodes 400 as a 16.16 fixed point number', () {
      final writer = BinaryWriter()..fixed(400);
      expect(writer.toBytes(), [0x01, 0x90, 0x00, 0x00]);
      expect(BinaryReader(writer.toBytes()).fixed(), 400);
    });

    test('encodes 2.14 coordinates the way fvar expects, clamping the ones '
        'that overflow', () {
      final writer = BinaryWriter()
        ..f2dot14(1)
        ..f2dot14(-1)
        ..f2dot14(0);
      expect(writer.toBytes(), [0x40, 0x00, 0xC0, 0x00, 0x00, 0x00]);

      final overflowing = BinaryReader(
        (BinaryWriter()
              ..f2dot14(2)
              ..f2dot14(-2))
            .toBytes(),
      );
      // 2 is not representable: the largest 2.14 value is one step short of it.
      expect(overflowing.f2dot14(), closeTo(1.99993, 0.00001));
      expect(overflowing.f2dot14(), -2);
    });

    test('rejects a value too large for the field it is written to', () {
      expect(
        () => BinaryWriter().uint16(0x10000),
        throwsA(isA<AssertionError>()),
      );
      expect(() => BinaryWriter().int16(32768), throwsA(isA<AssertionError>()));
      expect(() => BinaryWriter().uint8(-1), throwsA(isA<AssertionError>()));
      expect(
        () => BinaryWriter().tag('toolong'),
        throwsA(isA<AssertionError>()),
      );
    });

    test(
      'pads to the alignment it is given and leaves an aligned buffer be',
      () {
        final writer = BinaryWriter()
          ..bytes([1, 2, 3])
          ..align(4);
        expect(writer.length, 4);
        expect(writer.toBytes(), [1, 2, 3, 0]);
        writer.align(4);
        expect(writer.length, 4, reason: 'an aligned buffer is left alone');
        writer.align(8);
        expect(writer.toBytes(), [1, 2, 3, 0, 0, 0, 0, 0]);
      },
    );

    test('patches a field written before its value was known', () {
      final writer = BinaryWriter()
        ..uint16(0)
        ..uint32(0)
        ..bytes([9, 9])
        ..patchUint16(0, 0xBEEF)
        ..patchUint32(2, 0x01020304);
      expect(writer.toBytes(), [0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04, 9, 9]);
    });

    test('grows past its initial capacity without losing anything', () {
      final writer = BinaryWriter(1);
      for (var value = 0; value < 1000; value++) {
        writer.uint16(value);
      }
      expect(writer.length, 2000);
      final reader = BinaryReader(writer.toBytes());
      for (var value = 0; value < 1000; value++) {
        expect(reader.uint16(), value);
      }
    });

    test('reads from a chosen offset without disturbing the original', () {
      final data = Uint8List.fromList([0, 0, 0x12, 0x34]);
      final reader = BinaryReader(data);
      expect(reader.at(2).uint16(), 0x1234);
      expect(reader.offset, 0, reason: 'the original cursor has not moved');
      expect(reader.remaining, 4);
    });
  });

  group('a table checksum', () {
    test('adds up the big-endian words of the table', () {
      expect(
        tableCheckSum(Uint8List.fromList([0x00, 0x01, 0x00, 0x02])),
        0x00010002,
      );
      expect(
        tableCheckSum(
          Uint8List.fromList([0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02]),
        ),
        3,
      );
      expect(tableCheckSum(Uint8List(0)), 0);
    });

    test('zero pads a table whose length is not a multiple of four, and '
        'wraps at thirty-two bits', () {
      expect(tableCheckSum(Uint8List.fromList([0x01])), 0x01000000);
      expect(tableCheckSum(Uint8List.fromList([0x00, 0x00, 0xAB])), 0x0000AB00);
      expect(
        tableCheckSum(Uint8List.fromList([0x00, 0x01, 0x00, 0x02, 0xFF, 0xFF])),
        0x00000002,
        reason: '0x00010002 + 0xFFFF0000 wraps to 2',
      );
      expect(
        tableCheckSum(
          Uint8List.fromList([0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00]),
        ),
        0,
      );
    });
  });

  group('an assembled font file', () {
    List<FontTableData> tablesOf(Map<String, int> lengths) => [
      for (final entry in lengths.entries)
        (
          tag: entry.key,
          data: Uint8List.fromList([
            for (var index = 0; index < entry.value; index++)
              (index + entry.key.codeUnitAt(0)) & 0xFF,
          ]),
        ),
    ];

    test(
      'describes its directory with the binary search fields sfnt wants',
      () {
        final five = BinaryReader(
          assembleSfnt(
            tablesOf(const {
              'aaaa': 4,
              'bbbb': 4,
              'cccc': 4,
              'dddd': 4,
              'eeee': 4,
            }),
          ),
        );
        expect(five.uint32(), trueTypeSfntVersion);
        expect(five.uint16(), 5, reason: 'numTables');
        expect(five.uint16(), 64, reason: 'searchRange is 16 * 4');
        expect(five.uint16(), 2, reason: 'entrySelector is log2(4)');
        expect(five.uint16(), 16, reason: 'rangeShift is 5 * 16 - 64');

        final one = BinaryReader(assembleSfnt(tablesOf(const {'aaaa': 4})), 4);
        expect(one.uint16(), 1);
        expect(one.uint16(), 16);
        expect(one.uint16(), 0);
        expect(one.uint16(), 0);
      },
    );

    test('sorts its table records by tag whatever order they arrive in', () {
      final bytes = assembleSfnt(
        tablesOf(const {'zzzz': 4, 'head': 54, 'aaaa': 4, 'glyf': 12}),
      );
      final reader = BinaryReader(bytes, 12);
      final tags = [
        for (var index = 0; index < 4; index++)
          () {
            final tag = reader.tag();
            reader.offset += 12;
            return tag;
          }(),
      ];
      expect(tags, ['aaaa', 'glyf', 'head', 'zzzz']);
    });

    test('records the checksum, offset and length of each table', () {
      final tables = tablesOf(const {'aaaa': 7, 'bbbb': 4, 'cccc': 130});
      final bytes = assembleSfnt(tables);
      final byTag = {for (final table in tables) table.tag: table.data};
      final reader = BinaryReader(bytes, 12);
      for (var index = 0; index < 3; index++) {
        final tag = reader.tag();
        final checkSum = reader.uint32();
        final offset = reader.uint32();
        final length = reader.uint32();
        final data = byTag[tag]!;
        expect(length, data.length, reason: '$tag length');
        expect(checkSum, tableCheckSum(data), reason: '$tag checksum');
        expect(offset % 4, 0, reason: '$tag starts on a four byte boundary');
        expect(
          Uint8List.sublistView(bytes, offset, offset + length),
          data,
          reason: '$tag contents',
        );
      }
      expect(bytes.length % 4, 0, reason: 'the file itself is padded out');
    });

    test('lays tables out in the order a rasteriser reads them', () {
      final bytes = assembleSfnt(
        tablesOf(const {'zzzz': 4, 'glyf': 4, 'aaaa': 4, 'head': 54}),
      );
      final reader = BinaryReader(bytes, 12);
      final offsets = <String, int>{};
      for (var index = 0; index < 4; index++) {
        final tag = reader.tag();
        reader.offset += 4;
        offsets[tag] = reader.uint32();
        reader.offset += 4;
      }
      // head comes before glyf because the physical order says so, and the two
      // unlisted tags follow in tag order.
      expect(offsets['head'], lessThan(offsets['glyf']!));
      expect(offsets['glyf'], lessThan(offsets['aaaa']!));
      expect(offsets['aaaa'], lessThan(offsets['zzzz']!));
    });

    test('patches head so the whole file checksums to the magic constant', () {
      final bytes = minimalFontBytes([
        Outline.empty,
        Outline([square(0, 0, 500)]),
      ]);
      expect(tableCheckSum(bytes), 0xB1B0AFBA);

      // The adjustment is what had to be added to reach the magic constant, so
      // clearing it again leaves the rest of the file behind.
      final reader = BinaryReader(bytes, 12);
      var headOffset = -1;
      while (headOffset < 0) {
        final tag = reader.tag();
        reader.offset += 4;
        final offset = reader.uint32();
        reader.offset += 4;
        if (tag == 'head') {
          headOffset = offset;
        }
      }
      final adjustment = BinaryReader(
        bytes,
        headOffset + headCheckSumAdjustmentOffset,
      ).uint32();
      final cleared = Uint8List.fromList(bytes)
        ..setRange(
          headOffset + headCheckSumAdjustmentOffset,
          headOffset + headCheckSumAdjustmentOffset + 4,
          const [0, 0, 0, 0],
        );
      expect((tableCheckSum(cleared) + adjustment) & 0xFFFFFFFF, 0xB1B0AFBA);
    });
  });

  group('the cmap table', () {
    test('offers a Unicode and a Windows record for each subtable', () {
      final table = buildCmapTable(const {0xE000: 1});
      final records = cmapEncodingRecords(table);
      expect(
        [for (final record in records) (record.platform, record.encoding)],
        [(0, 3), (0, 4), (3, 1), (3, 10)],
      );
      expect(records[0].offset, 4 + records.length * 8);
      expect(
        records[0].offset,
        records[2].offset,
        reason: 'both format 4 records point at the same subtable',
      );
      expect(
        records[1].offset,
        records[3].offset,
        reason: 'both format 12 records point at the same subtable',
      );
      expect(records[1].offset, greaterThan(records[0].offset));
    });

    test('compresses a contiguous run of code points into one range', () {
      const mapping = {0xE000: 1, 0xE001: 2, 0xE002: 3, 0xE003: 4};
      final table = buildCmapTable(mapping);
      final records = cmapEncodingRecords(table);
      expect(cmapFormat12GroupCount(table, records[1].offset), 1);
      expect(
        cmapFormat4SegmentCount(table, records[0].offset),
        2,
        reason: 'one segment plus the mandatory 0xFFFF terminator',
      );
      expect(decodeCmapSubtable(table, records[0].offset), mapping);
      expect(decodeCmapSubtable(table, records[1].offset), mapping);
    });

    test('keeps runs apart when either the code point or the glyph jumps', () {
      // The first two runs are separated by a gap in the code points, the
      // second and third by a jump in the glyph IDs.
      const mapping = {0x41: 1, 0x42: 2, 0x50: 3, 0x51: 4, 0x52: 9, 0x53: 10};
      final table = buildCmapTable(mapping);
      final records = cmapEncodingRecords(table);
      expect(cmapFormat12GroupCount(table, records[1].offset), 3);
      expect(cmapFormat4SegmentCount(table, records[0].offset), 4);
      expect(decodeCmapSubtable(table, records[0].offset), mapping);
      expect(decodeCmapSubtable(table, records[1].offset), mapping);
    });

    test('reaches beyond the basic multilingual plane only in format 12', () {
      const mapping = {0xE000: 1, 0x1F600: 5, 0x1F601: 6, 0x10FFFF: 7};
      final table = buildCmapTable(mapping);
      final records = cmapEncodingRecords(table);
      expect(decodeCmapSubtable(table, records[1].offset), mapping);
      expect(decodeCmapSubtable(table, records[0].offset), const {0xE000: 1});

      // A run that crosses the end of the plane is clipped, not lost.
      const crossing = {0xFFFE: 1, 0xFFFF: 2, 0x10000: 3, 0x10001: 4};
      final clipped = buildCmapTable(crossing);
      final clippedRecords = cmapEncodingRecords(clipped);
      expect(
        cmapFormat12GroupCount(clipped, clippedRecords[1].offset),
        1,
        reason: 'format 12 keeps the run whole',
      );
      expect(decodeCmapSubtable(clipped, clippedRecords[1].offset), crossing);
      expect(decodeCmapSubtable(clipped, clippedRecords[0].offset), const {
        0xFFFE: 1,
        0xFFFF: 2,
      });
    });

    test('drops format 4 when the mapping needs more segments than it can '
        'describe', () {
      // A format 4 subtable stores its own length in sixteen bits, which caps
      // it at 8189 segments plus the terminator.
      final mapping = {
        for (var index = 0; index < 8190; index++)
          0x1000 + index * 2: index + 1,
      };
      final table = buildCmapTable(mapping);
      final records = cmapEncodingRecords(table);
      expect(
        [for (final record in records) (record.platform, record.encoding)],
        [(0, 4), (3, 10)],
      );
      expect(cmapFormat12GroupCount(table, records[0].offset), 8190);
      expect(decodeCmapSubtable(table, records[0].offset), mapping);
    });

    test('lets a parsed font resolve every code point it was given', () {
      const mapping = {0xE000: 1, 0xE001: 2, 0x1F600: 3};
      final parsed = ParsedFont.parse(
        minimalFontBytes([
          Outline.empty,
          Outline([square(0, 0, 100)]),
          Outline([square(0, 0, 200)]),
          Outline([square(0, 0, 300)]),
        ], characterMap: mapping),
      );
      expect(parsed.characterMap, mapping);
      for (final entry in mapping.entries) {
        expect(parsed.glyphIdFor(entry.key), entry.value);
      }
      expect(parsed.glyphIdFor(0x41), 0, reason: 'an unmapped code point');
    });
  });

  group('the name table builder', () {
    test('allocates custom name IDs from 256 upward', () {
      final builder = NameTableBuilder()..add(NameId.family, 'Family');
      expect(builder.addCustom('Weight'), 256);
      expect(builder.addCustom('Grade'), 257);
      expect(builder.addCustom('Optical size'), 258);
    });

    test('gives two identical custom strings the same ID', () {
      final builder = NameTableBuilder();
      final first = builder.addCustom('Regular');
      expect(builder.addCustom('Bold'), first + 1);
      expect(builder.addCustom('Regular'), first);
      expect(
        decodeNameTable(builder.build())
            .where((record) => record.platform == 3),
        hasLength(2),
        reason: 'the repeated string is stored once',
      );

      // A string already stored under a fixed ID is not one of those.
      final fixed = NameTableBuilder()..add(NameId.subfamily, 'Regular');
      expect(fixed.addCustom('Regular'), NameId.firstCustom);
    });

    test('ignores a null or an empty value', () {
      final builder = NameTableBuilder()
        ..add(NameId.copyright, null)
        ..add(NameId.trademark, '')
        ..add(NameId.family, 'Family');
      final records = decodeNameTable(builder.build());
      expect({for (final record in records) record.nameId}, {NameId.family});

      final empty = NameTableBuilder().build();
      expect(empty, hasLength(6), reason: 'a header and nothing else');
      expect(decodeNameTable(empty), isEmpty);
    });

    test('stores every string for both Macintosh and Windows', () {
      final builder = NameTableBuilder()
        ..add(NameId.family, 'Icons')
        ..add(NameId.version, 'Version 1.000');
      final records = decodeNameTable(builder.build());
      expect(records, hasLength(4));
      expect(
        records
            .where((record) => record.platform == 3)
            .map((record) => record.value),
        ['Icons', 'Version 1.000'],
      );
      expect(
        records
            .where((record) => record.platform == 1)
            .map((record) => record.value),
        ['Icons', 'Version 1.000'],
      );
      expect(
        records
            .where((record) => record.platform == 3)
            .map((record) => (record.encoding, record.language)),
        everyElement((1, 0x0409)),
      );
    });

    test('sorts its records by platform, encoding, language and name ID', () {
      final builder = NameTableBuilder()
        ..add(NameId.postScriptName, 'Icons-Regular')
        ..add(NameId.family, 'Icons')
        ..add(NameId.fullName, 'Icons Regular');
      final records = decodeNameTable(builder.build());
      final keys = [
        for (final record in records)
          [record.platform, record.encoding, record.language, record.nameId],
      ];
      final sorted = [...keys]
        ..sort((a, b) {
          for (var index = 0; index < a.length; index++) {
            final difference = a[index].compareTo(b[index]);
            if (difference != 0) {
              return difference;
            }
          }
          return 0;
        });
      expect(keys, sorted);
      expect(keys.first.first, 1, reason: 'Macintosh records come first');
    });

    test('replaces what Mac Roman cannot hold but keeps the Windows text', () {
      final builder = NameTableBuilder()..add(NameId.designer, 'Ångström ©');
      final records = decodeNameTable(builder.build());
      expect(
        records.firstWhere((record) => record.platform == 3).value,
        'Ångström ©',
      );
      expect(
        records.firstWhere((record) => record.platform == 1).value,
        '?ngstr?m ?',
      );
    });
  });

  group('the glyf and loca tables', () {
    test('gives an empty outline no space at all in glyf', () {
      final built = buildGlyfAndLoca([
        Outline.empty,
        Outline([square(0, 0, 100)]),
        Outline.empty,
      ]);
      final offsets = locaOffsets(built, 3);
      expect(offsets.first, 0);
      expect(offsets[0], offsets[1], reason: 'the first glyph draws nothing');
      expect(offsets[1], lessThan(offsets[2]));
      expect(offsets[2], offsets[3], reason: 'the last glyph draws nothing');
      expect(offsets.last, built.glyf.length);
      expect(built.longFormat, isFalse);
    });

    test('starts every glyph on a four byte boundary', () {
      // A three point contour makes a glyph whose length is not a multiple of
      // four, so the next one has to be padded up to it.
      final built = buildGlyfAndLoca([
        Outline([
          Contour([on(0, 0), on(7, 0), on(0, 7)]),
        ]),
        Outline([square(0, 0, 10)]),
      ]);
      for (final offset in locaOffsets(built, 2)) {
        expect(offset % 4, 0, reason: 'offset $offset');
      }
    });

    test('writes the bounding box of the points it encodes', () {
      final built = buildGlyfAndLoca([
        Outline([
          Contour([on(-30, 12), off(400, -250), on(120, 60)]),
        ]),
      ]);
      expect(decodeGlyphBounds(built.glyf, 0), (
        xMin: -30,
        yMin: -250,
        xMax: 400,
        yMax: 60,
      ));
    });

    test('run-length encodes a run of identical point flags', () {
      final built = buildGlyfAndLoca([
        Outline([
          Contour([for (var index = 0; index < 10; index++) on(index * 10, 0)]),
        ]),
      ]);
      final decoded = decodeGlyphFlags(built.glyf, 0);
      expect(decoded.flags, hasLength(10));
      expect(
        decoded.byteLength,
        3,
        reason: 'the first flag, then one repeated flag and its count',
      );
      expect(
        decoded.flags.first,
        GlyphFlag.onCurve |
            GlyphFlag.overlapSimple |
            GlyphFlag.xSameOrPositive |
            GlyphFlag.ySameOrPositive,
        reason: 'the first point moves nowhere and flags the overlap',
      );
      expect(
        decoded.flags.skip(1),
        everyElement(
          GlyphFlag.onCurve |
              GlyphFlag.xShort |
              GlyphFlag.xSameOrPositive |
              GlyphFlag.ySameOrPositive,
        ),
      );
    });

    test('picks the shortest form each coordinate delta fits in', () {
      final built = buildGlyfAndLoca([
        Outline([
          Contour([
            on(0, 0), // no movement at all
            on(255, 0), // the largest short delta
            on(0, 0), // a negative short delta
            on(300, 400), // too far for the short form
          ]),
        ]),
      ]);
      final flags = decodeGlyphFlags(built.glyf, 0).flags;
      expect(flags[0] & GlyphFlag.xShort, 0);
      expect(flags[0] & GlyphFlag.xSameOrPositive, GlyphFlag.xSameOrPositive);
      expect(flags[1] & GlyphFlag.xShort, GlyphFlag.xShort);
      expect(
        flags[1] & GlyphFlag.xSameOrPositive,
        GlyphFlag.xSameOrPositive,
        reason: 'a short delta of +255',
      );
      expect(flags[1] & GlyphFlag.yShort, 0, reason: 'y did not move');
      expect(flags[2] & GlyphFlag.xShort, GlyphFlag.xShort);
      expect(
        flags[2] & GlyphFlag.xSameOrPositive,
        0,
        reason: 'a short delta of -255',
      );
      expect(flags[3] & GlyphFlag.xShort, 0);
      expect(
        flags[3] & GlyphFlag.xSameOrPositive,
        0,
        reason: 'neither short nor unmoved, so the long form is used',
      );
      expect(flags[3] & GlyphFlag.yShort, 0);
      expect(flags[3] & GlyphFlag.ySameOrPositive, 0);
    });

    test('round trips an outline with long, short and zero deltas', () {
      final outline = Outline([
        Contour([
          on(0, 0),
          on(0, 0), // a repeated point, so both deltas are zero
          off(600, -300), // far enough to need the long form
          on(-450, 900),
          off(-451, 899),
        ]),
        square(120, 130, 40),
      ]);
      final parsed = ParsedFont.parse(minimalFontBytes([outline]));
      expectSameOutline(parsed.glyphOutlines.first, outline, 'the only glyph');
    });

    test(
      'switches loca to the long format once glyf outgrows the short one',
      () {
        final wide = Outline([
          Contour([
            for (var index = 0; index < 500; index++)
              on((index % 50) * 3, (index % 7) * 5),
          ]),
        ]);
        final small = buildGlyfAndLoca([wide]);
        expect(small.longFormat, isFalse);
        expect(small.loca, hasLength(2 * 2));

        final many = buildGlyfAndLoca([
          for (var index = 0; index < 200; index++) wide,
        ]);
        expect(many.glyf.length, greaterThan(0x1FFFE));
        expect(many.longFormat, isTrue);
        expect(many.loca, hasLength(201 * 4));
        final offsets = locaOffsets(many, 200);
        expect(offsets.last, many.glyf.length);
        expect(offsets[1], greaterThan(0));
      },
    );
  });

  group('the variation model', () {
    test('rejects a set of locations that does not start with the default', () {
      expect(
        () => VariationModel(
          const [
            {'wght': 1.0},
            <String, double>{},
          ],
          axisOrder: const ['wght'],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => VariationModel(const [], axisOrder: const ['wght']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'treats an axis written as zero as absent when spotting duplicates',
      () {
        expect(
          () => VariationModel(
            const [
              <String, double>{},
              {'wght': 0.0},
            ],
            axisOrder: const ['wght'],
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => VariationModel(
            const [
              <String, double>{},
              {'wght': 1.0},
              {'wght': 1.0, 'GRAD': 0.0},
            ],
            axisOrder: const ['wght', 'GRAD'],
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('orders masters from the fewest moved axes to the most', () {
      final model = VariationModel(
        const [
          <String, double>{},
          {'b': 1.0, 'a': 1.0},
          {'b': -1.0},
          {'a': 1.0},
        ],
        axisOrder: const ['a', 'b'],
      );
      expect(model.sortedLocations, const [
        <String, double>{},
        {'a': 1.0},
        {'b': -1.0},
        {'b': 1.0, 'a': 1.0},
      ]);
      expect(model.originalOrder, const [0, 3, 2, 1]);
      expect(model.masterCount, 4);
    });

    test('gives each master the region between the default and its peak', () {
      final model = VariationModel(
        const [
          <String, double>{},
          {'a': 1.0},
          {'b': -1.0},
          {'a': 1.0, 'b': -1.0},
        ],
        axisOrder: const ['a', 'b'],
      );
      expect(model.supports, const [
        <String, AxisRegion>{},
        {'a': (start: 0.0, peak: 1.0, end: 1.0)},
        {'b': (start: -1.0, peak: -1.0, end: 0.0)},
        {
          'a': (start: 0.0, peak: 1.0, end: 1.0),
          'b': (start: -1.0, peak: -1.0, end: 0.0),
        },
      ]);
    });

    test('scores a support at one on its peak, zero outside and linearly in '
        'between', () {
      const support = <String, AxisRegion>{
        'a': (start: 0.0, peak: 1.0, end: 1.0),
      };
      expect(VariationModel.supportScalar(const {'a': 1.0}, support), 1);
      expect(VariationModel.supportScalar(const {'a': 0.5}, support), 0.5);
      expect(VariationModel.supportScalar(const {'a': 0.25}, support), 0.25);
      expect(VariationModel.supportScalar(const {'a': 0.0}, support), 0);
      expect(VariationModel.supportScalar(const {'a': -1.0}, support), 0);
      expect(
        VariationModel.supportScalar(const <String, double>{}, support),
        0,
        reason: 'an axis left out sits at its default',
      );
      expect(
        VariationModel.supportScalar(const {'a': 0.5, 'b': 1.0}, support),
        0.5,
        reason: 'an axis the support says nothing about is ignored',
      );
      expect(
        VariationModel.supportScalar(
          const {'a': 0.5, 'b': -0.5},
          const {
            'a': (start: 0.0, peak: 1.0, end: 1.0),
            'b': (start: -1.0, peak: -1.0, end: 0.0),
          },
        ),
        0.25,
        reason: 'the axes multiply',
      );
      expect(
        VariationModel.supportScalar(
          const {'a': 5.0},
          const {'a': (start: 0.0, peak: 0.0, end: 0.0)},
        ),
        1,
        reason: 'a peak at the default applies everywhere',
      );
    });

    test('reconstructs every master of a one-axis model from its deltas', () {
      expectMastersReconstruct(
        const [
          <String, double>{},
          {'wght': -1.0},
          {'wght': 1.0},
        ],
        const ['wght'],
      );
    });

    test('reconstructs every master of a model with interaction masters', () {
      expectMastersReconstruct(
        const [
          <String, double>{},
          {'FILL': 1.0},
          {'wght': -1.0},
          {'wght': 1.0},
          {'FILL': 1.0, 'wght': -1.0},
          {'FILL': 1.0, 'wght': 1.0},
        ],
        const ['FILL', 'wght'],
      );
    });

    test('reconstructs every master of the material icon axis set', () {
      const axes = IconAxisSet.material;
      expect(axes.masterLocations, hasLength(21));
      expectMastersReconstruct(axes.masterLocations, axes.tags);
    });

    test('reconstructs every master of a model with an intermediate one', () {
      expectMastersReconstruct(
        const [
          <String, double>{},
          {'a': 0.5},
          {'a': 1.0},
          {'a': -1.0},
        ],
        const ['a'],
      );
    });

    test('refuses to solve for the wrong number of master values', () {
      final model = VariationModel(
        const [
          <String, double>{},
          {'a': 1.0},
        ],
        axisOrder: const ['a'],
      );
      expect(
        () => model.solveDeltas<double>(
          [1],
          subtract: (a, b) => a - b,
          scale: (value, factor) => value * factor,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'interpolates continuously on either side of an intermediate master',
      () {
        final model = VariationModel(
          const [
            <String, double>{},
            {'a': 0.5},
            {'a': 1.0},
          ],
          axisOrder: const ['a'],
        );
        final deltas = model.solveDeltas<double>(
          [10, 30, 20],
          subtract: (a, b) => a - b,
          scale: (value, factor) => value * factor,
        );
        expect(
          reconstructAt(model, deltas, const {'a': 0.5}),
          closeTo(30, 1e-9),
        );
        // Just past the middle master the value should barely have moved.
        expect(
          reconstructAt(model, deltas, const {'a': 0.5000001}),
          closeTo(30, 1e-3),
        );
        // And ramps on towards the master beyond it rather than back to the
        // default.
        expect(
          reconstructAt(model, deltas, const {'a': 0.75}),
          closeTo(25, 1e-9),
        );
        expect(reconstructAt(model, deltas, const {'a': 1}), closeTo(20, 1e-9));
      },
    );
  });

  group('normalising an axis coordinate', () {
    const weight = FontAxis(
      tag: 'wght',
      name: 'Weight',
      minimum: 100,
      defaultValue: 400,
      maximum: 700,
    );
    const grade = FontAxis(
      tag: 'GRAD',
      name: 'Grade',
      minimum: -50,
      defaultValue: 0,
      maximum: 200,
    );

    test('maps the minimum, the default and the maximum to -1, 0 and 1', () {
      expect(weight.normalize(100), -1);
      expect(weight.normalize(400), 0);
      expect(weight.normalize(700), 1);
      expect(grade.normalize(-50), -1);
      expect(grade.normalize(0), 0);
      expect(grade.normalize(200), 1);
    });

    test('runs linearly on each side of the default with its own slope', () {
      expect(weight.normalize(250), -0.5);
      expect(weight.normalize(550), 0.5);
      expect(grade.normalize(-25), -0.5);
      expect(grade.normalize(100), 0.5);
      expect(
        grade.normalize(-10),
        closeTo(-0.2, 1e-12),
        reason: 'the two sides have different scales',
      );
      expect(grade.normalize(10), closeTo(0.05, 1e-12));
    });

    test('clamps a value outside the range the axis offers', () {
      expect(weight.normalize(-1000), -1);
      expect(weight.normalize(0), -1);
      expect(weight.normalize(9999), 1);
      expect(grade.normalize(500), 1);
    });

    test('copes with an axis whose default sits at one of its ends', () {
      final fill = IconAxisSet.fillAxis.axis;
      expect(fill.normalize(0), 0, reason: 'FILL defaults to its minimum');
      expect(fill.normalize(-1), 0, reason: 'clamped to the minimum');
      expect(fill.normalize(0.5), 0.5);
      expect(fill.normalize(1), 1);
      expect(fill.normalize(2), 1);

      const pinned = FontAxis(
        tag: 'test',
        name: 'Test',
        minimum: 0,
        defaultValue: 10,
        maximum: 10,
      );
      expect(pinned.normalize(10), 0);
      expect(pinned.normalize(20), 0);
      expect(pinned.normalize(5), -0.5);
      expect(pinned.normalize(0), -1);
    });

    test('is undone by denormalising it again', () {
      for (final value in [100.0, 250.0, 400.0, 550.0, 700.0]) {
        expect(
          weight.denormalize(weight.normalize(value)),
          closeTo(value, 1e-9),
          reason: 'weight $value',
        );
      }
      final opticalSize = IconAxisSet.opticalSizeAxis.axis;
      for (final value in [20.0, 24.0, 36.0, 48.0]) {
        expect(
          opticalSize.denormalize(opticalSize.normalize(value)),
          closeTo(value, 1e-9),
          reason: 'optical size $value',
        );
      }
    });
  });
}
