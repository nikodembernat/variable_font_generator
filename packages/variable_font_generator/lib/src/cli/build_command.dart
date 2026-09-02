import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:recase/recase.dart';
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
        defaultsTo: 'build/icons',
      )
      ..addOption(
        'family',
        help: 'The font family name. Also names the generated font file.',
        valueHelp: 'name',
        defaultsTo: 'CustomIcons',
      )
      ..addOption(
        'class-name',
        help: 'The generated Dart class. Defaults to the family name.',
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
        allowed: ['FILL', 'wght', 'GRAD', 'opsz'],
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

    final family = results.option('family')!;
    final packageName = results.option('package');
    final className = results.option('class-name') ?? ReCase(family).pascalCase;
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
      libraryFileName: libraryFileName,
      packageName: packageName,
      axisSet: IconAxisSet([
        for (final axis in IconAxisSet.material.axes)
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
      previewPath: results.option('preview'),
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
      ..writeln('  font     ${p.normalize(result.fontPath)}')
      ..writeln('  bindings ${p.normalize(result.libraryPath)}');
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
    return 0;
  }

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
