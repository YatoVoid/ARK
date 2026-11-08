// Drawing for the station window: filled rectangles with anti-aliased round
// corners, and text from glyphs that SDL2_ttf renders once per window size.
//
// Layout code works in design units, where the window is at least 1180x900.
// The pixel buffer is the window's real size in physical pixels, and every
// primitive converts units to pixels by the scale g_s (thousandths). So text
// is rendered at the size it is shown, never stretched, and a wider window
// gives the layout more width instead of black bars. The frame is redrawn
// from scratch when something changes, then copied to the window 1:1.
//
// Fonts are Inter and JetBrains Mono, both SIL Open Font License, bundled in
// assets/fonts with their licenses.

#link <SDL2_ttf>

// Window size in design units, and the scale from units to pixels.
// One global per line, and no #define that names them: hcc 0.0.15
// crashes on "I64 a = 1, b = 2;" at file scope and on macros whose body
// holds an identifier that isn't itself a macro.
I64 g_cw = 1440;
I64 g_ch = 900;
I64 g_s = 1000;
I64 g_pw = 1440;   // physical pixels
I64 g_ph = 900;
#define MIN_W 1360
#define MIN_H 900

#define SDL_PIXELFORMAT_ARGB8888    0x16362004
#define SDL_TEXTUREACCESS_STREAMING 1
#define SDL_WINDOW_ALLOW_HIGHDPI    0x00002000
extern "c" U0 *SDL_CreateTexture(U0 *renderer, U32 format, I32 access, I32 w, I32 h);
extern "c" I32 SDL_UpdateTexture(U0 *texture, SdlRect *rect, U0 *pixels, I32 pitch);
extern "c" I32 SDL_GetRendererOutputSize(U0 *renderer, I32 *w, I32 *h);
extern "c" U0 SDL_SetWindowMinimumSize(U0 *window, I32 w, I32 h);

extern "c" I32 TTF_Init();
extern "c" U0 TTF_Quit();
extern "c" U0 *TTF_OpenFont(U8 *file, I32 ptsize);
extern "c" U0 TTF_CloseFont(U0 *font);
extern "c" I32 TTF_FontHeight(U0 *font);
extern "c" I32 TTF_FontAscent(U0 *font);
extern "c" I32 TTF_GlyphMetrics32(U0 *font, U32 ch, I32 *minx, I32 *maxx, I32 *miny, I32 *maxy, I32 *advance);
// SDL_Color is a 4-byte struct passed by value, which x86_64 passes in one
// integer register, so it is declared as a U32 with red in the low byte.
extern "c" U0 *TTF_RenderGlyph32_Blended(U0 *font, U32 ch, U32 color);

// SDL_Surface field offsets on x86_64.
#define SURF_W       16
#define SURF_H       20
#define SURF_PITCH   24
#define SURF_PIXELS  32

#define GLYPHS 96   // printable ASCII, 32 to 127

class Glyph
{
  I64 w, h, adv;          // pixels
  U8 *alpha;
};

class Font
{
  Glyph g[GLYPHS];
  I64 height;             // pixels
  I64 ascent;
};

#define F_SMALL  0   // Inter 12
#define F_BODY   1   // Inter 13
#define F_MED    2   // Inter Medium 14
#define F_LABEL  3   // Inter SemiBold 11, for caps labels
#define F_H2     4   // Inter SemiBold 15
#define F_H1     5   // Fira Sans Condensed SemiBold 27
#define F_BIG    6   // Fira Sans Condensed Bold 50
#define F_MONO   7   // JetBrains Mono 12
#define F_BTN    8   // Inter Bold 14
#define F_SEMI   9   // Inter SemiBold 13
#define FONTS    10

U8 *g_font_file[FONTS] = {
  "Inter-Regular.ttf", "Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf",
  "Inter-SemiBold.ttf", "FiraSansCondensed-SemiBold.ttf", "FiraSansCondensed-Bold.ttf", "JetBrainsMono-Regular.ttf",
  "Inter-Bold.ttf", "Inter-SemiBold.ttf"
};
I64 g_font_size[FONTS] = {12, 13, 14, 11, 15, 27, 50, 12, 14, 13};

