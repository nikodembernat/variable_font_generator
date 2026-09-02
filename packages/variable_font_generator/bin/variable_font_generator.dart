import 'dart:io';

import 'package:variable_font_generator/src/cli/runner.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
}
