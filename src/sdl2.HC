// The SDL2 functions ARK uses. Adapted from
// examples/common/sdl2.HC in YatoVoid/holyc-graphics-guide (MIT).
// Types follow SDL's headers: int -> I32, Uint32 -> U32, opaque pointers -> U0 *.

#link <SDL2>

#define SDL_INIT_VIDEO          0x00000020
#define SDL_WINDOWPOS_CENTERED  0x2FFF0000
#define SDL_WINDOW_SHOWN        0x00000004
#define SDL_WINDOW_RESIZABLE    0x00000020
#define SDL_RENDERER_ACCELERATED  0x00000002
#define SDL_RENDERER_PRESENTVSYNC 0x00000004

#define SDL_QUIT       0x100
#define SDL_WINDOWEVENT 0x200
#define SDL_KEYDOWN    0x300
#define SDL_TEXTINPUT  0x303
#define SDL_MOUSEBUTTONDOWN 0x401
#define SDL_EVENT_BYTES 64

// Byte offsets into SDL_Event. A keyboard event's keysym starts at 16
// (scancode, then sym); a text-input event's UTF-8 text starts at 12.
#define EV_KEY_SYM   20
#define EV_KEY_MOD   24
#define EV_TEXT      12
#define EV_MOUSE_X   20   // SDL_MouseButtonEvent x, then y, in window coordinates
#define EV_MOUSE_Y   24

// SDL_Keycode values (sym, not scancode), so they follow the keyboard layout.
#define KEY_BACKSPACE 8
#define KEY_TAB       9
#define KEY_RETURN    13
#define KEY_ESCAPE    27
#define KEY_DELETE    127
#define KEY_F1        0x4000003A
#define KEY_F2        0x4000003B
#define KEY_F3        0x4000003C
#define KEY_F4        0x4000003D
#define KEY_F5        0x4000003E
#define KEY_F6        0x4000003F
#define KEY_F7        0x40000040
#define KEY_F8        0x40000041
#define KEY_F9        0x40000042
#define KEY_F10       0x40000043
#define KEY_F12       0x40000045
#define KEY_RIGHT     0x4000004F
#define KEY_LEFT      0x40000050
#define KEY_DOWN      0x40000051
#define KEY_UP        0x40000052
#define KEY_PAGEDOWN  0x4000004E
#define KEY_PAGEUP    0x4000004B

#define KMOD_CTRL  0x00C0
#define KMOD_SHIFT 0x0003

class SdlRect
{
  I32 x, y, w, h;
};

extern "c" I32 SDL_Init(U32 flags);
extern "c" U0 SDL_Quit();
extern "c" U8 *SDL_GetError();
extern "c" U0 *SDL_CreateWindow(U8 *title, I32 x, I32 y, I32 w, I32 h, U32 flags);
extern "c" U0 SDL_DestroyWindow(U0 *window);
extern "c" U0 SDL_SetWindowTitle(U0 *window, U8 *title);
extern "c" U0 SDL_GetWindowSize(U0 *window, I32 *w, I32 *h);

extern "c" U0 *SDL_CreateRenderer(U0 *window, I32 index, U32 flags);
extern "c" U0 SDL_DestroyRenderer(U0 *renderer);
extern "c" I32 SDL_SetRenderDrawColor(U0 *renderer, U8 r, U8 g, U8 b, U8 a);
extern "c" I32 SDL_RenderClear(U0 *renderer);
extern "c" I32 SDL_RenderFillRect(U0 *renderer, SdlRect *rect);
extern "c" I32 SDL_RenderDrawRect(U0 *renderer, SdlRect *rect);
extern "c" U0 SDL_RenderPresent(U0 *renderer);
extern "c" I32 SDL_RenderCopy(U0 *renderer, U0 *texture, SdlRect *src, SdlRect *dst);
extern "c" U0 *SDL_CreateTextureFromSurface(U0 *renderer, U0 *surface);
extern "c" I32 SDL_QueryTexture(U0 *texture, U32 *format, I32 *access, I32 *w, I32 *h);
extern "c" U0 SDL_DestroyTexture(U0 *texture);
extern "c" U0 SDL_FreeSurface(U0 *surface);

extern "c" I32 SDL_PollEvent(U0 *event);
extern "c" I32 SDL_WaitEventTimeout(U0 *event, I32 timeout_ms);
extern "c" U0 SDL_StartTextInput();
extern "c" U32 SDL_GetTicks();
extern "c" U0 SDL_Delay(U32 ms);

