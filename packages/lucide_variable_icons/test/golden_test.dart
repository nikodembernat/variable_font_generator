import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_variable_icons/lucide_variable_icons.dart';
import 'package:lucide_variable_icons/lucide_variable_icons_index.dart';

import 'support/icon_sheet.dart';

/// A spread of icons chosen to show every part of the pipeline at work: shapes
/// that fill, detail strokes that have to be cut back out of a fill, paths that
/// cross themselves, tiny closed shapes, and a plain open stroke that fill
/// cannot touch.
const _icons = [
  LucideIcons.square,
  LucideIcons.star,
  LucideIcons.heart,
  LucideIcons.battery,
  LucideIcons.circleCheck,
  LucideIcons.calendarDays,
  LucideIcons.house,
  LucideIcons.arrowRight,
  LucideIcons.infinity,
  LucideIcons.skull,
];

/// Identifies the boundary a golden is captured from, so that each image is
/// cropped to the sheet rather than to the whole test surface.
const _sheet = ValueKey('sheet');

void main() {
  Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
    tester.view
      ..physicalSize = const Size(1400, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(key: _sheet, child: sheet),
      ),
    );
  }

  Future<void> expectSheet(
    WidgetTester tester,
    String name, {
    required List<IconThemeData> settings,
    List<IconData> icons = _icons,
  }) async {
    await pumpSheet(tester, IconSheet(icons: icons, settings: settings));
    await expectLater(
      find.byKey(_sheet),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('the weight axis thickens the strokes', (tester) async {
    await expectSheet(
      tester,
      'weight',
      settings: const [
        IconThemeData(weight: 100),
        IconThemeData(weight: 250),
        IconThemeData(weight: 400),
        IconThemeData(weight: 550),
        IconThemeData(weight: 700),
      ],
    );
  });

  testWidgets('the three stroke axes carry an icon from light to heavy', (
    tester,
  ) async {
    // Weight, grade and optical size all move the same thing — how much ink a
    // stroke lays down — so they are shown moving together, which is what an
    // application does with them in practice: a heavier weight against denser
    // text at a smaller size.
    await expectSheet(
      tester,
      'strokes',
      settings: const [
        IconThemeData(weight: 100, grade: -50, opticalSize: 48),
        IconThemeData(weight: 250, grade: -25, opticalSize: 40),
        IconThemeData(weight: 400, grade: 0, opticalSize: 32),
        IconThemeData(weight: 550, grade: 100, opticalSize: 26),
        IconThemeData(weight: 700, grade: 200, opticalSize: 20),
      ],
    );
  });

  testWidgets('the fill axis closes shapes and cuts their detail back out', (
    tester,
  ) async {
    await expectSheet(
      tester,
      'fill',
      settings: const [
        IconThemeData(fill: 0),
        IconThemeData(fill: 0.25),
        IconThemeData(fill: 0.5),
        IconThemeData(fill: 0.75),
        IconThemeData(fill: 1),
      ],
    );
  });

  testWidgets('the grade axis adjusts weight without changing the silhouette', (
    tester,
  ) async {
    await expectSheet(
      tester,
      'grade',
      settings: const [
        IconThemeData(grade: -50),
        IconThemeData(grade: -25),
        IconThemeData(grade: 0),
        IconThemeData(grade: 100),
        IconThemeData(grade: 200),
      ],
    );
  });

  testWidgets('the optical size axis thins the strokes as it grows', (
    tester,
  ) async {
    await expectSheet(
      tester,
      'optical_size',
      settings: const [
        IconThemeData(opticalSize: 20),
        IconThemeData(opticalSize: 24),
        IconThemeData(opticalSize: 32),
        IconThemeData(opticalSize: 40),
        IconThemeData(opticalSize: 48),
      ],
    );
  });

  testWidgets('the axes combine', (tester) async {
    await expectSheet(
      tester,
      'combined',
      // One walk across the whole design space rather than five unrelated
      // corners of it, so that a person reading the sheet can see what is
      // meant to be changing: every axis moves the same way at once, from
      // light and open on the left to heavy and filled on the right.
      settings: const [
        IconThemeData(fill: 0, weight: 100, grade: -50, opticalSize: 48),
        IconThemeData(fill: 0.25, weight: 250, grade: -25, opticalSize: 40),
        IconThemeData(fill: 0.5, weight: 400, grade: 0, opticalSize: 32),
        IconThemeData(fill: 0.75, weight: 550, grade: 100, opticalSize: 26),
        IconThemeData(fill: 1, weight: 700, grade: 200, opticalSize: 20),
      ],
    );
  });

  testWidgets('every icon draws at the default instance', (tester) async {
    await pumpSheet(tester, const IconGrid(icons: allLucideIcons));
    await expectLater(
      find.byKey(_sheet),
      matchesGoldenFile('goldens/all_icons.png'),
    );
  });

  testWidgets('every icon draws filled', (tester) async {
    await pumpSheet(
      tester,
      const IconGrid(icons: allLucideIcons, setting: IconThemeData(fill: 1)),
    );
    await expectLater(
      find.byKey(_sheet),
      matchesGoldenFile('goldens/all_icons_filled.png'),
    );
  });

  testWidgets("an icon can be asked for by this set's own type", (
    tester,
  ) async {
    // The whole point of the generated extension type: a signature that takes
    // an icon from this set and nothing else, while `Icon` still accepts one.
    // Both halves are checked when this file is compiled rather than when it
    // runs, which is where an extension type does its work.
    Widget leading(LucideIconData icon) => Icon(icon, size: 48);
    const List<LucideIconData> everyIcon = allLucideIcons;
    const Map<String, LucideIconData> byName = lucideIconsByName;

    await pumpSheet(
      tester,
      Directionality(
        textDirection: TextDirection.ltr,
        child: leading(LucideIcons.house),
      ),
    );

    expect(find.byIcon(LucideIcons.house), findsOneWidget);
    expect(everyIcon, hasLength(byName.length));
    expect(byName['house'], LucideIcons.house);
  });
}
