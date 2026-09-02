import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/bindings/dart_identifiers.dart';
import 'package:variable_font_generator/src/generator/icon_axes.dart';
import 'package:variable_font_generator/src/generator/icon_font_generator.dart';

/// Thrown when two icons would produce the same Dart identifier.
final class IdentifierCollisionException implements Exception {
  /// Creates an exception naming both icons and the identifier they share.
  const IdentifierCollisionException({
    required this.identifier,
    required this.first,
    required this.second,
  });

  /// The identifier both icons wanted.
  final String identifier;

  /// The icon that claimed it first.
  final String first;

  /// The icon that collided with it.
  final String second;

  @override
  String toString() =>
      'Icons "$first" and "$second" both map to the Dart identifier '
      '"$identifier". Rename one of the source files.';
}

/// How the generated Dart file refers to the font.
///
/// Flutter resolves a font family declared by a package under the name
/// `packages/<package>/<family>`, and `TextStyle` adds that prefix itself when
/// it is given a package. So a font shipped inside a package has to name the
/// package, and one that lives in an application's own assets must not.
@immutable
final class FontReference {
  /// Creates a reference to a font shipped by [package].
  const FontReference.package({required this.family, required this.package});

  /// Creates a reference to a font declared in an application's own pubspec.
  const FontReference.application({required this.family}) : package = null;

  /// The font family name, which must match the `family:` in the pubspec.
  final String family;

  /// The package the font ships in, or `null` for an application-local font.
  final String? package;

  @override
  String toString() => package == null
      ? 'FontReference($family)'
      : 'FontReference($family in $package)';
}

/// Generates the Dart source of an icon class for a generated font.
///
/// Each icon becomes a `static const IconData` with the family and package
/// written out as string literals. That is deliberate: `IconData`'s parameters
/// are annotated `@mustBeConst`, and Flutter's release-mode icon tree shaker
/// only recognises literals, so pulling the family into a shared constant would
/// quietly stop the font being subset.
@immutable
final class FlutterBindingsGenerator {
  /// Creates a generator.
  const FlutterBindingsGenerator({
    required this.className,
    required this.font,
    this.extensionTypeName,
    this.axisSet = IconAxisSet.material,
    this.identifierStyle = IdentifierStyle.camelCase,
    this.mirroredInRightToLeft = const {},
    this.comments = const {},
    this.sourceDescription,
  });

  /// The name of the generated class.
  final String className;

  /// The name of an extension type wrapping `IconData`, or `null` to leave the
  /// icons as plain `IconData`.
  ///
  /// When set, every icon is declared with this type instead, and the type
  /// itself is written into the same library. It exists so that a signature can
  /// ask for an icon from this set in particular rather than any icon at all.
  ///
  /// An extension type is the only wrapper that costs nothing here. It is
  /// erased during compilation, so the values stay `IconData` instances and
  /// Flutter's icon tree shaker — which looks for constant `IconData` in the
  /// compiled program — still finds them. A subclass would not do: `IconData`
  /// is a `final class`, so it cannot be extended at all.
  ///
  /// The type is declared empty, and the icons stay inside the class. That is
  /// not a matter of taste: `@staticIconProvider` is what tells the tree
  /// shaker that a declaration is not a use, and the tool reads it off a
  /// class. An extension type is not one, so the annotation on it would be
  /// ignored without a word of complaint, and a web build — which has no
  /// whole-program pass to fall back on — would keep every icon in the set
  /// whether or not the application draws it.
  final String? extensionTypeName;

  /// How the generated code refers to the font.
  final FontReference font;

  /// The axes the font offers, used to document the class.
  final IconAxisSet axisSet;

  /// How icon names become identifiers.
  final IdentifierStyle identifierStyle;

  /// Icon names that should be flipped in right-to-left layouts.
  ///
  /// Names are matched as they appear in the source files, before they are
  /// turned into identifiers.
  final Set<String> mirroredInRightToLeft;

  /// What each icon's generated member says about itself, keyed the way
  /// [mirroredInRightToLeft] is: by the name in the source file.
  ///
  /// The comment becomes the summary line of the member's documentation, which
  /// is what a reader sees first and what tooling shows beside the name. A
  /// newline in it starts a new line of the comment. An icon with nothing said
  /// about it keeps the line naming its source file, and so does one with
  /// something said about it — knowing which file drew an icon is worth a line
  /// either way.
  final Map<String, String> comments;

  /// A line describing where the icons came from, included in the header.
  final String? sourceDescription;

