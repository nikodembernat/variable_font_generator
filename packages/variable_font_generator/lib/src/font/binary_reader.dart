import 'dart:convert';
import 'dart:typed_data';

/// A big-endian cursor over font data.
///
/// The package writes fonts, but it also reads them back: every test that
/// checks a generated font renders correctly parses it with this reader first,
/// so a mistake in the writer cannot hide behind a matching mistake in the
/// verifier.
final class BinaryReader {
  /// Creates a reader over [data], optionally starting at [offset].
  BinaryReader(this.data, [this.offset = 0]);

  /// The bytes being read.
  final Uint8List data;

  /// The current position.
  int offset;

  /// Whether the whole buffer has been consumed.
  bool get isAtEnd => offset >= data.length;

  /// How many bytes remain.
  int get remaining => data.length - offset;

  /// Reads an unsigned byte.
  int uint8() => data[offset++];

  /// Reads a signed byte.
  int int8() {
    final value = data[offset++];
    return value >= 0x80 ? value - 0x100 : value;
  }

  /// Reads an unsigned 16 bit integer.
  int uint16() {
    final value = (data[offset] << 8) | data[offset + 1];
    offset += 2;
    return value;
  }

  /// Reads a signed 16 bit integer.
  int int16() {
    final value = uint16();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  /// Reads an unsigned 32 bit integer.
  int uint32() {
    final value =
        (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
    offset += 4;
    return value;
  }

  /// Reads a signed 32 bit integer.
  int int32() {
    final value = uint32();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  /// Reads a signed 64 bit integer.
  int int64() {
    var value = 0;
    for (var index = 0; index < 8; index++) {
      value = (value << 8) | data[offset + index];
    }
    offset += 8;
    return value;
  }

  /// Reads a 16.16 fixed point number.
  double fixed() => int32() / 65536;

  /// Reads a 2.14 fixed point number.
  double f2dot14() => int16() / 16384;

  /// Reads a four character tag.
  String tag() {
    final value = ascii.decode(Uint8List.sublistView(data, offset, offset + 4));
    offset += 4;
    return value;
  }

  /// Reads [count] raw bytes.
  Uint8List take(int count) {
    final value = Uint8List.sublistView(data, offset, offset + count);
    offset += count;
    return value;
  }

  /// Returns a reader over the same data starting at [newOffset].
  BinaryReader at(int newOffset) => BinaryReader(data, newOffset);
}
