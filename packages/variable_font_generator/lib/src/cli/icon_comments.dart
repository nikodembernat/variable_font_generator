import 'dart:convert';

/// Reads the doc comments an icon set carries for its icons.
///
/// The format is the dullest one that says what it means: a JSON object from
/// icon name to the prose that should appear on the generated member, keyed the
/// same way the code point map is, so that one file can be kept beside the
/// other and read by the same eyes.
///
/// ```json
/// {
///   "arrow-right": "Points at what comes next.",
///   "house": "Home.\nUsed for the first tab."
/// }
/// ```
///
/// A comment is prose rather than markup, and a newline in it starts a new line
/// of the comment. An entry with nothing but whitespace in it is treated as
/// absent, so that emptying one out is the same as deleting it.
Map<String, String> parseIconComments(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'A comment file must be a JSON object of icon name to comment',
    );
  }
  final comments = <String, String>{};
  for (final entry in decoded.entries) {
    final comment = switch (entry.value) {
      final String value => value,
      _ => throw FormatException(
        'The comment for "${entry.key}" is not a string',
      ),
    };
    if (comment.trim().isNotEmpty) {
      comments[entry.key] = comment;
    }
  }
  return comments;
}
