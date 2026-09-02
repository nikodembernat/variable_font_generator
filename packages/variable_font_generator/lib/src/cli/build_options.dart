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
    required this.libraryFileName,
    required this.names,
    this.className,
    this.extensionTypeName,
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
    this.summaryPath,
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

  /// The name of the generated Dart class, or `null` to write no bindings.
  ///
  /// Naming a class is the whole of the request for them. A build that only
  /// wants the font — because the icons are for a web page, or for a project
  /// that is not Flutter's — leaves it unset.
  final String? className;

  /// The file name of the generated Dart library, without a directory.
  final String libraryFileName;

  /// The name of an extension type wrapping `IconData`, or `null` to leave the
  /// icons as plain `IconData`.
  final String? extensionTypeName;

  /// The strings that go into the font's `name` table.
  final FontNames names;

  /// The Flutter package the font ships in, or `null` for an
  /// application-local font.
  ///
  /// It fills in `fontPackage` on every generated `IconData`, and does nothing
  /// else. Who the font belongs to and where its files are written are
  /// separate questions; [writePubspec] answers the second.
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

  /// Whether a `pubspec.yaml` is written alongside the output, making the
  /// output directory a Flutter package.
  final bool writePubspec;

  /// Whether the output is laid out as a Flutter package, with everything
  /// under `lib/`.
  ///
  /// A package can only expose what is under `lib/`, so writing a pubspec —
  /// which is what declares the output directory to be a package — is what
  /// decides this. A build that writes no pubspec leaves its files exactly
  /// where it was asked to put them.
  bool get isPackage => writePubspec;

  /// Where the code point assignments are remembered between builds.
  final String? codePointMapPath;

  /// Where a preview image of the generated icons is written, if anywhere.
  final String? previewPath;

  /// Where a `key=value` summary of what the build wrote is left, if anywhere.
  ///
  /// It exists so that whatever ran the build can find the files without
  /// having to know how the paths are put together. Appending it to a GitHub
  /// Actions step's `$GITHUB_OUTPUT` is exactly what that file wants.
  final String? summaryPath;

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
      isPackage ? 'lib/fonts/$family.ttf' : 'fonts/$family.ttf';

  /// Where the Dart library goes, relative to [outputDirectory].
  String get libraryRelativePath =>
      isPackage ? 'lib/$libraryFileName' : libraryFileName;

  /// The file name of the generated index library.
  String get indexFileName =>
      '${libraryFileName.replaceFirst(RegExp(r'\.dart$'), '')}_index.dart';

  /// Where the index library goes, relative to [outputDirectory].
  String get indexRelativePath =>
      isPackage ? 'lib/$indexFileName' : indexFileName;

  @override
  String toString() => 'BuildOptions($inputDirectory -> $outputDirectory)';
}
