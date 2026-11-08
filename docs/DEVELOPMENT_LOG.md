# Development log

## 2026-11-07, M0: toolchain spikes

Goal: prove the four risky pieces work from HolyC before building on them.

1. **libsodium from HolyC.** `tests/test_crypto.HC` passes all 13 checks. The first build failed because hcc's runtime has no `MemCmp`. Swapped in libsodium's constant-time `sodium_memcmp`, wrapped as `Same()`, which is what keys and hashes should be compared with anyway.
2. **Window and text.** `tests/spike_window.HC` opens an SDL2 window and draws DejaVu Sans Mono with SDL2_ttf. Passing `SDL_Color` by value as a `U32` works. Checked with a screenshot.
3. **Link layer over fake serial.** `src/link.HC` plus `tests/test_link.HC` over a socat pty pair: 1 to 1000 byte messages arrive intact both ways, including the 243/244 byte frame boundary.
4. **ESP32 relay.** `firmware/relay/relay.ino` compiles against esp32 core 3.3.12 (884 KB, 67% of flash). Raised the serial RX buffer to 2048 bytes, because the default 256 is smaller than one full hex line (503 bytes).

No hcc compiler bugs hit so far.

### Hardware change

Only one ESP32 is available, not two. A second ESP-NOW node isn't possible, so the relay now runs its own Wi-Fi access point instead. Station A talks to it over USB serial. Station B joins its Wi-Fi and uses UDP, through `socat` so that `link.HC` still sees a serial port. ESP-NOW is dropped because it can't be tested with one board. The new firmware compiles but hasn't been flashed: the ESP32 didn't enumerate over USB (no kernel event at all, so probably a charge-only cable). The CH340 on `/dev/ttyUSB0` turned out to be the UNO clone (avrdude reads ATmega328P signature 1E 95 0F).

## 2026-11-07, M2: the incident log

`src/log.HC` and `src/station.HC`, tested by `tests/test_log.HC` (23 checks).

Problems hit:
- **No octal in HolyC.** `mkdir(dir, 0700)` created a directory with mode `1274` (decimal 700), which the owner couldn't list. Modes are now hex constants.
- **A misleading error.** `U8 out[MSG_MAX]` with `MSG_MAX` undefined (its file wasn't included) was reported as "`out` has not been defined" at every use, not at the declaration.
- **Lost output on crash.** A segfault in the test swallowed all buffered `ok` lines, which made it look like the first check crashed. gdb's backtrace pointed at the real spot (reading a log file that didn't exist, because of the permission bug above).

## 2026-11-07, relay on the UNO Q

No data cable for the ESP32 turned up. The UNO Q showed up over adb (`2341:0078`, Debian 13, aarch64, Python 3, socat, NetworkManager), joined the phone hotspot with `nmcli`, and runs `relay/hub.py`.

`tests/test_link.HC` over the real path: station A through `adb forward` and USB, station B over Wi-Fi to the UNO Q. All six sizes arrived intact both ways. The hub log showed one client joining from 127.0.0.1 (the USB forward) and one from the laptop's Wi-Fi address.

Gotcha: `adb shell 'pkill -f ark/hub.py; ...'` killed its own shell (exit 143), because the pattern matched the shell's command line.

## 2026-11-07, M3 started: the station screen

`src/main.HC`, `src/screen.HC`, `src/team.HC`, `src/font.HC`, `station.sh`. The look is TempleOS: white background, the 16 VGA colors, Terry's 8x8 system font on an 80x50 grid, scaled to the window.

Three hcc problems, all found by running the program and looking at it:
- **`StrPrint(buf, ...)` reallocates `buf`.** Passing a stack array aborted with `free(): invalid size`. All formatting into fixed buffers now uses libc `snprintf` with an explicit size.
- **64-bit hex literals are cut to 32 bits.** `U64 x = 0x00180018183C3C18;` stores `0x183C3C18`, in a table, a global or a local. Every glyph came out with its bottom four rows missing. The font is now a `U8` array, 8 bytes per glyph.
- **No `StrFind` or `StrICmp`** in the runtime. libc `strchr` and `strcasecmp` are declared in `tos.HH` and work.

### First two-station run

Bug: creating a station from the screen failed with "Could not write the station directory". `StationCreate(s, s->dir, ...)` hands `StationInit` a pointer into the struct it then zeroes, so the directory name was gone before it got copied. `StationInit` now copies the name out first, and `test_log` has a check for this exact call.

After the fix, tested by hand: station A over USB through the UNO Q, station B over Wi-Fi. Created both stations, opened an incident on A, joined from B with the six-digit code, admitted with F9, and posted entries both ways. All worked.

## 2026-11-07, making the screen explain itself

