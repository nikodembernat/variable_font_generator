import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:variable_font_generator/src/bindings/dart_identifiers.dart';
import 'package:variable_font_generator/src/cli/build_options.dart';
import 'package:variable_font_generator/src/cli/build_runner.dart';
import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/font/font_names.dart';
import 'package:variable_font_generator/src/generator/icon_axes.dart';

/// Builds a variable icon font and its Flutter bindings from a directory of
/// SVG files.
final class BuildCommand extends Command<int> {
  /// Creates the command and declares its options.
  BuildCommand({Stdout? output}) : _output = output ?? stdout {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Directory the font and bindings are written to.',
        valueHelp: 'dir',
        defaultsTo: '.',
      )
      ..addOption(
        'family',
        help:
            'The font family name, which also names the generated font file. '
            'Defaults to the class name, or to CustomIcons when there is no '
            'class either.',
        valueHelp: 'name',
      )
      ..addOption(
        'class-name',
        help:
            'The Dart class to hold every icon. Naming one is what asks for '
            'the Flutter bindings; without it only the font is written, which '
            "is what a project that is not Flutter's wants.",
        valueHelp: 'name',
      )
      ..addOption(
        'extension-name',
        help:
            'Declares an extension type of this name wrapping IconData, and '
            'gives every generated icon that type, so that a signature can ask '
            'for an icon from this set rather than any icon at all. Costs '
            'nothing at run time and leaves icon tree shaking working, because '
            'an extension type is erased during compilation. Needs Dart 3.3 '
            'in the project the bindings land in.',
        valueHelp: 'name',
      )
      ..addOption(
        'package',
        help:
            'The Flutter package the font ships in. Setting it writes a '
            'package layout with the font under lib/, and fills in '
            'fontPackage on every generated IconData.',
        valueHelp: 'name',
      )
      ..addOption(
        'library',
        help:
            'File name of the generated Dart library. Defaults to the package '
            'name, or icons.dart.',
        valueHelp: 'file.dart',
      )
      ..addOption(
        'naming',
        help: 'How icon names become Dart identifiers.',
        allowed: ['camel', 'snake'],
        allowedHelp: {
          'camel': 'arrow-right becomes arrowRight (the Dart convention).',
          'snake': "arrow-right becomes arrow_right (Flutter's Icons class).",
        },
        defaultsTo: 'camel',
      )
      ..addMultiOption(
        'axes',
        help: 'Which variation axes the font offers.',
        allowed: ['FILL', 'wght', 'GRAD', 'opsz', 'wdth'],
        allowedHelp: {
          'FILL': 'Closes the holes in outlined shapes. Icon.fill.',
          'wght': 'Thickens the strokes. Icon.weight.',
          'GRAD': 'Thickens them more finely. Icon.grade.',
          'opsz': 'Thins them as the icon grows. Icon.opticalSize.',
          'wdth':
              'Narrows or widens the shapes. Off by default: the Icon widget '
              'cannot drive it, so it needs a TextStyle fontVariations entry.',
        },
        defaultsTo: ['FILL', 'wght', 'GRAD', 'opsz'],
      )
      ..addOption(
        'units-per-em',
        help: "The font's design grid resolution.",
        valueHelp: 'n',
        defaultsTo: '1000',
      )
      ..addOption(
        'curve-tolerance',
        help:
            'How far, in design units, a curve may deviate from the artwork. '
            'Raising it makes a smaller font out of coarser outlines.',
        valueHelp: 'units',
        defaultsTo: '1',
      )
      ..addOption(
        'start-codepoint',
        help: 'The code point the first icon is placed at.',
        valueHelp: 'hex',
        defaultsTo: '0xE000',
      )
      ..addOption(
        'codepoints',
        help:
            'A JSON file remembering which code point each icon has. Keeping '
            'it means adding or removing icons never moves the others, which '
            'would silently change what an already-published application '
            'draws.',
        valueHelp: 'file.json',
      )
      ..addOption(
        'comments',
        help:
            'A JSON file of doc comments for the generated icons, keyed by '
            'icon name exactly as --codepoints is. Each becomes the summary '
            'line of its member, above the line naming the source file.',
        valueHelp: 'file.json',
      )
      ..addOption(
        'font-version',
        help: 'The version recorded in the font.',
        valueHelp: 'x.yyy',
        defaultsTo: '1.000',
      )
      ..addOption('copyright', help: 'Copyright notice for the font.')
      ..addOption('designer', help: 'Designer credited in the font.')
      ..addOption('manufacturer', help: 'Manufacturer credited in the font.')
      ..addOption('license', help: 'License description stored in the font.')
      ..addOption('license-url', help: 'License URL stored in the font.')
      ..addOption(
        'vendor-id',
        help: 'Four character foundry identifier stored in OS/2.',
        valueHelp: 'ABCD',
        defaultsTo: 'NONE',
      )
      ..addMultiOption(
        'mirror-rtl',
        help:
            'Icon names that should be flipped in right-to-left layouts. Sets '
            'matchTextDirection on their IconData.',
        valueHelp: 'name',
      )
      ..addOption(
        'summary',
        help:
            'Write a key=value summary of everything the build produced. '
            r'Point it at $GITHUB_OUTPUT to turn the paths into the outputs '
            'of a GitHub Actions step.',
        valueHelp: 'file',
      )
      ..addOption(
        'preview',
        help:
            'Write a PNG contact sheet showing a sample of the icons at every '
            'axis extreme.',
        valueHelp: 'file.png',
      )
      ..addFlag(
        'index',
        help:
            'Also write a second library listing every icon by name. Keep it '
            'out of an application that only draws a few icons: naming them '
            'all is what stops the release build dropping the rest.',
      )
      ..addFlag(
        'recursive',
        abbr: 'r',
        help: 'Search sub directories of the input for SVG files.',
      )
      ..addFlag(
        'pubspec',
        help: 'Write a pubspec.yaml declaring the font. Requires --package.',
      )
      ..addFlag(
        'reproducible',
        help:
            'Record a fixed timestamp in the font so that two builds of the '
            'same icons produce identical bytes.',
        defaultsTo: true,
      );
  }

  final Stdout _output;

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build a variable icon font and Flutter bindings from a directory of '
      'SVG files.';

  @override
  String get invocation => 'variable_font_generator build <svg-directory>';

  @override
  Future<int> run() async {
    final results = argResults!;
    final rest = results.rest;
    if (rest.length != 1) {
      usageException('Expected exactly one directory of SVG files.');
    }

    final packageName = results.option('package');
    final className = results.option('class-name');
    final extensionTypeName = results.option('extension-name');

    // Naming a class is the whole of the request for bindings, and the class
    // names the font too unless something else was asked for, so that a set
    // has one name rather than two that have to be kept in step.
    final family = results.option('family') ?? className ?? _defaultFamily;

    if (className == null) {
      for (final describesBindings in [
        if (extensionTypeName != null) '--extension-name',
        if (results.option('library') != null) '--library',
        if (results.option('comments') != null) '--comments',
        if (results.flag('index')) '--index',
      ]) {
        usageException(
          '$describesBindings describes the Dart bindings, which are only '
          'written when --class-name names a class to put them in.',
        );
      }
    } else {
      if (!isPublicDartIdentifier(className)) {
        usageException(
          '"$className" cannot name a Dart class. Pass --class-name with a '
          'name that can.',
        );
      }
      if (extensionTypeName != null &&
          !isPublicDartIdentifier(extensionTypeName)) {
        usageException(
          '"$extensionTypeName" cannot name a Dart extension type.',
        );
      }
      if (extensionTypeName == className) {
        usageException(
          'The icon class and the extension type would both be called '
          '"$className", and one declaration would shadow the other.',
        );
      }
    }
    final libraryFileName =
        results.option('library') ??
        (packageName == null ? 'icons.dart' : '$packageName.dart');
    final unitsPerEm = int.parse(results.option('units-per-em')!);
    final requested = results.multiOption('axes').toSet();

    final options = BuildOptions(
      inputDirectory: rest.single,
      outputDirectory: results.option('output')!,
      family: family,
      className: className,
      extensionTypeName: extensionTypeName,
      libraryFileName: libraryFileName,
      packageName: packageName,
      axisSet: IconAxisSet([
        for (final axis in IconAxisSet.everything.axes)
          if (requested.contains(axis.axis.tag)) axis,
      ]),
      metrics: FontMetrics(
        unitsPerEm: unitsPerEm,
        ascender: (unitsPerEm * 0.8).round(),
        descender: -(unitsPerEm * 0.2).round(),
      ),
      identifierStyle: results.option('naming') == 'snake'
          ? IdentifierStyle.snakeCase
          : IdentifierStyle.camelCase,
      startCodePoint: _parseCodePoint(results.option('start-codepoint')!),
      curveTolerance: double.parse(results.option('curve-tolerance')!),
      vendorId: results.option('vendor-id')!.padRight(4).substring(0, 4),
      emitIndex: results.flag('index'),
      recursive: results.flag('recursive'),
      writePubspec: results.flag('pubspec'),
      codePointMapPath: results.option('codepoints'),
      commentsPath: results.option('comments'),
      previewPath: results.option('preview'),
      summaryPath: results.option('summary'),
      mirroredInRightToLeft: results.multiOption('mirror-rtl').toSet(),
      timestamp: results.flag('reproducible') ? DateTime.utc(2000) : null,
      names: FontNames(
        family: family,
        version: results.option('font-version')!,
        copyright: results.option('copyright'),
        designer: results.option('designer'),
        manufacturer: results.option('manufacturer'),
        license: results.option('license'),
        licenseUrl: results.option('license-url'),
        description:
            'A variable icon font generated by variable_font_generator.',
      ),
    );

    final result = runBuild(options, log: _output.writeln);
    _output
      ..writeln()
      ..writeln('  font     ${p.normalize(result.fontPath)}');
    if (result.libraryPath case final path?) {
      _output.writeln('  bindings ${p.normalize(path)}');
    }
    if (result.indexPath case final path?) {
      _output.writeln('  index    ${p.normalize(path)}');
    }
    if (result.pubspecPath case final path?) {
      _output.writeln('  pubspec  ${p.normalize(path)}');
    }
    if (result.codePointMapPath case final path?) {
      _output.writeln('  points   ${p.normalize(path)}');
    }
    if (result.previewPath case final path?) {
      _output.writeln('  preview  ${p.normalize(path)}');
    }
    if (result.summaryPath case final path?) {
      _output.writeln('  summary  ${p.normalize(path)}');
    }
    return 0;
  }

  /// The family a build falls back to when it is told neither a family nor a
  /// class to name one after.
  static const _defaultFamily = 'CustomIcons';

  static int _parseCodePoint(String value) {
    final normalized = value.toLowerCase().replaceFirst(
      RegExp(r'^(0x|u\+)'),
      '',
    );
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) {
      throw FormatException('Not a hexadecimal code point: $value');
    }
    return parsed;
  }
}
