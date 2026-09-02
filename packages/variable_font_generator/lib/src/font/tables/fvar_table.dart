import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/font/binary_writer.dart';
import 'package:variable_font_generator/src/variations/font_axis.dart';

/// A position in the design space that the font gives a name to.
///
/// Named instances are what a font picker lists: without them a variable font
/// looks like a single style even though it covers a whole range.
@immutable
final class NamedInstance {
  /// Creates a named instance.
  const NamedInstance({
    required this.name,
    required this.coordinates,
    this.postScriptName,
  });

  /// The style name, such as `Bold` or `Filled Light`.
  final String name;

  /// The user-space coordinate of each axis, keyed by axis tag.
  final Map<String, double> coordinates;

  /// An explicit PostScript name for this instance, or `null` to leave it out.
  final String? postScriptName;

  @override
  String toString() => 'NamedInstance($name, $coordinates)';
}

/// The `fvar` axis flag that hides an axis from font pickers.
const fvarAxisHidden = 0x0001;

/// Builds the `fvar` table, which declares the font's axes and named
/// instances.
///
/// [axisNameIds] and [instanceNameIds] hold the `name` table IDs the strings
/// were stored under, in the same order as [axes] and [instances].
Uint8List buildFvarTable({
  required List<FontAxis> axes,
  required List<int> axisNameIds,
  required List<NamedInstance> instances,
  required List<int> instanceNameIds,
  required List<int?> instancePostScriptNameIds,
}) {
  final hasPostScriptNames = instancePostScriptNameIds.any((id) => id != null);
  final instanceSize = axes.length * 4 + (hasPostScriptNames ? 6 : 4);

  final writer = BinaryWriter()
    ..uint16(1) // majorVersion
    ..uint16(0) // minorVersion
    ..uint16(16) // axesArrayOffset: straight after this header
    ..uint16(2) // reserved, required to be 2
    ..uint16(axes.length)
    ..uint16(20) // axisSize
    ..uint16(instances.length)
    ..uint16(instanceSize);

  for (var index = 0; index < axes.length; index++) {
    final axis = axes[index];
    writer
      ..tag(axis.tag)
      ..fixed(axis.minimum)
      ..fixed(axis.defaultValue)
      ..fixed(axis.maximum)
      ..uint16(axis.hidden ? fvarAxisHidden : 0)
      ..uint16(axisNameIds[index]);
  }

  for (var index = 0; index < instances.length; index++) {
    final instance = instances[index];
    writer
      ..uint16(instanceNameIds[index])
      ..uint16(0); // flags, reserved
    for (final axis in axes) {
      writer.fixed(instance.coordinates[axis.tag] ?? axis.defaultValue);
    }
    if (hasPostScriptNames) {
      writer.uint16(instancePostScriptNameIds[index] ?? 0xFFFF);
    }
  }
  return writer.toBytes();
}
