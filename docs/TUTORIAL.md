# Building ARK, step by step

Each part matches a commit range in the git history. Everything here has been run unless it's marked otherwise.

## Part 1: calling libsodium from HolyC

hcc calls any C function you declare with `extern "c"`, and `#link <sodium>` adds `-lsodium` at link time. libsodium's API is all byte buffers and lengths, so a binding is one line:

```holyc
#link <sodium>
extern "c" I32 crypto_sign_detached(U8 *sig, U64 *siglen, U8 *m, U64 mlen, U8 *sk);
```

C `unsigned long long` maps to `U64`, `size_t` to `I64`, `int` to `I32`. See `src/crypto.HC` for the whole set and the small wrappers around it.

Run the test:

```sh
hcc tests/test_crypto.HC -o build/test_crypto && ./build/test_crypto
```

Expected: 13 `ok` lines and `all passed`.

## Part 2: a window with real text

`src/canvas.HC` declares the SDL2_ttf functions ARK uses. The only trick is `TTF_RenderGlyph32_Blended`, which takes an `SDL_Color` struct by value. On x86_64 a 4-byte struct is passed in one integer register, so it's declared as `U32` and packed with red in the low byte:

```holyc
U32 Color(I64 r, I64 g, I64 b) { return r | (g << 8) | (b << 16) | (0xFF << 24); }
```

ARK renders each printable character once at startup and keeps only its alpha values. Drawing text after that is a loop that blends those values into the pixel buffer, so no FreeType call happens per frame.

```sh
hcc tests/render_views.HC -o build/render_views
SDL_VIDEODRIVER=offscreen ./build/render_views
magick build/ui-overview.ppm overview.png
```

Expected: `rendered`, and an image of the Overview page with a sample incident.

## Part 3: talking over a serial port

`src/link.HC` opens the port with plain `open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)`. The baud rate is set outside the program with `stty`, so no termios structs have to be mirrored in HolyC. Messages are cut into frames of 250 bytes or less and sent as hex lines.

You don't need hardware to test this. socat can make two linked fake serial ports:

```sh
socat pty,raw,echo=0,link=/tmp/pa pty,raw,echo=0,link=/tmp/pb &
hcc tests/test_link.HC -o build/test_link && ./build/test_link /tmp/pa /tmp/pb
```

Expected: six `ok` lines.
