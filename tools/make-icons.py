#!/usr/bin/env python3
"""Draws the Network page icons and converts them for the station.

    python3 tools/make-icons.py

Writes assets/icons/NAME.svg (the source, open it in any browser) and
assets/icons/NAME.img (what the station loads: "ARKIMG1\\n", width and
height as little-endian 32-bit, then RGBA bytes). The station has no PNG
decoder, and this format needs none. Needs ImageMagick with librsvg.

The diagram icons follow network topology drawings: isometric blue boxes
with a white edge. The g-* glyphs are flat white shapes the station tints.
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


# Glyphs: solid white shapes on a 48-unit grid, with holes cut by a mask.
# The station uses only their alpha and tints them, so one file serves
# every colour. Each entry is (solid shapes, cut-outs).
W = 'fill="#fff"'
K = 'fill="#000"'
SW = 'fill="none" stroke="#fff" stroke-linecap="round" stroke-linejoin="round"'
SK = 'fill="none" stroke="#000" stroke-linecap="round" stroke-linejoin="round"'
LOCK_BODY = ('<path d="M15 22v-6a9 9 0 0 1 18 0v6" %s stroke-width="5"/><rect x="9" y="21" width="30" height="22" rx="4" %s/>'
             % (SW, W))
GLOBE_CUTS = ('<ellipse cx="24" cy="24" rx="8" ry="19" %s stroke-width="2.6"/><path d="M5 24h38M8 15h32M8 33h32" %s '
              'stroke-width="2.6"/>' % (SK, SK))
GLYPHS = {
    "overview": ('<rect x="6" y="6" width="16" height="20" rx="3" %s/><rect x="26" y="6" width="16" height="12" rx="3" %s/>'
                 '<rect x="26" y="22" width="16" height="20" rx="3" %s/><rect x="6" y="30" width="16" height="12" rx="3" %s/>'
                 % (W, W, W, W), ""),
    "server": ('<rect x="7" y="6" width="34" height="16" rx="3" %s/><rect x="7" y="26" width="34" height="16" rx="3" %s/>'
               % (W, W),
               '<circle cx="14" cy="14" r="2.6" %s/><circle cx="14" cy="34" r="2.6" %s/>'
               '<rect x="21" y="12.5" width="14" height="3" rx="1.5" %s/><rect x="21" y="32.5" width="14" height="3" rx="1.5" %s/>'
               % (K, K, K, K)),
    "chat": ('<rect x="5" y="7" width="38" height="26" rx="7" %s/><path d="M13 31v11l11-10z" %s/>' % (W, W),
             '<circle cx="15" cy="20" r="2.8" %s/><circle cx="24" cy="20" r="2.8" %s/><circle cx="33" cy="20" r="2.8" %s/>'
             % (K, K, K)),
    "scope": ('<ellipse cx="24" cy="11" rx="16" ry="6" %s/><rect x="8" y="11" width="32" height="26" %s/>'
              '<ellipse cx="24" cy="37" rx="16" ry="6" %s/>' % (W, W, W),
              '<path d="M8 11a16 6 0 0 0 32 0M8 20a16 6 0 0 0 32 0M8 29a16 6 0 0 0 32 0" %s stroke-width="2.8"/>' % SK),
    "clock": ('<circle cx="24" cy="24" r="19" %s/>' % W,
              '<path d="M24 12v12h9" %s stroke-width="3.6"/>' % SK),
    "team": ('<circle cx="16" cy="15" r="7" %s/><path d="M3 41a13 12 0 0 1 26 0z" %s/>'
             '<circle cx="35" cy="19" r="5.5" %s/><path d="M30 41a8 10 0 0 1 15 0z" %s/>' % (W, W, W, W), ""),
    "network": ('<path d="M24 10L10 36H38Z" %s stroke-width="4"/><circle cx="24" cy="10" r="6.5" %s/>'
                '<circle cx="10" cy="36" r="6.5" %s/><circle cx="38" cy="36" r="6.5" %s/>' % (SW, W, W, W), ""),
    "report": ('<path d="M11 4h19l10 10v30a2 2 0 0 1-2 2H11a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z" %s/>' % W,
               '<path d="M29.5 4v10.5H40" %s stroke-width="2.6"/><rect x="15" y="22" width="18" height="3" rx="1.5" %s/>'
               '<rect x="15" y="29" width="18" height="3" rx="1.5" %s/><rect x="15" y="36" width="11" height="3" rx="1.5" %s/>'
               % (SK, K, K, K)),
    "guide": ('<circle cx="24" cy="24" r="19" %s/>' % W,
              '<path d="M18 19a6 6 0 1 1 9 5.2c-2 1.2-3 2.4-3 4.8" %s stroke-width="4"/><circle cx="24" cy="35.5" r="2.6" %s/>'
              % (SK, K)),
    "globeoff": ('<circle cx="24" cy="24" r="19" %s/><path d="M7 43L43 7" %s stroke-width="3.4"/>' % (W, SW),
                 GLOBE_CUTS + '<path d="M7 43L43 7" %s stroke-width="9"/>' % SK),
    "bell": ('<path d="M24 5a3 3 0 0 1 3 3v1.4a12 12 0 0 1 9 11.6v8l4 5v2.5H8V34l4-5v-8a12 12 0 0 1 9-11.6V8a3 3 0 0 1 3-3z" %s/>'
             '<path d="M19 39.5a5 5 0 0 0 10 0z" %s/>' % (W, W), ""),
    "lock": (LOCK_BODY, '<circle cx="24" cy="30" r="3.4" %s/><rect x="22.4" y="30" width="3.2" height="7" rx="1.2" %s/>'
             % (K, K)),
    "lockx": (LOCK_BODY, '<path d="M19 27l10 10M29 27l-10 10" %s stroke-width="3.6"/>' % SK),
    "globe": ('<circle cx="24" cy="24" r="19" %s/>' % W, GLOBE_CUTS),
    "relay": ('<circle cx="24" cy="19" r="4.5" %s/><rect x="22" y="21" width="4" height="21" %s/>'
              '<rect x="15" y="40" width="18" height="4" rx="2" %s/>'
              '<path d="M16 11a12 12 0 0 0 0 16M32 11a12 12 0 0 1 0 16M10 5a20 20 0 0 0 0 28M38 5a20 20 0 0 1 0 28" %s '
              'stroke-width="3.4"/>' % (W, W, W, SW), ""),
    "chain": ('<g transform="rotate(-45 24 24)"><rect x="4" y="17" width="22" height="14" rx="7" %s stroke-width="5"/>'
              '<rect x="22" y="17" width="22" height="14" rx="7" %s stroke-width="5"/></g>' % (SW, SW), ""),
    "terminal": ('<rect x="4" y="8" width="40" height="32" rx="4" %s/>' % W,
                 '<path d="M12 18l7 6-7 6" %s stroke-width="3.8"/><rect x="23" y="28" width="12" height="3.6" rx="1.8" %s/>'
                 % (SK, K)),
    "shield": ('<path d="M24 4l16 6v12c0 11-7 19-16 22-9-3-16-11-16-22V10z" %s/>' % W,
               '<path d="M17 24l5 5 9-10" %s stroke-width="4"/>' % SK),
    "login": ('<rect x="27" y="6" width="15" height="36" rx="2" %s/><rect x="4" y="22" width="16" height="4" rx="2" %s/>'
              '<path d="M16 14l10 10-10 10z" %s/>' % (W, W, W), '<path d="M27 6v36" %s stroke-width="5"/>' % SK),
    "account": ('<circle cx="18" cy="15" r="8" %s/><path d="M4 42a14 12 0 0 1 28 0z" %s/>'
                '<rect x="33" y="20" width="12" height="4" rx="2" %s/><rect x="37" y="16" width="4" height="12" rx="2" %s/>'
                % (W, W, W, W), ""),
    "pii": ('<rect x="4" y="9" width="40" height="30" rx="4" %s/>' % W,
            '<circle cx="15" cy="21" r="4.5" %s/><path d="M8.5 33a6.5 5.5 0 0 1 13 0z" %s/>'
            '<rect x="25" y="17" width="13" height="3" rx="1.5" %s/><rect x="25" y="24" width="13" height="3" rx="1.5" %s/>'
            '<rect x="25" y="31" width="9" height="3" rx="1.5" %s/>' % (K, K, K, K, K)),
    "phi": ('<rect x="17" y="5" width="14" height="38" rx="3" %s/><rect x="5" y="17" width="38" height="14" rx="3" %s/>'
            % (W, W), ""),
    "pci": ('<rect x="4" y="10" width="40" height="28" rx="4" %s/>' % W,
            '<rect x="4" y="16" width="40" height="6" %s/><rect x="9" y="27" width="9" height="6" rx="1.2" %s/>' % (K, K)),
    "cred": ('<circle cx="15" cy="24" r="10" %s/><rect x="23" y="21.5" width="22" height="5" rx="1" %s/>'
             '<rect x="37" y="25" width="4" height="8" rx="1" %s/><rect x="30" y="25" width="4" height="5" rx="1" %s/>'
             % (W, W, W, W), '<circle cx="12.5" cy="24" r="3.6" %s/>' % K),
    "detect": ('<circle cx="20" cy="20" r="11.5" %s stroke-width="5.5"/><path d="M28.5 28.5L41 41" %s stroke-width="7"/>'
               % (SW, SW), ""),
    "contain": ('<rect x="4" y="7" width="19" height="10" rx="1.5" %s/><rect x="25" y="7" width="19" height="10" rx="1.5" %s/>'
                '<rect x="4" y="19" width="9" height="10" rx="1.5" %s/><rect x="15" y="19" width="18" height="10" rx="1.5" %s/>'
                '<rect x="35" y="19" width="9" height="10" rx="1.5" %s/><rect x="4" y="31" width="19" height="10" rx="1.5" %s/>'
                '<rect x="25" y="31" width="19" height="10" rx="1.5" %s/>' % (W, W, W, W, W, W, W), ""),
    "eradicate": ('<ellipse cx="24" cy="29" rx="10" ry="13" %s/><circle cx="24" cy="12.5" r="6" %s/>'
                  '<path d="M14 23H6M14 30H5M15 37l-7 5M34 23h8M34 30h9M33 37l7 5M20 8l-4-4M28 8l4-4" %s stroke-width="3.2"/>'
                  % (W, W, SW), '<path d="M24 19v22" %s stroke-width="2.6"/>' % SK),
    "recover": ('<path d="M38.5 26A14.5 14.5 0 1 1 33.5 13" %s stroke-width="5.5"/><path d="M27 6l12 3-3 12z" %s/>'
                % (SW, W), ""),
    "pencil": ('<g transform="rotate(45 24 24)"><rect x="18.5" y="1" width="11" height="35" rx="2" %s/>'
               '<path d="M18.5 37.5h11L24 47z" %s/></g>' % (W, W),
               '<g transform="rotate(45 24 24)"><rect x="17" y="8" width="14" height="2.8" %s/></g>' % K),
    "folder": ('<path d="M4 12a3 3 0 0 1 3-3h11l4 5h19a3 3 0 0 1 3 3v22a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z" %s/>' % W, ""),
}


def glyph(solid, cuts):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 48 48">\n'
            '<mask id="m"><rect width="48" height="48" fill="#fff"/>%s</mask>\n'
            '<g mask="url(#m)">%s</g>\n</svg>\n' % (cuts, solid))


def convert(name, text, size=SIZE):
    src = os.path.join(OUT, name + ".svg")
    with open(src, "w") as fh:
        fh.write(text)
    raw = subprocess.run(["magick", "-background", "none", src, "-resize", "%dx%d" % (size, size),
                          "-depth", "8", "rgba:-"], check=True, capture_output=True).stdout
    if len(raw) != size * size * 4:
        sys.exit("unexpected size for %s: %d bytes" % (name, len(raw)))
    with open(os.path.join(OUT, name + ".img"), "wb") as fh:
        fh.write(b"ARKIMG1\n" + struct.pack("<II", size, size) + raw)
    print("wrote assets/icons/%s.svg and .img" % name)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in (("relay", relay), ("laptop", laptop)):
        convert(name, make())
    for name, (solid, cuts) in GLYPHS.items():
        convert("g-" + name, glyph(solid, cuts), 96)


if __name__ == "__main__":
    main()
