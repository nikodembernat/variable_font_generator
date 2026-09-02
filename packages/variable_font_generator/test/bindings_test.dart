import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// What the Dart grammar allows as a member name, minus the leading underscore
/// that would make the member library-private.
final validDartIdentifier = RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$');

/// Names chosen to break an identifier generator: empty, punctuation only,
/// leading digits with and without a spelled-out word, reserved words,
/// `Object` members, leading underscores and non-ASCII letters.
const awkwardNames = [
  '',
  '   ',
  '---',
  '!!!',
  '.',
  '1',
  '10k',
  '24-hours',
  '0-ring',
  '99-bottles',
  '2.5x',
  'class',
  'switch',
  'in',
  'is',
  'hash-code',
  'to-string',
  '_hidden',
  '_-x',
  'a b c',
  r'a$b',
  'ÜBER',
  '🙂',
  'arrow-right',
];

void main() {
  group('toDartIdentifier', () {
    test('camel cases a hyphenated icon name', () {
      expect(toDartIdentifier('arrow-right'), 'arrowRight');
      expect(toDartIdentifier('a-large-small'), 'aLargeSmall');
    });

    test('snake cases the same names when asked for that style', () {
      expect(
        toDartIdentifier('arrow-right', style: IdentifierStyle.snakeCase),
        'arrow_right',
      );
      expect(
        toDartIdentifier('a-large-small', style: IdentifierStyle.snakeCase),
        'a_large_small',
      );
    });

    test('spells out a leading digit so the name can start an identifier', () {
      expect(toDartIdentifier('1-circle'), 'oneCircle');
      expect(toDartIdentifier('24-hours'), startsWith('twentyFour'));
      expect(toDartIdentifier('360-degrees'), 'threeSixtyDegrees');
      expect(
        toDartIdentifier('1-circle', style: IdentifierStyle.snakeCase),
        'one_circle',
      );
    });

    test('takes the longest run of digits it has a word for', () {
      // `10k` has to read as `tenK`; taking the shortest run would give the
      // nonsense `oneZeroK`.
      expect(toDartIdentifier('10k'), 'tenK');
      // `99` has no word, so the single leading digit is spelled out and the
      // rest of the number is left alone.
      expect(toDartIdentifier('99-bottles'), 'nine9Bottles');
    });

    test('prefixes a letter when no leading digit has a word at all', () {
      expect(toDartIdentifier('0-ring'), 'n0Ring');
      expect(
        toDartIdentifier('0-ring', style: IdentifierStyle.snakeCase),
        'n0_ring',
      );
    });

    test('suffixes a reserved word so the generated member compiles', () {
      for (final word in [
        'class',
        'switch',
        'new',
        'try',
        'void',
        'in',
        'is',
      ]) {
        expect(toDartIdentifier(word), '${word}Icon', reason: word);
        expect(
          toDartIdentifier(word, style: IdentifierStyle.snakeCase),
          '${word}_icon',
          reason: word,
        );
      }
    });

    test('suffixes a name that would shadow a member of Object', () {
      expect(toDartIdentifier('hash-code'), 'hashCodeIcon');
      expect(toDartIdentifier('runtime-type'), 'runtimeTypeIcon');
      expect(toDartIdentifier('to-string'), 'toStringIcon');
      // Snake case never collides, because no `Object` member is snake cased.
      expect(
        toDartIdentifier('hash-code', style: IdentifierStyle.snakeCase),
        'hash_code',
      );
    });

    test('drops a leading underscore so the icon is not library private', () {
      expect(toDartIdentifier('_hidden'), 'hidden');
      expect(toDartIdentifier('_-x'), 'x');
      expect(
        toDartIdentifier('_hidden', style: IdentifierStyle.snakeCase),
        'hidden',
      );
    });

    test(
      'still yields a usable name for an empty or punctuation-only name',
      () {
        expect(toDartIdentifier(''), 'icon');
        expect(toDartIdentifier('   '), 'icon');
        expect(toDartIdentifier('---'), 'icon');
        expect(toDartIdentifier('!!!'), 'icon');
        expect(toDartIdentifier('🙂'), 'icon');
      },
    );

    test('trims surrounding whitespace before casing the name', () {
      expect(toDartIdentifier('  arrow-right\n'), 'arrowRight');
    });

    test('always produces a name Dart would accept as a member', () {
      for (final name in awkwardNames) {
        for (final style in IdentifierStyle.values) {
          final identifier = toDartIdentifier(name, style: style);
          final where = '"$name" as ${style.name}';
          expect(identifier, matches(validDartIdentifier), reason: where);
          expect(dartReservedWords, isNot(contains(identifier)), reason: where);
          expect(dartObjectMembers, isNot(contains(identifier)), reason: where);
        }
      }
    });

    test('gives every fixture icon a distinct valid identifier', () {
      for (final style in IdentifierStyle.values) {
        final identifiers = {
          for (final icon in fixtureIcons)
            toDartIdentifier(icon.name, style: style),
        };
        expect(
          identifiers,
          hasLength(fixtureIcons.length),
          reason: 'two fixture icons collided in ${style.name}',
        );
        for (final identifier in identifiers) {
          expect(identifier, matches(validDartIdentifier));
        }
      }
    });
  });

  group('isPublicDartIdentifier', () {
    test('accepts what can name a public class', () {
      expect(isPublicDartIdentifier('LucideIcons'), isTrue);
      expect(isPublicDartIdentifier('MyIconData'), isTrue);
      expect(isPublicDartIdentifier(r'$Weird'), isTrue);
      expect(isPublicDartIdentifier('a1_b2'), isTrue);
    });

    test('rejects what cannot', () {
      expect(isPublicDartIdentifier(''), isFalse);
      expect(isPublicDartIdentifier('My Icons'), isFalse);
      expect(isPublicDartIdentifier('my-icons'), isFalse);
      expect(isPublicDartIdentifier('9Lives'), isFalse);
      expect(isPublicDartIdentifier('class'), isFalse);
      expect(isPublicDartIdentifier('extension'), isFalse);
    });

    test('rejects a private name, which nobody outside could use', () {
      expect(isPublicDartIdentifier('_Hidden'), isFalse);
    });

    test('accepts every identifier the icon namer produces', () {
      for (final name in awkwardNames) {
        expect(
          isPublicDartIdentifier(toDartIdentifier(name)),
          isTrue,
          reason: 'from "$name"',
        );
      }
    });
  });

  group('parseIconComments', () {
    test('reads a comment for each name it is given', () {
      expect(
        parseIconComments('{"house": "Home.", "x": "Closes the thing."}'),
        {'house': 'Home.', 'x': 'Closes the thing.'},
      );
    });

    test('keeps the newlines that separate the lines of a comment', () {
      expect(parseIconComments(r'{"house": "Home.\nThe first tab."}'), {
        'house': 'Home.\nThe first tab.',
      });
    });

    test('treats a comment with nothing in it as no comment at all', () {
      // Emptying an entry out should be the same as deleting it, rather than
      // leaving a member with a blank line of documentation above it.
      expect(
        parseIconComments(r'{"house": "", "x": "   ", "y": "\n"}'),
        isEmpty,
      );
    });

    test('rejects anything that is not an object of comments', () {
      expect(() => parseIconComments('[]'), throwsFormatException);
      expect(() => parseIconComments('"house"'), throwsFormatException);
      expect(() => parseIconComments('{"house": 3}'), throwsFormatException);
      expect(() => parseIconComments('{"house": null}'), throwsFormatException);
    });
  });

  group('FlutterBindingsGenerator', () {
    const icons = [
      GeneratedIcon(name: 'house', codePoint: 0xe001, glyphId: 2),
      GeneratedIcon(name: 'arrow-right', codePoint: 0xe000, glyphId: 1),
      GeneratedIcon(name: 'class', codePoint: 0xe002, glyphId: 3),
    ];
    const packageGenerator = FlutterBindingsGenerator(
      className: 'MyIcons',
      font: FontReference.package(family: 'MyFam', package: 'my_pkg'),
      mirroredInRightToLeft: {'arrow-right'},
    );
    const applicationGenerator = FlutterBindingsGenerator(
      className: 'MyIcons',
      font: FontReference.application(family: 'MyFam'),
    );
    const wrappingGenerator = FlutterBindingsGenerator(
      className: 'MyIcons',
      extensionTypeName: 'MyIconData',
      font: FontReference.package(family: 'MyFam', package: 'my_pkg'),
    );

    test('tells the formatter and the analyser to leave it alone', () {
      // Machine output: a formatter would rewrite it to no purpose, and a lint
      // would report something nobody can go and fix, since editing the file
      // by hand is the one thing its own header tells you not to do.
      for (final source in [
        packageGenerator.generate(icons),
        packageGenerator.generateIndex(icons, libraryImport: 'a.dart'),
      ]) {
        final header = source.split('\n\n').first.split('\n');
        expect(header, contains('// ignore_for_file: type=lint'));
        expect(header, contains('// dart format off'));
        expect(
          header.indexOf('// dart format off'),
          lessThan(
            source
                .split('\n')
                .indexOf("import 'package:flutter/widgets.dart';"),
          ),
          reason:
              'the formatter stops where it is told, so it has to be told '
              'before there is anything to format',
        );
      }
    });

    test('declares a tree-shakeable abstract final icon class', () {
      final source = packageGenerator.generate(icons);
      expect(source, contains('@staticIconProvider'));
      expect(source, contains('abstract final class MyIcons {'));
      expect(source, contains("import 'package:flutter/widgets.dart';"));
    });

    test('declares exactly one const IconData per icon', () {
      final source = packageGenerator.generate(icons);
      expect(
        RegExp('static const IconData ').allMatches(source),
        hasLength(icons.length),
      );
      expect(source, contains('static const IconData house = IconData('));
      expect(source, contains('static const IconData arrowRight = IconData('));
      // The reserved word is renamed here too, otherwise the file would not
      // compile.
      expect(source, contains('static const IconData classIcon = IconData('));
    });

    test('writes each code point as a hex literal', () {
      final source = packageGenerator.generate(icons);
      for (final icon in icons) {
        expect(
          source,
          contains('0x${icon.codePoint.toRadixString(16)},'),
          reason: icon.name,
        );
      }
    });

    test('repeats the family as a string literal in every declaration', () {
      // IconData's parameters are @mustBeConst and the release-mode tree shaker
      // only recognises literals, so a shared constant would silently stop the
      // font being subset.
      final source = packageGenerator.generate(icons);
      expect(
        RegExp("fontFamily: 'MyFam',").allMatches(source),
        hasLength(icons.length),
      );
      expect(
        source,
        isNot(matches(RegExp("fontFamily: (?!')"))),
        reason: 'the family must never be referred to indirectly',
      );
    });

    test('repeats the package as a string literal for a package font', () {
      final source = packageGenerator.generate(icons);
      expect(
        RegExp("fontPackage: 'my_pkg',").allMatches(source),
        hasLength(icons.length),
      );
      expect(source, isNot(matches(RegExp("fontPackage: (?!')"))));
    });

    test('omits fontPackage entirely for an application-local font', () {
      final source = applicationGenerator.generate(icons);
      expect(source, isNot(contains('fontPackage')));
      expect(
        RegExp("fontFamily: 'MyFam',").allMatches(source),
        hasLength(icons.length),
      );
    });

    test('marks only the named icons as mirrored in right-to-left', () {
      final source = packageGenerator.generate(icons);
      expect(
        RegExp('matchTextDirection: true,').allMatches(source),
        hasLength(1),
      );
      final arrow = source.substring(
        source.indexOf('IconData arrowRight'),
        source.indexOf('IconData house'),
      );
      expect(arrow, contains('matchTextDirection: true,'));
      expect(
        source.substring(source.indexOf('IconData house')),
        isNot(contains('matchTextDirection')),
      );
      // A generator given no names mirrors nothing at all.
      expect(
        applicationGenerator.generate(icons),
        isNot(contains('matchTextDirection')),
      );
    });

    test('sorts the declarations by identifier, not by code point', () {
      final source = packageGenerator.generate(icons);
      final declared = [
        for (final match in RegExp(
          'static const IconData ([A-Za-z0-9_]+) =',
        ).allMatches(source))
          match.group(1),
      ];
      expect(declared, ['arrowRight', 'classIcon', 'house']);
    });

    test('documents the axes of the set it was built for', () {
      final source = packageGenerator.generate(icons);
      expect(source, contains('[Icon.fill]'));
      expect(source, contains('[Icon.weight]'));
      expect(source, contains('[Icon.grade]'));
      expect(source, contains('[Icon.opticalSize]'));
      // GRAD runs below zero, so the negative bound has to survive formatting.
      expect(source, contains('from -50.0 to 200.0'));
    });

    test('names the source of the icons in the header when told', () {
      const described = FlutterBindingsGenerator(
        className: 'MyIcons',
        font: FontReference.application(family: 'MyFam'),
        sourceDescription: '3 icons from lucide',
      );
      expect(
        described.generate(icons),
        contains('// Source: 3 icons from lucide'),
      );
      expect(
        applicationGenerator.generate(icons),
        isNot(contains('// Source')),
      );
    });

    test('throws naming both icons when two names collapse together', () {
      const colliding = [
        GeneratedIcon(name: 'arrow-right', codePoint: 0xe000, glyphId: 1),
        GeneratedIcon(name: 'arrow_right', codePoint: 0xe001, glyphId: 2),
      ];
      expect(
        () => applicationGenerator.generate(colliding),
        throwsA(
          isA<IdentifierCollisionException>()
              .having((e) => e.identifier, 'identifier', 'arrowRight')
              .having((e) => e.first, 'first', 'arrow-right')
              .having((e) => e.second, 'second', 'arrow_right'),
        ),
      );
    });

    test('collides only in the style that actually merges the names', () {
      // The `Object`-member suffix is what merges these two in camel case;
      // snake case never applies it, so there they stay apart.
      const shadowing = [
        GeneratedIcon(name: 'hash-code', codePoint: 0xe000, glyphId: 1),
        GeneratedIcon(name: 'hash-code-icon', codePoint: 0xe001, glyphId: 2),
      ];
      const camel = FlutterBindingsGenerator(
        className: 'MyIcons',
        font: FontReference.application(family: 'MyFam'),
      );
      const snake = FlutterBindingsGenerator(
        className: 'MyIcons',
        font: FontReference.application(family: 'MyFam'),
        identifierStyle: IdentifierStyle.snakeCase,
      );
      expect(
        () => camel.generate(shadowing),
        throwsA(
          isA<IdentifierCollisionException>().having(
            (e) => e.identifier,
            'identifier',
            'hashCodeIcon',
          ),
        ),
      );
      final source = snake.generate(shadowing);
      expect(source, contains('static const IconData hash_code = IconData('));
      expect(
        source,
        contains('static const IconData hash_code_icon = IconData('),
      );
    });

    test('declares no wrapper type unless one was named', () {
      expect(packageGenerator.generate(icons), isNot(contains('extension')));
    });

    test('declares the wrapper as a const extension type over IconData', () {
      final source = wrappingGenerator.generate(icons);
      expect(
        source,
        contains(
          'extension type const MyIconData(IconData _icon) '
          'implements IconData;',
        ),
        reason:
            'It has to be const to hold constants, and it has to implement '
            'IconData for Icon to take one.',
      );
    });

    test('gives every icon the wrapper type, around a plain IconData', () {
      final source = wrappingGenerator.generate(icons);
      expect(
        RegExp('static const MyIconData ').allMatches(source),
        hasLength(icons.length),
      );
      expect(
        RegExp(r'MyIconData\(\s*IconData\(').allMatches(source),
        hasLength(icons.length),
        reason:
            'The constant inside stays an IconData, which is what the icon '
            'tree shaker looks for.',
      );
      expect(source, isNot(contains('static const IconData ')));
    });

    test('keeps the code point and the font on the inner IconData', () {
      final source = wrappingGenerator.generate(icons);
      expect(
        source,
        contains(
          'static const MyIconData arrowRight = MyIconData(\n'
          '    IconData(\n'
          '      0xe000,\n'
          "      fontFamily: 'MyFam',\n"
          "      fontPackage: 'my_pkg',\n"
          '    ),\n'
          '  );\n',
        ),
      );
    });

    test('leaves the icons in the class, where the annotation is read', () {
      final source = wrappingGenerator.generate(icons);
      expect(
        source.indexOf('extension type const MyIconData'),
        lessThan(source.indexOf('@staticIconProvider')),
      );
      expect(
        source,
        contains('implements IconData;'),
        reason:
            'The extension type has to stay empty. @staticIconProvider is '
            'what tells the tree shaker a declaration is not a use, and the '
            'tool reads it off a class; an extension type is not one, so the '
            'annotation on it would be ignored silently and a web build would '
            'keep every icon in the set.',
      );
      expect(
        RegExp(r'@staticIconProvider\nabstract final class MyIcons \{')
            .hasMatch(source),
        isTrue,
      );
    });

    test('documents the wrapper as something to write in a signature', () {
      final source = wrappingGenerator.generate(icons);
      expect(source, contains('/// The type of every icon in [MyIcons].'));
      expect(source, contains('Widget leading(MyIconData icon)'));
    });

    test('types the index by the wrapper, and drops the unused import', () {
      final index = wrappingGenerator.generateIndex(
        icons,
        libraryImport: 'package:my_pkg/my_icons.dart',
      );
      expect(index, contains('const allMyIcons = <MyIconData>['));
      expect(index, contains('const myIconsByName = <String, MyIconData>{'));
      expect(
        index,
        isNot(contains("import 'package:flutter/widgets.dart';")),
        reason:
            'Nothing in the file names IconData any more, and an unused '
            'import is an analysis failure in the project it lands in.',
      );
    });

    test('says nothing about an icon it was told nothing about', () {
      expect(
        packageGenerator.generate(icons),
        contains('  /// The `house` icon.\n'),
      );
    });

    test('puts a comment above the line naming the source file', () {
      const documented = FlutterBindingsGenerator(
        className: 'MyIcons',
        font: FontReference.application(family: 'MyFam'),
        comments: {'arrow-right': 'Points at what comes next.'},
      );
      expect(
        documented.generate(icons),
        contains(
          '  /// Points at what comes next.\n'
          '  ///\n'
          '  /// The `arrow-right` icon.\n'
          '  static const IconData arrowRight = IconData(',
        ),
        reason:
            'The comment is what a reader should see first, and which file '
            'drew the icon is worth keeping either way.',
      );
    });

    test('gives a comment of several lines several lines', () {
      const documented = FlutterBindingsGenerator(
        className: 'MyIcons',
        font: FontReference.application(family: 'MyFam'),
        comments: {'house': 'Home.\n\nThe first tab, by convention.'},
      );
      expect(
        documented.generate(icons),
        contains(
          '  /// Home.\n'
          '  ///\n'
          '  /// The first tab, by convention.\n'
          '  ///\n'
          '  /// The `house` icon.\n',
        ),
      );
    });

    test('keys comments by the source name, not the identifier', () {
      const documented = FlutterBindingsGenerator(
        className: 'MyIcons',
        font: FontReference.application(family: 'MyFam'),
        comments: {'arrowRight': 'Written against the wrong name.'},
      );
      expect(
        documented.generate(icons),
        isNot(contains('Written against the wrong name.')),
        reason:
            'The same key the code point map uses, so that one file matches '
            'the other.',
      );
    });

    test('builds an index that keys icons by their source name', () {
      final index = packageGenerator.generateIndex(
        icons,
        libraryImport: 'package:my_pkg/my_icons.dart',
      );
      expect(index, contains("import 'package:my_pkg/my_icons.dart';"));
      expect(index, contains('const allMyIcons = <IconData>['));
      expect(index, contains("'arrow-right': MyIcons.arrowRight,"));
      expect(index, contains("'class': MyIcons.classIcon,"));
      // Sorted by identifier, like the class itself.
      expect(
        index.indexOf('MyIcons.arrowRight,'),
        lessThan(index.indexOf('MyIcons.house,')),
      );
    });
  });

  group('FlutterPubspecGenerator', () {
    const reference = FontReference.package(family: 'MyFam', package: 'my_pkg');
    const generator = FlutterPubspecGenerator(
      font: reference,
      assetPath: 'lib/fonts/MyFam.ttf',
    );

    test('nests the family and asset the way Flutter reads a fonts block', () {
      expect(parseSimpleYaml(generator.fontsBlock()), {
        'fonts': [
          {
            'family': 'MyFam',
            'fonts': [
              {'asset': 'lib/fonts/MyFam.ttf'},
            ],
          },
        ],
      });
    });

    test('indents the whole block without changing its shape', () {
      final block = generator.fontsBlock(indent: 6);
      for (final line in block.split('\n').where((l) => l.isNotEmpty)) {
        expect(line, startsWith(' ' * 6));
        expect(line, isNot(contains('\t')));
      }
      expect(
        parseSimpleYaml(block),
        parseSimpleYaml(generator.fontsBlock(indent: 0)),
      );
    });

    test('writes a package pubspec that depends on the flutter sdk', () {
      final parsed = parseSimpleYaml(
        generator.package(name: 'my_pkg', description: 'Some icons.'),
      );
      expect(parsed['name'], 'my_pkg');
      expect(parsed['description'], 'Some icons.');
      expect(parsed['version'], '1.0.0');
      expect(parsed['dependencies'], {
        'flutter': {'sdk': 'flutter'},
      });
      expect(parsed['environment'], {'sdk': '^3.13.0', 'flutter': '>=3.27.0'});
    });

    test('puts the fonts block under the pubspec flutter key', () {
      final parsed = parseSimpleYaml(
        generator.package(name: 'my_pkg', description: 'Some icons.'),
      );
      expect(parsed['flutter'], {
        'fonts': [
          {
            'family': 'MyFam',
            'fonts': [
              {'asset': 'lib/fonts/MyFam.ttf'},
            ],
          },
        ],
      });
    });

    test('carries the constraints and metadata it is given', () {
      final parsed = parseSimpleYaml(
        generator.package(
          name: 'my_pkg',
          description: 'Some icons.',
          version: '2.3.4',
          sdkConstraint: '^3.99.0',
          flutterConstraint: '>=4.0.0',
          repository: 'https://example.com/my_pkg',
          topics: ['icons', 'fonts'],
        ),
      );
      expect(parsed['version'], '2.3.4');
      expect(parsed['repository'], 'https://example.com/my_pkg');
      expect(parsed['topics'], ['icons', 'fonts']);
      expect(parsed['environment'], {'sdk': '^3.99.0', 'flutter': '>=4.0.0'});

      // Both are optional, and neither key appears when it has no value.
      final bare = parseSimpleYaml(
        generator.package(name: 'my_pkg', description: 'Some icons.'),
      );
      expect(bare.containsKey('repository'), isFalse);
      expect(bare.containsKey('topics'), isFalse);
    });

    test('tells an application-local user to leave fontPackage unset', () {
      const local = FlutterPubspecGenerator(
        font: FontReference.application(family: 'MyFam'),
        assetPath: 'fonts/MyFam.ttf',
      );
      final notes = local.usageNotes(
        className: 'MyIcons',
        libraryPath: 'my_icons.dart',
      );
      expect(notes, contains('leave `fontPackage` unset'));
      expect(notes, contains('- asset: fonts/MyFam.ttf'));
      expect(
        generator.usageNotes(
          className: 'MyIcons',
          libraryPath: 'package:my_pkg/my_icons.dart',
        ),
        contains('packages/my_pkg/MyFam'),
      );
    });
  });

  group('CodePointMap', () {
    test('assigns consecutive code points from the given start', () {
      final map = CodePointMap();
      expect(map.assign(['a', 'b', 'c'], startCodePoint: 0xf000), [
        0xf000,
        0xf001,
        0xf002,
      ]);
      expect(map.length, 3);
      expect(map['b'], 0xf001);
      // With no start given, the run begins at the private use area.
      expect(CodePointMap().assign(['a']), [0xe000]);
    });

    test('returns the same code point twice for a repeated name', () {
      expect(CodePointMap().assign(['a', 'a', 'b']), [0xe000, 0xe000, 0xe001]);
    });

    test('keeps every existing assignment when new icons are added', () {
      final map = CodePointMap()..assign(['a', 'b', 'c']);
      expect(map.assign(['a', 'b', 'c', 'd', 'e']), [
        0xe000,
        0xe001,
        0xe002,
        0xe003,
        0xe004,
      ]);
    });

    test('places a new icon after the highest used code point, not first', () {
      final map = CodePointMap()..assign(['b', 'c']);
      // `a` sorts first but must not take `b`'s code point.
      expect(map.assign(['a', 'b', 'c']), [0xe002, 0xe000, 0xe001]);
    });

    test('does not renumber the survivors when an icon is dropped', () {
      final map = CodePointMap()..assign(['a', 'b', 'c']);
      expect(map.assign(['a', 'c']), [0xe000, 0xe002]);
      expect(map['b'], 0xe001, reason: 'assign alone never forgets a name');
    });

    test('reuses a code point only once prune has retired it', () {
      final map = CodePointMap()..assign(['a', 'b', 'c']);
      expect(map.assign(['d']), [0xe003]);
      map.prune({'a', 'c', 'd'});
      expect(map.assign(['e']), [0xe001], reason: "b's slot is free now");
    });

    test('prunes only the names it is not given', () {
      final map = CodePointMap()
        ..assign(['a', 'b', 'c'])
        ..prune({'a', 'c'});
      expect(map.length, 2);
      expect(map['a'], 0xe000);
      expect(map['c'], 0xe002);
      expect(map['b'], isNull);
      map.prune(const {});
      expect(map.length, 0);
    });

    test('round trips through JSON, sorted by name', () {
      final map = CodePointMap()..assign(['zebra', 'apple', 'mango']);
      final json = map.toJson();
      expect(json, endsWith('\n'));
      expect(
        json.indexOf('apple'),
        lessThan(json.indexOf('mango')),
        reason: 'names are sorted so a diff stays readable',
      );
      final restored = CodePointMap.fromJson(json);
      expect(restored.length, 3);
      for (final name in ['zebra', 'apple', 'mango']) {
        expect(restored[name], map[name], reason: name);
      }
    });

    test('reads code points written as hex or U+ strings', () {
      final map = CodePointMap.fromJson(
        '{"a": "0xe000", "b": "U+E005", "c": 12}',
      );
      expect(map['a'], 0xe000);
      expect(map['b'], 0xe005);
      expect(map['c'], 12);
    });

    test('rejects JSON that is not an object of names', () {
      expect(CodePointMap.fromJson('{}').length, 0);
      expect(() => CodePointMap.fromJson('[]'), throwsFormatException);
      expect(() => CodePointMap.fromJson('"nope"'), throwsFormatException);
      expect(() => CodePointMap.fromJson('7'), throwsFormatException);
    });

    test('rejects a code point that is not a number', () {
      expect(() => CodePointMap.fromJson('{"a": true}'), throwsFormatException);
      expect(() => CodePointMap.fromJson('{"a": null}'), throwsFormatException);
    });

    test('copies the assignments it is constructed from', () {
      final seed = {'a': 5};
      final map = CodePointMap(seed);
      seed['a'] = 6;
      expect(map['a'], 5);
    });
  });

  group('runBuild for an application', () {
    late Directory temporary;
    late BuildOptions options;
    late BuildResult result;

    setUpAll(() {
      temporary = Directory.systemTemp.createTempSync('vfg-bindings-app-');
      options = BuildOptions(
        inputDirectory: fixtureDirectory,
        outputDirectory: temporary.path,
        family: 'ProbeIcons',
        className: 'ProbeIcons',
        libraryFileName: 'probe_icons.dart',
        codePointMapPath: p.join(temporary.path, 'codepoints.json'),
        emitIndex: true,
        timestamp: fixtureTimestamp,
        names: const FontNames(family: 'ProbeIcons'),
      );
      result = runBuild(options);
    });

    tearDownAll(() => temporary.deleteSync(recursive: true));

    test('writes the font outside lib when there is no package', () {
      expect(
        result.fontPath,
        p.join(temporary.path, 'fonts', 'ProbeIcons.ttf'),
      );
      final font = File(result.fontPath);
      expect(font.existsSync(), isTrue);
      expect(font.lengthSync(), result.fontBytes);
      expect(result.iconCount, fixtureIcons.length);
    });

    test('writes the bindings at the file name it was given', () {
      expect(result.libraryPath, p.join(temporary.path, 'probe_icons.dart'));
      expect(File(result.libraryPath!).existsSync(), isTrue);
      expect(
        result.indexPath,
        p.join(temporary.path, 'probe_icons_index.dart'),
      );
      expect(File(result.indexPath!).existsSync(), isTrue);
      expect(result.pubspecPath, isNull);
    });

    test('generates a Dart library that looks like a parseable file', () {
      final source = File(result.libraryPath!).readAsStringSync();
      expect(
        RegExp('static const IconData ').allMatches(source),
        hasLength(fixtureIcons.length),
      );
      expect(
        '{'.allMatches(source).length,
        '}'.allMatches(source).length,
        reason: 'unbalanced braces',
      );
      expect(
        '('.allMatches(source).length,
        ')'.allMatches(source).length,
        reason: 'unbalanced parentheses',
      );
      expect(source, contains('abstract final class ProbeIcons {'));
      expect(source, isNot(contains('fontPackage')));
      for (final icon in fixtureIcons) {
        expect(
          source,
          contains('/// The `${icon.name}` icon.'),
          reason: icon.name,
        );
      }
    });

    test('writes a code point map that is valid JSON covering every icon', () {
      expect(
        result.codePointMapPath,
        p.join(temporary.path, 'codepoints.json'),
      );
      final decoded = jsonDecode(
        File(result.codePointMapPath!).readAsStringSync(),
      );
      expect(decoded, isA<Map<String, dynamic>>());
      final map = decoded! as Map<String, dynamic>;
      expect(map, hasLength(fixtureIcons.length));
      expect(map.values.toSet(), hasLength(fixtureIcons.length));
      expect(
        map.values.cast<int>().toList()..sort(),
        List.generate(fixtureIcons.length, (i) => 0xe000 + i),
      );
      for (final icon in fixtureIcons) {
        expect(map.containsKey(icon.name), isTrue, reason: icon.name);
      }
    });

    test('produces byte-identical output when run again unchanged', () {
      final font = File(result.fontPath).readAsBytesSync();
      final library = File(result.libraryPath!).readAsStringSync();
      final index = File(result.indexPath!).readAsStringSync();
      final codePoints = File(result.codePointMapPath!).readAsStringSync();

      final again = runBuild(options);

      expect(again.fontPath, result.fontPath);
      expect(File(again.fontPath).readAsBytesSync(), font);
      expect(File(again.libraryPath!).readAsStringSync(), library);
      expect(File(again.indexPath!).readAsStringSync(), index);
      expect(File(again.codePointMapPath!).readAsStringSync(), codePoints);
    });
  });

  group('runBuild for a package', () {
    late Directory temporary;
    late BuildResult result;

    setUpAll(() {
      temporary = Directory.systemTemp.createTempSync('vfg-bindings-pkg-');
      result = runBuild(
        BuildOptions(
          inputDirectory: fixtureDirectory,
          outputDirectory: temporary.path,
          family: 'ProbeIcons',
          className: 'ProbeIcons',
          libraryFileName: 'probe_icons.dart',
          packageName: 'probe_icons',
          writePubspec: true,
          timestamp: fixtureTimestamp,
          names: const FontNames(family: 'ProbeIcons'),
        ),
      );
    });

    tearDownAll(() => temporary.deleteSync(recursive: true));

    test('puts the font under lib, the only place a package can expose it', () {
      expect(
        result.fontPath,
        p.join(temporary.path, 'lib', 'fonts', 'ProbeIcons.ttf'),
      );
      expect(File(result.fontPath).existsSync(), isTrue);
      expect(
        result.libraryPath,
        p.join(temporary.path, 'lib', 'probe_icons.dart'),
      );
    });

    test(
      'names the package on every IconData so Flutter can find the font',
      () {
        final source = File(result.libraryPath!).readAsStringSync();
        expect(
          RegExp("fontPackage: 'probe_icons',").allMatches(source),
          hasLength(fixtureIcons.length),
        );
        expect(
          RegExp("fontFamily: 'ProbeIcons',").allMatches(source),
          hasLength(fixtureIcons.length),
        );
      },
    );

    test('writes a pubspec pointing at the font inside lib', () {
      expect(result.pubspecPath, p.join(temporary.path, 'pubspec.yaml'));
      final parsed = parseSimpleYaml(
        File(result.pubspecPath!).readAsStringSync(),
      );
      expect(parsed['name'], 'probe_icons');
      expect(parsed['flutter'], {
        'fonts': [
          {
            'family': 'ProbeIcons',
            'fonts': [
              {'asset': 'lib/fonts/ProbeIcons.ttf'},
            ],
          },
        ],
      });
    });

    test('writes no index library unless one was asked for', () {
      expect(result.indexPath, isNull);
      expect(
        File(p.join(temporary.path, 'lib', 'probe_icons_index.dart'))
            .existsSync(),
        isFalse,
      );
      expect(result.previewPath, isNull);
    });
  });

  group('runBuild refuses impossible builds', () {
    test('will not write an index with no class to declare it from', () {
      final temporary = Directory.systemTemp.createTempSync('vfg-bindings-no-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      expect(
        () => runBuild(
          BuildOptions(
            inputDirectory: fixtureDirectory,
            outputDirectory: temporary.path,
            family: 'ProbeIcons',
            libraryFileName: 'probe_icons.dart',
            emitIndex: true,
            timestamp: fixtureTimestamp,
            names: const FontNames(family: 'ProbeIcons'),
          ),
        ),
        throwsStateError,
      );
    });

    test('writes the font and nothing else when no class is named', () {
      final temporary = Directory.systemTemp.createTempSync('vfg-bindings-no-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final result = runBuild(
        BuildOptions(
          inputDirectory: fixtureDirectory,
          outputDirectory: temporary.path,
          family: 'ProbeIcons',
          libraryFileName: 'probe_icons.dart',
          timestamp: fixtureTimestamp,
          names: const FontNames(family: 'ProbeIcons'),
        ),
      );
      expect(result.libraryPath, isNull);
      expect(result.indexPath, isNull);
      expect(File(result.fontPath).existsSync(), isTrue);
      expect(
        temporary
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => p.basename(file.path)),
        ['ProbeIcons.ttf'],
      );
    });

    test('will not write a pubspec without a package to name in it', () {
      final temporary = Directory.systemTemp.createTempSync('vfg-bindings-no-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      expect(
        () => runBuild(
          BuildOptions(
            inputDirectory: fixtureDirectory,
            outputDirectory: temporary.path,
            family: 'ProbeIcons',
            className: 'ProbeIcons',
            libraryFileName: 'probe_icons.dart',
            writePubspec: true,
            timestamp: fixtureTimestamp,
            names: const FontNames(family: 'ProbeIcons'),
          ),
        ),
        throwsStateError,
      );
    });

    test('fails when the input directory holds no SVG files', () {
      final temporary = Directory.systemTemp.createTempSync('vfg-bindings-mt-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final input = Directory(p.join(temporary.path, 'input'))
        ..createSync(recursive: true);
      expect(
        () => runBuild(
          BuildOptions(
            inputDirectory: input.path,
            outputDirectory: temporary.path,
            family: 'ProbeIcons',
            className: 'ProbeIcons',
            libraryFileName: 'probe_icons.dart',
            timestamp: fixtureTimestamp,
            names: const FontNames(family: 'ProbeIcons'),
          ),
        ),
        throwsStateError,
      );
    });
  });
}

