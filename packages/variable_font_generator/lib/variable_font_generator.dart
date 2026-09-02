/// Generates a variable OpenType icon font, and the Flutter bindings for it,
/// from a directory of SVG icons.
///
/// The pipeline has three stages. Icons are parsed and their stroked centre
/// lines are turned into outlines that are an affine function of the stroke
/// width, so the same icon can be re-drawn at any weight with the same points
/// in the same order. Those outlines are evaluated at a set of master positions
/// and solved into `gvar` deltas. Finally a Dart class is written giving every
/// icon a name and a code point.
///
/// The shortest path from a directory to a font:
///
/// ```dart
/// final icons = loadSvgIcons(Directory('assets/icons'));
/// final font = const IconFontGenerator().generate(
///   icons: icons,
///   names: const FontNames(family: 'MyIcons'),
/// );
/// File('MyIcons.ttf').writeAsBytesSync(font.bytes);
///
/// final bindings = const FlutterBindingsGenerator(
///   className: 'MyIcons',
///   font: FontReference.application(family: 'MyIcons'),
/// ).generate(font.icons);
/// ```
library;

export 'src/bindings/dart_identifiers.dart'
    show
        IdentifierStyle,
        dartObjectMembers,
        dartReservedWords,
        leadingNumberNames,
        toDartIdentifier;
export 'src/bindings/flutter_bindings.dart'
    show FlutterBindingsGenerator, FontReference, IdentifierCollisionException;
export 'src/bindings/flutter_pubspec.dart' show FlutterPubspecGenerator;
export 'src/cli/build_options.dart' show BuildOptions;
export 'src/cli/build_runner.dart' show BuildResult, runBuild;
export 'src/cli/codepoint_map.dart' show CodePointMap;
export 'src/cli/icon_loader.dart' show loadSvgIcons;
export 'src/cli/runner.dart' show buildCommandRunner, packageVersion, runCli;
export 'src/font/binary_reader.dart' show BinaryReader;
export 'src/font/binary_writer.dart' show BinaryWriter;
export 'src/font/font_metrics.dart' show FontMetrics;
export 'src/font/font_names.dart' show FontNames;
export 'src/font/glyph.dart' show VariableGlyph;
export 'src/font/sfnt.dart'
    show FontTableData, assembleSfnt, tableCheckSum, trueTypeSfntVersion;
export 'src/font/tables/cmap_table.dart' show buildCmapTable;
export 'src/font/tables/fvar_table.dart' show NamedInstance, buildFvarTable;
export 'src/font/tables/glyf_table.dart'
    show GlyfAndLoca, GlyphFlag, buildGlyfAndLoca;
export 'src/font/tables/gvar_table.dart'
    show GlyphVariationTuple, PointDelta, buildGvarTable, phantomPointCount;
export 'src/font/tables/name_table.dart' show NameId, NameTableBuilder;
export 'src/font/tables/stat_table.dart' show AxisValueName, buildStatTable;
export 'src/font/ttf_writer.dart' show writeVariableFont;
export 'src/font/variable_font.dart' show VariableFont;
export 'src/generator/icon_axes.dart' show IconAxis, IconAxisSet;
export 'src/generator/icon_font_generator.dart'
    show GeneratedFont, GeneratedIcon, IconFontGenerator, privateUseAreaStart;
export 'src/generator/icon_outline_builder.dart' show IconOutlineBuilder;
export 'src/generator/notdef_glyph.dart' show buildNotdefOutline;
export 'src/geometry/arc.dart' show arcToCubics;
export 'src/geometry/bezier.dart'
    show
        Cubic,
        Quadratic,
        cubicToQuadratics,
        cubicTurnAngle,
        evaluateCubic,
        evaluateQuadratic,
        flattenQuadratic,
        isCubicDegenerate,
        isQuadraticDegenerate,
        limitQuadraticTurn,
        quadraticTurnAngle,
        splitCubic,
        splitQuadratic,
        tangentPreservingQuadratic;
export 'src/geometry/outline.dart'
    show Contour, ContourSegment, Outline, OutlinePoint;
export 'src/geometry/path.dart'
    show
        CubicSegment,
        LineSegment,
        Path,
        PathSegment,
        QuadraticSegment,
        SubPath;
export 'src/geometry/path_parser.dart' show PathParseException, parseSvgPath;
export 'src/geometry/stroke_style.dart' show StrokeCap, StrokeJoin;
export 'src/geometry/stroke_template.dart'
    show StrokeContourTemplate, StrokePointTemplate, StrokeTemplate;
export 'src/geometry/stroker.dart' show Stroker;
export 'src/geometry/vec2.dart' show Vec2;
export 'src/raster/coverage_bitmap.dart' show CoverageBitmap;
export 'src/raster/png.dart' show encodeCoverageAsPng;
export 'src/raster/preview.dart'
    show PreviewColumn, defaultPreviewColumns, renderPreviewSheet;
export 'src/raster/rasterizer.dart' show Rasterizer;
export 'src/svg/svg_icon.dart' show SvgIcon, SvgShape;
export 'src/svg/svg_parser.dart' show SvgParseException, parseSvgIcon;
export 'src/svg/svg_transform.dart' show AffineTransform, parseSvgTransform;
export 'src/variations/font_axis.dart' show FontAxis;
export 'src/variations/variation_model.dart'
    show AxisLocation, AxisRegion, MasterSupport, VariationModel;
