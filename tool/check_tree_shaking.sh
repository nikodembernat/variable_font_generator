#!/usr/bin/env bash
# Checks that Flutter's icon tree shaker still recognises the generated icons.
#
# It builds a throwaway application that draws three icons out of
# packages/lucide_variable_icons and reads the font that came out of the build,
# which should hold those three and nothing else.
#
# The check earns its place because the failure it guards against is silent.
# `@staticIconProvider` is what tells the tree shaker that a declaration is not
# a use, and the tool reads that annotation off a class; moving the icons into
# the body of the extension type would leave the annotation on something that
# is not a class, where it is ignored without a word. Nothing would fail: the
# font would simply arrive with every icon in it. A web build is what catches
# it, because it has no whole-program pass to fall back on.
#
# Needs a Flutter SDK, and fontTools (pip install fonttools).
set -euo pipefail
cd "$(dirname "$0")/.."
repository="$PWD"
package="$repository/packages/lucide_variable_icons"
font="$package/lib/fonts/LucideVariable.ttf"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

# Scaffolded first, then given a pubspec of our own, so that whatever the
# template writes cannot decide what this depends on.
flutter create . --project-name tree_shaking_probe --platforms web > /dev/null

cat > pubspec.yaml <<EOF
name: tree_shaking_probe
description: Draws a few icons so that the build can be inspected.
publish_to: none
version: 1.0.0
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
  lucide_variable_icons:
    path: $package
EOF

cat > lib/main.dart <<'EOF'
import 'package:flutter/widgets.dart';
import 'package:lucide_variable_icons/lucide_variable_icons.dart';

// Named through the generated wrapper type, which is the point of the check.
Widget draw(LucideIconData icon) => Icon(icon, size: 32);

void main() => runApp(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        draw(LucideIcons.house),
        draw(LucideIcons.star),
        draw(LucideIcons.battery),
      ],
    ),
  ),
);
EOF

flutter pub get > /dev/null
flutter build web --release

subset="$work/build/web/assets/packages/lucide_variable_icons/lib/fonts/LucideVariable.ttf"
python3 - "$font" "$subset" "$package/codepoints.json" <<'EOF'
import json
import sys

from fontTools.ttLib import TTFont

whole, subset, codepoints = sys.argv[1:4]
assignments = json.load(open(codepoints))
drawn = {name: assignments[name] for name in ('house', 'star', 'battery')}

kept = set(TTFont(subset).getBestCmap())
everything = set(TTFont(whole).getBestCmap())
wanted = {int(str(point), 16) if isinstance(point, str) else point
          for point in drawn.values()}

print(f'the font holds {len(everything)} icons, '
      f'the build kept {len(kept)}: '
      + ', '.join(sorted(hex(point) for point in kept)))

if kept != wanted:
    missing = sorted(hex(p) for p in wanted - kept)
    extra = sorted(hex(p) for p in kept - wanted)
    sys.exit(
        'The build should have kept exactly the three icons it draws.\n'
        f'  missing: {missing or "none"}\n'
        f'  extra:   {extra or "none"}\n'
        'An icon that is drawn and missing means the tree shaker cannot see '
        'the declarations; every icon kept means it cannot see that a '
        'declaration is not a use.'
    )
print('the tree shaker keeps exactly the icons that are drawn')
EOF
