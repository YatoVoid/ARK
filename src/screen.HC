// An 80x50 grid of 8x8 character cells in the 16 TempleOS colors, drawn
// into a 640x400 pixel buffer and scaled up to fill the window. Every
// frame is drawn from scratch: at this size that costs nothing and there
// is no stale state to clean up.

#define COLS   80
#define ROWS   50
#define CELL   8
#define SCR_W  (COLS * CELL)
#define SCR_H  (ROWS * CELL)

// TempleOS / VGA palette indexes.
#define BLACK     0
#define BLUE      1
#define GREEN     2
#define CYAN      3
#define RED       4
#define PURPLE    5
#define BROWN     6
#define LTGRAY    7
#define DKGRAY    8
#define LTBLUE    9
#define LTGREEN   10
#define LTCYAN    11
#define LTRED     12
#define LTPURPLE  13
#define YELLOW    14
#define WHITE     15

#define SDL_PIXELFORMAT_ARGB8888    0x16362004
#define SDL_TEXTUREACCESS_STREAMING 1
extern "c" U0 *SDL_CreateTexture(U0 *renderer, U32 format, I32 access, I32 w, I32 h);
extern "c" I32 SDL_UpdateTexture(U0 *texture, SdlRect *rect, U0 *pixels, I32 pitch);
extern "c" I32 SDL_GetRendererOutputSize(U0 *renderer, I32 *w, I32 *h);

U32 g_palette[16] = {
  0xFF000000, 0xFF0000AA, 0xFF00AA00, 0xFF00AAAA,
  0xFFAA0000, 0xFFAA00AA, 0xFFAA5500, 0xFFAAAAAA,
  0xFF555555, 0xFF5555FF, 0xFF55FF55, 0xFF55FFFF,
  0xFFFF5555, 0xFFFF55FF, 0xFFFFFF55, 0xFFFFFFFF
};

class Screen
{
  U0 *window;
  U0 *renderer;
  U0 *texture;
  SdlRect shown;          // where the last frame landed, in renderer pixels
  U32 pixels[SCR_W * SCR_H];
};

Bool ScreenOpen(Screen *s, U8 *title, I64 scale)
{
  if (SDL_Init(SDL_INIT_VIDEO) != 0)
    return FALSE;
  s->window = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                               SCR_W * scale, SCR_H * scale,
                               SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
  if (s->window == NULL)
    return FALSE;
  s->renderer = SDL_CreateRenderer(s->window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
  if (s->renderer == NULL)
    return FALSE;
  s->texture = SDL_CreateTexture(s->renderer, SDL_PIXELFORMAT_ARGB8888,
                                 SDL_TEXTUREACCESS_STREAMING, SCR_W, SCR_H);
  if (s->texture == NULL)
    return FALSE;
  SDL_StartTextInput();
  return TRUE;
}

U0 ScreenClose(Screen *s)
{
  SDL_DestroyTexture(s->texture);
  SDL_DestroyRenderer(s->renderer);
  SDL_DestroyWindow(s->window);
  SDL_Quit();
}

U0 FillCells(Screen *s, I64 col, I64 row, I64 w, I64 h, I64 color)
{
  I64 x0 = MaxI64(col * CELL, 0), y0 = MaxI64(row * CELL, 0);
  I64 x1 = MinI64((col + w) * CELL, SCR_W), y1 = MinI64((row + h) * CELL, SCR_H);
  U32 c = g_palette[color & 15];
  for (I64 y = y0; y < y1; y++)
    for (I64 x = x0; x < x1; x++)
      s->pixels[y * SCR_W + x] = c;
}

// A one-pixel line across the middle of a row of cells.
U0 RuleCells(Screen *s, I64 col, I64 row, I64 w, I64 color)
{
  I64 y = row * CELL + CELL / 2;
  U32 c = g_palette[color & 15];
  for (I64 x = col * CELL; x < MinI64((col + w) * CELL, SCR_W); x++)
    s->pixels[y * SCR_W + x] = c;
}

U0 PutChar(Screen *s, I64 col, I64 row, U8 ch, I64 fg, I64 bg)
{
  if (col < 0 || row < 0 || col >= COLS || row >= ROWS)
    return;
  I64 index = ch;
  U8 *glyph = &sys_font_std[index * 8];
  U32 f = g_palette[fg & 15], b = g_palette[bg & 15];
  for (I64 y = 0; y < CELL; y++) {
    I64 bits = glyph[y];
    U32 *line = &s->pixels[(row * CELL + y) * SCR_W + col * CELL];
    for (I64 x = 0; x < CELL; x++) {
      if (bits & (1 << x))
        line[x] = f;
      else
        line[x] = b;
    }
  }
}

// Draws text from (col, row), clipped to max_w cells. Returns the column
// after the last character drawn.
I64 PutText(Screen *s, I64 col, I64 row, U8 *text, I64 fg, I64 bg, I64 max_w = COLS)
{
  I64 i = 0;
  while (text[i] && i < max_w && col + i < COLS) {
    PutChar(s, col + i, row, text[i], fg, bg);
    i++;
  }
  return col + i;
}

// Copies the pixel buffer to the window, as large as fits without
// changing the aspect ratio.
U0 ScreenPresent(Screen *s)
{
  SDL_UpdateTexture(s->texture, NULL, s->pixels, SCR_W * 4);
  I32 w, h;
  SDL_GetRendererOutputSize(s->renderer, &w, &h);
  SdlRect dst;
  if (w * SCR_H > h * SCR_W) {
    dst.h = h;
    dst.w = h * SCR_W / SCR_H;
  } else {
    dst.w = w;
    dst.h = w * SCR_H / SCR_W;
  }
  dst.x = (w - dst.w) / 2;
  dst.y = (h - dst.h) / 2;
  SDL_SetRenderDrawColor(s->renderer, 0xFF, 0xFF, 0xFF, 0xFF);
  SDL_RenderClear(s->renderer);
  SDL_RenderCopy(s->renderer, s->texture, NULL, &dst);
  MemCpy(&s->shown, &dst, sizeof(SdlRect));
  SDL_RenderPresent(s->renderer);
}

// Turns a mouse position (window coordinates) into a cell. Window and
// renderer sizes differ on scaled displays, so it converts between them.
Bool ScreenCell(Screen *s, I64 x, I64 y, I64 *col, I64 *row)
{
  I32 win_w, win_h, out_w, out_h;
  SDL_GetWindowSize(s->window, &win_w, &win_h);
  SDL_GetRendererOutputSize(s->renderer, &out_w, &out_h);
  if (win_w <= 0 || win_h <= 0 || s->shown.w <= 0 || s->shown.h <= 0)
    return FALSE;
  I64 px = x * out_w / win_w - s->shown.x;
  I64 py = y * out_h / win_h - s->shown.y;
  if (px < 0 || py < 0 || px >= s->shown.w || py >= s->shown.h)
    return FALSE;
  *col = px * COLS / s->shown.w;
  *row = py * ROWS / s->shown.h;
  return TRUE;
}
