import 'dart:math' as math;
import 'dart:typed_data';

import 'package:variable_font_generator/src/font/glyph.dart';
import 'package:variable_font_generator/src/font/sfnt.dart';
import 'package:variable_font_generator/src/font/tables/cmap_table.dart';
import 'package:variable_font_generator/src/font/tables/core_tables.dart';
import 'package:variable_font_generator/src/font/tables/fvar_table.dart';
import 'package:variable_font_generator/src/font/tables/glyf_table.dart';
import 'package:variable_font_generator/src/font/tables/gvar_table.dart';
import 'package:variable_font_generator/src/font/tables/name_table.dart';
import 'package:variable_font_generator/src/font/tables/os2_table.dart';
import 'package:variable_font_generator/src/font/tables/stat_table.dart';
import 'package:variable_font_generator/src/font/variable_font.dart';
import 'package:variable_font_generator/src/geometry/outline.dart';

/// A point's position during delta solving, before it is rounded to whole
/// design units.
typedef _Offset = ({double x, double y});

/// Writes [font] as a variable TrueType file.
///
/// The result carries `glyf`, `loca`, `cmap`, `head`, `hhea`, `hmtx`, `maxp`,
/// `name`, `OS/2` and `post`, plus the `fvar`, `gvar` and `STAT` tables that
/// make it variable. No `avar` table is written: each axis is arranged to have
/// a linear effect on either side of its default, which is exactly what the
/// normalised axis mapping already provides. Nor is `HVAR`, because advance
/// widths do not vary, and a missing `HVAR` means precisely that.
Uint8List writeVariableFont(VariableFont font) {
  font.validate();

  final now = DateTime.now().toUtc();
  final glyphs = font.glyphs;
  final defaultOutlines = [
    for (final glyph in glyphs) glyph.defaultOutline.rounded,
  ];

  final names = NameTableBuilder()
    ..add(NameId.copyright, font.names.copyright)
    ..add(NameId.family, font.names.family)
    ..add(NameId.subfamily, font.names.subfamily)
    ..add(NameId.uniqueIdentifier, font.names.uniqueIdentifier)
    ..add(NameId.fullName, font.names.fullName)
    ..add(NameId.version, font.names.versionString)
    ..add(NameId.postScriptName, font.names.postScriptName)
    ..add(NameId.manufacturer, font.names.manufacturer)
    ..add(NameId.designer, font.names.designer)
    ..add(NameId.description, font.names.description)
    ..add(NameId.vendorUrl, font.names.vendorUrl)
    ..add(NameId.designerUrl, font.names.designerUrl)
    ..add(NameId.license, font.names.license)
    ..add(NameId.licenseUrl, font.names.licenseUrl)
    ..add(NameId.typographicFamily, font.names.family)
    ..add(NameId.typographicSubfamily, font.names.subfamily)
    ..add(NameId.sampleText, font.names.sampleText)
    ..add(NameId.variationsPostScriptNamePrefix, font.names.postScriptName);

  final axisNameIds = [
    for (final axis in font.axes) names.addCustom(axis.name),
  ];
  final instanceNameIds = [
    for (final instance in font.instances) names.addCustom(instance.name),
  ];
  final instancePostScriptNameIds = [
    for (final instance in font.instances)
      switch (instance.postScriptName) {
        final value? => names.addCustom(value),
        null => null,
      },
  ];
  final axisValueNameIds = [
    for (final value in font.axisValueNames) names.addCustom(value.name),
  ];

  final glyf = buildGlyfAndLoca(defaultOutlines);
  final gvar = buildGvarTable(
    glyphTuples: [for (final glyph in glyphs) _tuplesFor(glyph, font)],
    glyphContourEnds: [
      for (final outline in defaultOutlines) _contourEndsOf(outline),
    ],
    axisOrder: font.axisTags,
  );

  final bounds = _boundsOf(glyphs);
  final advanceWidthMax = glyphs.fold(
    0,
    (best, glyph) => math.max(best, glyph.advanceWidth),
  );
  final codePoints = font.characterMap.keys.toSet();
  final opticalSizeAxis = font.axes
      .where((axis) => axis.tag == 'opsz')
      .firstOrNull;
  final weightAxis = font.axes.where((axis) => axis.tag == 'wght').firstOrNull;

  final tables = <FontTableData>[
    (
      tag: 'head',
      data: buildHeadTable(
        metrics: font.metrics,
        fontRevision: font.names.revision,
        xMin: bounds.minX,
        yMin: bounds.minY,
        xMax: bounds.maxX,
        yMax: bounds.maxY,
        longLocaFormat: glyf.longFormat,
        created: font.created ?? now,
        modified: font.modified ?? now,
      ),
    ),
    (
      tag: 'hhea',
      data: buildHheaTable(
        metrics: font.metrics,
        advanceWidthMax: advanceWidthMax,
        minLeftSideBearing: bounds.minX,
        minRightSideBearing: advanceWidthMax - bounds.maxX,
        xMaxExtent: bounds.maxX,
        numberOfHMetrics: glyphs.length,
      ),
    ),
    (tag: 'hmtx', data: buildHmtxTable(glyphs)),
    (
      tag: 'maxp',
      data: buildMaxpTable(
        numGlyphs: glyphs.length,
        maxPoints: glyphs.fold(
          0,
          (best, glyph) => math.max(best, glyph.pointCount),
        ),
        maxContours: glyphs.fold(
          0,
          (best, glyph) => math.max(best, glyph.defaultOutline.contours.length),
        ),
      ),
    ),
    (
      tag: 'OS/2',
      data: buildOs2Table(
        metrics: font.metrics,
        averageCharWidth: advanceWidthMax,
        weightClass: weightAxis?.defaultValue.round().clamp(1, 1000) ?? 400,
        firstCharIndex: codePoints.isEmpty ? 0 : codePoints.reduce(math.min),
        lastCharIndex: codePoints.isEmpty ? 0 : codePoints.reduce(math.max),
        vendorId: font.vendorId,
        lowerOpticalPointSize: opticalSizeAxis?.minimum ?? 0,
        upperOpticalPointSize: opticalSizeAxis?.maximum ?? 0xFFFF,
        codePoints: codePoints,
      ),
    ),
    (tag: 'cmap', data: buildCmapTable(font.characterMap)),
    (tag: 'loca', data: glyf.loca),
    (tag: 'glyf', data: glyf.glyf),
    (
      tag: 'fvar',
      data: buildFvarTable(
        axes: font.axes,
        axisNameIds: axisNameIds,
        instances: font.instances,
        instanceNameIds: instanceNameIds,
        instancePostScriptNameIds: instancePostScriptNameIds,
      ),
    ),
    (
      tag: 'STAT',
      data: buildStatTable(
        axisTags: font.axisTags,
        axisNameIds: axisNameIds,
        values: font.axisValueNames,
        valueNameIds: axisValueNameIds,
        elidedFallbackNameId: NameId.subfamily,
      ),
    ),
    if (gvar.isNotEmpty) (tag: 'gvar', data: gvar),
    (
      tag: 'post',
      data: buildPostTable(
        glyphs: glyphs,
        underlinePosition: -font.metrics.unitsPerEm ~/ 10,
        underlineThickness: font.metrics.unitsPerEm ~/ 20,
      ),
    ),
    // `name` comes last so that every identifier the tables above asked for has
    // been allocated.
    (tag: 'name', data: names.build()),
  ];

  return assembleSfnt(tables);
}

