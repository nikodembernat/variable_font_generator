import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:variable_font_generator/variable_font_generator.dart';

import 'support/fixtures.dart';

/// A [Stdout] that keeps what it is told instead of printing it.
///
/// Only the two methods the command line uses are implemented; anything else
/// throws, which is the point — a test that starts depending on more of
/// `Stdout` should say so.
final class _CapturedOutput implements Stdout {
  final _buffer = StringBuffer();

  /// Everything written so far.
  String get text => _buffer.toString();

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not captured');
}

/// Parses a `key=value` summary file the way a shell would.
Map<String, String> readSummary(String path) => {
  for (final line in File(path).readAsLinesSync())
    if (line.contains('=')) line.split('=').first: line.split('=').last,
};

void main() {
  Directory makeTemporaryDirectory() {
    final directory = Directory.systemTemp.createTempSync('vfg-cli-');
    addTearDown(() => directory.deleteSync(recursive: true));
    return directory;
  }

  /// Runs the command line, returning everything it printed and its exit code.
  ///
  /// Both streams are captured, which keeps the deliberate failures below from
  /// printing to the console of a run that is passing.
  Future<({int code, String output, String errors})> run(
    List<String> arguments,
  ) async {
    final output = _CapturedOutput();
    final errors = _CapturedOutput();
    final code = await IOOverrides.runZoned(
      () => runCli(arguments, output: output),
      stderr: () => errors,
    );
    return (code: code, output: output.text, errors: errors.text);
  }

  group('the command line', () {
    test('prints its version', () async {
      final result = await run(['--version']);
      expect(result.code, 0);
      expect(result.output.trim(), 'variable_font_generator $packageVersion');
    });

    test('refuses anything but exactly one directory of icons', () {
      final runner = buildCommandRunner();
      expect(
        () => runner.run(['build']),
        throwsA(isA<UsageException>()),
        reason: 'no directory at all',
      );
      expect(
        () => runner.run(['build', 'one', 'two']),
        throwsA(isA<UsageException>()),
        reason: 'two directories',
      );
    });

    test('reports a code point that is not a number as a failure', () async {
      final result = await run([
        'build',
        fixtureDirectory,
        '--start-codepoint',
        'wxyz',
      ]);
      expect(result.code, 1);
      expect(result.errors, contains('Not a hexadecimal code point: wxyz'));
    });

    test('reports an unreadable directory as a failure', () async {
      final result = await run(['build', 'no/such/directory']);
      expect(result.code, isNot(0));
      expect(result.errors, contains('no/such/directory'));
    });

    test('reports a usage mistake as one, and not as a crash', () async {
      final result = await run(['build']);
      expect(
        result.code,
        64,
        reason: 'EX_USAGE, which is what a shell script would look for',
      );
      expect(result.errors, contains('exactly one directory'));
    });
  });

  group('the command line checks the names it is given', () {
    Future<void> expectUsageError(List<String> arguments) async {
      await expectLater(
        buildCommandRunner().run(['build', fixtureDirectory, ...arguments]),
        throwsA(isA<UsageException>()),
      );
    }

    test('rejects a class name that is not a Dart identifier', () async {
      await expectUsageError(['--class-name', 'my icons']);
      await expectUsageError(['--class-name', '9Lives']);
      await expectUsageError(['--class-name', 'class']);
      await expectUsageError(['--class-name', '_Private']);
    });

    test('rejects an extension type name that is not one either', () async {
      await expectUsageError([
        '--class-name',
        'ProbeIcons',
        '--extension-name',
        'my-icon-data',
      ]);
      await expectUsageError([
        '--class-name',
        'ProbeIcons',
        '--extension-name',
        'extension',
      ]);
    });

    test('refuses to let the class and the extension type share a name', () {
      expect(
        buildCommandRunner().run([
          'build',
          fixtureDirectory,
          '--class-name',
          'Same',
          '--extension-name',
          'Same',
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test('refuses what describes bindings when no class is named', () async {
      await expectUsageError(['--index']);
      await expectUsageError(['--extension-name', 'ProbeIconData']);
      await expectUsageError(['--library', 'probe_icons.dart']);
      await expectUsageError(['--comments', 'comments.json']);
    });
  });

  group('the command line builds', () {
    test('a font and its bindings, and says where it put them', () async {
      final directory = makeTemporaryDirectory();
      final result = await run([
        'build',
        fixtureDirectory,
        '--output',
        directory.path,
        '--class-name',
        'ProbeIcons',
        '--extension-name',
        'ProbeIconData',
        '--index',
        '--summary',
        p.join(directory.path, 'summary.txt'),
      ]);

      expect(result.code, 0);
      expect(result.output, contains('Read ${fixtureIcons.length} icons'));
      expect(result.output, contains('ProbeIcons.ttf'));

      final bindings = File(p.join(directory.path, 'icons.dart'))
          .readAsStringSync();
      expect(
        bindings,
        contains(
          'extension type const ProbeIconData(IconData _icon) '
          'implements IconData;',
        ),
      );
      expect(bindings, contains('abstract final class ProbeIcons {'));
      expect(
        RegExp('static const ProbeIconData ').allMatches(bindings),
        hasLength(fixtureIcons.length),
      );
    });

    test('a font on its own when no class is named', () async {
      final directory = makeTemporaryDirectory();
      final result = await run([
        'build',
        fixtureDirectory,
        '--output',
        directory.path,
        '--family',
        'ProbeIcons',
        '--summary',
        p.join(directory.path, 'summary.txt'),
      ]);

      expect(result.code, 0);
      expect(result.output, isNot(contains('bindings')));
      expect(
        File(p.join(directory.path, 'fonts', 'ProbeIcons.ttf')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(directory.path, 'icons.dart')).existsSync(),
        isFalse,
        reason: 'nothing but the font was asked for',
      );

      final summary = readSummary(p.join(directory.path, 'summary.txt'));
      expect(summary.keys, isNot(contains('bindings')));
      expect(summary.keys, isNot(contains('class-name')));
      expect(summary['font'], endsWith('ProbeIcons.ttf'));
    });
  });

  group('the command line documents the icons it is given comments for', () {
    test('and says so when a comment names no icon it built', () async {
      final directory = makeTemporaryDirectory();
      final comments = p.join(directory.path, 'comments.json');
      File(comments).writeAsStringSync(
        '{"arrow-right": "Points at what comes next.", '
        r'"house": "Home.\nThe first tab.", '
        '"no-such-icon": "Left behind by a rename."}',
      );

      final result = await run([
        'build',
        fixtureDirectory,
        '--output',
        directory.path,
        '--class-name',
        'ProbeIcons',
        '--comments',
        comments,
      ]);

      expect(result.code, 0);
      expect(
        result.output,
        contains('No icon is called "no-such-icon"'),
        reason: 'A comment that goes nowhere is worth a word, not a failure.',
      );

      final bindings = File(p.join(directory.path, 'icons.dart'))
          .readAsStringSync();
      expect(
        bindings,
        contains(
          '  /// Points at what comes next.\n'
          '  ///\n'
          '  /// The `arrow-right` icon.\n',
        ),
      );
      expect(bindings, contains('  /// Home.\n  /// The first tab.\n  ///\n'));
      expect(bindings, isNot(contains('Left behind by a rename.')));
    });
  });

  group('the command line names the font', () {
    Future<Map<String, String>> summaryFor(List<String> arguments) async {
      final directory = makeTemporaryDirectory();
      final summary = p.join(directory.path, 'summary.txt');
      final result = await run([
        'build',
        fixtureDirectory,
        '--output',
        directory.path,
        ...arguments,
        '--summary',
        summary,
      ]);
      expect(result.code, 0);
      return readSummary(summary);
    }

    test('after the class, so that a set has one name and not two', () async {
      final summary = await summaryFor(['--class-name', 'ProbeIcons']);
      expect(summary['family'], 'ProbeIcons');
      expect(summary['class-name'], 'ProbeIcons');
      expect(summary['font'], endsWith('ProbeIcons.ttf'));
    });

    test('as it was told to, when it was told', () async {
      final summary = await summaryFor([
        '--family',
        'Brand',
        '--class-name',
        'ProbeIcons',
      ]);
      expect(summary['family'], 'Brand', reason: 'the family it was given');
      expect(summary['class-name'], 'ProbeIcons');
      expect(summary['font'], endsWith('Brand.ttf'));
    });

    test('from the family alone when there is no class to name it', () async {
      // The reason --family survives having a class to fall back on: a build
      // with no bindings has no class, and the font still needs a name.
      final summary = await summaryFor(['--family', 'Brand']);
      expect(summary['family'], 'Brand');
      expect(summary.keys, isNot(contains('class-name')));
      expect(summary.keys, isNot(contains('bindings')));
      expect(summary['font'], endsWith('Brand.ttf'));
    });

    test('with something rather than nothing when told neither', () async {
      final summary = await summaryFor([]);
      expect(summary['family'], 'CustomIcons');
      expect(summary.keys, isNot(contains('class-name')));
    });
  });

  group('the build summary', () {
    late Directory directory;
    late Map<String, String> summary;

    setUpAll(() {
      directory = Directory.systemTemp.createTempSync('vfg-summary-');
      final options = BuildOptions(
        inputDirectory: fixtureDirectory,
        outputDirectory: directory.path,
        family: 'ProbeIcons',
        className: 'ProbeIcons',
        extensionTypeName: 'ProbeIconData',
        libraryFileName: 'probe_icons.dart',
        packageName: 'probe_icons',
        emitIndex: true,
        writePubspec: true,
        codePointMapPath: p.join(directory.path, 'codepoints.json'),
        summaryPath: p.join(directory.path, 'summary.txt'),
        timestamp: fixtureTimestamp,
        names: const FontNames(family: 'ProbeIcons'),
      );
      final result = runBuild(options);
      expect(result.summaryPath, options.summaryPath);
      summary = readSummary(options.summaryPath!);
    });

    tearDownAll(() => directory.deleteSync(recursive: true));

    test('names every file the build wrote', () {
      for (final key in [
        'font',
        'bindings',
        'index',
        'pubspec',
        'codepoints',
      ]) {
        expect(
          File(summary[key]!).existsSync(),
          isTrue,
          reason: '$key: ${summary[key]}',
        );
      }
    });

    test('carries the numbers a caller would otherwise have to measure', () {
      expect(summary['icon-count'], '${fixtureIcons.length}');
      expect(
        int.parse(summary['font-bytes']!),
        File(summary['font']!).lengthSync(),
      );
    });

    test('repeats the names the bindings were generated under', () {
      expect(summary['family'], 'ProbeIcons');
      expect(summary['package'], 'probe_icons');
      expect(summary['class-name'], 'ProbeIcons');
      expect(summary['extension-name'], 'ProbeIconData');
    });

    test('leaves out what was not written, rather than saying so', () {
      expect(summary.keys, isNot(contains('preview')));
    });

    test('holds nothing a shell would have to quote or a line to itself', () {
      final lines = File(p.join(directory.path, 'summary.txt'))
          .readAsLinesSync();
      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(
          line,
          matches(RegExp(r'^[a-z-]+=[^\r\n]+$')),
          reason: 'a GitHub Actions output file takes one key=value per line',
        );
      }
    });
  });
}