Feedback from the first hands-on run: the look works, but a new user can't tell what to type. Nothing said what PII means, what number goes in Records, or what a phase is. Changes, keeping the dense TempleOS style:
- **F1 opens a help page** covering the screen, the phases (NIST-style detect, contain, eradicate, recover), every status badge, joining and panic. Note, Chat, Scope and Phase moved to F2 to F5, so F1 means help as it does everywhere else.
- **Adding scope is now a form.** All five fields are visible, each with a one-line explanation. Data type and status show numbered choices with what each one means.
- **The mouse works** on the key bar and on numbered choices. Clicks are mapped through the letterboxed, scaled frame back to cells.
- Scope entries in the log read as a sentence: "HR-DB, 4120 PII records of TX residents, EXFILTRATED".
- The phase line under the note prompt shows all four phases with the current one highlighted.
- Fixed deadline citations being cut off at the right edge.

## 2026-11-07 evening, the manager dashboard

A Figma design for ARK (navy, sidebar, control panel) replaced the TempleOS screen. Decision 13 explains why. Built as `src/canvas.HC` (drawing) and `src/app.HC` (pages and input). `src/screen.HC` and `src/font.HC` are gone.

Checked without clicking through a window: `tests/render_views.HC` draws every page from a sample incident to `build/ui-*.ppm` under `SDL_VIDEODRIVER=offscreen`, and the images were read one by one. That caught phase labels overflowing their buttons, the scope form's footer overlapping its border, short search results stuck to the bottom of the list, and badges running past the card edge.

`tests/test_ui.HC` then drives the window like a user. It found two real bugs on its first run:
- After the incident opened, keyboard focus stayed on the setup field, so the first note typed on the Overview went nowhere.
- Clicking a data-type tile dropped focus, after which Enter no longer saved the scope form.

Two more hcc problems:
- **A pointer argument read from a register a call already reused.** In `Clip(c, ...)`, the first `c->clip_x0 = MaxI64(x, 0)` was stored through `%rdi`, which by then held `x`. It crashed. The fix is to compute into locals first. A scan of the disassembly (a store through an argument register after a call, with no reload) found no other case in ARK.
- **`F64` through `extern "c"` doesn't work.** `sqrt` from libm returned 0, so every rounded corner came out square. Corner coverage is now sampled with integers.

## 2026-11-07 night, alerts and the internet kill switch

The panel's buttons changed meaning (decision 14): red cuts the internet, green restores it, the buzzer sounds for alerts. New entry kinds ALERT and NETWORK, an Alert option in the composer (F5), and a control panel rebuilt around the alert, CUT and RESTORE.

`test_ui` covers it with stand-in commands (`touch` and `rm` on a marker file), because running the real `nmcli networking off` on the dev laptop would also cut off the session doing the work. 47 checks pass, including: one on-screen press only arms CUT, the panel's CUT is one press, a failed command doesn't show as cut, only the manager can restore, alerts from members wait until acknowledged, the manager's own alerts don't alert them.

Writing the test showed that an alert from someone who was never admitted gets NOT A MEMBER and is ignored, which is the behaviour we want.

Not yet checked: the real `nmcli` cut with station A on USB, and the new firmware on the UNO.

## 2026-11-07, the relay's LED matrix

The UNO Q's matrix showed Arduino's factory animation. It now plays an ARK animation, installed as a UNO Q App set as the boot default (`firmware/relay-matrix`). Frames are drawn by a Python script and checked as a GIF before flashing. The first preview had the cabin two columns off-center under the mast.

`arduino-app-cli` failed under `adb shell` with `Stat /Data/Local/Tmp`: adb exports Android's `TMPDIR`. Setting `TMPDIR=/tmp` fixed it. The relay hub had stopped after a reboot of the board and was started again by hand; it doesn't start at boot yet.

## 2026-11-07 late, server log and a sharp window

The incident log was a group chat. It is now two pages: Server log (commands, sudo, logins, failed logins, web requests, from `tools/ark-watch`) and Chat log. A worker picks a flagged event and presses Report to manager, which sends an alert naming it (decision 15).

The window used to be a fixed 1440x900 buffer stretched to fit, which blurred text and couldn't resize. Drawing now happens at the window's real pixel size: layout stays in units, every primitive scales them, and glyphs are re-rendered at the new size.

Two more hcc 0.0.15 crashes (segfault in the compiler, no message):
- `I64 a = 1, b = 2;` at file scope.
- A `#define` whose body names a variable or function, e.g. `#define CW g_cw`. Macros may only expand to literals and other macros.

Both were found by bisecting the include list with a stub `Main`. A build that pipes hcc through `head` hides the crash, because the pipe's exit code is head's.

## 2026-11-07 night, demo runbook and GIF

`docs/DEMO.md` holds every command: setup, clean slate, relay, one or two laptops, feeding the server log, the five-step story, rehearsing with stand-in cut commands. `docs/demo.gif` is drawn from the code: `tests/render_demo.HC` runs a manager and a worker station through that story in one process and dumps each screen, and `tools/make-demo-gif.py` adds the hardware and which links each step uses. Rendering it showed the chat log printing an alert's internal `[ref]`; it's hidden now.
