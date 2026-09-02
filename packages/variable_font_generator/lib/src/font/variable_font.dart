import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/font/font_names.dart';
import 'package:variable_font_generator/src/font/glyph.dart';
import 'package:variable_font_generator/src/font/tables/fvar_table.dart';
import 'package:variable_font_generator/src/font/tables/stat_table.dart';
import 'package:variable_font_generator/src/variations/font_axis.dart';
import 'package:variable_font_generator/src/variations/variation_model.dart';

/// Everything needed to write a variable font file.
@immutable
final class VariableFont {
  /// Creates a font description.
  const VariableFont({
    required this.names,
    required this.axes,
    required this.model,
    required this.glyphs,
    this.metrics = const FontMetrics(),
    this.instances = const [],
    this.axisValueNames = const [],
    this.vendorId = 'NONE',
    this.created,
    this.modified,
  });

  /// The em size and vertical metrics.
  final FontMetrics metrics;

  /// The strings that go into the `name` table.
  final FontNames names;

  /// The variation axes, in the order `fvar` and `gvar` list them.
  final List<FontAxis> axes;

  /// Named positions in the design space, listed in `fvar`.
  final List<NamedInstance> instances;

  /// Named positions on individual axes, listed in `STAT`.
  final List<AxisValueName> axisValueNames;

  /// The model relating master locations to deltas.
  ///
  /// Its master order must match the order of each glyph's
  /// [VariableGlyph.masters].
  final VariationModel model;

  /// The glyphs, in glyph ID order. The first must be `.notdef`.
  final List<VariableGlyph> glyphs;

  /// The four character foundry identifier stored in `OS/2`.
  final String vendorId;

  /// When the font was first made. Defaults to the moment it is written.
  final DateTime? created;

  /// When the font was last changed. Defaults to the moment it is written.
  final DateTime? modified;

  /// The axis tags, in font order.
  List<String> get axisTags => [for (final axis in axes) axis.tag];

  /// The code point of every mapped glyph, keyed by glyph ID.
  Map<int, int> get characterMap => {
    for (var index = 0; index < glyphs.length; index++)
      ?glyphs[index].codePoint: index,
  };

  /// Throws when the description could not produce a valid font.
  void validate() {
    metrics.validate();
    if (glyphs.isEmpty) {
      throw StateError('A font needs at least the .notdef glyph');
    }
    if (glyphs.length > 0xFFFF) {
      throw StateError(
        'A font may hold at most 65535 glyphs but ${glyphs.length} were given',
      );
    }
    if (axes.length > 0xFFFF) {
      throw StateError('Too many axes');
    }
    for (final axis in axes) {
      axis.validate();
    }
    for (final glyph in glyphs) {
      glyph.validate();
      if (glyph.masters.length != model.masterCount) {
        throw StateError(
          'Glyph "${glyph.name}" has ${glyph.masters.length} masters but the '
          'model expects ${model.masterCount}',
        );
      }
    }
  }

  @override
  String toString() =>
      'VariableFont(${names.fullName}, ${glyphs.length} glyphs, '
      '${axes.length} axes)';
}
