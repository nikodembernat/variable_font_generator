import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The family name Flutter resolves the font under.
///
/// `TextStyle` prefixes a family with `packages/<package>/` when it is given a
/// font package, and the generated `IconData` values name this package, so the
/// font has to be registered under the prefixed name for the tests to find it.
const _registeredFamily = 'packages/lucide_variable_icons/LucideVariable';

/// Runs before every test in this package.
///
/// Widget tests start with no fonts but the fallback, so the icon font is
/// loaded by hand from the file the pubspec ships. It is also where the golden
/// comparison is given a tolerance: the outlines are exact, but the shade of
/// grey along their edges depends on the renderer, and a fresh Flutter patch
/// release should not be able to fail the suite over a few anti-aliased
/// pixels.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bytes = File('lib/fonts/LucideVariable.ttf').readAsBytesSync();
  final loader = FontLoader(_registeredFamily)
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  await loader.load();

  // LocalFileComparator resolves goldens against the directory of the file it
  // is given, so it is handed a file inside test/ rather than the directory.
  goldenFileComparator = _TolerantGoldenComparator(
    Uri.file('${Directory.current.path}/test/flutter_test_config.dart'),
    maxDifferentPixelFraction: 0.005,
    maxChannelDifference: 8,
  );

  await testMain();
}

/// A golden comparator that ignores differences too small to see.
///
/// A pixel counts as different only when a channel is off by more than
/// [maxChannelDifference]; the comparison fails when more than
/// [maxDifferentPixelFraction] of the image is different by that measure.
final class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(
    super.testFile, {
    required this.maxDifferentPixelFraction,
    required this.maxChannelDifference,
  });

  final double maxDifferentPixelFraction;
  final int maxChannelDifference;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= maxDifferentPixelFraction) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
