// Drawing for the station window: a 1440x900 pixel buffer, filled
// rectangles with anti-aliased round corners, and text from glyphs that
// SDL2_ttf renders once at startup. The whole frame is redrawn only when
// something changed (an event, a message, the clock ticking a minute), then
// copied to the window scaled to fit.
//
// Fonts are Inter and JetBrains Mono, both SIL Open Font License, bundled in
// assets/fonts with their licenses.

#link <SDL2_ttf>

#define CW  1440
#define CH  900

#define SDL_PIXELFORMAT_ARGB8888    0x16362004
#define SDL_TEXTUREACCESS_STREAMING 1
#define SDL_HINT_RENDER_SCALE_QUALITY "SDL_RENDER_SCALE_QUALITY"
extern "c" U0 *SDL_CreateTexture(U0 *renderer, U32 format, I32 access, I32 w, I32 h);
extern "c" I32 SDL_UpdateTexture(U0 *texture, SdlRect *rect, U0 *pixels, I32 pitch);
extern "c" I32 SDL_GetRendererOutputSize(U0 *renderer, I32 *w, I32 *h);
extern "c" I32 SDL_SetHint(U8 *name, U8 *value);
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
  I64 w, h, adv;
  U8 *alpha;
};

class Font
{
  Glyph g[GLYPHS];
  I64 height;
  I64 ascent;
};

#define F_SMALL  0   // Inter 12
#define F_BODY   1   // Inter 13
#define F_MED    2   // Inter Medium 14
#define F_LABEL  3   // Inter SemiBold 11, for caps labels
#define F_H2     4   // Inter SemiBold 15
#define F_H1     5   // Inter SemiBold 22
#define F_BIG    6   // Inter Bold 40
#define F_MONO   7   // JetBrains Mono 12
#define F_BTN    8   // Inter Bold 14
#define F_SEMI   9   // Inter SemiBold 13
#define FONTS    10

class Canvas
{
  U0 *window;
  U0 *renderer;
  U0 *texture;
  SdlRect shown;          // where the last frame landed, in renderer pixels
  Font font[FONTS];
  I64 clip_x0, clip_y0, clip_x1, clip_y1;
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
#define C_CYAN      0xFF22D3EE
#define C_CYAN_FG   0xFF67E8F9
#define C_GREEN     0xFF22C55E
#define C_GREEN_FG  0xFF86EFAC
#define C_GREEN_BTN 0xFF15803D
#define C_GREEN_DK  0xFF14532D
#define C_AMBER     0xFFF59E0B
#define C_AMBER_FG  0xFFFCD34D
#define C_RED       0xFFEF4444
#define C_RED_FG    0xFFFCA5A5
#define C_RED_BTN   0xFFB91C1C
#define C_RED_DK    0xFF7F1D1D
#define C_PURPLE    0xFFA78BFA
#define C_PURPLE_FG 0xFFC4B5FD

// a out of 255 of color c over color under, as one opaque color.
U32 Mix(U32 c, U32 under, I64 a)
{
  I64 r = ((c >> 16) & 0xFF) * a + ((under >> 16) & 0xFF) * (255 - a);
  I64 g = ((c >> 8) & 0xFF) * a + ((under >> 8) & 0xFF) * (255 - a);
  I64 b = (c & 0xFF) * a + (under & 0xFF) * (255 - a);
  return 0xFF000000 | ((r / 255) << 16) | ((g / 255) << 8) | (b / 255);
}

// ---- setup ----------------------------------------------------------------

Bool LoadFont(Canvas *c, I64 slot, U8 *dir, U8 *file, I64 size)
{
  U8 path[512];
  snprintf(path, 512, "%s/%s", dir, file);
  U0 *f = TTF_OpenFont(path, size);
  if (f == NULL)
    return FALSE;
  Font *font = &c->font[slot];
  font->height = TTF_FontHeight(f);
  font->ascent = TTF_FontAscent(f);
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
    g->alpha = MAlloc(MaxI64(1, g->w * g->h));
    for (I64 y = 0; y < g->h; y++) {
      U32 *row = (px + y * pitch)(U32 *);
      for (I64 x = 0; x < g->w; x++)
        g->alpha[y * g->w + x] = row[x] >> 24;
    }
    SDL_FreeSurface(surf);
  }
  TTF_CloseFont(f);
  return TRUE;
}

U0 ClipAll(Canvas *c)
{
  c->clip_x0 = 0;
  c->clip_y0 = 0;
  c->clip_x1 = CW;
  c->clip_y1 = CH;
}

U0 Clip(Canvas *c, I64 x, I64 y, I64 w, I64 h)
{
  // Computed into locals first: hcc 0.0.15 stores the first
  // "c->field = Call()" through the register c arrived in, which the call
  // has already reused. See docs/BUILDING.md.
  I64 x0 = MaxI64(x, 0), y0 = MaxI64(y, 0);
  I64 x1 = MinI64(x + w, CW), y1 = MinI64(y + h, CH);
  c->clip_x0 = x0;
  c->clip_y0 = y0;
  c->clip_x1 = x1;
  c->clip_y1 = y1;
}

