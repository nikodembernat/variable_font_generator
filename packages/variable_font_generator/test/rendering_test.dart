import 'dart:io';

import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// Where the reference images live.
const _goldenDirectory = 'test/goldens';

/// Rewrites the reference images instead of comparing against them.
///
/// Run `UPDATE_GOLDENS=1 dart test test/rendering_test.dart` after a deliberate
/// change, then look at the diff before committing it.
final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

/// The design-space positions the reference images are drawn at.
const _positions = <String, Map<String, double>>{
  'default': {},
  'weight_min': {'wght': 100.0},
  'weight_max': {'wght': 700.0},
  'filled': {'FILL': 1.0},
  'filled_bold': {'FILL': 1.0, 'wght': 700.0},
  'grade_max': {'GRAD': 200.0},
  'optical_size_max': {'opsz': 48.0},
};

void main() {
  late GeneratedFont generated;
  late ParsedFont parsed;
  late Map<String, int> glyphIds;

  setUpAll(() {
    generated = buildFixtureFont();
    parsed = ParsedFont.parse(generated.bytes);
    glyphIds = {for (final icon in generated.icons) icon.name: icon.glyphId};
  });

  /// Renders every fixture icon side by side, straight out of the font file.
  CoverageBitmap renderSheet(Map<String, double> axisValues, {int cell = 48}) {
    const columns = 9;
    final rows = (fixtureIcons.length + columns - 1) ~/ columns;
    final sheet = CoverageBitmap.empty(columns * cell, rows * cell);
    const rasterizer = Rasterizer();
    final transform = Rasterizer.transformFor(
      minX: 0,
      minY: parsed.descender.toDouble(),
      maxX: parsed.unitsPerEm.toDouble(),
      maxY: parsed.ascender.toDouble(),
      width: cell,
      height: cell,
    );
    for (var index = 0; index < fixtureIcons.length; index++) {
      final bitmap = rasterizer.rasterize(
        parsed.glyphOutlineAt(
          glyphIds[fixtureIcons[index].name]!,
          axisValues: axisValues,
        ),
        width: cell,
        height: cell,
        transform: transform,
      );
      final column = index % columns;
      final row = index ~/ columns;
      for (var y = 0; y < cell; y++) {
        final target = (row * cell + y) * sheet.width + column * cell;
        sheet.pixels.setRange(target, target + cell, bitmap.pixels, y * cell);
      }
    }
    return sheet;
  }

  group('what the font actually draws', () {
    for (final entry in _positions.entries) {
      test('matches the reference image at ${entry.key}', () {
        final rendered = renderSheet(entry.value);
        final file = File('$_goldenDirectory/${entry.key}.png');
        if (_updateGoldens) {
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(encodeCoverageAsPng(rendered));
          return;
        }
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Missing ${file.path}. Create it with '
              'UPDATE_GOLDENS=1 dart test test/rendering_test.dart',
        );
        expect(
          encodeCoverageAsPng(rendered),
          file.readAsBytesSync(),
          reason:
              'The font draws something different from ${file.path}. Look at '
              'the two images before updating the reference.',
        );
      });
    }
  });

  group('fidelity of the outlines that reach the font', () {
    // The font stores whole design units and quadratic curves, so its outlines
    // are an approximation of the artwork. Comparing what it draws against the
    // same artwork stroked at a far finer tolerance says how good that
    // approximation is, across the whole pipeline: parsing, stroking, rounding,
    // encoding into `glyf` and `gvar`, and reading it all back.
    const preciseBuilder = IconOutlineBuilder(curveTolerance: 0.05);
    const rasterizer = Rasterizer(samplesPerPixel: 16);
    const size = 192;

    for (final position in const [
      <String, double>{},
      {'wght': 700.0},
      {'FILL': 1.0},
    ]) {
      test('is within a fraction of a percent at $position', () {
        final resolved = resolveFixtureLocation(position);
        final transform = Rasterizer.transformFor(
          minX: 0,
          minY: parsed.descender.toDouble(),
          maxX: parsed.unitsPerEm.toDouble(),
          maxY: parsed.ascender.toDouble(),
          width: size,
          height: size,
        );
        var worst = 1.0;
        var worstName = '';
        for (final icon in fixtureIcons) {
          final fromFont = rasterizer.rasterize(
            parsed.glyphOutlineAt(glyphIds[icon.name]!, axisValues: position),
            width: size,
            height: size,
            transform: transform,
          );
          final fromArtwork = rasterizer.rasterize(
            preciseBuilder
                .build(icon)
                .evaluate(
                  strokeScale: resolved.strokeScale,
                  fill: resolved.fill,
                ),
            width: size,
            height: size,
            transform: transform,
          );
          final overlap = fromFont.intersectionOverUnion(fromArtwork);
          if (overlap < worst) {
            worst = overlap;
            worstName = icon.name;
          }
        }
        expect(
          worst,
          greaterThan(0.985),
          reason: 'worst was $worstName at $worst',
        );
      });
    }
  });
}
