import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/bindings/dart_identifiers.dart';
import 'package:variable_font_generator/src/font/font_metrics.dart';
import 'package:variable_font_generator/src/font/font_names.dart';
import 'package:variable_font_generator/src/generator/icon_axes.dart';
import 'package:variable_font_generator/src/generator/icon_font_generator.dart';

/// Everything a build needs to know, resolved from the command line.
@immutable
final class BuildOptions {
  /// Creates a set of options.
  const BuildOptions({
    required this.inputDirectory,
    required this.outputDirectory,
    required this.family,
    required this.className,
    required this.libraryFileName,
    required this.names,
    this.packageName,
    this.axisSet = IconAxisSet.material,
    this.metrics = const FontMetrics(),
    this.identifierStyle = IdentifierStyle.camelCase,
    this.startCodePoint = privateUseAreaStart,
    this.curveTolerance = 1,
    this.vendorId = 'NONE',
    this.recursive = false,
    this.writePubspec = false,
    this.codePointMapPath,
    this.previewPath,
    this.emitIndex = false,
    this.mirroredInRightToLeft = const {},
    this.timestamp,
  });

  /// Where the SVG files are.
  final String inputDirectory;

  /// Where everything is written.
  final String outputDirectory;

  /// The font family name.
  final String family;

  /// The name of the generated Dart class.
  final String className;

  /// The file name of the generated Dart library, without a directory.
  final String libraryFileName;

  /// The strings that go into the font's `name` table.
  final FontNames names;

  /// The Flutter package the font ships in, or `null` for an
  /// application-local font.
  ///
  /// When set, a complete package layout is written: the font under `lib/`,
  /// where other projects can reach it, and `fontPackage` filled in on every
  /// generated `IconData`.
  final String? packageName;

  /// The axes the font will offer.
  final IconAxisSet axisSet;

  /// The em size and vertical metrics.
  final FontMetrics metrics;

  /// How icon names become Dart identifiers.
  final IdentifierStyle identifierStyle;

  /// The code point the first icon is placed at.
  final int startCodePoint;

  /// How far, in design units, a curve may deviate from the artwork.
  final double curveTolerance;

  /// The four character foundry identifier stored in `OS/2`.
  final String vendorId;

  /// Whether sub directories of the input are searched too.
  final bool recursive;

  /// Whether a `pubspec.yaml` is written alongside the output.
  final bool writePubspec;

  /// Where the code point assignments are remembered between builds.
  final String? codePointMapPath;

  /// Where a preview image of the generated icons is written, if anywhere.
  final String? previewPath;

  /// Whether a second library listing every icon by name is written.
  final bool emitIndex;

  /// Icon names that should be flipped in right-to-left layouts.
  final Set<String> mirroredInRightToLeft;

  /// The timestamp recorded in the font, or `null` for the current time.
  ///
  /// Pinning it makes a build byte-for-byte reproducible, which is what lets a
  /// generated font be compared against a golden file.
  final DateTime? timestamp;

  /// Where the font file goes, relative to [outputDirectory].
  String get fontRelativePath =>
      packageName == null ? 'fonts/$family.ttf' : 'lib/fonts/$family.ttf';

  /// Where the Dart library goes, relative to [outputDirectory].
  String get libraryRelativePath =>
      packageName == null ? libraryFileName : 'lib/$libraryFileName';

  /// The file name of the generated index library.
  String get indexFileName =>
      '${libraryFileName.replaceFirst(RegExp(r'\.dart$'), '')}_index.dart';

  /// Where the index library goes, relative to [outputDirectory].
  String get indexRelativePath =>
      packageName == null ? indexFileName : 'lib/$indexFileName';

  @override
  String toString() => 'BuildOptions($inputDirectory -> $outputDirectory)';
}
