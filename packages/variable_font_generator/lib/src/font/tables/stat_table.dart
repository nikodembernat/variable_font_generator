import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/font/binary_writer.dart';

/// A named position on one axis, listed in the `STAT` table.
@immutable
final class AxisValueName {
  /// Creates a named axis position.
  const AxisValueName({
    required this.axisTag,
    required this.name,
    required this.value,
    this.isDefault = false,
    this.isElidable = false,
  });

  /// The axis this name belongs to.
  final String axisTag;

  /// The name shown for this position, such as `Bold`.
  final String name;

  /// The user-space value the name applies to.
  final double value;

  /// Whether this is the axis's default position.
  final bool isDefault;

  /// Whether the name may be left out of a composed style name.
  ///
  /// `Regular` is the usual example: a font picker shows `Bold Italic`, not
  /// `Bold Italic Regular Width`.
  final bool isElidable;

  @override
  String toString() => 'AxisValueName($axisTag = $value, "$name")';
}

/// The `STAT` axis value flag marking a name as elidable.
const statElidableAxisValueName = 0x0002;

/// The `STAT` axis value flag marking a value as older than the default.
const statOlderSiblingFontAttribute = 0x0001;

/// Builds the `STAT` table, version 1.2.
///
/// Every variable font is required to have one. It is what lets an application
/// build a sensible style name out of an arbitrary point in the design space,
/// and some text stacks refuse to treat a font as variable without it.
///
/// [axisTags] fixes the axis order, [axisNameIds] gives the `name` table ID of
/// each axis name, and [valueNameIds] gives the ID of each entry in [values].
Uint8List buildStatTable({
  required List<String> axisTags,
  required List<int> axisNameIds,
  required List<AxisValueName> values,
  required List<int> valueNameIds,
  required int elidedFallbackNameId,
}) {
  const headerSize = 20;
  const designAxesOffset = headerSize;
  final axisValueOffsetsOffset = designAxesOffset + axisTags.length * 8;

  final writer = BinaryWriter()
    ..uint16(1) // majorVersion
    ..uint16(2) // minorVersion
    ..uint16(8) // designAxisSize
    ..uint16(axisTags.length)
    ..uint32(designAxesOffset)
    ..uint16(values.length)
    ..uint32(values.isEmpty ? 0 : axisValueOffsetsOffset)
    ..uint16(elidedFallbackNameId);

  for (var index = 0; index < axisTags.length; index++) {
    writer
      ..tag(axisTags[index])
      ..uint16(axisNameIds[index])
      ..uint16(index); // axisOrdering
  }

  // Every axis value here uses format 1, whose table is twelve bytes long, so
  // the offsets are a simple arithmetic sequence.
  const axisValueSize = 12;
  final firstValueOffset = values.length * 2;
  for (var index = 0; index < values.length; index++) {
    writer.uint16(firstValueOffset + index * axisValueSize);
  }

  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    writer
      ..uint16(1) // format 1: a single value on a single axis
      ..uint16(axisTags.indexOf(value.axisTag))
      ..uint16(value.isElidable ? statElidableAxisValueName : 0)
      ..uint16(valueNameIds[index])
      ..fixed(value.value);
  }
  return writer.toBytes();
}