class Canvas
{
  U0 *window;
  U0 *renderer;
  U0 *texture;
  U8 font_dir[512];
  Font font[FONTS];
  I64 clip_x0, clip_y0, clip_x1, clip_y1;   // pixels
  U32 *pixels;
};

// ---- colors ---------------------------------------------------------------

#define C_BG        0xFF0B1020
#define C_PANEL     0xFF0F1629
#define C_SURFACE   0xFF121A2F
#define C_RAISED    0xFF1A2440
#define C_LINE      0xFF1F2A44
#define C_LINE2     0xFF2A3758
#define C_ROWLINE   0xFF1A2340
#define C_TEXT      0xFFE6EBF5
#define C_MUTED     0xFFA3AEC6
#define C_FAINT     0xFF8592AD
#define C_CYAN      0xFFE8E1CC
#define C_CYAN_FG   0xFFF2ECDC
#define C_GREEN     0xFF4DAF7C
#define C_GREEN_FG  0xFF9CD5B3
#define C_GREEN_BTN 0xFF2E7D55
#define C_GREEN_DK  0xFF1D4F37
#define C_AMBER     0xFFE3B341
#define C_AMBER_FG  0xFFF0D07F
#define C_RED       0xFFE0483B
#define C_RED_FG    0xFFF2A79E
#define C_RED_BTN   0xFFB7281D
#define C_RED_DK    0xFF6E1A14
#define C_PURPLE    0xFF8FA7D6
#define C_PURPLE_FG 0xFFBACBEA
// Phases have their own hues, kept apart from the severity colors above.
#define C_DETECT    0xFF6FA0E8
#define C_CONTAIN   0xFFEE8A3C
#define C_ERADICATE 0xFFB18AE6
#define C_RECOVER   0xFF45B9AE

// a out of 255 of color c over color under, as one opaque color.
U32 Mix(U32 c, U32 under, I64 a)
{
  I64 r = ((c >> 16) & 0xFF) * a + ((under >> 16) & 0xFF) * (255 - a);
  I64 g = ((c >> 8) & 0xFF) * a + ((under >> 8) & 0xFF) * (255 - a);
  I64 b = (c & 0xFF) * a + (under & 0xFF) * (255 - a);
  return 0xFF000000 | ((r / 255) << 16) | ((g / 255) << 8) | (b / 255);
}

// Units to pixels and back.
I64 Px(I64 v)
{
  return v * g_s / 1000;
}

I64 Un(I64 px)
{
  return px * 1000 / g_s;
}

// ---- fonts ----------------------------------------------------------------

U0 FreeFonts(Canvas *c)
{
  for (I64 f = 0; f < FONTS; f++)
    for (I64 i = 0; i < GLYPHS; i++) {
      if (c->font[f].g[i].alpha != NULL)
        Free(c->font[f].g[i].alpha);
      c->font[f].g[i].alpha = NULL;
    }
}

Bool LoadFont(Canvas *c, I64 slot)
{
  U8 path[600];
  snprintf(path, 600, "%s/%s", c->font_dir, g_font_file[slot]);
  U0 *f = TTF_OpenFont(path, MaxI64(6, Px(g_font_size[slot])));
  if (f == NULL)
    return FALSE;
  Font *font = &c->font[slot];
  I64 height = TTF_FontHeight(f), ascent = TTF_FontAscent(f);
  font->height = height;
  font->ascent = ascent;
  for (I64 i = 0; i < GLYPHS; i++) {
    Glyph *g = &font->g[i];
    I32 minx, maxx, miny, maxy, adv;
    TTF_GlyphMetrics32(f, 32 + i, &minx, &maxx, &miny, &maxy, &adv);
    g->adv = adv;
    U0 *surf = TTF_RenderGlyph32_Blended(f, 32 + i, 0xFFFFFFFF);
    if (surf == NULL)
      continue;
    g->w = *((surf + SURF_W)(I32 *));
    g->h = *((surf + SURF_H)(I32 *));
    I64 pitch = *((surf + SURF_PITCH)(I32 *));
    U8 *px = *((surf + SURF_PIXELS)(U8 **));
    U8 *alpha = MAlloc(MaxI64(1, g->w * g->h));
    for (I64 y = 0; y < g->h; y++) {
      U32 *row = (px + y * pitch)(U32 *);
      for (I64 x = 0; x < g->w; x++)
        alpha[y * g->w + x] = row[x] >> 24;
    }
    g->alpha = alpha;
    SDL_FreeSurface(surf);
  }
  TTF_CloseFont(f);
  return TRUE;
}

