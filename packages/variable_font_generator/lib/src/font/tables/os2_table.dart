import 'dart:typed_data';

import 'package:variable_font_generator/src/font/binary_writer.dart';
import 'package:variable_font_generator/src/font/font_metrics.dart';

/// The `fsSelection` bit that marks a font as regular.
const fsSelectionRegular = 0x0040;

/// The `fsSelection` bit asking clients to lay text out with the typographic
/// metrics rather than the Windows ones.
///
/// Setting it removes any ambiguity about which ascender a client uses, which
/// matters because Flutter's `Icon` widget positions a glyph from the font's
/// ascender and descender.
const fsSelectionUseTypoMetrics = 0x0080;

/// Builds the `OS/2` table, version 5.
///
/// Version 5 is the one that carries the optical size range, which a font with
/// an `opsz` axis should declare so that clients know which sizes it was drawn
/// for.
Uint8List buildOs2Table({
  required FontMetrics metrics,
  required int averageCharWidth,
  required int weightClass,
  required int firstCharIndex,
  required int lastCharIndex,
  required String vendorId,
  required double lowerOpticalPointSize,
  required double upperOpticalPointSize,
  required Set<int> codePoints,
}) {
  final writer = BinaryWriter(100)
    ..uint16(5) // version
    ..int16(averageCharWidth)
    ..uint16(weightClass)
    ..uint16(5) // usWidthClass: medium
    // fsType 0: installable embedding, the permissive value open fonts use.
    ..uint16(0)
    ..int16(metrics.unitsPerEm ~/ 2) // ySubscriptXSize
    ..int16(metrics.unitsPerEm ~/ 2) // ySubscriptYSize
    ..int16(0) // ySubscriptXOffset
    ..int16(metrics.unitsPerEm ~/ 10) // ySubscriptYOffset
    ..int16(metrics.unitsPerEm ~/ 2) // ySuperscriptXSize
    ..int16(metrics.unitsPerEm ~/ 2) // ySuperscriptYSize
    ..int16(0) // ySuperscriptXOffset
    ..int16(metrics.unitsPerEm ~/ 2) // ySuperscriptYOffset
    ..int16(metrics.unitsPerEm ~/ 20) // yStrikeoutSize
    ..int16(metrics.unitsPerEm ~/ 4) // yStrikeoutPosition
    ..int16(0) // sFamilyClass: no classification
    // PANOSE, all zero: "any", which is what a symbol font should claim.
    ..zeros(10);
  _unicodeRangeBits(codePoints).forEach(writer.uint32);

  writer
    ..tag(vendorId)
    ..uint16(fsSelectionRegular | fsSelectionUseTypoMetrics)
    ..uint16(firstCharIndex > 0xFFFF ? 0xFFFF : firstCharIndex)
    ..uint16(lastCharIndex > 0xFFFF ? 0xFFFF : lastCharIndex)
    ..int16(metrics.ascender)
    ..int16(metrics.descender)
    ..int16(metrics.lineGap)
    ..uint16(metrics.ascender)
    ..uint16(-metrics.descender)
    // Code page ranges: bit 0 is Latin 1, which every font should claim so that
    // legacy Windows text stacks consider it usable.
    ..uint32(1)
    ..uint32(0)
    ..int16(0) // sxHeight, not meaningful for icons
    ..int16(metrics.ascender) // sCapHeight
    ..uint16(0) // usDefaultChar
    ..uint16(0) // usBreakChar
    ..uint16(1) // usMaxContext
    ..uint16(lowerOpticalPointSize.round().clamp(0, 0xFFFF))
    ..uint16(upperOpticalPointSize.round().clamp(0, 0xFFFF));
  return writer.toBytes();
}

/// The four `ulUnicodeRange` words for [codePoints].
///
/// Only the bits an icon font can plausibly need are computed: the Private Use
/// Area, its two supplementary planes, and Basic Latin for fonts that map
/// ordinary characters as well.
List<int> _unicodeRangeBits(Set<int> codePoints) {
  final words = [0, 0, 0, 0];
  void setBit(int bit) {
    words[bit ~/ 32] |= 1 << (bit % 32);
  }

  for (final codePoint in codePoints) {
    if (codePoint <= 0x007F) {
      setBit(0); // Basic Latin
    } else if (codePoint >= 0xE000 && codePoint <= 0xF8FF) {
      setBit(60); // Private Use Area
    } else if (codePoint >= 0xF0000 && codePoint <= 0x10FFFD) {
      setBit(90); // Supplementary Private Use Area
    }
  }
  return words;
}
