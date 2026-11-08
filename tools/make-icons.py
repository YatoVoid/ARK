#!/usr/bin/env python3
"""Draws the Network page icons and converts them for the station.

    python3 tools/make-icons.py

Writes assets/icons/NAME.svg (the source, open it in any browser) and
assets/icons/NAME.img (what the station loads: "ARKIMG1\\n", width and
height as little-endian 32-bit, then RGBA bytes). The station has no PNG
decoder, and this format needs none. Needs ImageMagick with librsvg.

The style follows network topology diagrams: isometric blue boxes with a
white edge and a white glyph on top.
"""
import os
import struct
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "icons")
SIZE = 192

TOP, LEFT, RIGHT = "#2E9BD6", "#1673AE", "#0E5A8C"
EDGE = "#FFFFFF"


def poly(points, fill, stroke=EDGE, width=3):
    pts = " ".join("%.1f,%.1f" % p for p in points)
    return '<polygon points="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>' % (
        pts, fill, stroke, width)


def iso(origin, u, v):
    """A point on a plane spanned by vectors u and v from origin, (s, t) in 0..1."""
    def at(s, t):
        return (origin[0] + u[0] * s + v[0] * t, origin[1] + u[1] * s + v[1] * t)
    return at


def slab(left, u, v, depth, top=TOP, lft=LEFT, rgt=RIGHT):
    """An isometric box: top face spanned by u and v from its left corner."""
    a = left
    b = (a[0] + u[0], a[1] + u[1])
    c = (b[0] + v[0], b[1] + v[1])
    d = (a[0] + v[0], a[1] + v[1])
    down = lambda p: (p[0], p[1] + depth)
    return [poly([a, b, down(b), down(a)], lft), poly([b, c, down(c), down(b)], rgt), poly([a, b, c, d], top)]


def arrow(at, s0, s1, t, head=0.09):
    """A white arrow on a plane from (s0, t) to (s1, t)."""
    p0, p1 = at(s0, t), at(s1, t)
    sign = 1 if s1 > s0 else -1
    tip = at(s1 + sign * head, t)
    h1, h2 = at(s1, t - head * 0.9), at(s1, t + head * 0.9)
    return ('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="6" stroke-linecap="round"/>'
            % (p0[0], p0[1], p1[0], p1[1], EDGE)) + poly([h1, tip, h2], EDGE, EDGE, 1)


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n%s\n</svg>\n'
            % (SIZE, SIZE, SIZE, SIZE, "\n".join(body)))


def relay():
    """A switch: forwards what it gets, reads none of it."""
    left, u, v = (14, 92), (82, 32), (82, -32)
    body = slab(left, u, v, 34)
    at = iso(left, u, v)
    body.append(arrow(at, 0.22, 0.70, 0.34))
    body.append(arrow(at, 0.78, 0.30, 0.66))
    return svg(body)


def laptop():
    """A station: a laptop whose screen shows log lines."""
    base_left, u, v = (22, 128), (86, 34), (62, -25)
    body = slab(base_left, u, v, 9)
    d = (base_left[0] + v[0], base_left[1] + v[1])          # back-left of the deck
    c = (d[0] + u[0], d[1] + u[1])                          # back-right
    lift = (8, -86)
    d2, c2 = (d[0] + lift[0], d[1] + lift[1]), (c[0] + lift[0], c[1] + lift[1])
    body.append(poly([d, c, c2, d2], LEFT))
    scr = iso(d, (c[0] - d[0], c[1] - d[1]), lift)
    body.append(poly([scr(0.07, 0.10), scr(0.93, 0.10), scr(0.93, 0.90), scr(0.07, 0.90)], "#0B3E66", "#0B3E66", 1))
    for t, length in ((0.74, 0.62), (0.56, 0.78), (0.38, 0.50)):
        p0, p1 = scr(0.17, t), scr(0.17 + length * 0.7, t)
        body.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#CFE6F7" stroke-width="5" '
                    'stroke-linecap="round"/>' % (p0[0], p0[1], p1[0], p1[1]))
    return svg(body)


def convert(name, text):
    src = os.path.join(OUT, name + ".svg")
    with open(src, "w") as fh:
        fh.write(text)
    raw = subprocess.run(["magick", "-background", "none", src, "-resize", "%dx%d" % (SIZE, SIZE),
                          "-depth", "8", "rgba:-"], check=True, capture_output=True).stdout
    if len(raw) != SIZE * SIZE * 4:
        sys.exit("unexpected size for %s: %d bytes" % (name, len(raw)))
    with open(os.path.join(OUT, name + ".img"), "wb") as fh:
        fh.write(b"ARKIMG1\n" + struct.pack("<II", SIZE, SIZE) + raw)
    print("wrote assets/icons/%s.svg and .img" % name)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in (("relay", relay), ("laptop", laptop)):
        convert(name, make())


if __name__ == "__main__":
    main()