Bool LoadFonts(Canvas *c)
{
  FreeFonts(c);
  for (I64 f = 0; f < FONTS; f++)
    if (!LoadFont(c, f))
      return FALSE;
  return TRUE;
}

// ---- size -----------------------------------------------------------------

U0 ClipAll(Canvas *c)
{
  c->clip_x0 = 0;
  c->clip_y0 = 0;
  c->clip_x1 = g_pw;
  c->clip_y1 = g_ph;
}

// Clip to a box given in units.
U0 Clip(Canvas *c, I64 x, I64 y, I64 w, I64 h)
{
  // Computed into locals first: hcc 0.0.15 stores the first
  // "c->field = Call()" through the register c arrived in, which the call
  // has already reused. See docs/BUILDING.md.
  I64 x0 = MaxI64(Px(x), 0), y0 = MaxI64(Px(y), 0);
  I64 x1 = MinI64(Px(x + w), g_pw), y1 = MinI64(Px(y + h), g_ph);
  c->clip_x0 = x0;
  c->clip_y0 = y0;
  c->clip_x1 = x1;
  c->clip_y1 = y1;
}

// Matches the buffer, scale and fonts to the window's current pixel size.
// The scale keeps at least MIN_W x MIN_H units on screen.
Bool CanvasResize(Canvas *c)
{
  I32 w, h;
  SDL_GetRendererOutputSize(c->renderer, &w, &h);
  if (w <= 0 || h <= 0)
    return FALSE;
  if (w == g_pw && h == g_ph && c->pixels != NULL)
    return TRUE;
  I64 s = MinI64(h * 1000 / MIN_H, w * 1000 / MIN_W);
  s = MaxI64(s, 500);
  g_s = s;
  g_pw = w;
  g_ph = h;
  g_cw = Un(w);
  g_ch = Un(h);
  if (c->pixels != NULL)
    Free(c->pixels);
  c->pixels = CAlloc(g_pw * g_ph * 4);
  if (c->texture != NULL)
    SDL_DestroyTexture(c->texture);
  c->texture = SDL_CreateTexture(c->renderer, SDL_PIXELFORMAT_ARGB8888,
                                 SDL_TEXTUREACCESS_STREAMING, g_pw, g_ph);
  ClipAll(c);
  return c->texture != NULL && LoadFonts(c);
}

