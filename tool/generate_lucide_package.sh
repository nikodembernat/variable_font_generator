#!/usr/bin/env bash
# Regenerates packages/lucide_variable_icons from the fixture icons.
#
# The package is checked in so that the Flutter golden tests have something to
# render. `dart test test/generated_package_test.dart` in the generator package
# fails if it drifts from what the generator would produce today.
set -euo pipefail
cd "$(dirname "$0")/.."

dart run packages/variable_font_generator/bin/variable_font_generator.dart build \
  packages/variable_font_generator/test/fixtures/lucide \
  --output packages/lucide_variable_icons/lib \
  --family LucideVariable \
  --package lucide_variable_icons \
  --class-name LucideIcons \
  --extension-name LucideIconData \
  --index \
  --codepoints packages/lucide_variable_icons/codepoints.json \
  --font-version 1.000 \
  --copyright "Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022." \
  --designer "Lucide Contributors" \
  --license "ISC" \
  --license-url "https://github.com/lucide-icons/lucide/blob/main/LICENSE" \
  --vendor-id "VFG " \
  --mirror-rtl arrow-right,navigation,navigation-2
