// Draws every page of the station from a sample incident and writes each
// frame to build/ui-*.ppm. Run with SDL_VIDEODRIVER=offscreen; it's how the
// layout gets checked without clicking through a real window.

#include "../src/util.HC"
#include "../src/crypto.HC"
#include "../src/link.HC"
#include "../src/log.HC"
#include "../src/station.HC"
#include "../src/team.HC"
#include "../src/deadlines.HC"
#include "../src/sdl2.HC"
#include "../src/canvas.HC"
#include "../src/app.HC"

extern "c" I32 system(U8 *command);

U0 Note(App *a, I64 kind, I64 phase, U8 *text)
{
  U8 *msg = MAlloc(MSG_MAX);
  Post(a->st, kind, phase, text, StrLen(text), msg);
  Free(msg);
}

U0 Shot(App *a, U8 *name)
{
  Draw(a);
  U8 path[128];
  snprintf(path, 128, "build/ui-%s.ppm", name);
  CanvasDump(a->cv, path);
}

I32 Main(I32 argc, U8 **argv)
{
  CryptoInit();
  system("rm -rf build/tmp-ui");
  App *a = AppNew("build/tmp-ui", "/nonexistent", NULL);
  if (!CanvasOpen(a->cv, "render", "assets/fonts")) {
    "canvas: %s\n", SDL_GetError();
    return 1;
  }
  Shot(a, "setup-name");
  a->mode = MODE_NEW_PASS;
  a->fields[FLD_SETUP].len = 5;
  StrCpy(a->fields[FLD_SETUP].text, "hunte");
  Shot(a, "setup-pass");
  ClearField(a, FLD_SETUP);
  StationCreate(a->st, a->st->dir, "Dana Kessler", "correct horse battery");
  a->mode = MODE_NEW_CHOICE;
  Shot(a, "setup-choice");
  a->mode = MODE_READY;
  Shot(a, "setup-joinwait");

  U8 *msg = MAlloc(MSG_MAX);
  StartIncident(a->st, "Ransomware on FS-01, Brightline Health", msg);
  a->link.fd = 5;
  Note(a, KIND_NOTE, PHASE_DETECT, "Ransom note found on FS-01 by night shift. Shares show .lck extension since 02:10.");
  Note(a, KIND_CHAT, PHASE_DETECT, "Pulling FS-01 and NAS-02 off the switch now. Don't log in from the domain.");
  Note(a, KIND_SCOPE, PHASE_DETECT, "FS-01|PII|TX|4120|ENCRYPTED");
  Note(a, KIND_NOTE, PHASE_CONTAIN, "Moved the response to CONTAIN: stopping the spread: isolate, block, reset passwords.");
  Note(a, KIND_SCOPE, PHASE_CONTAIN, "HR-DB|PII|TX|?|EXFILTRATED");
  Note(a, KIND_SCOPE, PHASE_CONTAIN, "imaging-archive|PHI|EU|412|EXFILTRATED");
  Note(a, KIND_SCOPE, PHASE_CONTAIN, "NAS-02|OTHER|-|0|CLEAN");
  Note(a, KIND_NOTE, PHASE_CONTAIN, "Carrier confirmed coverage; forensic firm statement of work signed. Claim number A-55102.");
  Note(a, KIND_CHAT, PHASE_CONTAIN, "Draft EU notice sent to Priya for review. Need the imaging-archive count confirmed by 16:00.");
  Free(msg);

  a->team.peer_count = 1;
  MemSet(a->team.peers[0].pk, 7, PK_BYTES);
  StrCpy(a->team.peers[0].name, "Marcus Hale");
  a->team.peers[0].heard = time(NULL);
  a->team.join_pending = TRUE;
  MemSet(a->team.join_pk, 9, PK_BYTES);
  StrCpy(a->team.join_name, "Priya Shah");

  U8 *names[VIEWS] = {"overview", "log", "scope", "clocks", "team", "network", "guide"};
  for (I64 v = 0; v < VIEWS; v++) {
    a->view = v;
    Shot(a, names[v]);
  }
  OpenScope(a);
  StrCpy(a->fields[FLD_ASSET].text, "Payroll share");
  a->fields[FLD_ASSET].len = 13;
  a->scope_type = 0;
  a->scope_status = 1;
  StrCpy(a->scope_error, "Pick what kind of data it holds.");
  Shot(a, "scope-form");
  a->scope_open = FALSE;
  a->view = V_LOG;
  a->focus = FLD_SEARCH;
  StrCpy(a->fields[FLD_SEARCH].text, "fs-01");
  a->fields[FLD_SEARCH].len = 5;
  Shot(a, "log-search");
  "rendered\n";
  return 0;
}
