import 'dart:convert';

import 'package:variable_font_generator/src/generator/icon_font_generator.dart';

/// Remembers which code point each icon was given.
///
/// Code points are part of a font's public contract: an application compiles
/// `IconData(0xe123)` into its own source, so moving an icon to a different
/// code point silently changes what that application draws. Keeping the map in
/// a file next to the font means a rebuild after adding or removing icons
/// leaves the existing ones exactly where they were.
final class CodePointMap {
  /// Creates a map from icon name to code point.
  CodePointMap([Map<String, int>? assignments])
    : _assignments = {...?assignments};

  /// Parses a map previously written by [toJson].
  factory CodePointMap.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'A code point map must be a JSON object of name to code point',
      );
    }
    return CodePointMap({
      for (final entry in decoded.entries)
        entry.key: switch (entry.value) {
          final int value => value,
          final String value => int.parse(
            value.replaceFirst(RegExp(r'^(0x|U\+)'), ''),
            radix: 16,
          ),
          _ => throw FormatException(
            'The code point for "${entry.key}" is not a number',
          ),
        },
    });
  }

  final Map<String, int> _assignments;

  /// The code point assigned to [name], or `null` if it has none yet.
  int? operator [](String name) => _assignments[name];

  /// How many assignments are stored.
  int get length => _assignments.length;

  /// Assigns code points to [names], keeping any this map already knows.
  ///
  /// New names are placed at the lowest free code points at or above
  /// [startCodePoint], so a set that has only grown keeps a contiguous range.
  List<int> assign(
    List<String> names, {
    int startCodePoint = privateUseAreaStart,
  }) {
    final used = _assignments.values.toSet();
    var next = startCodePoint;
    final result = <int>[];
    for (final name in names) {
      final existing = _assignments[name];
      if (existing != null) {
        result.add(existing);
        continue;
      }
      while (used.contains(next)) {
        next++;
      }
      used.add(next);
      _assignments[name] = next;
      result.add(next);
    }
    return result;
  }

  /// Drops assignments for names not in [names].
  ///
  /// Retiring a code point frees it for reuse, which is only safe when no
  /// application still refers to it, so this is never done automatically.
  void prune(Set<String> names) =>
      _assignments.removeWhere((name, _) => !names.contains(name));

  /// Serialises the map as pretty-printed JSON, sorted by name.
  String toJson() {
    final sorted = _assignments.keys.toList()..sort();
    return '${const JsonEncoder.withIndent('  ').convert({for (final name in sorted) name: _assignments[name]})}\n';
  }

  @override
  String toString() => 'CodePointMap($length assignments)';
}
