import 'dart:convert';
import 'dart:typed_data';

/// A growable big-endian buffer for building font tables.
///
/// Every OpenType numeric field is big-endian, so the writer offers one method
/// per field type from the specification rather than a general purpose byte
/// sink. Values are range-checked in debug builds, which turns a silently
/// truncated field into an immediate failure.
final class BinaryWriter {
  /// Creates an empty writer.
  BinaryWriter([int initialCapacity = 256])
    : _bytes = Uint8List(initialCapacity);

  Uint8List _bytes;
  int _length = 0;

  /// How many bytes have been written.
  int get length => _length;

  /// Appends an unsigned byte.
  void uint8(int value) {
    assert(value >= 0 && value <= 0xFF, '$value does not fit in a uint8');
    _ensure(1);
    _bytes[_length++] = value & 0xFF;
  }

  /// Appends a signed byte.
  void int8(int value) {
    assert(value >= -128 && value <= 127, '$value does not fit in an int8');
    _ensure(1);
    _bytes[_length++] = value & 0xFF;
  }

  /// Appends an unsigned 16 bit integer.
  void uint16(int value) {
    assert(value >= 0 && value <= 0xFFFF, '$value does not fit in a uint16');
    _ensure(2);
    _bytes[_length++] = (value >> 8) & 0xFF;
    _bytes[_length++] = value & 0xFF;
  }

  /// Appends a signed 16 bit integer.
  void int16(int value) {
    assert(
      value >= -32768 && value <= 32767,
      '$value does not fit in an int16',
    );
    _ensure(2);
    _bytes[_length++] = (value >> 8) & 0xFF;
    _bytes[_length++] = value & 0xFF;
  }

  /// Appends an unsigned 32 bit integer.
  void uint32(int value) {
    assert(
      value >= 0 && value <= 0xFFFFFFFF,
      '$value does not fit in a uint32',
    );
    _ensure(4);
    _bytes[_length++] = (value >> 24) & 0xFF;
    _bytes[_length++] = (value >> 16) & 0xFF;
    _bytes[_length++] = (value >> 8) & 0xFF;
    _bytes[_length++] = value & 0xFF;
  }

  /// Appends a signed 32 bit integer.
  void int32(int value) {
    assert(
      value >= -2147483648 && value <= 2147483647,
      '$value does not fit in an int32',
    );
    uint32(value & 0xFFFFFFFF);
  }

  /// Appends a signed 64 bit integer, used by `head` for its timestamps.
  void int64(int value) {
    _ensure(8);
    for (var shift = 56; shift >= 0; shift -= 8) {
      _bytes[_length++] = (value >> shift) & 0xFF;
    }
  }

  /// Appends a 16.16 fixed point number.
  void fixed(double value) => int32((value * 65536).round());

  /// Appends a 2.14 fixed point number, the encoding used for normalised axis
  /// coordinates.
  void f2dot14(double value) =>
      int16((value * 16384).round().clamp(-32768, 32767));

  /// Appends a four character tag.
  void tag(String value) {
    assert(value.length == 4, 'A tag must be four characters, got "$value"');
    ascii.encode(value).forEach(uint8);
  }

  /// Appends raw [data].
  void bytes(List<int> data) {
    _ensure(data.length);
    _bytes.setRange(_length, _length + data.length, data);
    _length += data.length;
  }

  /// Appends [count] zero bytes.
  void zeros(int count) {
    _ensure(count);
    _length += count;
  }

  /// Appends zero bytes until the length is a multiple of [alignment].
  void align(int alignment) {
    final remainder = _length % alignment;
    if (remainder != 0) {
      zeros(alignment - remainder);
    }
  }

  /// Overwrites the unsigned 16 bit integer at [offset].
  ///
  /// Used to fill in a length or an offset that is only known after the data it
  /// describes has been written.
  void patchUint16(int offset, int value) {
    assert(value >= 0 && value <= 0xFFFF, '$value does not fit in a uint16');
    _bytes[offset] = (value >> 8) & 0xFF;
    _bytes[offset + 1] = value & 0xFF;
  }

  /// Overwrites the unsigned 32 bit integer at [offset].
  void patchUint32(int offset, int value) {
    assert(
      value >= 0 && value <= 0xFFFFFFFF,
      '$value does not fit in a uint32',
    );
    _bytes[offset] = (value >> 24) & 0xFF;
    _bytes[offset + 1] = (value >> 16) & 0xFF;
    _bytes[offset + 2] = (value >> 8) & 0xFF;
    _bytes[offset + 3] = value & 0xFF;
  }

  /// The bytes written so far.
  Uint8List toBytes() => Uint8List.sublistView(_bytes, 0, _length);

  void _ensure(int extra) {
    if (_length + extra <= _bytes.length) {
      return;
    }
    var capacity = _bytes.isEmpty ? 256 : _bytes.length;
    while (capacity < _length + extra) {
      capacity *= 2;
    }
    final grown = Uint8List(capacity)..setRange(0, _length, _bytes);
    _bytes = grown;
  }
}
