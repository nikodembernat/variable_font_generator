## 0.2.0

- `--extension-name` declares an extension type wrapping `IconData` and gives
  every generated icon that type, so a signature can ask for an icon from this
  set rather than any icon at all. It is erased during compilation, so the
  values stay `IconData` instances and icon tree shaking keeps working.
- `--no-bindings` writes the font on its own, for a project that is not
  Flutter's.
- `--summary` writes a `key=value` list of everything the build produced.
  Pointing it at `$GITHUB_OUTPUT` turns those paths into a step's outputs.
- The class and extension type names are checked before anything is written,
  rather than being emitted as Dart that will not compile.
- **Breaking**: `BuildResult.libraryPath` is nullable, because a build without
  bindings writes no library.

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
