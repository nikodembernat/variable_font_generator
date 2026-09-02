# variable_font_generator

Turns a directory of SVG icons into a **variable** OpenType font, and writes the
Flutter bindings for it.

The font responds to the four axes Flutter's `Icon` widget already knows how to
drive, so an icon can be animated from outlined to filled, thickened to match
the text beside it, or thinned as it grows — without shipping a second file.

```dart
Icon(MyIcons.house, size: 32, fill: 1, weight: 700)
```

| axis | `Icon` parameter | range | what it does |
| ---- | ---------------- | ----- | ------------ |
| `FILL` | `fill` | 0 – 1 | closes the holes in outlined shapes, cutting any detail strokes back out of the solid |
| `wght` | `weight` | 100 – 700 | thickens the strokes |
| `GRAD` | `grade` | -50 – 200 | thickens them more finely, for matching surrounding text |
| `opsz` | `opticalSize` | 20 – 48 | thins them as the icon grows, so it reads the same at any size |
| `wdth` | — | 75 – 125 | narrows or widens the shapes, keeping the strokes' thickness |

Those four are every axis `Icon` can drive. `wdth` is off by default because
`Icon` has no parameter for it; turn it on with `--axes FILL,wght,GRAD,opsz,wdth`
and reach it through `TextStyle`:

```dart
Text(
  String.fromCharCode(MyIcons.house.codePoint),
  style: const TextStyle(
    fontFamily: 'MyIcons',
    fontSize: 32,
    fontVariations: [FontVariation.width(87.5)],
  ),
)
```

## Install

```sh
dart pub global activate variable_font_generator
```

Or add it as a dev dependency and run it with `dart run`:

```sh
dart pub add --dev variable_font_generator
```

Or take a compiled executable, which needs no Dart SDK at all. Every release
carries one for Linux, macOS and Windows; `tool/build_binary.sh` in the
repository builds one from source in a few seconds.

