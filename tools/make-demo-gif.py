#!/usr/bin/env python3
"""Builds docs/demo.gif from the screens tests/render_demo.HC writes.

    hcc tests/render_demo.HC -o build/render_demo
    SDL_VIDEODRIVER=offscreen ./build/render_demo
    python3 tools/make-demo-gif.py

Each frame: what the step is, both laptops' screens as the code drew them,
and the hardware underneath with the links that step uses lit up.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONT = os.path.join(ROOT, "assets", "fonts")
SEMI = os.path.join(FONT, "Inter-SemiBold.ttf")
REG = os.path.join(FONT, "Inter-Regular.ttf")
MONO = os.path.join(FONT, "JetBrainsMono-Regular.ttf")

W, H = 1600, 1010
BG, PANEL, LINE, TEXT, MUTED, FAINT = "#0B1020", "#0F1629", "#2A3758", "#E6EBF5", "#A3AEC6", "#8592AD"
CYAN, RED, GREEN, AMBER, PURPLE = "#22D3EE", "#EF4444", "#22C55E", "#F59E0B", "#A78BFA"

# Hardware boxes: name -> (x, y, w, h, title, sub)
BOXES = {
    "server": (40, 690, 240, 84, "FS-01, the watched server", "tools/ark-watch reads its journal"),
    "a": (400, 690, 240, 84, "Laptop A, manager", "station-a, Dana Kessler"),
    "q": (770, 690, 250, 84, "Arduino UNO Q, relay", "forwards sealed messages only"),
    "b": (1150, 690, 240, 84, "Laptop B, worker", "station-b, Marcus Hale"),
    "net": (40, 860, 240, 84, "Internet", "and the company network"),
    "panel": (400, 860, 240, 84, "Arduino UNO, panel", "red CUT, green RESTORE, buzzer"),
}
# Links: name -> (from, to, label)
LINKS = {
    "feed": ("server", "a", "event feed"),
    "usb": ("a", "q", "USB cable"),
    "wifi": ("q", "b", "separate Wi-Fi"),
    "net": ("net", "a", "network"),
    "serial": ("panel", "a", "USB serial"),
}

STEPS = [
    {
        "title": "1  The watcher sends every server command to station A",
        "sub": "Station A signs each one into the Server log and sends it, sealed, through the relay. Laptop B gets the same rows.",
        "hot": {"feed": CYAN, "usb": CYAN, "wifi": CYAN},
        "led": GREEN, "note": "",
    },
    {
        "title": "2  The worker checks a suspicious command",
        "sub": "Marcus filters to Suspicious and opens sudo cat /etc/shadow: who ran it, where, and why ARK flagged it.",
        "hot": {},
        "led": GREEN, "note": "",
    },
    {
        "title": "3  Report to manager",
        "sub": "The report is a signed alert naming that event. It reaches laptop A, the panel beeps three times, and B shows it as REPORTED.",
        "hot": {"wifi": CYAN, "usb": CYAN, "serial": AMBER},
        "led": GREEN, "note": "beep beep beep",
    },
    {
        "title": "4  The manager presses red: laptop A goes offline",
        "sub": "Any link an attacker had through laptop A is gone. The team keeps working: the relay link is USB, not the network.",
        "hot": {"serial": RED, "net": "cut", "usb": CYAN, "wifi": CYAN},
        "led": RED, "note": "red button pressed",
    },
    {
        "title": "5  Backups done, attacker out: the manager presses green",
        "sub": "Only the manager's station can restore. Both the cut and the restore are signed entries everyone can see.",
        "hot": {"serial": GREEN, "net": GREEN, "usb": CYAN, "wifi": CYAN},
        "led": GREEN, "note": "green button pressed",
    },
]


def esc(text):
    return text.replace("\\", "\\\\").replace("'", "\\'")


def text(mvg, font, size, color, x, y, s):
    mvg.append("stroke none font '%s' font-size %d fill '%s' text %d,%d '%s'" % (font, size, color, x, y, esc(s)))


def mid(box, side):
    x, y, w, h = box[:4]
    return {"r": (x + w, y + h // 2), "l": (x, y + h // 2), "t": (x + w // 2, y), "b": (x + w // 2, y + h)}[side]


def link_points(name):
    a, b, _ = LINKS[name]
    if name == "net":
        return mid(BOXES["net"], "r"), (BOXES["a"][0] + 40, BOXES["a"][1] + 84)
    if name == "serial":
        return mid(BOXES["panel"], "t"), mid(BOXES["a"], "b")
    return mid(BOXES[a], "r"), mid(BOXES[b], "l")


def frame(step, n, shots, out):
    mvg = ["viewbox 0 0 %d %d" % (W, H), "stroke-antialias 1", "text-antialias 1"]
    text(mvg, MONO, 15, FAINT, 40, 42, "ARK DEMO  %d / %d" % (n, len(STEPS)))
    text(mvg, SEMI, 26, TEXT, 40, 80, step["title"][3:])
    text(mvg, REG, 16, MUTED, 40, 108, step["sub"])

    for who, x in (("a", 40), ("b", 820)):
        label = "LAPTOP A   manager   Dana Kessler" if who == "a" else "LAPTOP B   worker   Marcus Hale"
        text(mvg, SEMI, 14, CYAN if who == "a" else PURPLE, x, 146, label)
        mvg.append("fill none stroke '%s' stroke-width 1 roundrectangle %d,%d %d,%d 6,6" % (LINE, x - 1, 155, x + 741, 155 + 491))
        mvg.append("image over %d,%d 740,490 '%s'" % (x, 156, shots[who]))

    text(mvg, SEMI, 13, FAINT, 40, 668, "HARDWARE")
    for name in LINKS:
        (x1, y1), (x2, y2) = link_points(name)
        state = step["hot"].get(name)
        color = state if state and state != "cut" else LINE
        if state == "cut":
            color = RED
            mvg.append("push graphic-context")
            mvg.append("stroke '%s' stroke-width 3 stroke-dasharray 8 6 line %d,%d %d,%d" % (color, x1, y1, x2, y2))
            mvg.append("pop graphic-context")
            cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
            mvg.append("fill '%s' stroke '%s' stroke-width 2 circle %d,%d %d,%d" % (BG, RED, cx, cy, cx + 15, cy))
            mvg.append("stroke '%s' stroke-width 3 line %d,%d %d,%d" % (RED, cx - 6, cy - 6, cx + 6, cy + 6))
            mvg.append("stroke '%s' stroke-width 3 line %d,%d %d,%d" % (RED, cx - 6, cy + 6, cx + 6, cy - 6))
        else:
            mvg.append("stroke '%s' stroke-width %d line %d,%d %d,%d" % (color, 3 if state else 2, x1, y1, x2, y2))
        mvg.append("stroke none")
        lx, ly = (x1 + x2) // 2, (y1 + y2) // 2
        label = LINKS[name][2] if state != "cut" else "network cut"
        tw = len(label) * 7
        if name == "serial":
            text(mvg, REG, 13, color if state else FAINT, lx + 14, ly + 4, label)
        elif name == "net":
            text(mvg, REG, 13, color if state else FAINT, lx - tw - 26, ly + 22, label)
        else:
            text(mvg, REG, 13, color if state else FAINT, lx - tw // 2, ly + 24, label)

    for name, (x, y, w, h, title, sub) in BOXES.items():
        border = LINE
        if name == "a":
            border = CYAN
        elif name == "b":
            border = PURPLE
        mvg.append("fill '%s' stroke '%s' stroke-width 1.5 roundrectangle %d,%d %d,%d 8,8" % (PANEL, border, x, y, x + w, y + h))
        mvg.append("stroke none")
        text(mvg, SEMI, 16, TEXT, x + 16, y + 34, title)
        text(mvg, REG, 13, MUTED, x + 16, y + 58, sub)

    # The panel's lights and buzzer.
    px, py = BOXES["panel"][0] + BOXES["panel"][2] + 24, BOXES["panel"][1]
    for i, (name, color) in enumerate((("green LED", GREEN), ("red LED", RED))):
        on = step["led"] == color
        fill = color if on else "#1A2440"
        mvg.append("fill '%s' stroke none circle %d,%d %d,%d" % (fill, px + 10, py + 22 + i * 30, px + 18, py + 22 + i * 30))
        text(mvg, REG, 13, TEXT if on else FAINT, px + 28, py + 27 + i * 30, name + (" on" if on else ""))
    if step["note"]:
        color = AMBER if "beep" in step["note"] else step["led"]
        text(mvg, SEMI, 15, color, px + 150, py + 42, step["note"])

    text(mvg, REG, 12, FAINT, 1060, 990, "Screens drawn by the ARK code (tests/render_demo.HC). Messages are handed")
    text(mvg, REG, 12, FAINT, 1060, 1005, "between stations directly in the render; in use they go through the relay.")

    mvg_path = out + ".mvg"
    with open(mvg_path, "w") as f:
        f.write("\n".join(mvg) + "\n")
    subprocess.run(["magick", "-size", "%dx%d" % (W, H), "xc:" + BG, "-draw", "@" + mvg_path, out], check=True)


def main():
    build = os.path.join(ROOT, "build")
    for n in range(1, len(STEPS) + 1):
        for who in "ab":
            if not os.path.exists(os.path.join(build, "demo-%d-%s.ppm" % (n, who))):
                sys.exit("missing build/demo-%d-%s.ppm: run build/render_demo first" % (n, who))
    tmp = tempfile.mkdtemp()
    frames = []
    for n, step in enumerate(STEPS, 1):
        shots = {}
        for who in "ab":
            png = os.path.join(tmp, "%d-%s.png" % (n, who))
            subprocess.run(["magick", os.path.join(build, "demo-%d-%s.ppm" % (n, who)),
                            "-filter", "Lanczos", "-resize", "740x490", png], check=True)
            shots[who] = png
        out = os.path.join(tmp, "frame-%d.png" % n)
        frame(step, n, shots, out)
        frames.append(out)
    gif = os.path.join(ROOT, "docs", "demo.gif")
    cmd = ["magick"]
    for i, f in enumerate(frames):
        cmd += ["-delay", "550" if i == len(frames) - 1 else "450", f]
    cmd += ["-loop", "0", "-dither", "None", "-colors", "128", "-layers", "Optimize", gif]
    subprocess.run(cmd, check=True)
    subprocess.run(["magick", frames[2], os.path.join(build, "demo-frame-3.png")], check=True)
    print("wrote", os.path.relpath(gif, ROOT), "%d KB" % (os.path.getsize(gif) // 1024))


if __name__ == "__main__":
    main()
