import 'dart:io';

import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

void main() {
  group('a generated font, read back', () {
    late GeneratedFont generated;
    late ParsedFont parsed;

    setUpAll(() {
      generated = buildFixtureFont();
      parsed = ParsedFont.parse(generated.bytes);
    });

    test('carries every table a variable icon font needs', () {
      expect(
        parsed.tables.keys,
        containsAll([
          'head',
          'hhea',
          'hmtx',
          'maxp',
          'name',
          'OS/2',
          'post',
          'cmap',
          'loca',
          'glyf',
          'fvar',
          'gvar',
          'STAT',
        ]),
      );
    });

    test('has one glyph per icon, plus .notdef', () {
      expect(parsed.numGlyphs, generated.icons.length + 1);
      expect(parsed.glyphNames.first, '.notdef');
    });

    test('has metrics that let Flutter centre a glyph in its box', () {
      // Icon renders with height: 1.0 and even leading distribution, so the
      // line box is exactly one font size tall and the leading is split evenly.
      // With no leading to split, a glyph filling the em box fills the icon.
      expect(parsed.ascender - parsed.descender, parsed.unitsPerEm);
      expect(parsed.lineGap, 0);
    });

    test('maps every icon to the glyph it belongs to', () {
      for (final icon in generated.icons) {
        expect(
          parsed.glyphIdFor(icon.codePoint),
          icon.glyphId,
          reason: '${icon.name} at U+${icon.codePoint.toRadixString(16)}',
        );
      }
    });

    test('names its glyphs after the files they came from', () {
      for (final icon in generated.icons) {
        expect(parsed.glyphNames[icon.glyphId], icon.name.replaceAll('-', '_'));
      }
    });

    test('declares the four axes Flutter can drive', () {
      expect(
        [for (final axis in parsed.axes) axis.tag],
        ['FILL', 'wght', 'GRAD', 'opsz'],
      );
      final byTag = {for (final axis in parsed.axes) axis.tag: axis};
      expect(byTag['FILL']!.minimum, 0);
      expect(byTag['FILL']!.maximum, 1);
      expect(byTag['wght']!.defaultValue, 400);
      expect(byTag['GRAD']!.defaultValue, 0);
      expect(byTag['opsz']!.defaultValue, 24);
    });

    test('gives every glyph the same advance width', () {
      expect(
        parsed.advanceWidths.toSet(),
        {parsed.unitsPerEm},
        reason:
            'A glyph narrower than the em would sit off-centre in the square '
            'Icon draws it in.',
      );
    });

    test("sets each glyph's left side bearing to its own left edge", () {
      for (var glyph = 1; glyph < parsed.numGlyphs; glyph++) {
        final bounds = parsed.glyphOutlines[glyph].bounds;
        if (bounds == null) {
          continue;
        }
        expect(parsed.leftSideBearings[glyph], bounds.minX.round());
      }
    });

    test('reproduces the default outlines exactly', () {
      final byName = {
        for (final icon in generated.icons) icon.name: icon.glyphId,
      };
      for (final glyph in generated.description.glyphs.skip(1)) {
        final expected = glyph.defaultOutline.rounded;
        final actual = parsed.glyphOutlines[byName[glyph.name]!];
        expectSameOutline(actual, expected, glyph.name);
      }
    });
  });

  group('variations applied by the reader', () {
    late GeneratedFont generated;
    late ParsedFont parsed;
    late Map<String, int> glyphIds;

    setUpAll(() {
      generated = buildFixtureFont();
      parsed = ParsedFont.parse(generated.bytes);
      glyphIds = {for (final icon in generated.icons) icon.name: icon.glyphId};
    });

    // Every position the design space has a master at must come back exactly:
    // deltas are whole numbers and are solved against the rounded values that
    // precede them, so nothing is left to accumulate.
    for (final location in const [
      <String, double>{},
      {'wght': 100.0},
      {'wght': 700.0},
      {'GRAD': -50.0},
      {'GRAD': 200.0},
      {'opsz': 20.0},
      {'opsz': 48.0},
      {'FILL': 1.0},
      {'FILL': 1.0, 'wght': 100.0},
      {'FILL': 1.0, 'wght': 700.0},
      {'FILL': 1.0, 'GRAD': 200.0},
      {'FILL': 1.0, 'opsz': 48.0},
    ]) {
      test('are exact at $location', () {
        final resolved = resolveFixtureLocation(location);
        for (final glyph in generated.description.glyphs.skip(1)) {
          final template = fixtureTemplates[glyph.name]!;
          final expected = template
              .evaluate(strokeScale: resolved.strokeScale, fill: resolved.fill)
              .rounded;
          final actual = parsed.glyphOutlineAt(
            glyphIds[glyph.name]!,
            axisValues: location,
          );
          expectSameOutline(actual, expected, '${glyph.name} at $location');
        }
      });
    }

    // A position that moves several stroke axes at once is not a master: the
    // file reaches it by adding up what each of them does on its own. That is
    // the same answer as moving them together only while the outline is an
    // affine function of the width they add up to, so these are where a bend
    // anywhere in that line shows itself — and they are the corners an
    // application actually asks for, a heavy weight against dense text at a
    // small size.
    for (final location in const [
      {'FILL': 0.5, 'wght': 550.0, 'GRAD': 100.0, 'opsz': 30.0},
      {'wght': 700.0, 'GRAD': 200.0, 'opsz': 20.0},
      {'wght': 100.0, 'GRAD': -50.0, 'opsz': 48.0},
      {'FILL': 1.0, 'wght': 700.0, 'GRAD': 200.0, 'opsz': 20.0},
      {'wght': 550.0, 'GRAD': 100.0},
    ]) {
      test('stay close at $location', () {
        final resolved = resolveFixtureLocation(location);
        var worst = 0.0;
        var worstAt = '';
        for (final glyph in generated.description.glyphs.skip(1)) {
          final expected = fixtureTemplates[glyph.name]!.evaluate(
            strokeScale: resolved.strokeScale,
            fill: resolved.fill,
          );
          final actual = parsed.glyphOutlineAt(
            glyphIds[glyph.name]!,
            axisValues: location,
          );
          final expectedPoints = expected.allPoints;
          final actualPoints = actual.allPoints;
          expect(actualPoints.length, expectedPoints.length);
          for (var index = 0; index < actualPoints.length; index++) {
            final difference =
                (actualPoints[index].position - expectedPoints[index].position)
                    .length;
            if (difference > worst) {
              worst = difference;
              worstAt = glyph.name;
            }
          }
        }
        // Interpolating between whole-unit deltas cannot land on the exact
        // answer; a couple of units out of a thousand is a twentieth of a pixel
        // at the size an icon is normally drawn.
        expect(worst, lessThan(3), reason: 'worst was $worstAt');
      });
    }
  });

  test('the same icons always produce the same bytes', () {
    expect(buildFixtureFont().bytes, buildFixtureFont().bytes);
  });

  test('a font with no variable axes still parses', () {
    final icons = loadSvgIcons(Directory(fixtureDirectory));
    final font = const IconFontGenerator(axisSet: IconAxisSet([])).generate(
      icons: icons.take(3).toList(),
      names: const FontNames(family: 'Static'),
      timestamp: fixtureTimestamp,
    );
    final parsed = ParsedFont.parse(font.bytes);
    expect(parsed.axes, isEmpty);
    expect(parsed.numGlyphs, 4);
  });
}
