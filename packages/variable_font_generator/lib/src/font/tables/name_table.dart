import 'dart:convert';
import 'dart:typed_data';

import 'package:variable_font_generator/src/font/binary_writer.dart';

/// One string of the `name` table, with the identifier it is stored under.
typedef NameEntry = ({int nameId, String value});

/// Name IDs the specification gives a fixed meaning.
abstract final class NameId {
  /// Copyright notice.
  static const copyright = 0;

  /// Family name.
  static const family = 1;

  /// Subfamily, that is, the style within the family.
  static const subfamily = 2;

  /// A unique identifier for this exact font.
  static const uniqueIdentifier = 3;

  /// The full human readable name.
  static const fullName = 4;

  /// The version string.
  static const version = 5;

  /// The PostScript name.
  static const postScriptName = 6;

  /// Trademark notice.
  static const trademark = 7;

  /// Manufacturer.
  static const manufacturer = 8;

  /// Designer.
  static const designer = 9;

  /// Description.
  static const description = 10;

  /// Vendor URL.
  static const vendorUrl = 11;

  /// Designer URL.
  static const designerUrl = 12;

  /// License description.
  static const license = 13;

  /// License URL.
  static const licenseUrl = 14;

  /// Typographic family, used when the family name has to stay short for
  /// legacy software.
  static const typographicFamily = 16;

  /// Typographic subfamily.
  static const typographicSubfamily = 17;

  /// Sample text.
  static const sampleText = 19;

  /// The prefix variable fonts build their instance PostScript names from.
  static const variationsPostScriptNamePrefix = 25;

  /// The first name ID a font may use for its own purposes, such as axis and
  /// instance names.
  static const firstCustom = 256;
}

/// Collects strings and hands out the name IDs they end up under.
///
/// Variable fonts need this: `fvar` refers to axis and instance names by ID,
/// and those IDs have to be allocated as the axes are written.
final class NameTableBuilder {
  final _entries = <NameEntry>[];
  var _nextCustomId = NameId.firstCustom;

  /// Stores [value] under the fixed [nameId].
  ///
  /// A `null` or empty [value] is ignored, so optional metadata can be passed
  /// straight through.
  void add(int nameId, String? value) {
    if (value == null || value.isEmpty) {
      return;
    }
    _entries.add((nameId: nameId, value: value));
  }

  /// Stores [value] under a freshly allocated name ID and returns that ID.
  ///
  /// Identical strings share an ID, which keeps the table small when many named
  /// instances repeat a word.
  int addCustom(String value) {
    for (final entry in _entries) {
      if (entry.nameId >= NameId.firstCustom && entry.value == value) {
        return entry.nameId;
      }
    }
    final id = _nextCustomId++;
    _entries.add((nameId: id, value: value));
    return id;
  }

  /// Builds the `name` table, format 0.
  ///
  /// Every string is stored twice: once for Windows as UTF-16 and once for
  /// Macintosh as Roman. Records must be sorted by platform, encoding, language
  /// and name ID, which is what a reader's binary search relies on.
  Uint8List build() {
    final records =
        <
          ({
            int platform,
            int encoding,
            int language,
            int nameId,
            List<int> bytes,
          })
        >[];
    for (final entry in _entries) {
      records
        ..add((
          platform: 1, // Macintosh
          encoding: 0, // Roman
          language: 0, // English
          nameId: entry.nameId,
          bytes: _macRoman(entry.value),
        ))
        ..add((
          platform: 3, // Windows
          encoding: 1, // Unicode BMP
          language: 0x0409, // English (United States)
          nameId: entry.nameId,
          bytes: _utf16BigEndian(entry.value),
        ));
    }
    records.sort((a, b) {
      final byPlatform = a.platform.compareTo(b.platform);
      if (byPlatform != 0) {
        return byPlatform;
      }
      final byEncoding = a.encoding.compareTo(b.encoding);
      if (byEncoding != 0) {
        return byEncoding;
      }
      final byLanguage = a.language.compareTo(b.language);
      if (byLanguage != 0) {
        return byLanguage;
      }
      return a.nameId.compareTo(b.nameId);
    });

    final storage = BinaryWriter(1024);
    final offsets = <int>[];
    for (final record in records) {
      offsets.add(storage.length);
      storage.bytes(record.bytes);
    }

    final writer = BinaryWriter(1024)
      ..uint16(0) // version 0
      ..uint16(records.length)
      ..uint16(6 + records.length * 12); // storageOffset
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      writer
        ..uint16(record.platform)
        ..uint16(record.encoding)
        ..uint16(record.language)
        ..uint16(record.nameId)
        ..uint16(record.bytes.length)
        ..uint16(offsets[index]);
    }
    writer.bytes(storage.toBytes());
    return writer.toBytes();
  }

  static List<int> _utf16BigEndian(String value) {
    final writer = BinaryWriter(value.length * 2);
    value.codeUnits.forEach(writer.uint16);
    return writer.toBytes();
  }

  /// Encodes [value] as Mac Roman, which for the ASCII range every font name
  /// realistically uses is the same as ASCII.
  static List<int> _macRoman(String value) =>
      ascii.encode(value.replaceAll(RegExp(r'[^\x20-\x7E]'), '?'));
}
