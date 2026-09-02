import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A single channel, 8 bit coverage bitmap.
///
/// Used to compare shapes: rendering an icon from its source geometry and the
/// same icon from the generated font into two of these and measuring how much
/// they overlap is what proves the font really carries the artwork.
@immutable
final class CoverageBitmap {
  /// Creates a bitmap of [width] by [height] backed by [pixels].
  const CoverageBitmap({
    required this.width,
    required this.height,
    required this.pixels,
  });

  /// Creates an all-zero bitmap of [width] by [height].
  factory CoverageBitmap.empty(int width, int height) => CoverageBitmap(
    width: width,
    height: height,
    pixels: Uint8List(width * height),
  );

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  /// Coverage values in row-major order, from 0 (empty) to 255 (solid).
  final Uint8List pixels;

  /// The coverage at the given `(x, y)` position.
  int operator []((int, int) position) =>
      pixels[position.$2 * width + position.$1];

  /// The sum of every coverage value, which is proportional to the inked area.
  int get totalCoverage => pixels.fold(0, (total, value) => total + value);

  /// The fraction of pixels where this bitmap and [other] agree once both are
  /// reduced to solid or empty at [threshold].
  ///
  /// This is the Jaccard index, also called intersection over union: the number
  /// of pixels covered in both divided by the number covered in either. It is
  /// the right measure for shape comparison because it ignores how the two
  /// renderers anti-alias and only asks whether they inked the same area.
  ///
  /// Returns 1 when neither bitmap has any coverage at all.
  double intersectionOverUnion(CoverageBitmap other, {int threshold = 128}) {
    _requireSameSize(other);
    var intersection = 0;
    var union = 0;
    for (var index = 0; index < pixels.length; index++) {
      final inThis = pixels[index] >= threshold;
      final inOther = other.pixels[index] >= threshold;
      if (inThis && inOther) {
        intersection++;
      }
      if (inThis || inOther) {
        union++;
      }
    }
    return union == 0 ? 1 : intersection / union;
  }

  /// The mean absolute difference between this bitmap and [other], from 0
  /// (identical) to 1 (every pixel maximally different).
  double meanAbsoluteDifference(CoverageBitmap other) {
    _requireSameSize(other);
    if (pixels.isEmpty) {
      return 0;
    }
    var total = 0;
    for (var index = 0; index < pixels.length; index++) {
      total += (pixels[index] - other.pixels[index]).abs();
    }
    return total / (pixels.length * 255);
  }

  /// The largest absolute difference between corresponding pixels, from 0 to
  /// 255.
  int maxAbsoluteDifference(CoverageBitmap other) {
    _requireSameSize(other);
    var worst = 0;
    for (var index = 0; index < pixels.length; index++) {
      final difference = (pixels[index] - other.pixels[index]).abs();
      if (difference > worst) {
        worst = difference;
      }
    }
    return worst;
  }

  /// A bitmap where each pixel is the absolute difference between this bitmap
  /// and [other], useful for eyeballing where a comparison went wrong.
  CoverageBitmap difference(CoverageBitmap other) {
    _requireSameSize(other);
    final result = Uint8List(pixels.length);
    for (var index = 0; index < pixels.length; index++) {
      result[index] = (pixels[index] - other.pixels[index]).abs();
    }
    return CoverageBitmap(width: width, height: height, pixels: result);
  }

  void _requireSameSize(CoverageBitmap other) {
    if (other.width != width || other.height != height) {
      throw ArgumentError.value(
        other,
        'other',
        'Expected a ${width}x$height bitmap but got '
            '${other.width}x${other.height}',
      );
    }
  }

  @override
  String toString() => 'CoverageBitmap(${width}x$height)';
}