  /// Generates the Dart source for [icons].
  ///
  /// Throws an [IdentifierCollisionException] when two icons would end up with
  /// the same name, which is worth failing on: the alternative is a duplicate
  /// member that either fails to compile or, if the two happen to differ in
  /// case only, silently shadows.
  String generate(List<GeneratedIcon> icons) {
    final entries = _entriesFor(icons);

    final buffer = StringBuffer();
    _writeHeader(buffer, source: sourceDescription);
    buffer
      ..writeln("import 'package:flutter/widgets.dart';")
      ..writeln();
    if (extensionTypeName case final typeName?) {
      buffer
        ..writeln('/// The type of every icon in [$className].')
        ..writeln('///')
        ..writeln(
          '/// It wraps [IconData] so that a signature can ask for an '
          'icon from this',
        )
        ..writeln('/// set in particular:')
        ..writeln('///')
        ..writeln('/// ```dart')
        ..writeln('/// Widget leading($typeName icon) => Icon(icon);')
        ..writeln('/// ```')
        ..writeln('///')
        ..writeln(
          '/// Nothing is wrapped at run time. An extension type is '
          'erased during',
        )
        ..writeln(
          '/// compilation, so one of these values is an [IconData] '
          'and nothing else,',
        )
        ..writeln(
          "/// which is what keeps Flutter's icon tree shaker working: "
          'it looks for',
        )
        ..writeln(
          '/// constant [IconData] in the compiled program, and that '
          'is exactly what',
        )
        ..writeln('/// it finds.')
        ..writeln(
          'extension type const $typeName(IconData _icon) implements IconData;',
        )
        ..writeln();
    }
    buffer
      ..writeln('/// Icons from the `${font.family}` variable icon font.')
      ..writeln('///')
      ..writeln('/// Every icon responds to the axes the font was built with.')
      ..writeln('/// Pass them to [Icon] or set them on an [IconThemeData]:')
      ..writeln('///')
      ..writeln('/// ```dart')
      ..writeln('/// Icon(')
      ..writeln(
        '///   $className.'
        '${entries.isEmpty ? 'anIcon' : entries.first.identifier},',
      )
      ..writeln('///   size: 32,');
    for (final axis in axisSet.axes) {
      final parameter = _flutterParameterFor(axis.axis.tag);
      if (parameter != null) {
        buffer.writeln('///   $parameter: ${_exampleValue(axis)},');
      }
    }
    buffer
      ..writeln('/// )')
      ..writeln('/// ```')
      ..writeln('///')
      ..writeln('/// The axes, as Flutter names them:')
      ..writeln('///');
    for (final axis in axisSet.axes) {
      final parameter = _flutterParameterFor(axis.axis.tag);
      final name = parameter == null ? 'A variation' : '[Icon.$parameter]';
      buffer.writeln(
        '/// * $name — `${axis.axis.tag}`, from ${_number(axis.axis.minimum)} '
        'to ${_number(axis.axis.maximum)}, '
        'default ${_number(axis.axis.defaultValue)}.',
      );
    }
    buffer
      ..writeln('///')
      ..writeln(
        "/// A value outside an axis's range is clamped by the renderer, and "
        'an axis',
      )
      ..writeln(
        '/// the font does not have is ignored without complaint, so a '
        'mismatch shows',
      )
      ..writeln('/// up as an icon that simply does not change.')
      ..writeln('@staticIconProvider')
      ..writeln('abstract final class $className {');

    for (var index = 0; index < entries.length; index++) {
      final (:identifier, :icon) = entries[index];
      if (index > 0) {
        buffer.writeln();
      }
      final indent = extensionTypeName == null ? '    ' : '      ';
      if (comments[icon.name] case final comment?) {
        for (final line in comment.split('\n')) {
          final text = line.trimRight();
          buffer.writeln(text.isEmpty ? '  ///' : '  /// $text');
        }
        buffer.writeln('  ///');
      }
      buffer.writeln('  /// The `${icon.name}` icon.');
      if (extensionTypeName case final typeName?) {
        buffer
          ..writeln('  static const $typeName $identifier = $typeName(')
          ..writeln('    IconData(');
      } else {
        buffer.writeln('  static const IconData $identifier = IconData(');
      }
      buffer
        ..writeln('${indent}0x${icon.codePoint.toRadixString(16)},')
        ..writeln("${indent}fontFamily: '${font.family}',");
      if (font.package case final package?) {
        buffer.writeln("${indent}fontPackage: '$package',");
      }
      if (mirroredInRightToLeft.contains(icon.name)) {
        buffer.writeln('${indent}matchTextDirection: true,');
      }
      if (extensionTypeName != null) {
        buffer.writeln('    ),');
      }
      buffer.writeln('  );');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generates a separate library listing every icon by name.
  ///
  /// This is deliberately not part of the icon class. Flutter's release-mode
  /// tree shaker keeps only the icons an application actually names, and a list
  /// naming all of them would keep every one of them. Putting the list in its
  /// own library means an application that wants to search or browse the set
  /// can import it and pay for it, while one that just draws a few icons never
  /// touches it.
  ///
  /// [libraryImport] is the import URI of the library [generate] wrote.
  String generateIndex(
    List<GeneratedIcon> icons, {
    required String libraryImport,
  }) {
    final entries = _entriesFor(icons);

    final listName = toDartIdentifier('all $className');
    final mapName = toDartIdentifier('$className by name');
    final iconType = extensionTypeName ?? 'IconData';

    final buffer = StringBuffer();
    _writeHeader(buffer);
    // The icon type is the only type these declarations name, so the Flutter
    // import is only pulled in when that type is `IconData` itself. Importing
    // it needlessly would leave `unused_import` on a generated file.
    if (extensionTypeName == null) {
      buffer
        ..writeln("import 'package:flutter/widgets.dart';")
        ..writeln();
    }
    buffer
      ..writeln("import '$libraryImport';")
      ..writeln()
      ..writeln('/// Every icon in [$className], in name order.')
      ..writeln('///')
      ..writeln(
        '/// Importing this library keeps every icon in a release build, '
        'because',
      )
      ..writeln(
        '/// naming them all is exactly what stops the tree shaker dropping '
        'any.',
      )
      ..writeln('/// Import it only where you need to enumerate the set.')
      ..writeln('const $listName = <$iconType>[');
    for (final entry in entries) {
      buffer.writeln('  $className.${entry.identifier},');
    }
    buffer
      ..writeln('];')
      ..writeln()
      ..writeln('/// Every icon in [$className], keyed by its source name.')
      ..writeln('///')
      ..writeln('/// See [$listName] for what importing this costs.')
      ..writeln('const $mapName = <String, $iconType>{');
    for (final entry in entries) {
      buffer.writeln("  '${entry.icon.name}': $className.${entry.identifier},");
    }
    buffer.writeln('};');
    return buffer.toString();
  }

  /// Writes the lines every generated file starts with.
  ///
  /// The two directives say what the file is. A formatter would rewrite
  /// machine output to no purpose, and a lint would report something nobody
  /// can go and fix, since editing the file by hand is the one thing the line
  /// above tells you not to do. Turning the formatter off also means the file
  /// is exactly what this wrote and nothing else, which is what lets a
  /// checked-in copy be compared against a fresh build byte for byte.
  void _writeHeader(StringBuffer buffer, {String? source}) {
    buffer
      ..writeln('// GENERATED BY package:variable_font_generator.')
      ..writeln('// Do not edit this file by hand.');
    if (source != null) {
      buffer.writeln('// Source: $source');
    }
    buffer
      ..writeln('//')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln('// dart format off')
      ..writeln();
  }

  /// Names every icon and sorts them, failing on a collision.
  ///
  /// Two icons that end up with the same identifier would produce a duplicate
  /// member — a compile error at best, and at worst, when the two differ only
  /// in case, one of them silently shadowing the other. Both source names are
  /// reported so that the person who has to rename one knows which two.
  List<({String identifier, GeneratedIcon icon})> _entriesFor(
    List<GeneratedIcon> icons,
  ) {
    final claimed = <String, String>{};
    final entries = <({String identifier, GeneratedIcon icon})>[];
    for (final icon in icons) {
      final identifier = toDartIdentifier(icon.name, style: identifierStyle);
      final existing = claimed[identifier];
      if (existing != null) {
        throw IdentifierCollisionException(
          identifier: identifier,
          first: existing,
          second: icon.name,
        );
      }
      claimed[identifier] = icon.name;
      entries.add((identifier: identifier, icon: icon));
    }
    return entries..sort((a, b) => a.identifier.compareTo(b.identifier));
  }

  /// The name of the `Icon` parameter that drives the given axis tag, if
  /// there is one.
  static String? _flutterParameterFor(String tag) => switch (tag) {
    'FILL' => 'fill',
    'wght' => 'weight',
    'GRAD' => 'grade',
    'opsz' => 'opticalSize',
    _ => null,
  };

  static String _exampleValue(IconAxis axis) =>
      _number(axis.controlsFill ? axis.axis.maximum : axis.axis.defaultValue);

  static String _number(double value) =>
      value == value.roundToDouble() && value.abs() < 1e15
      ? value.toStringAsFixed(1)
      : '$value';
}
