# variable_font_generator

A Dart tool that turns a directory of SVG icons into a **variable** OpenType
icon font, and writes the Flutter bindings for it.

The generated font responds to the four axes Flutter's `Icon` widget already
drives — `fill`, `weight`, `grade` and `opticalSize` — so one file covers what
would otherwise be a family of them.

<!-- The picture below is the fill axis running from 0 to 1, drawn by Flutter
     from the generated font. It is a checked-in golden test. -->
![Icons at fill 0, 0.25, 0.5, 0.75 and 1](packages/lucide_variable_icons/test/goldens/fill.png)

## Layout

| | |
| --- | --- |
| [`packages/variable_font_generator`](packages/variable_font_generator) | the tool, as a pure Dart package |
| [`packages/lucide_variable_icons`](packages/lucide_variable_icons) | 45 Lucide icons built by it, with Flutter golden tests |
| [`action.yml`](action.yml) | the reusable GitHub action, which is this repository |
| [`tool/build_binary.sh`](tool/build_binary.sh) | compiles the tool into a single executable |
| [`tool/verify_font.py`](tool/verify_font.py) | checks a font against fontTools, FreeType, resvg, HarfBuzz and the OpenType Sanitizer |
| [`tool/check_tree_shaking.sh`](tool/check_tree_shaking.sh) | checks that a release build keeps exactly the icons it draws |

Start with the [package README](packages/variable_font_generator/README.md) —
it covers installation, the command line, how the axes are realised, and the
limitations.

## Quick start

```sh
cd packages/variable_font_generator
dart pub get
dart run bin/variable_font_generator.dart build ../../my-icons \
  --output ../../build/my_icons --family MyIcons
```

## In GitHub Actions

This repository is a reusable action. Point it at a directory of SVG files and
it writes the font, and the Flutter bindings if you want them:

```yaml
- uses: nikodembernat/variable_font_generator@main
  id: icons
  with:
    icons: assets/icons
    output: packages/my_icons
    family: MyIcons
    package: my_icons
    class-name: MyIcons
    extension-name: MyIconData
    pubspec: true
    index: true
    codepoints: packages/my_icons/codepoints.json

- run: echo "${{ steps.icons.outputs.icon-count }} icons in ${{ steps.icons.outputs.font }}"
```

`class-name` names the class holding every icon and `extension-name` declares an
extension type wrapping `IconData` for them to have, so a signature can ask for
an icon from this set rather than any icon at all. Leave `extension-name` out
and the icons stay plain `IconData`; set `bindings: false` and only the font is
written.

The action runs a compiled binary. Pinned to a version tag it takes the one
published with that release; pinned to anything else — a branch, a commit, a
fork, a `uses: ./` — it compiles the generator from its own checkout and caches
the result against the hash of that source, because only a tag says which
published binary matches the source being run. Either way there is nothing to
install in the workflow.

So `@main` always works, and always compiles; `@v0.2.0` fixes the version and
downloads.

### Inputs

Every option of the command line, named the same way. The ones most builds
touch:

| input | | |
| --- | --- | --- |
| `icons` | **required** | the directory of SVG files |
| `output` | `build/icons` | where everything is written |
| `family` | `CustomIcons` | the font family name |
| `bindings` | `true` | whether to write the Flutter bindings at all |
| `class-name` | the family name | the generated class, such as `LucideIcons` |
| `extension-name` | — | an extension type over `IconData`, such as `LucideIconData` |
| `package` | — | the Flutter package the font ships in |
| `index` | `false` | also list every icon by name in a second library |
| `pubspec` | `false` | write a `pubspec.yaml` declaring the font |
| `codepoints` | — | a JSON file remembering each icon's code point |
| `axes` | `FILL,wght,GRAD,opsz` | which variation axes to offer |
| `preview` | — | write a PNG contact sheet |
| `version` | the action's own | which build of the generator to run |

`naming`, `library`, `mirror-rtl`, `recursive`, `reproducible`, `units-per-em`,
`curve-tolerance`, `start-codepoint`, `font-version`, `copyright`, `designer`,
`manufacturer`, `license`, `license-url`, `vendor-id`, `working-directory` and
`dart-sdk` are there too; [`action.yml`](action.yml) describes each one.

### Outputs

`font`, `bindings`, `index`, `pubspec`, `codepoints` and `preview` are the paths
of what was written, empty for anything that was not. `icon-count` and
`font-bytes` describe the font, and `binary` is the generator itself, for a
later step that wants to call it directly.

### Committing the result back

The font and the bindings are generated files, so a workflow can keep them up to
date rather than asking a person to remember:

```yaml
- uses: nikodembernat/variable_font_generator@main
  with:
    icons: assets/icons
    output: packages/my_icons
    family: MyIcons
    package: my_icons
    pubspec: true
    codepoints: packages/my_icons/codepoints.json

- uses: peter-evans/create-pull-request@v7
  with:
    title: Rebuild the icon font
    branch: icons/rebuild
```

Keep `codepoints` under version control and pass it every time. Without it,
adding or removing one icon shifts the code points of all the ones after it, and
because `IconData(0xe123)` is compiled into applications, that silently changes
what an already-published build draws.

## As a binary

```sh
tool/build_binary.sh                    # build/bin/variable_font_generator
tool/build_binary.sh --output /usr/local/bin/variable_font_generator
```

It is a single self-contained executable of about 7 MB that needs no Dart SDK.
Releases carry one for `linux-x64`, `linux-arm64`, `macos-arm64`, `macos-x64`
and `windows-x64`, each with its SHA-256 beside it;
`.github/workflows/release.yaml` builds and publishes them.

The Linux binaries need only glibc 2.18, whatever they were built on: the
executable is the SDK's own AOT runtime with a snapshot appended, so its floor
is the SDK's rather than the build machine's.

## Working on this repository

```sh
# the generator: unit tests, round-trip tests and image comparisons
cd packages/variable_font_generator && dart pub get && dart test

# the Flutter package: golden tests rendered by the real engine
cd packages/lucide_variable_icons && flutter pub get && flutter test

# rebuild the checked-in Flutter package after changing the generator
./tool/generate_lucide_package.sh

# build the executable the GitHub action runs
./tool/build_binary.sh

# check that Flutter's icon tree shaker still recognises the generated icons
pip install fonttools && ./tool/check_tree_shaking.sh

# check a font against four independent implementations
pip install -r tool/requirements.txt
python3 tool/verify_font.py \
  --icons packages/variable_font_generator/test/fixtures/lucide \
  --font packages/lucide_variable_icons/lib/fonts/LucideVariable.ttf \
  --codepoints packages/lucide_variable_icons/codepoints.json
```

`packages/lucide_variable_icons` is generated and checked in, because the golden
tests need something to render. A test in the generator package fails if it
drifts from what the generator would produce today.

## Licence

The tool is MIT licensed; see [LICENSE](LICENSE).

The icons under `packages/variable_font_generator/test/fixtures/lucide` are from
[Lucide](https://lucide.dev) and are ISC licensed; their licence is kept beside
them. `packages/lucide_variable_icons` is built from those, and carries the same
licence.
