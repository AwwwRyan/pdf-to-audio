"""Generates every icon and splash asset from the vendored Lucide glyph.

    python -m pip install resvg-py pillow
    python tool/generate_icons.py
    dart run flutter_launcher_icons && dart run flutter_native_splash:create

Source glyph: assets/icon/book-headphones.svg (Lucide, ISC licence, see
assets/licenses/lucide.txt). Coordinates below use the glyph's own 24-unit
grid; its drawn bounds are x 4–20, y 2–22, centred on (12, 12).
"""

import io
import pathlib
import re

import resvg_py
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / 'assets' / 'icon'
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
STORE = ROOT / 'fastlane' / 'metadata' / 'android' / 'en-US' / 'images'

BRAND = '#2F5D7C'
GRADIENT_TOP = '#3B7FA8'
GRADIENT_BOTTOM = '#22506E'

def read_glyph(path):
    return re.search(r'<svg[^>]*>(.*)</svg>', path.read_text(encoding='utf-8'), re.S).group(1)


GLYPH = read_glyph(ICON_DIR / 'book-headphones.svg')


def glyph(cx, cy, scale, color='#FFFFFF', stroke=2.0, body=GLYPH, fill='none'):
    """A 24-unit Lucide glyph centred on (cx, cy), `scale` canvas units per
    glyph unit. Small circles are filled so thin strokes leave no pinhole."""
    body = body.replace('<circle', f'<circle fill="{color}"')
    return (f'<g transform="translate({cx - 12 * scale} {cy - 12 * scale}) scale({scale})" '
            f'fill="{fill}" stroke="{color}" stroke-width="{stroke}" '
            f'stroke-linecap="round" stroke-linejoin="round">{body}</g>')


GRADIENT = (f'<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="{GRADIENT_TOP}"/>'
            f'<stop offset="1" stop-color="{GRADIENT_BOTTOM}"/></linearGradient></defs>')


def svg(width, height, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">{body}</svg>')


def save(svg_text, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    png = bytes(resvg_py.svg_to_bytes(svg_string=svg_text))
    Image.open(io.BytesIO(png)).convert('RGBA').save(path, optimize=True)
    print('wrote', path.relative_to(ROOT))


# Adaptive icon layers use a 108-unit canvas: the launcher masks it, and only
# the central 66-unit circle is guaranteed visible. The glyph (16×20 units
# × 2.4) has a ~61-unit diagonal, inside it.
S = 1024
U = S / 108
save(svg(S, S, glyph(S / 2, S / 2, 2.4 * U, stroke=1.75)), ICON_DIR / 'icon_foreground.png')
save(svg(S, S, glyph(S / 2, S / 2, 2.4 * U, stroke=1.75)), ICON_DIR / 'icon_monochrome.png')
save(svg(S, S, GRADIENT + f'<rect width="{S}" height="{S}" fill="url(#bg)"/>'),
     ICON_DIR / 'icon_background.png')

# Legacy (pre-Android 8) icon: rounded square, transparent corners.
save(svg(S, S, GRADIENT + f'<rect width="{S}" height="{S}" rx="{S * 0.22}" fill="url(#bg)"/>'
         + glyph(S / 2, S / 2, 2.6 * U, stroke=1.75)), ICON_DIR / 'icon.png')

# Small copy bundled as a Flutter asset for the About dialog.
A = 192
save(svg(A, A, GRADIENT + f'<rect width="{A}" height="{A}" rx="{A * 0.22}" fill="url(#bg)"/>'
         + glyph(A / 2, A / 2, A / 108 * 2.6, stroke=1.75)), ICON_DIR / 'icon_192.png')

# Play Store icon: 512×512 full bleed; Play applies its own mask.
P = 512
save(svg(P, P, GRADIENT + f'<rect width="{P}" height="{P}" fill="url(#bg)"/>'
         + glyph(P / 2, P / 2, P / 108 * 2.6, stroke=1.75)), STORE / 'icon.png')

# Feature graphic for the store listing.
save(svg(1024, 500, GRADIENT + '<rect width="1024" height="500" fill="url(#bg)"/>'
         + glyph(512, 250, 11, stroke=1.6)), STORE / 'featureGraphic.png')

# Splash, pre-Android 12: drawn at its pixel size on xxxhdpi (4×), so a
# 384 px canvas is a 96 dp logo.
save(svg(384, 384, glyph(192, 192, 14)), ICON_DIR / 'splash_logo.png')

# Splash, Android 12+ without an icon background: 288 dp canvas, content
# inside a 192 dp circle. At 4×: 1152 px canvas, 768 px circle.
save(svg(1152, 1152, glyph(576, 576, 26)), ICON_DIR / 'splash_android12.png')

# Status-bar notification icon: white on transparent, 24 dp.
for density, px in {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96}.items():
    save(svg(px, px, glyph(px / 2, px / 2, px / 24)),
         RES / f'drawable-{density}' / 'ic_stat_accha_sunno.png')

# Home-screen widget controls: white masks, tinted per theme in the layout.
# Play/pause are filled for a solid centre button; the rotate arrows stay
# outlined so the "10" label drawn over them stays legible.
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, fill in {'play': 'white', 'pause': 'white', 'rotate-ccw': 'none', 'rotate-cw': 'none'}.items():
    body = read_glyph(ICON_DIR / 'widget' / f'{name}.svg')
    for density, k in DENSITIES.items():
        px = round(24 * k)
        save(svg(px, px, glyph(px / 2, px / 2, px / 24, body=body, fill=fill)),
             RES / f'drawable-{density}' / f'ic_widget_{name.replace("-", "_")}.png')
