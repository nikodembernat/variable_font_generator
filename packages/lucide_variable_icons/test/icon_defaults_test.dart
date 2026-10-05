import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_variable_icons/lucide_variable_icons.dart';
import 'package:lucide_variable_icons/lucide_variable_icons_index.dart';

/// What `Icon(icon)` draws with nothing else said, as an `Icon` in an
/// application with no icon theme of its own does.
///
/// The picture is taken at ten times the logical size, so that a tenth of a
/// pixel shows.
Future<({Uint8List alpha, int width})> _draw(
  WidgetTester tester,
  IconData icon, {
  IconThemeData? theme,
  double? size,
}) async {
  final key = GlobalKey();
  Widget child = Icon(icon, size: size);
  if (theme != null) {
    child = IconTheme(data: theme, child: child);
  }
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(key: key, child: child),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 10),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!.buffer.asUint8List();
  final alpha = Uint8List(bytes.length ~/ 4);
  for (var index = 0; index < alpha.length; index++) {
    alpha[index] = bytes[index * 4 + 3];
  }
  final width = image.width;
  image.dispose();
  return (alpha: alpha, width: width);
}

void main() {
  testWidgets("a plain Icon draws the artwork's own strokes", (tester) async {
    // Flutter fills in an optical size of 48 whenever none is given, whatever
    // size the icon is drawn at. The font has to give the artwork there, or
    // every icon nobody configured comes out thinner than it was drawn.
    const artwork = IconThemeData(
      fill: 0,
      weight: 400,
      grade: 0,
      opticalSize: 24,
    );
    for (final icon in allLucideIcons) {
      final plain = await _draw(tester, icon);
      final atDefault = await _draw(tester, icon, theme: artwork);
      expect(
        plain.alpha,
        atDefault.alpha,
        reason: 'code point ${icon.codePoint}',
      );
    }
  });

  testWidgets('a plain Icon sits where the artwork put it at every size', (
    tester,
  ) async {
    // The square is drawn from 3 to 21 on a 24 unit grid, so its ink is
    // centred in the icon's box. Flutter rounds a font's ascent to a whole
    // pixel before placing the baseline, so an em that is not all ascent moves
    // the icon by however much that rounding takes off, by up to half a pixel.
    for (var size = 12.0; size <= 64; size++) {
      final (:alpha, :width) = await _draw(
        tester,
        LucideIcons.square,
        size: size,
      );
      var ink = 0.0;
      var x = 0.0;
      var y = 0.0;
      for (var index = 0; index < alpha.length; index++) {
        ink += alpha[index];
        x += alpha[index] * (index % width + 0.5);
        y += alpha[index] * (index ~/ width + 0.5);
      }
      final centre = width / 2;
      // A twentieth of a logical pixel, in the tenfold picture. The renderer
      // places a glyph to within a quarter of a device pixel, which is what
      // is left at a few small sizes; the rounding this guards against moves
      // the icon by up to ten times as much.
      expect(x / ink, closeTo(centre, 0.5), reason: 'across, at size $size');
      expect(y / ink, closeTo(centre, 0.5), reason: 'down, at size $size');
    }
  });
}
