#!/usr/bin/env python3
"""Puts station renders in a desktop window frame for the README.

    hcc tests/render_views.HC -o build/render_views && SDL_VIDEODRIVER=offscreen ./build/render_views
    hcc tests/render_demo.HC -o build/render_demo && SDL_VIDEODRIVER=offscreen ./build/render_demo
    python3 tools/make-screens.py

Writes docs/screens/NAME.png. The title bar shows the same title the
station sets on its real window, so the role is readable at a glance.
Needs Pillow.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BUILD = os.path.join(ROOT, "build")
OUT = os.path.join(ROOT, "docs", "screens")
FONT = os.path.join(ROOT, "assets", "fonts", "Inter-Medium.ttf")

MANAGER = "ARK  Manager: Dana Kessler"
ANALYST = "ARK  Analyst: Marcus Hale"

SCREENS = [
    ("manager-overview", "ui-overview.ppm", MANAGER),
    ("analyst-overview", "ui-member-overview.ppm", ANALYST),
    ("server-log", "ui-server-picked.ppm", MANAGER),
    ("phase-request", "ui-phase-ask.ppm", MANAGER),
    ("network", "ui-member-network.ppm", ANALYST),
    ("report", "demo-7-a.ppm", MANAGER),
    ("breach-clocks", "ui-clocks.ppm", MANAGER),
]

WIDTH = 1200          # of the window, before the shadow margin
BAR = 34
MARGIN = 28
RADIUS = 10
BAR_BG = (26, 31, 44)
BAR_LINE = (44, 52, 72)
TITLE = (214, 220, 232)
GLYPH = (150, 160, 182)


def window(shot, title):
    scale = WIDTH / shot.width
    body = shot.resize((WIDTH, round(shot.height * scale)), Image.LANCZOS)
    w, h = WIDTH, BAR + body.height

    win = Image.new("RGBA", (w, h), BAR_BG + (255,))
    win.paste(body, (0, BAR))
    d = ImageDraw.Draw(win)
    d.line([(0, BAR - 1), (w, BAR - 1)], fill=BAR_LINE)
    f = ImageFont.truetype(FONT, 14)
    d.text((w / 2, BAR / 2), title, font=f, fill=TITLE, anchor="mm")
    # minimise, maximise, close, as KDE and GNOME draw them
    cy, x = BAR // 2, w - 22
    d.line([(x - 5, cy - 5), (x + 5, cy + 5)], fill=GLYPH, width=2)
    d.line([(x - 5, cy + 5), (x + 5, cy - 5)], fill=GLYPH, width=2)
    x -= 32
    d.rectangle([x - 5, cy - 5, x + 5, cy + 5], outline=GLYPH, width=2)
    x -= 32
    d.line([(x - 5, cy + 4), (x + 5, cy + 4)], fill=GLYPH, width=2)

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=RADIUS, fill=255)
    out = Image.new("RGBA", (w + 2 * MARGIN, h + 2 * MARGIN), (0, 0, 0, 0))
    shadow = Image.new("L", out.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle([MARGIN, MARGIN + 8, MARGIN + w, MARGIN + h + 8], radius=RADIUS, fill=120)
    out.putalpha(shadow.filter(ImageFilter.GaussianBlur(14)))
    out.paste(win, (MARGIN, MARGIN), mask)
    ImageDraw.Draw(out).rounded_rectangle([MARGIN, MARGIN, MARGIN + w - 1, MARGIN + h - 1], radius=RADIUS,
                                          outline=(58, 68, 94), width=1)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, src, title in SCREENS:
        path = os.path.join(BUILD, src)
        if not os.path.exists(path):
            sys.exit("missing build/%s: run render_views and render_demo first" % src)
        img = window(Image.open(path).convert("RGB"), title)
        dst = os.path.join(OUT, name + ".png")
        img.save(dst, optimize=True)
        print("wrote docs/screens/%s.png %d KB" % (name, os.path.getsize(dst) // 1024))


if __name__ == "__main__":
    main()
