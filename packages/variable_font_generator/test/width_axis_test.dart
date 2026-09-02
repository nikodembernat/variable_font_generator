import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// The `wdth` axis is off by default, because Flutter's `Icon` widget has no
/// parameter for it. These tests cover it on its own terms: it has to narrow
/// and widen the artwork, leave the strokes' thickness alone, and still
/// interpolate exactly alongside every other axis.
void main() {
  const axisSet = IconAxisSet.everything;

  ({double strokeScale, double fill, double widthScale}) resolve(
    Map<String, double> axisValues,
  ) => axisSet.resolve({
    for (final axis in axisSet.fontAxes)
      axis.tag: axis.normalize(axisValues[axis.tag] ?? axis.defaultValue),
  });

  group('the width axis', () {
    test('is not part of the set Icon can drive', () {
      expect(IconAxisSet.material.tags, isNot(contains('wdth')));
      expect(axisSet.tags, contains('wdth'));
    });

    test('scales the artwork horizontally and nothing else', () {
      final template = const IconFontGenerator(
        axisSet: axisSet,
      ).templateFor(fixtureIcons.firstWhere((icon) => icon.name == 'square'));
      const centre = 500.0;

      final normal = template.evaluate(
        strokeScale: 1,
        horizontalCentre: centre,
      );
      final narrow = template.evaluate(
        strokeScale: 1,
        widthScale: 0.75,
        horizontalCentre: centre,
      );
      final wide = template.evaluate(
        strokeScale: 1,
        widthScale: 1.25,
        horizontalCentre: centre,
      );

      final normalBounds = normal.bounds!;
      final narrowBounds = narrow.bounds!;
      final wideBounds = wide.bounds!;

      // Vertically nothing moves at all.
      expect(narrowBounds.minY, closeTo(normalBounds.minY, 1e-9));
      expect(wideBounds.maxY, closeTo(normalBounds.maxY, 1e-9));

      // Horizontally the centre line moves but the stroke keeps its thickness,
      // so the outline narrows by slightly less than the full scale.
      expect(
        narrowBounds.maxX - narrowBounds.minX,
        lessThan(normalBounds.maxX - normalBounds.minX),
      );
      expect(
        wideBounds.maxX - wideBounds.minX,
        greaterThan(normalBounds.maxX - normalBounds.minX),
      );
      // The shape stays centred on the point it was scaled about.
      expect(
        (narrowBounds.minX + narrowBounds.maxX) / 2,
        closeTo(centre, 1e-9),
      );
      expect((wideBounds.minX + wideBounds.maxX) / 2, closeTo(centre, 1e-9));
    });

    test('leaves the strokes as thick as they were', () {
      // A vertical stroke's width is unaffected by horizontal scaling, which is
      // the property that makes width independent of weight and saves the
      // design space twelve masters.
      final template = const IconFontGenerator(axisSet: axisSet)
          .templateFor(fixtureIcons.firstWhere((icon) => icon.name == 'plus'));
      double horizontalRun(Outline outline) {
        final bounds = outline.bounds!;
        return bounds.maxX - bounds.minX;
      }

      final normal = template.evaluate(strokeScale: 1, horizontalCentre: 500);
      final narrow = template.evaluate(
        strokeScale: 1,
        widthScale: 0.75,
        horizontalCentre: 500,
      );
      // The plus is a horizontal bar crossed by a vertical one. Narrowing
      // shortens the horizontal bar by the scale, and the amount it falls short
      // of that is exactly the stroke width, which did not scale.
      final scaledRun = horizontalRun(normal) * 0.75;
      expect(horizontalRun(narrow), greaterThan(scaledRun));
      expect(horizontalRun(narrow), lessThan(horizontalRun(normal)));
    });

    test('adds six masters and no more', () {
      expect(IconAxisSet.material.masterLocations, hasLength(21));
      expect(axisSet.masterLocations, hasLength(27));
      // Width pairs with fill, because filling moves a boundary onto a point
      // and how far it travels depends on the stretch. It pairs with both
      // positions the fill axis carries a master at, and with none of the
      // stroke axes, which is what keeps the count down.
      final pairs = axisSet.masterLocations
          .where((location) => location.containsKey('wdth'))
          .toList();
      expect(pairs, hasLength(6));
      for (final location in pairs) {
        expect(
          location.keys.toSet(),
          anyOf(equals({'wdth'}), equals({'FILL', 'wdth'})),
        );
      }
    });
  });

  group('a font built with the width axis', () {
    late GeneratedFont generated;
    late ParsedFont parsed;
    late Map<String, int> glyphIds;

    setUpAll(() {
      generated = buildFixtureFont(axisSet: axisSet);
      parsed = ParsedFont.parse(generated.bytes);
      glyphIds = {for (final icon in generated.icons) icon.name: icon.glyphId};
    });

    test('declares all five axes', () {
      expect(
        [for (final axis in parsed.axes) axis.tag],
        ['FILL', 'wght', 'GRAD', 'opsz', 'wdth'],
      );
      final width = parsed.axes.last;
      expect(width.minimum, 75);
      expect(width.defaultValue, 100);
      expect(width.maximum, 125);
    });

    for (final location in const [
      <String, double>{},
      {'wdth': 75.0},
      {'wdth': 125.0},
      {'wdth': 75.0, 'FILL': 1.0},
      {'wdth': 125.0, 'FILL': 1.0},
    ]) {
      test('reproduces the master at $location exactly', () {
        final resolved = resolve(location);
        for (final glyph in generated.description.glyphs.skip(1)) {
          final template = const IconFontGenerator(axisSet: axisSet)
              .templateFor(
                fixtureIcons.firstWhere((icon) => icon.name == glyph.name),
              );
          final expected = template
              .evaluate(
                strokeScale: resolved.strokeScale,
                fill: resolved.fill,
                widthScale: resolved.widthScale,
                horizontalCentre: parsed.unitsPerEm / 2,
              )
              .rounded;
          expectSameOutline(
            parsed.glyphOutlineAt(glyphIds[glyph.name]!, axisValues: location),
            expected,
            '${glyph.name} at $location',
          );
        }
      });
    }

    test('stays within a unit or two where width meets weight', () {
      // Width and weight need no master together: in exact arithmetic the model
      // reproduces their combination on its own. Deltas are whole design units
      // though, so four of them landing on the same point can be a couple of
      // units out — a twentieth of a pixel at the size an icon is drawn.
      const location = {'wdth': 75.0, 'wght': 700.0};
      final resolved = resolve(location);
      var worst = 0.0;
      for (final glyph in generated.description.glyphs.skip(1)) {
        final expected = const IconFontGenerator(axisSet: axisSet)
            .templateFor(
              fixtureIcons.firstWhere((icon) => icon.name == glyph.name),
            )
            .evaluate(
              strokeScale: resolved.strokeScale,
              fill: resolved.fill,
              widthScale: resolved.widthScale,
              horizontalCentre: parsed.unitsPerEm / 2,
            );
        final actual = parsed.glyphOutlineAt(
          glyphIds[glyph.name]!,
          axisValues: location,
        );
        final expectedPoints = expected.allPoints;
        final actualPoints = actual.allPoints;
        expect(actualPoints, hasLength(expectedPoints.length));
        for (var index = 0; index < actualPoints.length; index++) {
          final difference =
              (actualPoints[index].position - expectedPoints[index].position)
                  .length;
          worst = worst > difference ? worst : difference;
        }
      }
      expect(worst, lessThan(3));
    });

    test('narrows what it draws when the width axis is turned down', () {
      final glyph = glyphIds['circle']!;
      double width(Map<String, double> at) {
        final bounds = parsed.glyphOutlineAt(glyph, axisValues: at).bounds!;
        return bounds.maxX - bounds.minX;
      }

      expect(width(const {'wdth': 75.0}), lessThan(width(const {})));
      expect(width(const {'wdth': 125.0}), greaterThan(width(const {})));
    });
  });
}
