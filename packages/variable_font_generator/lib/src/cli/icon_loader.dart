import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:variable_font_generator/src/svg/svg_icon.dart';
import 'package:variable_font_generator/src/svg/svg_parser.dart';

/// Reads every SVG file in [directory] and parses it into an [SvgIcon].
///
/// Icons come back sorted by name so that a build is reproducible: the order
/// decides which code point each icon gets, and a directory listing's order is
/// not guaranteed.
///
/// [recursive] walks sub directories as well, naming an icon by its path
/// relative to [directory] with separators turned into hyphens, so
/// `arrows/left.svg` becomes `arrows-left`.
List<SvgIcon> loadSvgIcons(Directory directory, {bool recursive = false}) {
  if (!directory.existsSync()) {
    throw FileSystemException('No such directory', directory.path);
  }
  final files =
      directory
          .listSync(recursive: recursive)
          .whereType<File>()
          .where((file) => p.extension(file.path).toLowerCase() == '.svg')
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final icons = <SvgIcon>[];
  final seen = <String, String>{};
  for (final file in files) {
    final relative = p.relative(file.path, from: directory.path);
    final name = p.withoutExtension(relative).replaceAll(RegExp(r'[\\/]'), '-');
    final previous = seen[name];
    if (previous != null) {
      throw StateError(
        'Two icons are both named "$name": $previous and ${file.path}',
      );
    }
    seen[name] = file.path;
    icons.add(parseSvgIcon(file.readAsStringSync(), name: name));
  }
  icons.sort((a, b) => a.name.compareTo(b.name));
  return icons;
}