Bool CanvasOpen(Canvas *c, U8 *title, U8 *font_dir)
{
  if (SDL_Init(SDL_INIT_VIDEO) != 0 || TTF_Init() != 0)
    return FALSE;
  CopyText(c->font_dir, font_dir, 512);
  c->window = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 1440, 900,
                               SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
  if (c->window == NULL)
    return FALSE;
  SDL_SetWindowMinimumSize(c->window, 900, 600);
  c->renderer = SDL_CreateRenderer(c->window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
  if (c->renderer == NULL)
    return FALSE;
  if (!CanvasResize(c))
    return FALSE;
  SDL_StartTextInput();
  return TRUE;
}

U0 CanvasClose(Canvas *c)
{
  SDL_DestroyTexture(c->texture);
  SDL_DestroyRenderer(c->renderer);
  SDL_DestroyWindow(c->window);
  TTF_Quit();
  SDL_Quit();
}

// ---- shapes ---------------------------------------------------------------

// Pixel rectangle, clipped.
U0 FillPx(Canvas *c, I64 x0, I64 y0, I64 x1, I64 y1, U32 color)
{
  x0 = MaxI64(x0, c->clip_x0);
  y0 = MaxI64(y0, c->clip_y0);
  x1 = MinI64(x1, c->clip_x1);
  y1 = MinI64(y1, c->clip_y1);
  for (I64 py = y0; py < y1; py++) {
    U32 *row = &c->pixels[py * g_pw];
    for (I64 px = x0; px < x1; px++)
      row[px] = color;
  }
}

U0 Fill(Canvas *c, I64 x, I64 y, I64 w, I64 h, U32 color)
{
  FillPx(c, Px(x), Px(y), Px(x + w), Px(y + h), color);
}

U0 Blend(Canvas *c, I64 x, I64 y, U32 color, I64 a)
{
  if (a <= 0 || x < c->clip_x0 || y < c->clip_y0 || x >= c->clip_x1 || y >= c->clip_y1)
    return;
  U32 *p = &c->pixels[y * g_pw + x];
  if (a >= 255)
    *p = color;
  else
    *p = Mix(color, *p, a);
}

// Rounded rectangle in pixels. Corner pixels get partial coverage so edges
// stay smooth: 16 samples per pixel in eighths, all integer, because F64
// arguments to C functions don't survive hcc's calling convention.
U0 RoundPx(Canvas *c, I64 x, I64 y, I64 w, I64 h, I64 r, U32 color)
{
  r = MinI64(r, MinI64(w, h) / 2);
  if (r <= 0) {
    FillPx(c, x, y, x + w, y + h, color);
    return;
  }
  FillPx(c, x + r, y, x + w - r, y + h, color);
  FillPx(c, x, y + r, x + r, y + h - r, color);
  FillPx(c, x + w - r, y + r, x + w, y + h - r, color);
  I64 rr = r * 8 * r * 8;
  for (I64 dy = 0; dy < r; dy++) {
    for (I64 dx = 0; dx < r; dx++) {
      I64 inside = 0;
      for (I64 i = 0; i < 4; i++) {
        I64 ux = r * 8 - (dx * 8 + 2 * i + 1);
        for (I64 j = 0; j < 4; j++) {
          I64 uy = r * 8 - (dy * 8 + 2 * j + 1);
          if (ux * ux + uy * uy <= rr)
            inside++;
        }
      }
      if (inside == 0)
        continue;
      I64 a = inside * 255 / 16;
      Blend(c, x + dx, y + dy, color, a);
      Blend(c, x + w - 1 - dx, y + dy, color, a);
      Blend(c, x + dx, y + h - 1 - dy, color, a);
      Blend(c, x + w - 1 - dx, y + h - 1 - dy, color, a);
    }
  }
}

U0 Round(Canvas *c, I64 x, I64 y, I64 w, I64 h, I64 r, U32 color)
{
  I64 x0 = Px(x), y0 = Px(y);
  RoundPx(c, x0, y0, Px(x + w) - x0, Px(y + h) - y0, Px(r), color);
}

// Border width in pixels: one unit, at least one pixel.
I64 Hair()
{
  return MaxI64(1, Px(1));
}

// A rounded box with a one-unit border.
U0 Box(Canvas *c, I64 x, I64 y, I64 w, I64 h, I64 r, U32 fill, U32 border)
{
  I64 x0 = Px(x), y0 = Px(y), pw = Px(x + w) - x0, ph = Px(y + h) - y0, pr = Px(r), b = Hair();
  RoundPx(c, x0, y0, pw, ph, pr, border);
  RoundPx(c, x0 + b, y0 + b, pw - 2 * b, ph - 2 * b, MaxI64(0, pr - b), fill);
}

U0 HLine(Canvas *c, I64 x, I64 y, I64 w, U32 color)
{
  I64 y0 = Px(y);
  FillPx(c, Px(x), y0, Px(x + w), y0 + Hair(), color);
}

U0 VLine(Canvas *c, I64 x, I64 y, I64 h, U32 color)
{
  I64 x0 = Px(x);
  FillPx(c, x0, Px(y), x0 + Hair(), Px(y + h), color);
}

U0 Dot(Canvas *c, I64 cx, I64 cy, I64 d, U32 color)
{
  Round(c, cx - d / 2, cy - d / 2, d, d, d / 2, color);
}

// ---- images ---------------------------------------------------------------

// Icons drawn by tools/make-icons.py: "ARKIMG1\n", width and height as
// little-endian U32, then RGBA bytes. Kept this simple so nothing needs a
// PNG decoder.
class Image
{
  I64 w, h;
  U8 *rgba;               // NULL if the file was missing or bad
};

Bool LoadImage(Canvas *c, U8 *name, Image *img)
{
  img->w = 0;
  img->h = 0;
  img->rgba = NULL;
  U8 path[640];
  snprintf(path, 640, "%s/../icons/%s.img", c->font_dir, name);
  I32 fd = open(path, O_RDONLY);
  if (fd < 0)
    return FALSE;
  U8 head[16];
  I64 got = read(fd, head, 16);
  I64 w = head[8] | head[9] << 8 | head[10] << 16 | head[11] << 24;
  I64 h = head[12] | head[13] << 8 | head[14] << 16 | head[15] << 24;
  if (got != 16 || StrNCmp(head, "ARKIMG1\n", 8) != 0 || w <= 0 || h <= 0 || w > 1024 || h > 1024) {
    close(fd);
    return FALSE;
  }
  I64 size = w * h * 4, n = 0;
  U8 *buf = MAlloc(size);
  while (n < size) {
    got = read(fd, buf + n, size - n);
    if (got <= 0)
      break;
    n += got;
  }
  close(fd);
  if (n != size) {
    Free(buf);
    return FALSE;
  }
  img->w = w;
  img->h = h;
  img->rgba = buf;
  return TRUE;
}

// Draws the image into a size x size unit square, box-filtered so it stays
// smooth at any window scale. Missing images draw nothing.
U0 DrawImage(Canvas *c, Image *img, I64 x, I64 y, I64 size)
{
  if (img->rgba == NULL)
    return;
  I64 x0 = Px(x), y0 = Px(y), d = Px(x + size) - x0;
  if (d <= 0)
    return;
  for (I64 dy = 0; dy < d; dy++) {
    I64 sy0 = dy * img->h / d, sy1 = MaxI64((dy + 1) * img->h / d, sy0 + 1);
    for (I64 dx = 0; dx < d; dx++) {
      I64 sx0 = dx * img->w / d, sx1 = MaxI64((dx + 1) * img->w / d, sx0 + 1);
      I64 r = 0, g = 0, b = 0, al = 0, cnt = 0;
      for (I64 sy = sy0; sy < sy1; sy++)
        for (I64 sx = sx0; sx < sx1; sx++) {
          U8 *q = img->rgba + (sy * img->w + sx) * 4;
          r += q[0] * q[3];
          g += q[1] * q[3];
          b += q[2] * q[3];
          al += q[3];
          cnt++;
        }
      if (al == 0)
        continue;
      U32 col = 0xFF000000 | ((r / al) << 16) | ((g / al) << 8) | (b / al);
      Blend(c, x0 + dx, y0 + dy, col, al / cnt);
    }
  }
}

// ---- text -----------------------------------------------------------------

I64 AdvPx(Font *font, I64 ch)
{
  if (ch >= 32 && ch < 128)
    return font->g[ch - 32].adv;
  return 0;
}

I64 TextWidthPx(Canvas *c, I64 f, U8 *text, I64 n = -1)
{
  Font *font = &c->font[f];
  I64 w = 0;
  for (I64 i = 0; text[i] && (n < 0 || i < n); i++)
    w += AdvPx(font, text[i]);
  return w;
}

I64 TextWidth(Canvas *c, I64 f, U8 *text, I64 n = -1)
{
  return Un(TextWidthPx(c, f, text, n));
}

I64 TextHeight(Canvas *c, I64 f)
{
  return Un(c->font[f].height);
}

I64 DrawGlyph(Canvas *c, Font *font, I64 x, I64 y, I64 ch, U32 color)
{
  if (ch < 32 || ch >= 128)
    return x;
  Glyph *g = &font->g[ch - 32];
  if (g->alpha != NULL) {
    for (I64 gy = 0; gy < g->h; gy++) {
      I64 py = y + gy;
      if (py < c->clip_y0 || py >= c->clip_y1)
        continue;
      for (I64 gx = 0; gx < g->w; gx++) {
        I64 a = g->alpha[gy * g->w + gx];
        if (a > 0)
          Blend(c, x + gx, py, color, a);
      }
    }
  }
  return x + g->adv;
}

// Draws text with its top at y (units). Text wider than max_w is cut and
// ends in "...". Returns the x after the last glyph, in units.
I64 Text(Canvas *c, I64 f, I64 x, I64 y, U8 *text, U32 color, I64 max_w = 100000, I64 n = -1)
{
  Font *font = &c->font[f];
  I64 len = StrLen(text);
  if (n >= 0 && n < len)
    len = n;
  I64 px = Px(x), py = Px(y), room = Px(max_w);
  if (max_w >= 100000)
    room = 1 << 40;
  if (TextWidthPx(c, f, text, len) <= room) {
    for (I64 i = 0; i < len; i++)
      px = DrawGlyph(c, font, px, py, text[i], color);
    return Un(px);
  }
  I64 dots = TextWidthPx(c, f, "...");
  I64 used = 0, i = 0;
  while (i < len) {
    I64 adv = AdvPx(font, text[i]);
    if (used + adv > room - dots)
      break;
    used += adv;
    px = DrawGlyph(c, font, px, py, text[i], color);
    i++;
  }
  for (i = 0; i < 3; i++)
    px = DrawGlyph(c, font, px, py, '.', color);
  return Un(px);
}

// Text vertically centred on cy.
I64 TextMid(Canvas *c, I64 f, I64 x, I64 cy, U8 *text, U32 color, I64 max_w = 100000)
{
  return Text(c, f, x, cy - TextHeight(c, f) / 2, text, color, max_w);
}

I64 TextRight(Canvas *c, I64 f, I64 right, I64 y, U8 *text, U32 color)
{
  return Text(c, f, right - TextWidth(c, f, text), y, text, color);
}

// Splits text into lines no wider than max_w units, breaking at spaces
// where it can. starts and lens get one item per line. Returns the count.
I64 Wrap(Canvas *c, I64 f, U8 *text, I64 max_w, I64 *starts, I64 *lens, I64 max_lines)
{
  Font *font = &c->font[f];
  I64 room = Px(max_w);
  I64 n = 0, i = 0, len = StrLen(text);
  while (i < len && n < max_lines) {
    while (text[i] == ' ')
      i++;
    I64 start = i, w = 0, last_space = -1;
    while (i < len) {
      I64 adv = AdvPx(font, text[i]);
      if (w + adv > room && i > start)
        break;
      if (text[i] == ' ')
        last_space = i;
      w += adv;
      i++;
    }
    if (i < len && last_space > start)
      i = last_space;
    starts[n] = start;
    lens[n] = i - start;
    n++;
  }
  if (n == 0) {
    starts[0] = 0;
    lens[0] = 0;
    n = 1;
  }
  return n;
}

// ---- output ---------------------------------------------------------------

U0 Present(Canvas *c)
{
  SDL_UpdateTexture(c->texture, NULL, c->pixels, g_pw * 4);
  SDL_RenderCopy(c->renderer, c->texture, NULL, NULL);
  SDL_RenderPresent(c->renderer);
}

// Turns a mouse position in window coordinates into units. Window and
// renderer sizes differ on scaled (HiDPI) displays, so it converts.
Bool CanvasPoint(Canvas *c, I64 x, I64 y, I64 *cx, I64 *cy)
{
  I32 win_w, win_h;
  SDL_GetWindowSize(c->window, &win_w, &win_h);
  if (win_w <= 0 || win_h <= 0)
    return FALSE;
  *cx = Un(x * g_pw / win_w);
  *cy = Un(y * g_ph / win_h);
  return TRUE;
}

// Writes the frame as a PPM image, for checking the layout without a screen.
U0 CanvasDump(Canvas *c, U8 *path)
{
  I32 fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, MODE_FILE);
  if (fd < 0)
    return;
  U8 head[32];
  snprintf(head, 32, "P6\n%d %d\n255\n", g_pw, g_ph);
  WriteAll(fd, head, StrLen(head));
  U8 *rgb = MAlloc(g_pw * 3);
  for (I64 y = 0; y < g_ph; y++) {
    for (I64 x = 0; x < g_pw; x++) {
      U32 p = c->pixels[y * g_pw + x];
      rgb[x * 3] = p >> 16;
      rgb[x * 3 + 1] = p >> 8;
      rgb[x * 3 + 2] = p;
    }
    WriteAll(fd, rgb, g_pw * 3);
  }
  Free(rgb);
  close(fd);
}