/// Solves one glyph's masters into the tuples `gvar` stores.
List<GlyphVariationTuple> _tuplesFor(VariableGlyph glyph, VariableFont font) {
  final model = font.model;
  final defaultPoints = _pointsOf(glyph.defaultOutline.rounded);
  final masterValues = [
    for (final master in glyph.masters)
      _difference(_pointsOf(master.rounded), defaultPoints),
  ];

  final deltas = model.solveDeltas<List<_Offset>>(
    masterValues,
    subtract: (a, b) => [
      for (var index = 0; index < a.length; index++)
        (x: a[index].x - b[index].x, y: a[index].y - b[index].y),
    ],
    scale: (value, factor) => [
      for (final point in value) (x: point.x * factor, y: point.y * factor),
    ],
    normalize: (value) => [
      for (final point in value)
        (x: point.x.roundToDouble(), y: point.y.roundToDouble()),
    ],
  );

  final tuples = <GlyphVariationTuple>[];
  for (var index = 0; index < deltas.length; index++) {
    if (model.sortedLocations[index].isEmpty) {
      // The default master contributes the outline itself, not a delta.
      continue;
    }
    tuples.add((
      support: model.supports[index],
      deltas: [
        for (final point in deltas[index])
          (x: point.x.round(), y: point.y.round()),
      ],
    ));
  }
  return tuples;
}

/// The index of the last point of each contour, which is what tells `gvar`
/// where one contour ends and the next begins.
List<int> _contourEndsOf(Outline outline) {
  final ends = <int>[];
  var total = 0;
  for (final contour in outline.contours) {
    total += contour.points.length;
    ends.add(total - 1);
  }
  return ends;
}

/// A glyph's points followed by its four phantom points.
///
/// The phantom points never move here — advance widths and side bearings are
/// the same at every master — but `gvar` still counts them, so they have to be
/// present for the point numbering to line up.
List<_Offset> _pointsOf(Outline outline) => [
  for (final point in outline.allPoints)
    (x: point.position.x, y: point.position.y),
  for (var index = 0; index < phantomPointCount; index++) (x: 0.0, y: 0.0),
];

List<_Offset> _difference(List<_Offset> master, List<_Offset> reference) => [
  for (var index = 0; index < master.length; index++)
    (
      x: master[index].x - reference[index].x,
      y: master[index].y - reference[index].y,
    ),
];

/// The box covering every glyph at every master.
///
/// Using the union rather than just the default instance keeps clients that
/// size their glyph cache from `head` alone from clipping a heavy weight.
({int minX, int minY, int maxX, int maxY}) _boundsOf(
  List<VariableGlyph> glyphs,
) {
  var minX = 0.0;
  var minY = 0.0;
  var maxX = 0.0;
  var maxY = 0.0;
  var seen = false;
  for (final glyph in glyphs) {
    for (final master in glyph.masters) {
      final bounds = master.bounds;
      if (bounds == null) {
        continue;
      }
      if (!seen) {
        seen = true;
        minX = bounds.minX;
        minY = bounds.minY;
        maxX = bounds.maxX;
        maxY = bounds.maxY;
        continue;
      }
      minX = math.min(minX, bounds.minX);
      minY = math.min(minY, bounds.minY);
      maxX = math.max(maxX, bounds.maxX);
      maxY = math.max(maxY, bounds.maxY);
    }
  }
  return (
    minX: minX.floor(),
    minY: minY.floor(),
    maxX: maxX.ceil(),
    maxY: maxY.ceil(),
  );
}
