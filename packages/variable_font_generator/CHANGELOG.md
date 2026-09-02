## 0.1.0

First release.

- Builds a variable OpenType icon font from a directory of SVG icons, with the
  `FILL`, `wght`, `GRAD` and `opsz` axes that Flutter's `Icon` widget drives.
- Writes Flutter bindings: a class of `static const IconData` values named after
  the source files, and optionally a pubspec declaring the font and an index of
  every icon.
- Understands `path`, `circle`, `ellipse`, `rect`, `line`, `polyline`,
  `polygon` and `g`, with inherited presentation attributes, `style` attributes,
  elliptical arcs and `transform`.
- Keeps code point assignments stable across rebuilds through a JSON map.
- Exposes the whole pipeline as a library: SVG parsing, stroking, the variation
  model, the font writer, a font reader that applies variations, and a
  rasteriser.
