import 'dart:convert';
import 'dart:typed_data';

import 'package:variable_font_generator/src/font/binary_writer.dart';
import 'package:variable_font_generator/src/font/tables/core_tables.dart';

/// One finished table, ready to be placed in a font file.
typedef FontTableData = ({String tag, Uint8List data});

/// The `sfntVersion` of a font whose outlines live in a `glyf` table.
const trueTypeSfntVersion = 0x00010000;

/// The constant a correct font's total checksum is defined to add up to.
const _checkSumMagic = 0xB1B0AFBA;

/// The order tables are laid out in the file.
///
/// The directory is sorted by tag whatever happens, but the specification also
/// recommends a physical order that puts the tables a rasteriser touches first
/// near the front of the file. Tables not listed here follow, sorted by tag.
const _physicalOrder = [
  'head',
  'hhea',
  'maxp',
  'OS/2',
  'hmtx',
  'cmap',
  'fvar',
  'STAT',
  'avar',
  'loca',
  'glyf',
  'gvar',
  'HVAR',
  'MVAR',
  'name',
  'post',
];

/// Assembles [tables] into a complete font file.
///
/// Writes the table directory, pads every table to a four byte boundary,
/// computes each table's checksum and finally patches `head` so that the
/// checksum of the whole file comes out to the value the specification
/// requires.
Uint8List assembleSfnt(List<FontTableData> tables) {
  final ordered = tables.toList()
    ..sort((a, b) {
      final left = _physicalOrder.indexOf(a.tag);
      final right = _physicalOrder.indexOf(b.tag);
      if (left != right) {
        // Anything unlisted goes last, in tag order.
        return (left == -1 ? _physicalOrder.length : left).compareTo(
          right == -1 ? _physicalOrder.length : right,
        );
      }
      return a.tag.compareTo(b.tag);
    });

  final count = tables.length;
  final searchRange = _largestPowerOfTwoNotExceeding(count) * 16;
  final entrySelector = _log2(searchRange ~/ 16);

  final directorySize = 12 + count * 16;
  final offsets = <String, int>{};
  var cursor = directorySize;
  for (final table in ordered) {
    offsets[table.tag] = cursor;
    cursor += table.data.length;
    cursor += (4 - cursor % 4) % 4;
  }

  final writer = BinaryWriter(cursor)
    ..uint32(trueTypeSfntVersion)
    ..uint16(count)
    ..uint16(searchRange)
    ..uint16(entrySelector)
    ..uint16(count * 16 - searchRange);

  // Directory records are sorted by tag so that a reader can binary search
  // them, which is what the search range fields above describe.
  final byTag = tables.toList()..sort((a, b) => a.tag.compareTo(b.tag));
  var headRecordOffset = -1;
  for (final table in byTag) {
    if (table.tag == 'head') {
      headRecordOffset = offsets[table.tag]!;
    }
    writer
      ..tag(table.tag)
      ..uint32(tableCheckSum(table.data))
      ..uint32(offsets[table.tag]!)
      ..uint32(table.data.length);
  }

  for (final table in ordered) {
    writer
      ..bytes(table.data)
      ..align(4);
  }

  final bytes = writer.toBytes();
  if (headRecordOffset >= 0) {
    final adjustment = (_checkSumMagic - tableCheckSum(bytes)) & 0xFFFFFFFF;
    writer.patchUint32(
      headRecordOffset + headCheckSumAdjustmentOffset,
      adjustment,
    );
  }
  return bytes;
}

/// The checksum of [data]: the sum of its big-endian 32 bit words, with the
/// last word zero-padded, taken modulo two to the thirty-second.
int tableCheckSum(Uint8List data) {
  var sum = 0;
  final wholeWords = data.length - data.length % 4;
  for (var index = 0; index < wholeWords; index += 4) {
    sum =
        (sum +
            ((data[index] << 24) |
                (data[index + 1] << 16) |
                (data[index + 2] << 8) |
                data[index + 3])) &
        0xFFFFFFFF;
  }
  if (wholeWords < data.length) {
    var word = 0;
    for (var index = 0; index < 4; index++) {
      word =
          (word << 8) |
          (wholeWords + index < data.length ? data[wholeWords + index] : 0);
    }
    sum = (sum + word) & 0xFFFFFFFF;
  }
  return sum;
}

/// Reads the tag of the table a font file starts with, used by tests to check
/// a file is a font at all.
String sfntTagAt(Uint8List data, int offset) =>
    ascii.decode(Uint8List.sublistView(data, offset, offset + 4));

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
