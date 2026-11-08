// ARK station. Usage: ark DIR PORT [PANEL]
//   DIR    station directory (created on first run)
//   PORT   serial port or pty that reaches the relay
//   PANEL  optional serial port of the Arduino panel (firmware/panel)

#include "util.HC"
#include "crypto.HC"
#include "link.HC"
#include "log.HC"
#include "station.HC"
#include "team.HC"
#include "deadlines.HC"
#include "sdl2.HC"
#include "canvas.HC"
#include "app.HC"

#define SDL_MOUSEMOTION 0x400
#define SDL_MOUSEWHEEL  0x403
#define EV_WHEEL_Y      20

// Fonts live in assets/fonts, found from the working directory or next to
// the binary (build/ark -> ../assets/fonts).
U0 FontDir(U8 *argv0, U8 *out)
{
  if (access("assets/fonts/Inter-Regular.ttf", 0) == 0) {
    StrCpy(out, "assets/fonts");
    return;
  }
  CopyText(out, argv0, 400);
  U8 *slash = strrchr(out, '/');
  if (slash == NULL)
    StrCpy(out, "../assets/fonts");
  else
    StrCpy(slash, "/../assets/fonts");
}

I32 Main(I32 argc, U8 **argv)
{
  if (argc < 3) {
    "usage: ark DIR PORT [PANEL]\n";
    return 2;
  }
  if (!CryptoInit()) {
    "libsodium failed to start\n";
    return 1;
  }
  U8 *panel = NULL;
  if (argc > 3)
    panel = argv[3];
  App *a = AppNew(argv[1], argv[2], panel);

  U8 fonts[512];
  FontDir(argv[0], fonts);
  U8 *title = MStrPrint("ARK  %s", argv[1]);
  if (!CanvasOpen(a->cv, title, fonts)) {
    "could not open the window or fonts in %s: %s\n", fonts, SDL_GetError();
    return 1;
  }
  Free(title);

  U8 ev[SDL_EVENT_BYTES];
  I64 last_draw = 0;
  while (!a->quit) {
    if (SDL_WaitEventTimeout(ev, 50)) {
      do {
        U32 type = *(ev(U32 *));
        I64 x, y;
        if (type == SDL_QUIT) {
          a->quit = TRUE;
        } else if (type == SDL_TEXTINPUT) {
          OnText(a, ev + EV_TEXT);
          a->dirty = TRUE;
        } else if (type == SDL_KEYDOWN) {
          OnKey(a, *((ev + EV_KEY_SYM)(I32 *)), *((ev + EV_KEY_MOD)(U16 *)));
          a->dirty = TRUE;
        } else if (type == SDL_MOUSEBUTTONDOWN) {
          if (CanvasPoint(a->cv, *((ev + EV_MOUSE_X)(I32 *)), *((ev + EV_MOUSE_Y)(I32 *)), &x, &y))
            OnClick(a, x, y);
          a->dirty = TRUE;
        } else if (type == SDL_MOUSEMOTION) {
          if (CanvasPoint(a->cv, *((ev + EV_MOUSE_X)(I32 *)), *((ev + EV_MOUSE_Y)(I32 *)), &x, &y)) {
            a->mx = x;
            a->my = y;
            a->dirty = TRUE;
          }
        } else if (type == SDL_MOUSEWHEEL) {
          OnWheel(a, *((ev + EV_WHEEL_Y)(I32 *)));
          a->dirty = TRUE;
        } else if (type == SDL_WINDOWEVENT) {
          a->dirty = TRUE;
        }
      } while (SDL_PollEvent(ev));
    }
    PollLink(a);
    PollPanel(a);
    PanelUpdate(a, FALSE);
    Heartbeat(a);
    I64 now = SDL_GetTicks();
    if (a->dirty || now - last_draw >= 1000) {
      Draw(a);
      Present(a->cv);
      a->dirty = FALSE;
      last_draw = now;
    }
  }
  StationWipe(a->st);
  CanvasClose(a->cv);
  return 0;
}