In GitHub Actions there is nothing to install: the repository is a reusable
action. See [its README](https://github.com/nikodembernat/variable-font-generator#in-github-actions).

## Build a font

```sh
variable_font_generator build assets/icons \
  --output packages/my_icons \
  --family MyIcons \
  --package my_icons \
  --class-name MyIcons \
  --pubspec \
  --codepoints packages/my_icons/codepoints.json
```

That writes a complete Flutter package:

```
packages/my_icons/
├── pubspec.yaml                 # declares the font family
├── codepoints.json              # which code point each icon has
└── lib/
    ├── fonts/MyIcons.ttf
    └── my_icons.dart            # class MyIcons { static const IconData house = ...; }
```

Naming a class is the whole of the request for bindings: without `--class-name`
the font is written alone, which is what a project that is not Flutter's wants.
The class names the font too, so `--family` is only needed when the font should
be called something else — or when there is no class to name it after.

Two things are being asked for there, and they are separate. `--pubspec` says
the output directory is a package, which is what puts the font under `lib/` —
the only part of a package other projects can reach. `--package` says who the
font belongs to, and only fills in `fontPackage` on every `IconData`, so that
Flutter looks the family up as `packages/my_icons/MyIcons`. Drop both to build
for an application's own `assets/` directory: the files stay where `--output`
put them, and `fontPackage` is left unset, which is what a font declared in the
application's own pubspec needs.

### A type of your own for the icons

`--extension-name` declares an extension type wrapping `IconData` and gives
every generated icon that type, so a signature can ask for an icon from this set
rather than any icon at all:

```sh
variable_font_generator build assets/icons \
  --class-name MyIcons --extension-name MyIconData
```

```dart
extension type const MyIconData(IconData _icon) implements IconData;

@staticIconProvider
abstract final class MyIcons {
  static const MyIconData house = MyIconData(
    IconData(0xe000, fontFamily: 'MyIcons'),
  );
}

// Only this set's icons get past the signature, and `Icon` still takes one.
Widget leading(MyIconData icon) => Icon(icon, fill: 1);
```

It costs nothing at run time, and — unlike the subclass this looks like —
nothing at build time either. An extension type is erased during compilation, so
the values stay `IconData` instances and Flutter's icon tree shaker still finds
them. (There is no subclass to compare it against in any case: `IconData` is a
`final class`, so it cannot be extended.) A release build of an application
drawing three of the 45 icons in the fixture font subsets it from 219 KB to
12 KB, wrapper type or not.

Extension types are a Dart 3.3 feature, so the project the bindings land in
needs at least that. Leave the option out and the icons stay plain `IconData`.

### Keep the code points stable

`--codepoints <file>` remembers which code point every icon was given. Pass it
on every build. Without it, adding or removing one icon shifts all the ones
after it — and because `IconData(0xe123)` is compiled into applications, that
silently changes what an already-published build draws.

### Options

```
--output, -o        Where everything is written.       (the current directory)
--family            The font family name.       (--class-name, or CustomIcons)
--class-name        The class to hold the icons. Naming one asks for the
                    bindings; without it only the font is written.
--extension-name    An extension type over IconData to give the icons.
--package           Names the package in fontPackage on every icon.
--library           File name of the generated library.
--naming            camel | snake                           (camel)
--axes              Which of FILL, wght, GRAD, opsz, wdth to offer.
                                                            (all but wdth)
--index             Also write a library listing every icon by name.
--codepoints        A JSON file remembering the code points.
--start-codepoint   Where to start assigning them.          (0xE000)
--units-per-em      The design grid resolution.             (1000)
--curve-tolerance   How far a curve may deviate, in design units.  (1)
--mirror-rtl        Icons to flip in right-to-left layouts.
--preview           Write a PNG contact sheet of the result.
--summary           Write a key=value list of everything produced.
--pubspec           Make the output a package: a pubspec, and the font under
                    lib/. Needs --package.
--recursive, -r     Search sub directories for SVG files.
--font-version --copyright --designer --manufacturer --license --license-url
--vendor-id         Metadata stored in the font.
```

Run `variable_font_generator build --help` for the full list.

## What it does with the artwork

The generator is built for **stroked** icon sets — Lucide, Feather, Tabler and
anything else drawn as centre lines with a stroke width rather than as filled
shapes. That is what makes the axes possible: the stroke width is a number it
can turn.

Every SVG shape element is understood (`path`, `circle`, `ellipse`, `rect`,
`line`, `polyline`, `polygon`, and `g` for grouping), along with elliptical
arcs, inherited presentation attributes, `style` attributes and `transform`.

Each icon is stroked into an outline in which every point is an affine function
of the stroke width. Re-stroking at another weight therefore produces an outline
with the same contours, the same points, in the same order — which is precisely
what OpenType's `gvar` table needs in order to store the difference between
weights. Getting that invariant right is most of the work; the stroker also
handles the cases naive offsetting gets wrong:

- a path that crosses itself is cut at the crossings and stroked in pieces, so
  the fill rule does not punch a hole where the two passes overlap;
- a stroke wider than the shape it outlines drops its inner boundary rather than
  turning it inside out;
- a sharp inner corner falls back from its miter point before it can spike;
- a zero-length sub path becomes a dot, which is what SVG asks for.

### The fill axis

Filling closes the holes in closed shapes. A detail stroke sitting inside one —
the tick in a circle, the terminals in a battery, the door in a house — narrows
to nothing as the fill closes while a reversed copy widens in its place, so a
filled icon shows its detail as a gap cut out of the solid rather than losing it
in the fill.

The detail and the gap that replaces it never appear at the same time: the drawn
copy is withdrawn by half fill and the gap opens from half fill on. They cannot
share the axis, because a stroke and its reversed copy are the same width
wherever they overlap and cancel exactly — a detail splitting the fill with its
own replacement disappears in the middle and comes back as a hairline outline of
itself. The price is that at exactly half fill a detail has no width, and the
handover is what the extra master at half fill is for.

An open stroke that is not inside anything has no interior to fill, so `FILL`
leaves it alone. That is a real limitation rather than an oversight: an arrow
has no filled form, and inventing one would be guessing.

## Using it as a library

The command line is a thin wrapper. Everything is available directly:

```dart
import 'dart:io';
import 'package:variable_font_generator/variable_font_generator.dart';

final icons = loadSvgIcons(Directory('assets/icons'));

final font = const IconFontGenerator().generate(
  icons: icons,
  names: const FontNames(family: 'MyIcons'),
);
File('MyIcons.ttf').writeAsBytesSync(font.bytes);

final bindings = const FlutterBindingsGenerator(
  className: 'MyIcons',
  font: FontReference.application(family: 'MyIcons'),
).generate(font.icons);
File('lib/my_icons.dart').writeAsStringSync(bindings);
```

The pieces underneath are public too, and useful on their own: `parseSvgPath`
and `parseSvgIcon` for reading artwork, `Stroker` for turning centre lines into
outlines, `VariationModel` for solving master positions into deltas,
`writeVariableFont` for assembling a font, `ParsedFont` for reading one back and
applying its variations, and `Rasterizer` for drawing any of it into a bitmap.

## How the axes are realised

`wght`, `GRAD` and `opsz` all scale the stroke width, over the ranges Material
Symbols uses so that an application can pass the same numbers to either. `wdth`
scales the artwork horizontally and leaves the stroke's own thickness alone, the
way a condensed typeface keeps its stem weight.

An outline is affine in the stroke width, affine in the fill amount and affine
in the width, but not in their products — filling moves a hole's boundary onto a
point, and how far each point travels depends on how thick the stroke was and
how far the shape was stretched. Variation interpolation is linear, so the
design space carries a master wherever two effects meet: the default, each axis
alone at both ends, and each of the others combined with a fill, at half and at
full. Twenty-one in all, or twenty-seven with `wdth`, which makes interpolation
exact everywhere rather than approximate.

Stroke width and width need no master together, which is the whole reason for
defining width the way it is: moving the centre line and leaving the stroke
alone makes the two genuinely independent, and saves twelve masters.

No `avar` table is written, because each axis is arranged to be linear on either
side of its default, which the normalised axis mapping already provides. No
`HVAR` either: advance widths do not vary, and a missing `HVAR` means exactly
that.

## Is it right?

The package does not check itself against itself.

- Every master position is read back out of the finished file and compared
  against the outlines that went in. They match to the unit.
- The generated font is rasterised with **FreeType** and the source SVGs with
  **resvg**, and the two pictures are compared. Over all 1798 Lucide icons the
  mean overlap is 0.992 and the worst is 0.973.
- The **OpenType Sanitizer** — the validator Chrome and Firefox use to decide
  whether to load a web font — accepts the output.
- **fontTools** parses every table and instantiates the font at chosen axis
  values; **HarfBuzz** shapes text with it.
- Flutter golden tests render real `Icon` widgets through the actual engine,
  which is the only thing that proves the axes reach Skia. A font whose `fvar`
  or `gvar` is subtly wrong renders without complaint and simply refuses to
  change shape.
- A release build of a throwaway application drawing three of the 45 fixture
  icons is inspected, and the font that comes out of it has to hold those three
  and nothing else. That is the only way to see the icon tree shaker, which
  fails silently in both directions: a font with every icon in it, or one
  missing the icons being drawn.

`tool/verify_font.py` in the repository runs the first four; see
`.github/workflows/ci.yaml` for how they fit together.

## Limitations

- Built for stroked artwork. A set drawn as filled shapes will produce a font,
  but the stroke-width axes will have nothing to turn.
- Gradients, filters, clip paths, masks and text are ignored. Icon sets do not
  use them; if yours does, flatten it first.
- A `transform` with a non-uniform scale scales the stroke by the geometric mean
  of the two factors, rather than making it elliptical as SVG would.
- Composite glyphs are never written, so identical icons do not share outlines.
- `gvar` dominates the file size — about 6 KB per icon with all four of the
  `Icon` axes, of which a fifth is the half-fill master that keeps a detail from
  cancelling against the gap replacing it. Use `--axes` to drop the ones you do
  not need; a weight-only font is roughly a seventh of the size, and adding
  `wdth` costs about a third more.
- There is no `slnt` or `ital` axis. Slanting an icon shears it, which needs a
  master against every other axis and is rarely what anyone wants from a symbol.
