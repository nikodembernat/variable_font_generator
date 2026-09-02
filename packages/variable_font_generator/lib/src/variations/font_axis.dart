import 'package:meta/meta.dart';

/// A variation axis of a font.
///
/// The three values describe the axis in *user* coordinates, the numbers an
/// application passes in. Inside the font everything is expressed in
/// *normalised* coordinates running from -1 to 1, with 0 always at
/// [defaultValue]; [normalize] converts between the two.
@immutable
final class FontAxis {
  /// Creates an axis.
  const FontAxis({
    required this.tag,
    required this.name,
    required this.minimum,
    required this.defaultValue,
    required this.maximum,
    this.hidden = false,
  });

  /// The four character axis tag, such as `wght`.
  final String tag;

  /// The human readable axis name shown by font pickers.
  final String name;

  /// The smallest value an application may ask for.
  final double minimum;

  /// The value the font takes when nothing is asked for.
  final double defaultValue;

  /// The largest value an application may ask for.
  final double maximum;

  /// Whether the axis should be hidden from font pickers.
  final bool hidden;

  /// Converts a user coordinate to the -1 to 1 range the font stores.
  ///
  /// The mapping is piecewise linear with a knee at [defaultValue], which is
  /// exactly what the OpenType specification prescribes, and it is why an
  /// effect that is linear on each side of the default needs no `avar` table.
  double normalize(double value) {
    final clamped = value.clamp(minimum, maximum);
    if (clamped == defaultValue) {
      return 0;
    }
    if (clamped < defaultValue) {
      return defaultValue == minimum
          ? 0
          : (clamped - defaultValue) / (defaultValue - minimum);
    }
    return defaultValue == maximum
        ? 0
        : (clamped - defaultValue) / (maximum - defaultValue);
  }

  /// Converts a normalised coordinate back to a user coordinate.
  double denormalize(double normalized) {
    final clamped = normalized.clamp(-1.0, 1.0);
    if (clamped == 0) {
      return defaultValue;
    }
    return clamped < 0
        ? defaultValue + clamped * (defaultValue - minimum)
        : defaultValue + clamped * (maximum - defaultValue);
  }

  /// Throws an [ArgumentError] when this axis is not usable.
  void validate() {
    if (tag.length != 4) {
      throw ArgumentError.value(tag, 'tag', 'An axis tag must be 4 characters');
    }
    if (!(minimum <= defaultValue && defaultValue <= maximum)) {
      throw ArgumentError.value(
        defaultValue,
        'defaultValue',
        'Must lie between $minimum and $maximum for axis $tag',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FontAxis &&
      other.tag == tag &&
      other.name == name &&
      other.minimum == minimum &&
      other.defaultValue == defaultValue &&
      other.maximum == maximum &&
      other.hidden == hidden;

  @override
  int get hashCode =>
      Object.hash(tag, name, minimum, defaultValue, maximum, hidden);

  @override
  String toString() => 'FontAxis($tag: $minimum..$defaultValue..$maximum)';
}
