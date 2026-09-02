#!/usr/bin/env python3
"""Check a generated icon font against the artwork it was built from.

Three independent implementations are used, so that a mistake in the generator
cannot hide behind a matching mistake in its own tests:

  * the OpenType Sanitizer decides whether a browser would accept the file;
  * fontTools parses every table and instantiates the font at chosen axis
    values;
  * FreeType rasterises the glyphs and resvg rasterises the source SVGs, and
    the two images are compared.

Usage:
    python3 tool/verify_font.py --icons <dir> --font <ttf> --codepoints <json>
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys

import numpy as np


def fail(message: str) -> None:
    print(f'  FAIL {message}')
    fail.count += 1


fail.count = 0


def ok(message: str) -> None:
    print(f'  ok   {message}')


def check_sanitizer(font_path: str) -> None:
    print('OpenType Sanitizer')
    import ots

    result = ots.sanitize(font_path, check=False, capture_output=True)
    if result.returncode != 0:
        fail(f'rejected the font:\n{result.stdout.decode()}{result.stderr.decode()}')
        return
    output = result.stdout.decode().strip()
    if 'WARNING' in output.upper():
        fail(f'accepted the font with warnings:\n{output}')
    else:
        ok(output)


def check_structure(font_path: str, icon_names: list[str], codepoints: dict) -> None:
    print('Table structure')
    from fontTools.ttLib import TTFont

    font = TTFont(font_path, lazy=False)

    required = {'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post',
                'cmap', 'loca', 'glyf', 'fvar', 'gvar', 'STAT'}
    missing = required - set(font.keys())
    if missing:
        fail(f'missing tables: {sorted(missing)}')
    else:
        ok(f'all {len(required)} required tables present')

    head, hhea, os2 = font['head'], font['hhea'], font['OS/2']
    if hhea.ascent - hhea.descent != head.unitsPerEm:
        fail(f'ascender minus descender is {hhea.ascent - hhea.descent}, '
             f'not the em size {head.unitsPerEm}; Flutter would not centre the glyph')
    else:
        ok(f'em box {head.unitsPerEm} matches ascender {hhea.ascent} '
           f'and descender {hhea.descent}')

    if hhea.lineGap != 0:
        fail(f'lineGap is {hhea.lineGap}, not 0')
    if not (os2.fsSelection & 0x80):
        fail('OS/2 fsSelection does not set USE_TYPO_METRICS, so which '
             'ascender a client uses is ambiguous')
    else:
        ok('OS/2 asks clients to use the typographic metrics')
    for name, value in (('sTypoAscender', os2.sTypoAscender),
                        ('sTypoDescender', os2.sTypoDescender)):
        expected = hhea.ascent if name.endswith('Ascender') else hhea.descent
        if value != expected:
            fail(f'OS/2 {name} is {value} but hhea says {expected}')

    if not (head.flags & 0x0002):
        fail('head flags bit 1 (left side bearing at x=0) is clear')
    if head.flags & 0x0020:
        fail('head flags bit 5 (instructions may alter advance width) is set')

    axes = {a.axisTag: (a.minValue, a.defaultValue, a.maxValue) for a in font['fvar'].axes}
    expected_axes = {
        'FILL': (0.0, 0.0, 1.0),
        'wght': (100.0, 400.0, 700.0),
        'GRAD': (-50.0, 0.0, 200.0),
        'opsz': (20.0, 24.0, 48.0),
    }
    for tag, span in expected_axes.items():
        if tag not in axes:
            fail(f'no {tag} axis')
        elif axes[tag] != span:
            fail(f'{tag} spans {axes[tag]}, expected {span}')
    if set(axes) == set(expected_axes):
        ok(f'axes {", ".join(axes)} with the ranges Flutter expects')

    stat_axes = {a.AxisTag for a in font['STAT'].table.DesignAxisRecord.Axis}
    if not set(axes).issubset(stat_axes):
        fail(f'STAT is missing axis records for {sorted(set(axes) - stat_axes)}')
    else:
        ok(f'STAT describes all {len(stat_axes)} axes')

    cmap = font.getBestCmap()
    glyph_order = font.getGlyphOrder()
    for name in icon_names:
        code = codepoints.get(name)
        if code is None:
            fail(f'{name} has no code point')
            continue
        if code not in cmap:
            fail(f'{name} is not reachable at U+{code:04X}')
    if fail.count == 0:
        ok(f'all {len(icon_names)} icons reachable through cmap')

    advances = {font['hmtx'][g][0] for g in glyph_order}
    if advances != {head.unitsPerEm}:
        fail(f'advance widths are {sorted(advances)}, expected only '
             f'{head.unitsPerEm}; a narrower glyph would sit off-centre')
    else:
        ok('every glyph advances exactly one em')

    varied = sum(1 for g in glyph_order if font['gvar'].variations.get(g))
    if varied < len(icon_names):
        fail(f'only {varied} of {len(icon_names)} glyphs carry variation data')
    else:
        ok(f'{varied} glyphs carry variation data')


def check_shaping(font_path: str, icon_names: list[str], codepoints: dict) -> None:
    print('HarfBuzz shaping')
    import uharfbuzz as hb

    with open(font_path, 'rb') as handle:
        face = hb.Face(handle.read())
    font = hb.Font(face)
    missing = []
    for name in icon_names:
        buffer = hb.Buffer()
        buffer.add_str(chr(codepoints[name]))
        buffer.guess_segment_properties()
        hb.shape(font, buffer)
        if any(info.codepoint == 0 for info in buffer.glyph_infos):
            missing.append(name)
    if missing:
        fail(f'{len(missing)} icons shape to .notdef, e.g. {missing[:5]}')
    else:
        ok(f'all {len(icon_names)} icons shape to a real glyph')


def best_overlap(a: np.ndarray, b: np.ndarray) -> float:
    """How much two coverage maps overlap, from 0 to 1.

    This is intersection over union computed on the coverage itself rather than
    on a black-and-white version of it. Thresholding first would make the score
    hinge on how each renderer shades the pixels along an edge: a systematic
    half-level difference in anti-aliasing flips an entire outline's worth of
    pixels and reads as a large disagreement, when the outlines are in fact the
    same. Comparing coverage measures the shapes.

    The best of nine one-pixel placements is taken, because FreeType reports
    where it put a bitmap only in whole pixels.
    """
    left = a.astype(np.float64)
    best = 0.0
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            right = np.roll(np.roll(b, dy, axis=0), dx, axis=1).astype(np.float64)
            union = np.maximum(left, right).sum()
            score = (np.minimum(left, right).sum() / union) if union else 1.0
            best = max(best, score)
    return best


def render_glyph(face, codepoint: int, size: int, coords=None) -> np.ndarray:
    """Draw one glyph the way Flutter's Icon widget would.

    The em box fills the square, so the baseline sits at ascender over
    unitsPerEm of the way down. That is rarely a whole number of pixels, and
    FreeType only reports where it put a bitmap in whole pixels, so the outline
    is shifted by the fractional part before rendering. Without that the glyph
    lands up to half a pixel off, which on a stroke twenty pixels wide is
    several percent of the overlap and says nothing about whether the shapes
    agree.
    """
    import math

    import freetype

    if coords is not None:
        face.set_var_design_coords(coords)

    baseline = size * face.ascender / face.units_per_EM
    whole = math.floor(baseline)
    face.set_transform(
        freetype.Matrix(0x10000, 0, 0, 0x10000),
        # FreeType's y axis points up, so moving the glyph down the page is a
        # negative delta. The units are 26.6 fixed point.
        freetype.Vector(0, -round((baseline - whole) * 64)),
    )
    face.load_char(chr(codepoint), freetype.FT_LOAD_RENDER)

    bitmap = face.glyph.bitmap
    if bitmap.rows == 0 or bitmap.width == 0:
        return np.zeros((size, size), dtype=np.uint8)
    glyph = np.array(bitmap.buffer, dtype=np.uint8)
    glyph = glyph.reshape(bitmap.rows, bitmap.pitch)[:, :bitmap.width]

    canvas = np.zeros((size, size), dtype=np.uint8)
    top = whole - face.glyph.bitmap_top
    left = face.glyph.bitmap_left
    y0, x0 = max(0, top), max(0, left)
    y1 = min(size, top + glyph.shape[0])
    x1 = min(size, left + glyph.shape[1])
    if y1 > y0 and x1 > x0:
        canvas[y0:y1, x0:x1] = glyph[y0 - top:y1 - top, x0 - left:x1 - left]
    return canvas


def check_rendering(font_path: str, icon_dir: str, icon_names: list[str],
                    codepoints: dict, size: int, minimum: float,
                    report: str | None) -> None:
    print(f'Rendering, FreeType against resvg at {size}px')
    import freetype
    import resvg_py
    from PIL import Image

    face = freetype.Face(font_path)
    face.set_char_size(size * 64)

    scores = []
    tiles = []
    for name in icon_names:
        reference_bytes = resvg_py.svg_to_bytes(
            svg_path=os.path.join(icon_dir, f'{name}.svg'),
            width=size, height=size)
        reference = np.asarray(
            Image.open(io.BytesIO(bytes(reference_bytes))).convert('RGBA'),
            dtype=np.int16)[..., 3]
        rendered = render_glyph(face, codepoints[name], size).astype(np.int16)
        scores.append((best_overlap(reference, rendered), name))
        if report:
            a, b = reference >= 128, rendered >= 128
            tile = np.full((size, size, 3), 255, np.uint8)
            tile[a & ~b] = (255, 0, 0)
            tile[b & ~a] = (0, 180, 0)
            tile[a & b] = (200, 200, 255)
            tiles.append(np.concatenate([
                np.stack([255 - reference] * 3, -1).astype(np.uint8),
                np.stack([255 - rendered] * 3, -1).astype(np.uint8),
                tile], axis=1))

    scores.sort()
    values = np.array([s for s, _ in scores])
    print(f'  intersection over union: mean {values.mean():.5f}, '
          f'median {np.median(values):.5f}, worst {values.min():.5f} '
          f'({scores[0][1]})')
    below = [(s, n) for s, n in scores if s < minimum]
    if below:
        fail(f'{len(below)} icons below {minimum}: '
             + ', '.join(f'{n} ({s:.4f})' for s, n in below[:10]))
    else:
        ok(f'every icon at or above {minimum}')

    if report and tiles:
        columns = 4
        rows = [np.concatenate(tiles[i:i + columns], axis=1)
                for i in range(0, len(tiles), columns)]
        width = max(row.shape[1] for row in rows)
        rows = [np.pad(row, ((0, 0), (0, width - row.shape[1]), (0, 0)),
                       constant_values=255) for row in rows]
        Image.fromarray(np.concatenate(rows, axis=0)).save(report)
        print(f'  wrote {report}')


def check_weights(font_path: str, icon_dir: str, icon_names: list[str],
                  codepoints: dict, size: int, minimum: float) -> None:
    """Compare the font against the artwork at weights other than the default.

    check_rendering only ever looks at the default instance, so for a long
    while nothing checked that a glyph is the right *shape* anywhere else on
    the weight axis — only that it drew more ink when asked to be heavier. A
    stroked icon has an obvious reference at any weight: the same SVG with its
    stroke-width scaled to match, which is what the weight axis means.

    The scale factors are written down here rather than read from the font on
    purpose. This is the independent check; it should say what the axis is
    supposed to do, not ask the font what it did.
    """
    print(f'Rendering at other weights, against the artwork re-stroked to match')
    import re

    import freetype
    import resvg_py
    from PIL import Image

    axes = _fvar_axes(font_path)
    tags = [a.axisTag for a in axes]
    defaults = {a.axisTag: a.defaultValue for a in axes}
    if 'wght' not in tags:
        print('  --   no weight axis to check')
        return

    face = freetype.Face(font_path)
    face.set_char_size(size * 64)

    scores = {}
    for weight, factor in ((100, 0.5), (700, 1.5)):
        worst = (2.0, '')
        values = []
        for name in icon_names:
            source = open(os.path.join(icon_dir, f'{name}.svg')).read()
            widths = re.findall(r'stroke-width="([0-9.]+)"', source)
            if not widths:
                continue
            scaled = re.sub(r'stroke-width="([0-9.]+)"',
                            lambda m: f'stroke-width="{float(m.group(1)) * factor}"',
                            source)
            reference_bytes = resvg_py.svg_to_bytes(
                svg_string=scaled, width=size, height=size)
            reference = np.asarray(
                Image.open(io.BytesIO(bytes(reference_bytes))).convert('RGBA'),
                dtype=np.int16)[..., 3]
            coords = [weight if tag == 'wght' else defaults[tag] for tag in tags]
            rendered = render_glyph(face, codepoints[name], size, coords)
            score = best_overlap(reference, rendered.astype(np.int16))
            values.append(score)
            worst = min(worst, (score, name))
        array = np.array(values)
        scores[weight] = array
        print(f'  weight {weight}, stroke-width x{factor}: mean '
              f'{array.mean():.5f}, worst {worst[0]:.5f} ({worst[1]})')
        if array.min() >= minimum:
            ok(f'every icon at or above {minimum}')
        else:
            below = sorted((s, n) for s, n in zip(values, icon_names)
                           if s < minimum)[:5]
            fail('below {}: {}'.format(
                minimum, ', '.join(f'{n} {s:.4f}' for s, n in below)))


def check_variations(font_path: str, icon_names: list[str], codepoints: dict,
                     size: int) -> None:
    print('Variations, as FreeType applies them')
    import freetype

    face = freetype.Face(font_path)
    face.set_char_size(size * 64)
    tags = [a.axisTag for a in _fvar_axes(font_path)]
    defaults = {a.axisTag: a.defaultValue for a in _fvar_axes(font_path)}

    def coords(**overrides):
        # freetype-py converts design values to 16.16 itself, so these are
        # passed in the units fvar declares.
        return [overrides.get(tag, defaults[tag]) for tag in tags]

    sample = icon_names[:20]
    lighter_wrong, heavier_wrong, fill_wrong = [], [], []
    for name in sample:
        light = render_glyph(face, codepoints[name], size,
                             coords(wght=100)).sum()
        normal = render_glyph(face, codepoints[name], size,
                              coords()).sum()
        heavy = render_glyph(face, codepoints[name], size,
                             coords(wght=700)).sum()
        filled = render_glyph(face, codepoints[name], size,
                              coords(FILL=1)).sum()
        if not light < normal:
            lighter_wrong.append(name)
        if not heavy > normal:
            heavier_wrong.append(name)
        if filled < normal:
            fill_wrong.append(name)

    for label, wrong in (('a lighter weight draws less ink', lighter_wrong),
                         ('a heavier weight draws more ink', heavier_wrong),
                         ('filling never draws less ink', fill_wrong)):
        if wrong:
            fail(f'{label} — not true for {wrong}')
        else:
            ok(f'{label}, for all {len(sample)} sampled icons')


def _fvar_axes(font_path: str):
    from fontTools.ttLib import TTFont
    return TTFont(font_path, lazy=True)['fvar'].axes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--icons', required=True, help='directory of source SVG files')
    parser.add_argument('--font', required=True, help='the generated .ttf')
    parser.add_argument('--codepoints', required=True,
                        help='the JSON map of icon name to code point')
    parser.add_argument('--size', type=int, default=384,
                        help='pixels per side when rendering (default 384)')
    parser.add_argument('--min-iou', type=float, default=0.97,
                        help='lowest acceptable overlap per icon (default 0.97)')
    parser.add_argument('--min-weight-iou', type=float, default=0.92,
                        help='lowest acceptable overlap away from the default '
                             'weight. Lower than --min-iou on purpose: at the '
                             'far ends of the axis the artwork\'s own stroking '
                             'degenerates on small shapes, and the generator '
                             'deliberately does not follow it there')
    parser.add_argument('--report', help='write a side-by-side comparison image here')
    parser.add_argument('--limit', type=int, help='only check the first N icons')
    arguments = parser.parse_args()

    codepoints = json.load(open(arguments.codepoints))
    names = sorted(name[:-4] for name in os.listdir(arguments.icons)
                   if name.endswith('.svg'))
    if arguments.limit:
        names = names[:arguments.limit]
    print(f'{len(names)} icons, {arguments.font}\n')

    check_sanitizer(arguments.font)
    check_structure(arguments.font, names, codepoints)
    check_shaping(arguments.font, names, codepoints)
    check_variations(arguments.font, names, codepoints, arguments.size)
    check_rendering(arguments.font, arguments.icons, names, codepoints,
                    arguments.size, arguments.min_iou, arguments.report)
    check_weights(arguments.font, arguments.icons, names, codepoints,
                  arguments.size, arguments.min_weight_iou)

    print()
    if fail.count:
        print(f'{fail.count} check(s) failed')
        return 1
    print('everything checks out')
    return 0


if __name__ == '__main__':
    sys.exit(main())
