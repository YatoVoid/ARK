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

```sh
sudo pacman -S sdl2-compat sdl2_ttf libsodium socat arduino-cli
```

hcc: follow the [holyc-lang install guide](https://holyc-lang.com/docs/intro), or `scripts/build-linux.sh --install-hcc` from [holyc-graphics-guide](https://github.com/YatoVoid/holyc-graphics-guide). It installs to `~/.local`, so `~/.local/bin` has to be on your `PATH`.

## Tests

```sh
./tests/run.sh
```

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
