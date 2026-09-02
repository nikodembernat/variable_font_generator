import 'package:meta/meta.dart';

/// The strings stored in a font's `name` table.
@immutable
final class FontNames {
  /// Creates a name set.
  const FontNames({
    required this.family,
    this.subfamily = 'Regular',
    this.version = '1.000',
    this.copyright,
    this.manufacturer,
    this.designer,
    this.description,
    this.vendorUrl,
    this.designerUrl,
    this.license,
    this.licenseUrl,
    this.sampleText,
  });

  /// The family name, name ID 1.
  final String family;

  /// The style within the family, name ID 2.
  final String subfamily;

  /// The version, used to build name ID 5 and the `head` table's revision.
  final String version;

  /// Name ID 0.
  final String? copyright;

  /// Name ID 8.
  final String? manufacturer;

  /// Name ID 9.
  final String? designer;

  /// Name ID 10.
  final String? description;

  /// Name ID 11.
  final String? vendorUrl;

  /// Name ID 12.
  final String? designerUrl;

  /// Name ID 13.
  final String? license;

  /// Name ID 14.
  final String? licenseUrl;

  /// Name ID 19.
  final String? sampleText;

  /// The full font name, name ID 4.
  String get fullName =>
      subfamily.toLowerCase() == 'regular' ? family : '$family $subfamily';

  /// The PostScript name, name ID 6.
  ///
  /// PostScript names may only contain printable ASCII other than the ten
  /// characters `[](){}<>/%`, and must be at most 63 characters long.
  String get postScriptName {
    final buffer = StringBuffer();
    for (final unit in fullName.replaceAll(' ', '').codeUnits) {
      final isPrintable = unit >= 0x21 && unit <= 0x7E;
      final isForbidden = const [
        0x5B,
        0x5D,
        0x28,
        0x29,
        0x7B,
        0x7D,
        0x3C,
        0x3E,
        0x2F,
        0x25,
      ].contains(unit);
      if (isPrintable && !isForbidden) {
        buffer.writeCharCode(unit);
      }
    }
    final name = buffer.toString();
    return name.length <= 63 ? name : name.substring(0, 63);
  }

  /// The version string, name ID 5.
  String get versionString => 'Version $version';

  /// The numeric font revision stored in `head`.
  double get revision => double.tryParse(version) ?? 1.0;

  /// A unique identifier for this font, name ID 3.
  String get uniqueIdentifier => '$version;$family;$subfamily';

  @override
  String toString() => 'FontNames($fullName)';
}
