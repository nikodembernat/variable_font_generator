import 'dart:io';

import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

/// Where the sample icons live.
///
/// They are a slice of Lucide chosen to exercise every part of the pipeline:
/// each SVG shape element, elliptical arcs, paths that cross themselves,
/// zero-length sub paths, filled dots, detail strokes that have to be knocked
/// out of a fill, and shapes small enough that a heavy stroke turns their
/// inside out.
const fixtureDirectory = 'test/fixtures/lucide';

/// A fixed timestamp, so that two builds of the same icons are byte-identical.
final fixtureTimestamp = DateTime.utc(2000);

/// The parsed fixture icons, read once.
final List<SvgIcon> fixtureIcons = loadSvgIcons(Directory(fixtureDirectory));

/// The outline template of each fixture icon, keyed by name.
final Map<String, StrokeTemplate> fixtureTemplates = {
  for (final icon in fixtureIcons)
    icon.name: const IconFontGenerator().templateFor(icon),
};

/// Builds a font from the fixture icons.
GeneratedFont buildFixtureFont({IconAxisSet axisSet = IconAxisSet.material}) =>
    IconFontGenerator(axisSet: axisSet).generate(
      icons: fixtureIcons,
      names: const FontNames(
        family: 'LucideVariable',
        copyright: 'Copyright (c) Lucide Contributors',
        license: 'ISC',
      ),
      vendorId: 'VFG ',
      timestamp: fixtureTimestamp,
    );

/// The stroke scale, fill amount and width scale at a design-space position
/// given in user coordinates.
({double strokeScale, double fill, double widthScale}) resolveFixtureLocation(
  Map<String, double> axisValues, {
  IconAxisSet axisSet = IconAxisSet.material,
}) => axisSet.resolve({
  for (final axis in axisSet.fontAxes)
    axis.tag: axis.normalize(axisValues[axis.tag] ?? axis.defaultValue),
});

/// Fails unless [actual] and [expected] have the same contours, the same points
/// and the same on-curve flags.
void expectSameOutline(Outline actual, Outline expected, String what) {
  expect(
    actual.contours.length,
    expected.contours.length,
    reason: '$what: contour count',
  );
  for (var index = 0; index < expected.contours.length; index++) {
    final expectedPoints = expected.contours[index].points;
    final actualPoints = actual.contours[index].points;
    expect(
      actualPoints.length,
      expectedPoints.length,
      reason: '$what: contour $index point count',
    );
    for (var point = 0; point < expectedPoints.length; point++) {
      expect(
        actualPoints[point].onCurve,
        expectedPoints[point].onCurve,
        reason: '$what: contour $index point $point on-curve flag',
      );
      expect(
        actualPoints[point].position.x,
        expectedPoints[point].position.x,
        reason: '$what: contour $index point $point x',
      );
      expect(
        actualPoints[point].position.y,
        expectedPoints[point].position.y,
        reason: '$what: contour $index point $point y',
      );
    }
  }
}
