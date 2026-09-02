/// How the ends of an open stroked sub path are drawn.
enum StrokeCap {
  /// The stroke stops exactly at the end point.
  butt,

  /// A half disc of the stroke's radius is added at the end point.
  round,

  /// The stroke is extended by half its width and squared off.
  square;

  /// Parses the SVG `stroke-linecap` keyword [value].
  ///
  /// Unknown keywords fall back to [StrokeCap.butt], matching the SVG initial
  /// value.
  static StrokeCap parse(String value) => switch (value.trim()) {
    'round' => StrokeCap.round,
    'square' => StrokeCap.square,
    _ => StrokeCap.butt,
  };
}

/// How the corners between two stroked segments are filled in.
enum StrokeJoin {
  /// The outer edges are extended until they meet, falling back to [bevel] when
  /// the resulting spike would be longer than the miter limit.
  miter,

  /// A wedge of a disc of the stroke's radius fills the corner.
  round,

  /// The two outer corner points are joined by a straight line.
  bevel;

  /// Parses the SVG `stroke-linejoin` keyword [value].
  ///
  /// Unknown keywords fall back to [StrokeJoin.miter], matching the SVG initial
  /// value.
  static StrokeJoin parse(String value) => switch (value.trim()) {
    'round' => StrokeJoin.round,
    'bevel' => StrokeJoin.bevel,
    _ => StrokeJoin.miter,
  };
}