Bool CanvasOpen(Canvas *c, U8 *title, U8 *font_dir)
{
  if (SDL_Init(SDL_INIT_VIDEO) != 0 || TTF_Init() != 0)
    return FALSE;
  SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");
  c->window = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                               CW, CH, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
  if (c->window == NULL)
    return FALSE;
  SDL_SetWindowMinimumSize(c->window, CW / 2, CH / 2);
  c->renderer = SDL_CreateRenderer(c->window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
  if (c->renderer == NULL)
    return FALSE;
  c->texture = SDL_CreateTexture(c->renderer, SDL_PIXELFORMAT_ARGB8888,
                                 SDL_TEXTUREACCESS_STREAMING, CW, CH);
  if (c->texture == NULL)
    return FALSE;
  c->pixels = CAlloc(CW * CH * 4);
  ClipAll(c);
  Bool ok = LoadFont(c, F_SMALL, font_dir, "Inter-Regular.ttf", 12) &&
            LoadFont(c, F_BODY, font_dir, "Inter-Regular.ttf", 13) &&
            LoadFont(c, F_MED, font_dir, "Inter-Medium.ttf", 14) &&
            LoadFont(c, F_LABEL, font_dir, "Inter-SemiBold.ttf", 11) &&
            LoadFont(c, F_H2, font_dir, "Inter-SemiBold.ttf", 15) &&
            LoadFont(c, F_H1, font_dir, "Inter-SemiBold.ttf", 22) &&
            LoadFont(c, F_BIG, font_dir, "Inter-Bold.ttf", 40) &&
            LoadFont(c, F_MONO, font_dir, "JetBrainsMono-Regular.ttf", 12) &&
            LoadFont(c, F_BTN, font_dir, "Inter-Bold.ttf", 14) &&
            LoadFont(c, F_SEMI, font_dir, "Inter-SemiBold.ttf", 13);
  if (!ok)
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

U0 Fill(Canvas *c, I64 x, I64 y, I64 w, I64 h, U32 color)
{
  I64 x0 = MaxI64(x, c->clip_x0), y0 = MaxI64(y, c->clip_y0);
  I64 x1 = MinI64(x + w, c->clip_x1), y1 = MinI64(y + h, c->clip_y1);
  for (I64 py = y0; py < y1; py++) {
    U32 *row = &c->pixels[py * CW];
    for (I64 px = x0; px < x1; px++)
      row[px] = color;
  }
}

U0 Blend(Canvas *c, I64 x, I64 y, U32 color, I64 a)
{
  if (a <= 0 || x < c->clip_x0 || y < c->clip_y0 || x >= c->clip_x1 || y >= c->clip_y1)
    return;
  U32 *p = &c->pixels[y * CW + x];
  if (a >= 255)
    *p = color;
  else
    *p = Mix(color, *p, a);
}

// Rounded rectangle. Corner pixels get partial coverage so edges stay smooth.
U0 Round(Canvas *c, I64 x, I64 y, I64 w, I64 h, I64 r, U32 color)
{
  r = MinI64(r, MinI64(w, h) / 2);
  if (r <= 0) {
    Fill(c, x, y, w, h, color);
    return;
  }
  Fill(c, x + r, y, w - 2 * r, h, color);
  Fill(c, x, y + r, r, h - 2 * r, color);
  Fill(c, x + w - r, y + r, r, h - 2 * r, color);
  // 16 samples per corner pixel, in eighths of a pixel, all integer:
  // F64 arguments to C functions don't survive hcc's calling convention.
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

// A rounded box with a one-pixel border.
U0 Box(Canvas *c, I64 x, I64 y, I64 w, I64 h, I64 r, U32 fill, U32 border)
{
  Round(c, x, y, w, h, r, border);
  Round(c, x + 1, y + 1, w - 2, h - 2, MaxI64(0, r - 1), fill);
}

U0 HLine(Canvas *c, I64 x, I64 y, I64 w, U32 color)
{
  Fill(c, x, y, w, 1, color);
}

U0 Dot(Canvas *c, I64 cx, I64 cy, I64 d, U32 color)
{
  Round(c, cx - d / 2, cy - d / 2, d, d, d / 2, color);
}

// ---- text -----------------------------------------------------------------

I64 TextWidth(Canvas *c, I64 f, U8 *text, I64 n = -1)
{
  Font *font = &c->font[f];
  I64 w = 0;
  for (I64 i = 0; text[i] && (n < 0 || i < n); i++) {
    I64 ch = text[i];
    if (ch >= 32 && ch < 128)
      w += font->g[ch - 32].adv;
  }
  return w;
}

I64 TextHeight(Canvas *c, I64 f)
{
  return c->font[f].height;
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

// Draws text with its top at y. Text wider than max_w is cut and ends in
// "...". Returns the x after the last glyph.
I64 Text(Canvas *c, I64 f, I64 x, I64 y, U8 *text, U32 color, I64 max_w = 100000, I64 n = -1)
{
  Font *font = &c->font[f];
  I64 len = StrLen(text);
  if (n >= 0 && n < len)
    len = n;
  I64 full = TextWidth(c, f, text, len);
  if (full <= max_w) {
    for (I64 i = 0; i < len; i++)
      x = DrawGlyph(c, font, x, y, text[i], color);
    return x;
  }
  I64 dots = TextWidth(c, f, "...");
  I64 room = max_w - dots, used = 0, i = 0;
  while (i < len) {
    I64 ch = text[i];
    I64 adv = 0;
    if (ch >= 32 && ch < 128)
      adv = font->g[ch - 32].adv;
    if (used + adv > room)
      break;
    used += adv;
    x = DrawGlyph(c, font, x, y, ch, color);
    i++;
  }
  for (i = 0; i < 3; i++)
    x = DrawGlyph(c, font, x, y, '.', color);
  return x;
}

// Text vertically centred on cy.
I64 TextMid(Canvas *c, I64 f, I64 x, I64 cy, U8 *text, U32 color, I64 max_w = 100000)
{
  return Text(c, f, x, cy - c->font[f].height / 2, text, color, max_w);
}

I64 TextRight(Canvas *c, I64 f, I64 right, I64 y, U8 *text, U32 color)
{
  return Text(c, f, right - TextWidth(c, f, text), y, text, color);
}

// Splits text into lines no wider than max_w, breaking at spaces where it
// can. starts and lens get one item per line. Returns the line count.
I64 Wrap(Canvas *c, I64 f, U8 *text, I64 max_w, I64 *starts, I64 *lens, I64 max_lines)
{
  Font *font = &c->font[f];
  I64 n = 0, i = 0, len = StrLen(text);
  while (i < len && n < max_lines) {
    while (text[i] == ' ')
      i++;
    I64 start = i, w = 0, last_space = -1;
    while (i < len) {
      I64 ch = text[i];
      I64 adv = 0;
      if (ch >= 32 && ch < 128)
        adv = font->g[ch - 32].adv;
      if (w + adv > max_w && i > start)
        break;
      if (ch == ' ')
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
  SDL_UpdateTexture(c->texture, NULL, c->pixels, CW * 4);
  I32 w, h;
  SDL_GetRendererOutputSize(c->renderer, &w, &h);
  SdlRect dst;
  if (w * CH > h * CW) {
    dst.h = h;
    dst.w = h * CW / CH;
  } else {
    dst.w = w;
    dst.h = w * CH / CW;
  }
  dst.x = (w - dst.w) / 2;
  dst.y = (h - dst.h) / 2;
  SDL_SetRenderDrawColor(c->renderer, 0x0B, 0x10, 0x20, 0xFF);
  SDL_RenderClear(c->renderer);
  SDL_RenderCopy(c->renderer, c->texture, NULL, &dst);
  MemCpy(&c->shown, &dst, sizeof(SdlRect));
  SDL_RenderPresent(c->renderer);
}

// Turns a mouse position in window coordinates into canvas pixels. Window
// and renderer sizes differ on scaled displays, so it converts between them.
Bool CanvasPoint(Canvas *c, I64 x, I64 y, I64 *cx, I64 *cy)
{
  I32 win_w, win_h, out_w, out_h;
  SDL_GetWindowSize(c->window, &win_w, &win_h);
  SDL_GetRendererOutputSize(c->renderer, &out_w, &out_h);
  if (win_w <= 0 || win_h <= 0 || c->shown.w <= 0 || c->shown.h <= 0)
    return FALSE;
  I64 px = x * out_w / win_w - c->shown.x;
  I64 py = y * out_h / win_h - c->shown.y;
  if (px < 0 || py < 0 || px >= c->shown.w || py >= c->shown.h)
    return FALSE;
  *cx = px * CW / c->shown.w;
  *cy = py * CH / c->shown.h;
  return TRUE;
}

// Writes the frame as a PPM image, for checking the layout without a screen.
U0 CanvasDump(Canvas *c, U8 *path)
{
  I32 fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, MODE_FILE);
  if (fd < 0)
    return;
  U8 head[32];
  snprintf(head, 32, "P6\n%d %d\n255\n", CW, CH);
  WriteAll(fd, head, StrLen(head));
  U8 *rgb = MAlloc(CW * 3);
  for (I64 y = 0; y < CH; y++) {
    for (I64 x = 0; x < CW; x++) {
      U32 p = c->pixels[y * CW + x];
      rgb[x * 3] = p >> 16;
      rgb[x * 3 + 1] = p >> 8;
      rgb[x * 3 + 2] = p;
    }
    WriteAll(fd, rgb, CW * 3);
  }
  Free(rgb);
  close(fd);
}
