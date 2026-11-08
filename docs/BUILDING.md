# Building

Tested on Arch Linux (kernel 7.2, KDE Wayland), November 2026.

## Dependencies

| Need | Arch package | Checked version |
|---|---|---|
| hcc (HolyC compiler) | build from source, see below | 0.0.15-beta |
| SDL2 | `sdl2-compat` | 2.32.74 |
| SDL2_ttf | `sdl2_ttf` | 2.24.0 |
| libsodium | `libsodium` | 1.0.22 |
| socat (tests only) | `socat` | |
| arduino-cli (firmware) | `arduino-cli` | 1.5.1 |
| reportlab (report PDF) | `python-reportlab` | 5.1.0 |
| Ollama (report summary, optional) | [ollama.com/download](https://ollama.com/download) | 0.40.10 |
| gemma3:4b model (3.4 GB) | `ollama pull gemma3:4b` | |

```sh
sudo pacman -S sdl2-compat sdl2_ttf libsodium socat arduino-cli
```

hcc: follow the [holyc-lang install guide](https://holyc-lang.com/docs/intro), or `scripts/build-linux.sh --install-hcc` from [holyc-graphics-guide](https://github.com/YatoVoid/holyc-graphics-guide). It installs to `~/.local`, so `~/.local/bin` has to be on your `PATH`.

## Tests

```sh
./tests/run.sh
```

`test_ui` needs no display: run.sh sets `SDL_VIDEODRIVER=offscreen`. To look at every page without clicking:

```sh
hcc tests/render_views.HC -o build/render_views
SDL_VIDEODRIVER=offscreen ./build/render_views     # writes build/ui-*.ppm
```

## Report model

The Report page works without a model; it then writes the figures and timeline only. Without reportlab it writes report.md but no PDF. For the summary and next steps:

```sh
ollama pull gemma3:4b        # once, needs the internet
ollama serve                 # if the ollama service isn't running
tools/ark-report --warm      # optional: load it before the demo
```

Tested on an RTX 3050 Laptop GPU with 6 GB: about 7 s per report once loaded. Another model: `ARK_REPORT_MODEL=qwen2.5:3b`. `OLLAMA_HOST` must point at this machine; the tool refuses anything else.

## Serial port access

The UNO panel shows up as `/dev/ttyUSB*` or `/dev/ttyACM*`. Your user needs to be in the group that owns them (`uucp` on Arch, `dialout` on Debian/Ubuntu):

```sh
ls -l /dev/ttyUSB0
sudo usermod -aG uucp "$USER"   # then log out and back in
```

## Relay

See [relay/README.md](../relay/README.md). It needs `adb` (`android-tools` on Arch) on the laptop.

## Common failures

- `error: Variable or function 'MemCmp' has not been defined`: hcc's runtime has no `MemCmp`. Use libc `memcmp`, or `Same()` from `src/crypto.HC` for keys and hashes.
- Files or directories created with odd permissions (`d-w-rwxr-T`): HolyC has no octal literals, so `0700` means decimal 700. Write modes in hex (`0x1C0` for 0700).
- `Variable or function 'out' has not been defined` for a variable that is plainly declared: look for an undefined macro in its declaration (`U8 out[MSG_MAX]` with `MSG_MAX` missing). hcc reports the uses, not the declaration.
- `free(): invalid size` from `StrPrint`: hcc's `StrPrint(dst, ...)` reallocates `dst`. Only pass it heap memory, or use `snprintf(buf, size, ...)`.
- Glyphs or constants missing their top 32 bits: hcc 0.0.15 truncates 64-bit hex literals. Split the value into bytes or 32-bit halves.
- A segfault on a line like `c->field = Call(...)` near the top of a function whose first argument is `c`: hcc 0.0.15 can store through the register `c` arrived in after the call has reused it. Compute into a local, then assign.
- C functions that take or return `F64` (libm `sqrt` and the like) give 0 or garbage through `extern "c"`. Use integer math.
- hcc exits with code 139 and prints nothing: the compiler itself crashed. Two known causes in 0.0.15: several globals in one declaration (`I64 a = 1, b = 2;`), and a `#define` whose body names a variable or function. Bisect by compiling the includes one at a time with an empty `Main`.
- `could not open the window or fonts in ...`: run from the repo root or from `build/`, so `assets/fonts` is found.
