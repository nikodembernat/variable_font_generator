import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/font/font_names.dart';
import 'package:variable_font_generator/src/font/glyph.dart';
import 'package:variable_font_generator/src/font/tables/fvar_table.dart';
import 'package:variable_font_generator/src/font/tables/stat_table.dart';
import 'package:variable_font_generator/src/font/ttf_writer.dart';
import 'package:variable_font_generator/src/font/variable_font.dart';
import 'package:variable_font_generator/src/generator/icon_axes.dart';
import 'package:variable_font_generator/src/generator/icon_outline_builder.dart';
import 'package:variable_font_generator/src/generator/notdef_glyph.dart';
import 'package:variable_font_generator/src/geometry/stroke_template.dart';
import 'package:variable_font_generator/src/svg/svg_icon.dart';

/// Where one icon ended up in a generated font.
@immutable
final class GeneratedIcon {
  /// Creates a record of a placed icon.
  const GeneratedIcon({
    required this.name,
    required this.codePoint,
    required this.glyphId,
  });

  /// The icon's name, taken from its source file.
  final String name;

  /// The code point it is reachable at.
  final int codePoint;

  /// Its glyph ID within the font.
  final int glyphId;

  @override
  String toString() =>
      'GeneratedIcon($name, U+${codePoint.toRadixString(16).toUpperCase()})';
}

/// A finished font and the map from icon names to the code points that reach
/// them.
@immutable
final class GeneratedFont {
  /// Creates a result.
  const GeneratedFont({
    required this.bytes,
    required this.icons,
    required this.description,
  });

  /// The font file.
  final Uint8List bytes;

  /// Where every icon ended up, in the order they were placed.
  final List<GeneratedIcon> icons;

  /// The description the file was written from, kept so that tests can compare
  /// against the outlines that went in.
  final VariableFont description;

  @override
  String toString() =>
      'GeneratedFont(${icons.length} icons, ${bytes.length} bytes)';
}

/// The first code point of the Basic Multilingual Plane's Private Use Area.
///
/// Icon fonts live here by convention: the range is set aside precisely so that
/// a font can define its own meanings without colliding with real characters.
const privateUseAreaStart = 0xE000;

const _privateUseAreaEnd = 0xF8FF;
const _supplementaryPrivateUseAStart = 0xF0000;
const _supplementaryPrivateUseAEnd = 0xFFFFD;

/// Turns a set of parsed SVG icons into a variable icon font.
@immutable
final class IconFontGenerator {
  /// Creates a generator.
  const IconFontGenerator({
    this.axisSet = IconAxisSet.material,
    this.metrics = const FontMetrics(),
    this.curveTolerance = 1,
    this.startCodePoint = privateUseAreaStart,
  });

  /// The axes the font will offer.
  final IconAxisSet axisSet;

  /// The em size and vertical metrics.
  final FontMetrics metrics;

  /// See [IconOutlineBuilder.curveTolerance].
  final double curveTolerance;

  /// The code point the first icon is placed at.
  final int startCodePoint;

  /// Generates a font containing [icons].
  ///
  /// Icons keep the order they are given in. Unless [codePoints] says
  /// otherwise they are placed at consecutive code points starting from
  /// [startCodePoint]; passing an explicit list is how a rebuild keeps every
  /// icon where an already-published application expects to find it.
  GeneratedFont generate({
    required List<SvgIcon> icons,
    required FontNames names,
    List<int>? codePoints,
    String vendorId = 'NONE',
    List<NamedInstance>? instances,
    List<AxisValueName>? axisValueNames,
    DateTime? timestamp,
  }) {
    if (codePoints != null && codePoints.length != icons.length) {
      throw ArgumentError.value(
        codePoints,
        'codePoints',
        'Expected one code point per icon, '
            'got ${codePoints.length} for ${icons.length} icons',
      );
    }
    final builder = IconOutlineBuilder(
      metrics: metrics,
      curveTolerance: curveTolerance,
    );
    final model = axisSet.buildModel();
    // Masters are built in the order the model was created with, not the
    // order the model sorted them into; the model reindexes them itself when
    // it solves for deltas.
    final locations = axisSet.masterLocations;
    final settings = [
      for (final location in locations) axisSet.resolve(location),
    ];

    final notdef = buildNotdefOutline(metrics);
    final glyphs = <VariableGlyph>[
      VariableGlyph(
        name: '.notdef',
        codePoint: null,
        advanceWidth: builder.advanceWidth,
        masters: [
          for (var index = 0; index < locations.length; index++) notdef,
        ],
      ),
    ];

    final placed = <GeneratedIcon>[];
    final assigned =
        codePoints ?? _allocateCodePoints(icons.length, startCodePoint);
    for (var index = 0; index < icons.length; index++) {
      final icon = icons[index];
      final template = builder.build(icon);
      glyphs.add(
        VariableGlyph(
          name: icon.name,
          codePoint: assigned[index],
          advanceWidth: builder.advanceWidth,
          masters: [
            for (final setting in settings)
              template.evaluate(
                strokeScale: setting.strokeScale,
                fill: setting.fill,
                widthScale: setting.widthScale,
                horizontalCentre: builder.advanceWidth / 2,
              ),
          ],
        ),
      );
      placed.add(
        GeneratedIcon(
          name: icon.name,
          codePoint: assigned[index],
          glyphId: glyphs.length - 1,
        ),
      );
    }

    final font = VariableFont(
      metrics: metrics,
      names: names,
      axes: axisSet.fontAxes,
      instances: instances ?? axisSet.defaultInstances,
      axisValueNames: axisValueNames ?? axisSet.defaultAxisValueNames,
      model: model,
      glyphs: glyphs,
      vendorId: vendorId,
      created: timestamp,
      modified: timestamp,
    );

    return GeneratedFont(
      bytes: writeVariableFont(font),
      icons: placed,
      description: font,
    );
  }

  /// Builds the outline template for a single [icon], without placing it in a
  /// font.
  ///
  /// Useful for comparing an icon's geometry against its source without going
  /// through a font file first.
  StrokeTemplate templateFor(SvgIcon icon) => IconOutlineBuilder(
    metrics: metrics,
    curveTolerance: curveTolerance,
  ).build(icon);

  /// Hands out [count] consecutive code points from [start].
  ///
  /// The Basic Multilingual Plane's Private Use Area holds 6400 of them, which
  /// is enough for most icon sets; larger ones continue into the supplementary
  /// area, which a `cmap` subtable of format 12 can still reach.
  static List<int> _allocateCodePoints(int count, int start) {
    final result = <int>[];
    var next = start;
    while (result.length < count) {
      if (next > _privateUseAreaEnd && next < _supplementaryPrivateUseAStart) {
        next = _supplementaryPrivateUseAStart;
      }
      if (next > _supplementaryPrivateUseAEnd) {
        throw StateError(
          'Ran out of private use code points after ${result.length} icons',
        );
      }
      result.add(next);
      next++;
    }
    return result;
  }
}
