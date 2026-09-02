import 'package:meta/meta.dart';

/// The em size and vertical metrics of a generated font.
///
/// The defaults are chosen so that Flutter's `Icon` widget centres a glyph
/// exactly inside its box. `Icon` renders the glyph with `height: 1.0` and
/// `TextLeadingDistribution.even`, which makes the line box exactly one font
/// size tall and splits any leftover leading evenly above and below. When
/// [ascender] minus [descender] equals [unitsPerEm] there is no leftover
/// leading at all, so a glyph drawn from [descender] up to [ascender] fills the
/// icon's square precisely.
@immutable
final class FontMetrics {
  /// Creates metrics.
  const FontMetrics({
    this.unitsPerEm = 1000,
    this.ascender = 800,
    this.descender = -200,
    this.lineGap = 0,
  });

  /// The number of design units in one em.
  final int unitsPerEm;

  /// How far above the baseline the em box reaches.
  final int ascender;

  /// How far below the baseline the em box reaches, as a negative number.
  final int descender;

  /// Extra leading between lines. Icon fonts want none.
  final int lineGap;

  /// The height of the em box, which should equal [unitsPerEm].
  int get emBoxHeight => ascender - descender;

  /// Whether a glyph filling the em box will be centred by Flutter's `Icon`.
  bool get isIconCentred => emBoxHeight == unitsPerEm;

  /// Throws an [ArgumentError] when these metrics are not usable.
  void validate() {
    if (unitsPerEm < 16 || unitsPerEm > 16384) {
      throw ArgumentError.value(
        unitsPerEm,
        'unitsPerEm',
        'Must be between 16 and 16384',
      );
    }
    if (ascender <= descender) {
      throw ArgumentError.value(
        ascender,
        'ascender',
        'Must be greater than the descender ($descender)',
      );
    }
  }

  @override
  String toString() =>
      'FontMetrics(unitsPerEm: $unitsPerEm, ascender: $ascender, '
      'descender: $descender)';
}
