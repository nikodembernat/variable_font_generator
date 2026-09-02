import 'package:flutter/material.dart';

/// Lays icons out in a grid: one row per icon, one column per setting.
///
/// Golden files are cheapest to review when there are few of them and each says
/// a lot, so the tests render a whole sheet rather than one icon at a time.
final class IconSheet extends StatelessWidget {
  /// Creates a sheet.
  const IconSheet({
    required this.icons,
    required this.settings,
    this.iconSize = 48,
    super.key,
  });

  /// The icons to draw, one per row.
  final List<IconData> icons;

  /// The axis settings to draw them at, one per column.
  final List<IconThemeData> settings;

  /// How large each icon is drawn.
  final double iconSize;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final icon in icons)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final setting in settings)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: IconTheme(
                        data: setting.copyWith(
                          size: iconSize,
                          color: const Color(0xFF000000),
                        ),
                        child: Icon(icon),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

/// Lays a flat list of icons out in a grid, all at the same setting.
final class IconGrid extends StatelessWidget {
  /// Creates a grid.
  const IconGrid({
    required this.icons,
    this.setting = const IconThemeData(),
    this.columns = 8,
    this.iconSize = 48,
    super.key,
  });

  /// The icons to draw.
  final List<IconData> icons;

  /// The axis setting they are drawn at.
  final IconThemeData setting;

  /// How many icons fit on a row.
  final int columns;

  /// How large each icon is drawn.
  final double iconSize;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row * columns < icons.length; row++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var column = 0;
                    column < columns && row * columns + column < icons.length;
                    column++
                  )
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: IconTheme(
                        data: setting.copyWith(
                          size: iconSize,
                          color: const Color(0xFF000000),
                        ),
                        child: Icon(icons[row * columns + column]),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
