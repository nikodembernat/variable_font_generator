import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:variable_font_generator/src/raster/coverage_bitmap.dart';

/// Encodes [bitmap] as an 8 bit greyscale PNG.
///
/// Coverage is inverted so that ink shows up black on white, which is what a
/// person looking at the file expects.
Uint8List encodeCoverageAsPng(CoverageBitmap bitmap, {bool invert = true}) {
  final raw = BytesBuilder(copy: false);
  for (var row = 0; row < bitmap.height; row++) {
    // Every scanline is prefixed with its filter type; zero means "none".
    raw.addByte(0);
    final start = row * bitmap.width;
    if (invert) {
      raw.add(
        Uint8List.fromList([
          for (var column = 0; column < bitmap.width; column++)
            255 - bitmap.pixels[start + column],
        ]),
      );
    } else {
      raw.add(
        Uint8List.sublistView(bitmap.pixels, start, start + bitmap.width),
      );
    }
  }

  final header = BytesBuilder(copy: false)
    ..add(_uint32(bitmap.width))
    ..add(_uint32(bitmap.height))
    ..addByte(8) // Bit depth.
    ..addByte(0) // Colour type: greyscale.
    ..addByte(0) // Compression: deflate.
    ..addByte(0) // Filter: adaptive.
    ..addByte(0); // Interlace: none.

  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature.
    ..._chunk('IHDR', header.takeBytes()),
    ..._chunk(
      'IDAT',
      Uint8List.fromList(ZLibEncoder().convert(raw.takeBytes())),
    ),
    ..._chunk('IEND', Uint8List(0)),
  ]);
}

List<int> _chunk(String type, Uint8List data) {
  final typeAndData = Uint8List.fromList([...ascii.encode(type), ...data]);
  return [
    ..._uint32(data.length),
    ...typeAndData,
    ..._uint32(_crc32(typeAndData)),
  ];
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

final _crcTable = () {
  final table = Int32List(256);
  for (var index = 0; index < 256; index++) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? 0xEDB88320 ^ (value >> 1) : value >> 1;
    }
    table[index] = value;
  }
  return table;
}();

int _crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ ((crc >> 8) & 0x00FFFFFF);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
