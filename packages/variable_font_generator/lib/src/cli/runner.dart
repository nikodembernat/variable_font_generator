import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:variable_font_generator/src/cli/build_command.dart';

/// The version reported by `--version`.
const packageVersion = '0.2.0';

/// Builds the command line interface.
CommandRunner<int> buildCommandRunner({Stdout? output}) =>
    CommandRunner<int>(
        'variable_font_generator',
        'Generate a variable icon font, and the Flutter bindings for it, from '
            'a directory of SVG icons.',
      )
      ..argParser.addFlag(
        'version',
        negatable: false,
        help: 'Print the version and exit.',
      )
      ..addCommand(BuildCommand(output: output));

/// Runs the command line interface with [arguments] and returns an exit code.
Future<int> runCli(List<String> arguments, {Stdout? output}) async {
  final out = output ?? stdout;
  final runner = buildCommandRunner(output: output);
  try {
    final parsed = runner.argParser.parse(arguments);
    if (parsed.flag('version')) {
      out.writeln('variable_font_generator $packageVersion');
      return 0;
    }
  } on FormatException {
    // Fall through: the command runner reports the problem properly.
  }
  try {
    return await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    return 64; // EX_USAGE
  } on Object catch (error) {
    stderr.writeln('variable_font_generator: $error');
    return 1;
  }
}
