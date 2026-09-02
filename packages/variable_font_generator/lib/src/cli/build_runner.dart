import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:variable_font_generator/src/bindings/flutter_bindings.dart';
import 'package:variable_font_generator/src/bindings/flutter_pubspec.dart';
import 'package:variable_font_generator/src/cli/build_options.dart';
import 'package:variable_font_generator/src/cli/build_summary.dart';
import 'package:variable_font_generator/src/cli/codepoint_map.dart';
import 'package:variable_font_generator/src/cli/icon_loader.dart';
import 'package:variable_font_generator/src/generator/icon_font_generator.dart';
import 'package:variable_font_generator/src/raster/preview.dart';

/// What a build produced, so a caller can report it or check it.
typedef BuildResult = ({
  int iconCount,
  int fontBytes,
  String fontPath,
  String? libraryPath,
  String? indexPath,
  String? pubspecPath,
  String? previewPath,
  String? codePointMapPath,
  String? summaryPath,
});

/// Runs a build described by [options], writing the font and its bindings.
BuildResult runBuild(BuildOptions options, {void Function(String)? log}) {
  void report(String message) => log?.call(message);

  final icons = loadSvgIcons(
    Directory(options.inputDirectory),
    recursive: options.recursive,
  );
  if (icons.isEmpty) {
    throw StateError('No SVG files found in ${options.inputDirectory}');
  }
  report('Read ${icons.length} icons from ${options.inputDirectory}');

  final mapPath = options.codePointMapPath;
  final codePointMap = switch (mapPath) {
    final path? when File(path).existsSync() => CodePointMap.fromJson(
      File(path).readAsStringSync(),
    ),
    _ => CodePointMap(),
  };
  final previouslyKnown = codePointMap.length;
  final codePoints = codePointMap.assign([
    for (final icon in icons) icon.name,
  ], startCodePoint: options.startCodePoint);
  if (mapPath != null && previouslyKnown > 0) {
    report(
      'Kept $previouslyKnown existing code point '
      '${previouslyKnown == 1 ? 'assignment' : 'assignments'} from $mapPath',
    );
  }

  final generator = IconFontGenerator(
    axisSet: options.axisSet,
    metrics: options.metrics,
    curveTolerance: options.curveTolerance,
    startCodePoint: options.startCodePoint,
  );
  final font = generator.generate(
    icons: icons,
    names: options.names,
    codePoints: codePoints,
    vendorId: options.vendorId,
    timestamp: options.timestamp,
  );
  report(
    'Built ${options.family} with ${options.axisSet.tags.join(', ')} '
    '(${_describeSize(font.bytes.length)})',
  );

  final fontPath = p.join(options.outputDirectory, options.fontRelativePath);
  _write(fontPath, (file) => file.writeAsBytesSync(font.bytes));

  final reference = switch (options.packageName) {
    final package? => FontReference.package(
      family: options.family,
      package: package,
    ),
    null => FontReference.application(family: options.family),
  };
  final bindingsGenerator = FlutterBindingsGenerator(
    className: options.className,
    font: reference,
    extensionTypeName: options.extensionTypeName,
    axisSet: options.axisSet,
    identifierStyle: options.identifierStyle,
    mirroredInRightToLeft: options.mirroredInRightToLeft,
    sourceDescription:
        '${icons.length} icons from ${p.basename(options.inputDirectory)}',
  );

  String? libraryPath;
  String? indexPath;
  if (options.emitBindings) {
    libraryPath = p.join(options.outputDirectory, options.libraryRelativePath);
    _write(
      libraryPath,
      (file) => file.writeAsStringSync(bindingsGenerator.generate(font.icons)),
    );

    if (options.emitIndex) {
      indexPath = p.join(options.outputDirectory, options.indexRelativePath);
      _write(
        indexPath,
        (file) => file.writeAsStringSync(
          bindingsGenerator.generateIndex(
            font.icons,
            libraryImport: switch (options.packageName) {
              final package? => 'package:$package/${options.libraryFileName}',
              null => options.libraryFileName,
            },
          ),
        ),
      );
    }
  } else if (options.emitIndex) {
    throw StateError(
      'An index library lists the icons the bindings declare, so it needs '
      'them; either ask for bindings or drop the index',
    );
  }

  String? pubspecPath;
  if (options.writePubspec) {
    final packageName = options.packageName;
    if (packageName == null) {
      throw StateError(
        'A pubspec can only be written for a package; pass a package name',
      );
    }
    pubspecPath = p.join(options.outputDirectory, 'pubspec.yaml');
    _write(
      pubspecPath,
      (file) => file.writeAsStringSync(
        FlutterPubspecGenerator(
          font: reference,
          assetPath: options.fontRelativePath,
        ).package(
          name: packageName,
          description:
              '${options.family}: ${icons.length} variable icons, generated '
              'by package:variable_font_generator.',
        ),
      ),
    );
  }

  String? codePointsPath;
  if (mapPath != null) {
    codePointsPath = mapPath;
    _write(mapPath, (file) => file.writeAsStringSync(codePointMap.toJson()));
  }

  String? previewPath;
  if (options.previewPath case final path?) {
    previewPath = path;
    _write(
      path,
      (file) => file.writeAsBytesSync(
        renderPreviewSheet(
          icons: icons,
          axisSet: options.axisSet,
          metrics: options.metrics,
          curveTolerance: options.curveTolerance,
        ),
      ),
    );
    report('Wrote a preview to $path');
  }

  final result = (
    iconCount: icons.length,
    fontBytes: font.bytes.length,
    fontPath: fontPath,
    libraryPath: libraryPath,
    indexPath: indexPath,
    pubspecPath: pubspecPath,
    previewPath: previewPath,
    codePointMapPath: codePointsPath,
    summaryPath: options.summaryPath,
  );

  // Written last, and describing everything above it, so that a reader who
  // finds the file can trust that the build finished.
  if (options.summaryPath case final path?) {
    _write(
      path,
      (file) => file.writeAsStringSync(formatBuildSummary(options, result)),
    );
  }

  return result;
}

void _write(String path, void Function(File file) write) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  write(file);
}

String _describeSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