/// One significant line of the YAML subset [parseSimpleYaml] understands.
final class YamlLine {
  /// Creates a line with its indentation already measured.
  const YamlLine(this.indent, this.text);

  /// How many spaces the line is indented by.
  final int indent;

  /// The line with its indentation removed.
  final String text;
}

/// Parses the small YAML subset the pubspec generator emits.
///
/// This exists because the package does not depend on `package:yaml`. It
/// handles two-space indented mappings, `- ` sequences of mappings and plain
/// scalars, which is exactly the shape a Flutter `fonts:` block has, and throws
/// on anything else, so a malformed block fails rather than silently parsing.
Map<String, Object?> parseSimpleYaml(String source) {
  final lines = [
    for (final raw in source.split('\n'))
      if (raw.trim().isNotEmpty && !raw.trimLeft().startsWith('#'))
        YamlLine(raw.length - raw.trimLeft().length, raw.trimLeft()),
  ];
  var index = 0;

  Object? parseNode(int indent) {
    if (lines[index].text.startsWith('- ')) {
      final items = <Object?>[];
      while (index < lines.length &&
          lines[index].indent == indent &&
          lines[index].text.startsWith('- ')) {
        final content = lines[index].text.substring(2);
        if (!RegExp(r'^[^:\s]+:( |$)').hasMatch(content)) {
          items.add(_unquote(content));
          index++;
          continue;
        }
        lines[index] = YamlLine(indent + 2, content);
        items.add(parseNode(indent + 2));
      }
      return items;
    }
    final map = <String, Object?>{};
    while (index < lines.length &&
        lines[index].indent == indent &&
        !lines[index].text.startsWith('- ')) {
      final line = lines[index];
      final colon = line.text.indexOf(':');
      if (colon < 0) {
        throw FormatException('Not a mapping entry: ${line.text}');
      }
      final key = line.text.substring(0, colon);
      final value = line.text.substring(colon + 1).trim();
      index++;
      if (value.isNotEmpty) {
        map[key] = _unquote(value);
      } else if (index < lines.length && lines[index].indent > indent) {
        map[key] = parseNode(lines[index].indent);
      } else {
        map[key] = null;
      }
    }
    return map;
  }

  if (lines.isEmpty) {
    return {};
  }
  final root = parseNode(lines.first.indent);
  if (index != lines.length) {
    throw FormatException('Inconsistent indentation at: ${lines[index].text}');
  }
  if (root is! Map<String, Object?>) {
    throw const FormatException('Expected a mapping at the top level');
  }
  return root;
}

String _unquote(String value) =>
    (value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))
    ? value.substring(1, value.length - 1)
    : value;
