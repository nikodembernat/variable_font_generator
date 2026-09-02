import 'package:recase/recase.dart';

/// Every reserved word and built-in identifier that cannot be used as a class
/// member name in Dart.
///
/// The contextual keywords are included as well. They are legal in some
/// positions, but a static field called `await` or `yield` is a trap for anyone
/// reading the generated code, so they are renamed too.
const dartReservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

/// Members every Dart class inherits from `Object`, which a static field cannot
/// shadow without confusing readers.
const dartObjectMembers = {
  'hashCode',
  'noSuchMethod',
  'runtimeType',
  'toString',
};

/// How a leading digit is spelled out so that a name can start a Dart
/// identifier.
///
/// The entries mirror the ones Flutter's own icon generator uses, so an icon
/// set that follows Material's naming produces the same identifiers here as it
/// would in `package:flutter`.
const leadingNumberNames = {
  '1': 'one',
  '2': 'two',
  '3': 'three',
  '4': 'four',
  '5': 'five',
  '6': 'six',
  '7': 'seven',
  '8': 'eight',
  '9': 'nine',
  '10': 'ten',
  '11': 'eleven',
  '12': 'twelve',
  '13': 'thirteen',
  '14': 'fourteen',
  '15': 'fifteen',
  '16': 'sixteen',
  '17': 'seventeen',
  '18': 'eighteen',
  '19': 'nineteen',
  '20': 'twenty',
  '21': 'twentyOne',
  '22': 'twentyTwo',
  '23': 'twentyThree',
  '24': 'twentyFour',
  '30': 'thirty',
  '60': 'sixty',
  '360': 'threeSixty',
};

/// How generated identifiers are cased.
enum IdentifierStyle {
  /// `arrow-right` becomes `arrowRight`, the Dart convention for a member.
  camelCase,

  /// `arrow-right` becomes `arrow_right`, matching Flutter's own `Icons`
  /// class, which predates the convention.
  snakeCase;

  /// Applies this style to [name].
  String apply(String name) => switch (this) {
    IdentifierStyle.camelCase => ReCase(name).camelCase,
    IdentifierStyle.snakeCase => ReCase(name).snakeCase,
  };
}

/// Turns an icon's file name into a valid Dart member name.
///
/// The casing is `package:recase`'s, which is what makes `arrow-right` come out
/// as `arrowRight`. Three things `recase` cannot help with are fixed
/// afterwards: a name starting with a digit is not a valid identifier, a name
/// that collides with a reserved word will not compile, and a name starting
/// with an underscore would be library-private and invisible to the package's
/// users.
String toDartIdentifier(
  String name, {
  IdentifierStyle style = IdentifierStyle.camelCase,
}) {
  var stem = name.trim();

  // A leading number is spelled out, so `1-circle` becomes `oneCircle` rather
  // than the invalid `1Circle`. The longest matching run of digits wins, which
  // is what makes `10k` read as `tenK` and not `oneZeroK`.
  final digits = RegExp('^([0-9]+)').firstMatch(stem)?.group(1);
  if (digits != null) {
    for (var length = digits.length; length >= 1; length--) {
      final word = leadingNumberNames[digits.substring(0, length)];
      if (word != null) {
        stem = '$word-${stem.substring(length)}';
        break;
      }
    }
  }

  var identifier = style.apply(stem);
  identifier = identifier.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), '');
  while (identifier.startsWith('_')) {
    identifier = identifier.substring(1);
  }
  if (identifier.isEmpty) {
    identifier = 'icon';
  }
  if (RegExp('^[0-9]').hasMatch(identifier)) {
    identifier = 'n$identifier';
  }
  if (dartReservedWords.contains(identifier) ||
      dartObjectMembers.contains(identifier)) {
    identifier = style == IdentifierStyle.snakeCase
        ? '${identifier}_icon'
        : '${identifier}Icon';
  }
  return identifier;
}
