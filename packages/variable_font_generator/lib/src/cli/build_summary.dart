import 'package:path/path.dart' as p;
import 'package:variable_font_generator/src/cli/build_options.dart';
import 'package:variable_font_generator/src/cli/build_runner.dart';

/// Describes a finished build as `key=value` lines, one per line.
///
/// The format is deliberately the dullest one that a shell can read without a
/// parser, because the thing most likely to read it is a continuous
/// integration step: appending this to `$GITHUB_OUTPUT` turns every path the
/// build wrote into an output of the step that ran it.
///
/// Only keys the build actually produced appear. No value contains a newline,
/// which is what lets the file be concatenated onto `$GITHUB_OUTPUT` as it is.
String formatBuildSummary(BuildOptions options, BuildResult result) {
  final entries = <String, String?>{
    'family': options.family,
    'package': options.packageName,
    'class-name': options.emitBindings ? options.className : null,
    'extension-name': options.emitBindings ? options.extensionTypeName : null,
    'icon-count': '${result.iconCount}',
    'font-bytes': '${result.fontBytes}',
    'font': result.fontPath,
    'bindings': result.libraryPath,
    'index': result.indexPath,
    'pubspec': result.pubspecPath,
    'codepoints': result.codePointMapPath,
    'preview': result.previewPath,
  };

  final buffer = StringBuffer();
  for (final MapEntry(:key, :value) in entries.entries) {
    if (value != null) {
      buffer.writeln('$key=${_isPath(key) ? p.normalize(value) : value}');
    }
  }
  return buffer.toString();
}

/// Whether the value under [key] is a file system path, and so worth tidying
/// before it is written out.
bool _isPath(String key) => const {
  'font',
  'bindings',
  'index',
  'pubspec',
  'codepoints',
  'preview',
}.contains(key);
