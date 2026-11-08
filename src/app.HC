// The station's window: setup screens, then a sidebar of pages, a top bar
// with the incident phase and link state, and a control panel on the right
// that mirrors the hardware panel. main.HC only parses arguments and runs
// the loop; tests/render_views.HC draws every page from a sample log.

#define MODE_NEW_NAME   0
#define MODE_NEW_PASS   1
#define MODE_NEW_PASS2  2
#define MODE_NEW_CHOICE 3
#define MODE_NEW_TITLE  4
#define MODE_UNLOCK     5
#define MODE_READY      6

#define INPUT_MAX   200
#define BEAT_SECS   3
#define ONLINE_SECS (3 * BEAT_SECS)
#define PASS_MIN    8

#define V_OVERVIEW  0
#define V_SERVER    1
#define V_LOG       2   // the chat log: notes, chat, alerts, scope, team
#define V_SCOPE     3
#define V_CLOCKS    4
#define V_TEAM      5
#define V_NETWORK   6
#define V_REPORT    7
#define V_GUIDE     8
#define VIEWS       9

#define FLD_SETUP    0
#define FLD_COMPOSE  1
#define FLD_SEARCH   2
#define FLD_ASSET    3
#define FLD_WHERE    4
#define FLD_RECORDS  5
#define FIELDS       6

#define FILTER_ALL   0
#define FILTER_NOTE  1
#define FILTER_CHAT  2
#define FILTER_SCOPE 3
#define FILTER_TEAM  4

#define SF_ALL       0
#define SF_SUS       1
#define SF_COMMANDS  2
#define SF_LOGINS    3
#define SF_REQUESTS  4

// What a click on a hit region does.
#define H_NAV        1
#define H_FOCUS      2
#define H_PHASE      3
#define H_SEND       4
#define H_KIND       5
#define H_FILTER     6
#define H_SCOPE_OPEN 7
#define H_SCOPE_SHUT 8
#define H_SCOPE_SAVE 9
#define H_TYPE       10
#define H_STATUS     11
#define H_WHERE      12
#define H_UNKNOWN    13
#define H_APPROVE    14
#define H_PANIC      15
#define H_START      16
#define H_JOIN       17
#define H_CONTINUE   18
#define H_SEARCH_CLR 19
#define H_CUT        20
#define H_RESTORE    21
#define H_ACK        22
#define H_LOCK       23
#define H_EVENT      24
#define H_REPORT     25
#define H_SFILTER    26
#define H_WRITE      27
#define H_CLEAR      28   // delete this station's data and start over
#define H_BACK       29   // back to the name step, nothing written yet

#define RS_NONE     0
#define RS_RUNNING  1
#define RS_DONE     2
#define RS_FAILED   3
#define REPORT_MAX  65536
#define HITS         192

// Layout.
#define SIDE_W   232
#define TOP_H    64
#define PANEL_W  272
#define MAIN_X   SIDE_W
#define PAD      24
#define CX0      (MAIN_X + PAD)
#define COMPOSE_H 52

#define MAX_ASSETS  32
#define MAX_MEMBERS 32

U8 *g_phase_names[5] = {"", "DETECT", "CONTAIN", "ERADICATE", "RECOVER"};
U8 *g_phase_help[5] = {
  "",
  "confirming what happened and how far it reaches",
  "stopping the spread: isolate, block, reset passwords",
  "removing the attacker and their tools",
  "restoring systems and watching for a return"
};
U8 *g_view_names[VIEWS] = {"Overview", "Server log", "Chat log", "Scope", "Breach clocks", "Team", "Network", "Report", "Guide"};
U8 *g_data_types[5] = {"PII", "PHI", "PCI", "CRED", "OTHER"};
U8 *g_type_short[5] = {"names with SSN or ID", "health records", "card numbers", "logins, passwords", "anything else"};
U8 *g_scope_status[5] = {"ENCRYPTED", "EXFILTRATED", "SUSPECTED", "CONTAINED", "CLEAN"};
U8 *g_status_short[5] = {"locked by ransomware", "copied out", "not confirmed yet", "access cut off", "checked, not hit"};
U8 *g_where_picks[5] = {"TX", "CA", "NY", "EU", "-"};
U8 *g_where_labels[5] = {"TX", "CA", "NY", "EU", "None"};
U8 *g_filter_names[5] = {"All", "Notes", "Chat", "Scope", "Team"};
U8 *g_sfilter_names[5] = {"All", "Suspicious", "Commands", "Logins", "Requests"};
U8 *g_month[12] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
U8 *g_wday[7] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};

class Tm
{
  I32 sec, min, hour, mday, mon, year, wday, yday, isdst, pad;
  I64 gmtoff;
  U8 *zone;
};
extern "c" Tm *localtime_r(I64 *t, Tm *out);
extern "c" I32 access(U8 *path, I32 mode);
extern "c" U8 *getenv(U8 *name);
extern "c" I32 system(U8 *command);

class Field
{
  U8 text[INPUT_MAX + 1];
  I64 len;
};

class Hit
{
  I64 x, y, w, h, id, arg;
};

class Asset
{
  U8 name[32];
  U8 type[8];
  U8 where[8];
  U8 records[16];
  U8 status[16];
  I64 time;
  U8 author[PK_BYTES];
};

class Member
{
  U8 pk[PK_BYTES];
  U8 name[NAME_MAX];
  I64 time;
  Bool admin;
};

class App
{
  Canvas *cv;
  Station *st;
  Team team;
  Link link;
  U8 port[256];
  U8 panel_port[256];
  I64 mode;
  I64 view;
  Field fields[FIELDS];
  I64 focus;              // a FLD_ value, or -1
  I64 kind;               // KIND_NOTE or KIND_CHAT for the composer
  I64 filter;
  I64 scroll;             // log lines scrolled back from the newest
  Bool scope_open;
  I64 scope_type;         // -1 until picked
  I64 scope_status;
  Bool scope_unknown;
  U8 scope_error[96];
  U8 name[NAME_MAX];
  U8 pass[128];
  U8 msg[128];
  U32 msg_color;
  I64 msg_time;
  I64 last_beat;
  I64 cut_armed;          // time() of the first on-screen CUT press, 0 if not armed
  I64 lock_armed;         // same for the lock button and F12
  I64 alerts_acked;       // alerts from others this station has acknowledged
  I64 panel_alerts;       // alerts already beeped for
  Bool quit;
  Bool dirty;
  I64 mx, my;             // mouse, in canvas pixels
  Hit hits[HITS];
  I64 hit_count;
  I32 panel_fd;           // -1 without a panel
  U8 panel_line[32];
  I64 panel_len;
  I64 panel_problems;     // problem count last reported, to beep on new ones
  Bool panel_join;        // join request already beeped for
  Bool panel_cut;         // light state last sent
  I64 order[LOG_MAX];
  I64 server_filter;
  I64 server_scroll;      // events scrolled down from the newest
  I64 selected;           // entry index of the picked server event, or -1
  I64 risk[LOG_MAX];      // RISK_ per entry index, worked out once
  U8 *why[LOG_MAX];
  I64 risk_done;          // entries [0, risk_done) have a risk
  U8 reported[64][12];    // event refs named by alerts, rebuilt each frame
  I64 reported_count;
  I64 sus_open;           // suspicious events nobody has reported yet
  I32 feed_fd;            // DIR/feed from tools/ark-watch, -1 until it exists
  I64 feed_off;
  I64 feed_tried;
  U8 feed_line[1100];
  I64 feed_len;
  I64 feed_window;        // start of the current rate window
  I64 feed_posted;        // events posted in it
  I64 feed_dropped;
  I64 clear_armed;        // time() of the first Clear press, 0 if not armed
  I64 report_state;       // RS_ value
  I64 report_started;
  Bool report_warmed;
  U8 report_msg[256];
  U8 *report_text;        // DIR/report/report.md as last read
  I64 report_len;
  I64 report_scroll;
  I64 report_max_scroll;
  Asset assets[MAX_ASSETS];
  I64 asset_count;
  Member members[MAX_MEMBERS];
  I64 member_count;
};

// ---- small helpers --------------------------------------------------------

U0 Say(App *a, U8 *text, U32 color)
{
  CopyText(a->msg, text, 128);
  a->msg_color = color;
  a->msg_time = time(NULL);
}

U0 ClockText(I64 t, U8 *out)
{
  Tm tm;
  localtime_r(&t, &tm);
  snprintf(out, 8, "%02d:%02d", tm.hour, tm.min);
}

// "Nov 7, 18:52"
U0 DateText(I64 t, U8 *out)
{
  Tm tm;
  localtime_r(&t, &tm);
  snprintf(out, 32, "%s %d, %02d:%02d", g_month[tm.mon], tm.mday, tm.hour, tm.min);
}

// "Mon Dec 7, 18:52"
U0 DayDateText(I64 t, U8 *out)
{
  Tm tm;
  localtime_r(&t, &tm);
  snprintf(out, 32, "%s %s %d, %02d:%02d", g_wday[tm.wday], g_month[tm.mon], tm.mday, tm.hour, tm.min);
}

U0 Commas(I64 n, U8 *out)
{
  U8 raw[32];
  snprintf(raw, 32, "%ld", n);
  I64 len = StrLen(raw), j = 0;
  for (I64 i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0)
      out[j++] = ',';
    out[j++] = raw[i];
  }
  out[j] = 0;
}

U0 Fingerprint(U8 *pk, U8 *out)
{
  snprintf(out, 32, "%02X%02X %02X%02X %02X%02X %02X%02X",
           pk[0], pk[1], pk[2], pk[3], pk[4], pk[5], pk[6], pk[7]);
}

U0 ClearField(App *a, I64 f)
{
  sodium_memzero(a->fields[f].text, INPUT_MAX + 1);
  a->fields[f].len = 0;
}

Bool IsAdmin(Station *s)
{
  if (s->log->has_admin && Same(s->log->admin, s->pk, PK_BYTES))
    return TRUE;
  return FALSE;
}

Bool Ready(App *a)
{
  return a->mode == MODE_READY && a->st->epoch >= 0;
}

U0 Send(App *a, U8 *msg, I64 len)
{
  if (len > 0)
    LinkSend(&a->link, msg, len);
}

Bool PostAndSend(App *a, I64 kind, I64 phase, U8 *body, I64 len)
{
  U8 *msg = MAlloc(MSG_MAX);
  I64 n = Post(a->st, kind, phase, body, len, msg);
  Bool ok = n > 0;
  if (ok) {
    Send(a, msg, n);
    a->scroll = 0;
  } else {
    Say(a, "Not posted: this station has no team key yet.", C_RED_FG);
  }
  Free(msg);
  return ok;
}

I64 ProblemCount(App *a)
{
  return a->st->log->problems + a->st->rejected + a->st->damaged_on_load;
}

I64 OnlineCount(App *a)
{
  I64 now = time(NULL), n = 0;
  for (I64 i = 0; i < a->team.peer_count; i++)
    if (now - a->team.peers[i].heard <= ONLINE_SECS)
      n++;
  return n;
}

Bool PeerOnline(App *a, U8 *pk)
{
  if (Same(pk, a->st->pk, PK_BYTES))
    return TRUE;
  I64 now = time(NULL);
  for (I64 i = 0; i < a->team.peer_count; i++)
    if (Same(a->team.peers[i].pk, pk, PK_BYTES) && now - a->team.peers[i].heard <= ONLINE_SECS)
      return TRUE;
  return FALSE;
}

// ---- alerts and the internet switch -------------------------------------

// Alerts written by other stations. The manager acknowledges them locally.
I64 AlertCount(App *a)
{
  Log *log = a->st->log;
  I64 n = 0;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_ALERT && e->status == ST_OK && !Same(e->author, a->st->pk, PK_BYTES))
      n++;
  }
  return n;
}

// The newest alert from another station, or NULL.
Entry *NewestAlert(App *a)
{
  Log *log = a->st->log;
  Entry *best = NULL;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_ALERT && e->status == ST_OK && !Same(e->author, a->st->pk, PK_BYTES))
      if (best == NULL || e->lamport > best->lamport)
        best = e;
  }
  return best;
}

I64 UnackedAlerts(App *a)
{
  return MaxI64(0, AlertCount(a) - a->alerts_acked);
}

// The newest network entry, from this station only or from anyone.
Entry *LastNetwork(App *a, Bool mine)
{
  Log *log = a->st->log;
  Entry *best = NULL;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind != KIND_NETWORK || e->status != ST_OK)
      continue;
    if (mine && !Same(e->author, a->st->pk, PK_BYTES))
      continue;
    if (best == NULL || e->lamport > best->lamport)
      best = e;
  }
  return best;
}

// Whether this machine is cut off, as this station last logged it.
Bool IsCut(App *a)
{
  Entry *e = LastNetwork(a, TRUE);
  return e != NULL && StrNCmp(e->body, "Cut", 3) == 0;
}

// ---- reading the log ------------------------------------------------------

U0 IncidentTitle(Log *log, U8 *out)
{
  out[0] = 0;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_GENESIS && log->has_admin && Same(e->author, log->admin, PK_BYTES)) {
      U8 *nl = strchr(e->body, '\n');
      if (nl != NULL)
        CopyText(out, nl + 1, 96);
      return;
    }
  }
}

I64 OpenedAt(Log *log)
{
  for (I64 i = 0; i < log->count; i++)
    if (log->entries[i].kind == KIND_GENESIS)
      return log->entries[i].time;
  return time(NULL);
}

// The phase of the newest note that set one. Clicking a phase in the top
// bar posts such a note, so every station agrees on the phase.
I64 IncidentPhase(App *a)
{
  Log *log = a->st->log;
  LogSorted(log, a->order);
  for (I64 k = log->count - 1; k >= 0; k--) {
    Entry *e = &log->entries[a->order[k]];
    if (e->kind == KIND_NOTE && e->status == ST_OK && e->phase >= 1 && e->phase <= 4)
      return e->phase;
  }
  return PHASE_DETECT;
}

// The latest valid SCOPE entry for each asset, newest first.
U0 CollectAssets(App *a)
{
  Log *log = a->st->log;
  LogSorted(log, a->order);
  a->asset_count = 0;
  U8 body[BODY_MAX + 1];
  for (I64 k = log->count - 1; k >= 0 && a->asset_count < MAX_ASSETS; k--) {
    Entry *e = &log->entries[a->order[k]];
    if (e->kind != KIND_SCOPE || e->status != ST_OK)
      continue;
    StrCpy(body, e->body);
    U8 *f[5];
    if (!SplitScope(body, f))
      continue;
    Bool dup = FALSE;
    for (I64 i = 0; i < a->asset_count; i++)
      if (StrCmp(a->assets[i].name, f[0]) == 0)
        dup = TRUE;
    if (dup)
      continue;
    Asset *as = &a->assets[a->asset_count++];
    CopyText(as->name, f[0], 32);
    CopyText(as->type, f[1], 8);
    CopyText(as->where, f[2], 8);
    CopyText(as->records, f[3], 16);
    CopyText(as->status, f[4], 16);
    as->time = e->time;
    MemCpy(as->author, e->author, PK_BYTES);
  }
}

U0 CollectMembers(App *a)
{
  Log *log = a->st->log;
  a->member_count = 0;
  for (I64 i = 0; i < log->count && a->member_count < MAX_MEMBERS; i++) {
    Entry *e = &log->entries[i];
    if (e->status != ST_OK)
      continue;
    Member *m = &a->members[a->member_count];
    if (e->kind == KIND_GENESIS && log->has_admin && Same(e->author, log->admin, PK_BYTES)) {
      MemCpy(m->pk, e->author, PK_BYTES);
      m->admin = TRUE;
    } else if (e->kind == KIND_MEMBER_ADD && e->body_len > PK_BYTES) {
      MemCpy(m->pk, e->body, PK_BYTES);
      m->admin = FALSE;
    } else {
      continue;
    }
    NameOf(log, m->pk, m->name);
    m->time = e->time;
    a->member_count++;
  }
}

Bool ClockStarted(Clock *clocks, I64 n, I64 rule)
{
  for (I64 i = 0; i < n; i++)
    if (clocks[i].rule == rule)
      return TRUE;
  return FALSE;
}

U32 StatusColor(U8 *status)
{
  if (StrCmp(status, "EXFILTRATED") == 0)
    return C_RED;
  if (StrCmp(status, "ENCRYPTED") == 0)
    return C_PURPLE;
  if (StrCmp(status, "SUSPECTED") == 0)
    return C_AMBER;
  if (StrCmp(status, "CONTAINED") == 0)
    return C_CYAN;
  if (StrCmp(status, "CLEAN") == 0)
    return C_GREEN;
  return C_FAINT;
}

U32 LightOf(U32 color)
{
  if (color == C_RED)
    return C_RED_FG;
  if (color == C_PURPLE)
    return C_PURPLE_FG;
  if (color == C_AMBER)
    return C_AMBER_FG;
  if (color == C_CYAN)
    return C_CYAN_FG;
  if (color == C_GREEN)
    return C_GREEN_FG;
  return C_MUTED;
}

U32 RemainingColor(I64 left)
{
  if (left < 72 * 3600)
    return C_RED_FG;
  if (left < 7 * 86400)
    return C_AMBER_FG;
  return C_TEXT;
}

// The alert text without the "[ref] " that ties a report to its event.
U8 *AlertText(U8 *body)
{
  if (body[0] == '[' && StrLen(body) > 11 && body[9] == ']' && body[10] == ' ')
    return body + 11;
  return body;
}

// The text of an entry as one line, without time or author.
U0 EntryText(Log *log, Entry *e, U8 *out)
{
  if (e->kind == KIND_GENESIS) {
    U8 *nl = strchr(e->body, '\n');
    if (nl != NULL)
      snprintf(out, BODY_MAX + 128, "Opened the incident: %s", nl + 1);
    else
      StrCpy(out, "Opened the incident");
  } else if (e->kind == KIND_MEMBER_ADD) {
    U8 name[NAME_MAX];
    if (e->body_len >= PK_BYTES)
      NameOf(log, e->body, name);
    else
      StrCpy(name, "?");
    snprintf(out, BODY_MAX + 128, "Admitted %s to the team", name);
  } else if (e->kind == KIND_SCOPE) {
    U8 body[BODY_MAX + 1];
    StrCpy(body, e->body);
    U8 *f[5];
    if (SplitScope(body, f)) {
      U8 count[40];
      if (StrCmp(f[3], "?") == 0)
        StrCpy(count, "unknown number of");
      else
        Commas(strtoll(f[3], NULL, 10), count);
      if (StrCmp(f[2], "-") == 0)
        snprintf(out, BODY_MAX + 128, "%s: %s %s records, %s", f[0], count, f[1], f[4]);
      else
        snprintf(out, BODY_MAX + 128, "%s: %s %s records of %s residents, %s", f[0], count, f[1], f[2], f[4]);
    } else {
      snprintf(out, BODY_MAX + 128, "%s", e->body);
    }
  } else if (e->kind == KIND_ALERT) {
    StrCpy(out, AlertText(e->body));
  } else {
    StrCpy(out, e->body);
  }
  for (I64 i = 0; out[i]; i++)
    if (out[i] < 32)
      out[i] = ' ';
}

U0 KindTag(Entry *e, U8 *out)
{
  if (e->kind == KIND_NOTE && e->phase >= 1 && e->phase <= 4)
    snprintf(out, 24, "Note, %s", g_phase_names[e->phase]);
  else if (e->kind == KIND_NOTE)
    StrCpy(out, "Note");
  else if (e->kind == KIND_CHAT)
    StrCpy(out, "Chat");
  else if (e->kind == KIND_SCOPE)
    StrCpy(out, "Scope");
  else if (e->kind == KIND_ALERT)
    StrCpy(out, "ALERT");
  else if (e->kind == KIND_NETWORK)
    StrCpy(out, "Network");
  else
    StrCpy(out, "Team");
}

U32 KindColor(I64 kind)
{
  if (kind == KIND_ALERT || kind == KIND_NETWORK)
    return C_RED_FG;
  if (kind == KIND_CHAT)
    return C_PURPLE_FG;
  if (kind == KIND_SCOPE)
    return C_AMBER_FG;
  if (kind == KIND_NOTE)
    return C_CYAN_FG;
  return C_MUTED;
}

Bool PassesFilter(App *a, Entry *e, U8 *text)
{
  I64 f = a->filter;
  if (f == FILTER_NOTE && e->kind != KIND_NOTE)
    return FALSE;
  if (f == FILTER_CHAT && e->kind != KIND_CHAT)
    return FALSE;
  if (f == FILTER_SCOPE && e->kind != KIND_SCOPE)
    return FALSE;
  if (f == FILTER_TEAM && e->kind != KIND_MEMBER_ADD && e->kind != KIND_GENESIS)
    return FALSE;
  Field *q = &a->fields[FLD_SEARCH];
  if (q->len > 0) {
    U8 name[NAME_MAX];
    NameOf(a->st->log, e->author, name);
    if (strcasestr(text, q->text) == NULL && strcasestr(name, q->text) == NULL)
      return FALSE;
  }
  return TRUE;
}

// ---- server events --------------------------------------------------------

I64 EventCount(App *a)
{
  Log *log = a->st->log;
  I64 n = 0;
  for (I64 i = 0; i < log->count; i++)
    if (log->entries[i].kind == KIND_EVENT)
      n++;
  return n;
}

// Works out the risk of entries added since the last call, then which
// events alerts have already reported and how many suspicious ones haven't.
U0 RefreshRisk(App *a)
{
  Log *log = a->st->log;
  if (a->risk_done > log->count)
    a->risk_done = 0;
  for (I64 i = a->risk_done; i < log->count; i++) {
    Entry *e = &log->entries[i];
    a->risk[i] = RISK_NONE;
    a->why[i] = "";
    Event ev;
    if (e->kind == KIND_EVENT && e->status == ST_OK && EventFromBody(e->body, &ev)) {
      Tm tm;
      localtime_r(&e->time, &tm);
      a->risk[i] = EventRisk(&ev, tm.hour, &a->why[i]);
    }
  }
  a->risk_done = log->count;
  a->reported_count = 0;
  for (I64 i = 0; i < log->count && a->reported_count < 64; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_ALERT && e->status == ST_OK && AlertText(e->body) != e->body) {
      MemCpy(a->reported[a->reported_count], e->body + 1, 8);
      a->reported[a->reported_count][8] = 0;
      a->reported_count++;
    }
  }
  a->sus_open = 0;
  for (I64 i = 0; i < log->count; i++) {
    if (a->risk[i] != RISK_SUS)
      continue;
    U8 ref[12];
    EntryRef(&log->entries[i], ref);
    Bool done = FALSE;
    for (I64 k = 0; k < a->reported_count; k++)
      if (StrCmp(a->reported[k], ref) == 0)
        done = TRUE;
    if (!done)
      a->sus_open++;
  }
}

// The alert that reported this event, or NULL.
Entry *ReportOf(App *a, Entry *ev)
{
  U8 ref[12];
  EntryRef(ev, ref);
  Log *log = a->st->log;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_ALERT && e->status == ST_OK && e->body[0] == '[' && StrNCmp(e->body + 1, ref, 8) == 0)
      return e;
  }
  return NULL;
}

Bool ServerPasses(App *a, I64 idx, Event *ev)
{
  I64 f = a->server_filter;
  if (f == SF_SUS && a->risk[idx] != RISK_SUS)
    return FALSE;
  if (f == SF_COMMANDS && ev->source != EV_SHELL && ev->source != EV_SUDO)
    return FALSE;
  if (f == SF_LOGINS && ev->source != EV_LOGIN && ev->source != EV_FAIL && ev->source != EV_ACCOUNT)
    return FALSE;
  if (f == SF_REQUESTS && ev->source != EV_REQUEST)
    return FALSE;
  Field *q = &a->fields[FLD_SEARCH];
  if (q->len > 0 && strcasestr(ev->detail, q->text) == NULL && strcasestr(ev->user, q->text) == NULL &&
      strcasestr(ev->host, q->text) == NULL)
    return FALSE;
  return TRUE;
}

// ---- widgets --------------------------------------------------------------

U0 AddHit(App *a, I64 x, I64 y, I64 w, I64 h, I64 id, I64 arg = 0)
{
  if (a->hit_count == HITS)
    return;
  Hit *t = &a->hits[a->hit_count++];
  t->x = x;
  t->y = y;
  t->w = w;
  t->h = h;
  t->id = id;
  t->arg = arg;
}

Bool Hover(App *a, I64 x, I64 y, I64 w, I64 h)
{
  return a->mx >= x && a->mx < x + w && a->my >= y && a->my < y + h;
}

#define BTN_GHOST    0
#define BTN_PRIMARY  1
#define BTN_GREEN    2
#define BTN_RED      3
#define BTN_OFF      4

U0 Button(App *a, I64 x, I64 y, I64 w, I64 h, U8 *label, I64 style, I64 id, I64 arg = 0)
{
  Canvas *c = a->cv;
  U32 bg = C_SURFACE, border = C_LINE2, fg = C_TEXT;
  if (style == BTN_PRIMARY) {
    bg = C_CYAN;
    border = C_CYAN;
    fg = C_BG;
  } else if (style == BTN_GREEN) {
    bg = C_GREEN_BTN;
    border = C_GREEN_BTN;
  } else if (style == BTN_RED) {
    bg = C_RED_BTN;
    border = C_RED_BTN;
  } else if (style == BTN_OFF) {
    bg = C_SURFACE;
    border = C_LINE;
    fg = C_FAINT;
  }
  if (style != BTN_OFF && Hover(a, x, y, w, h)) {
    bg = Mix(0xFFFFFFFF, bg, 22);
    border = Mix(0xFFFFFFFF, border, 22);
  }
  Box(c, x, y, w, h, 6, bg, border);
  I64 f = F_MED;
  if (style == BTN_PRIMARY)
    f = F_SEMI;
  I64 tw = TextWidth(c, f, label);
  TextMid(c, f, x + (w - tw) / 2, y + h / 2, label, fg, w - 16);
  if (style != BTN_OFF)
    AddHit(a, x, y, w, h, id, arg);
}

// Small uppercase status label in a tinted box.
I64 Badge(App *a, I64 x, I64 cy, U8 *text, U32 color)
{
  Canvas *c = a->cv;
  I64 w = TextWidth(c, F_LABEL, text) + 14;
  Box(c, x, cy - 11, w, 22, 4, Mix(color, C_SURFACE, 34), Mix(color, C_SURFACE, 120));
  TextMid(c, F_LABEL, x + 7, cy, text, LightOf(color));
  return x + w;
}

U0 Card(App *a, I64 x, I64 y, I64 w, I64 h)
{
  Box(a->cv, x, y, w, h, 8, C_SURFACE, C_LINE);
}

// A card title row with a rule under it. Returns the y below the rule.
I64 CardHead(App *a, I64 x, I64 y, I64 w, U8 *title, U8 *note = NULL)
{
  Canvas *c = a->cv;
  TextMid(c, F_SEMI, x + 16, y + 21, title, C_TEXT);
  if (note != NULL)
    TextMid(c, F_SMALL, x + w - 16 - TextWidth(c, F_SMALL, note), y + 21, note, C_FAINT);
  HLine(c, x + 1, y + 42, w - 2, C_LINE);
  return y + 43;
}

U0 Input(App *a, I64 fld, I64 x, I64 y, I64 w, I64 h, U8 *placeholder, Bool secret = FALSE)
{
  Canvas *c = a->cv;
  Field *f = &a->fields[fld];
  Bool on = a->focus == fld;
  U32 border = C_LINE2;
  if (on)
    border = C_CYAN;
  else if (Hover(a, x, y, w, h))
    border = Mix(0xFFFFFFFF, C_LINE2, 30);
  Box(c, x, y, w, h, 6, C_BG, border);
  I64 cy = y + h / 2, tx = x + 12, room = w - 24;
  if (f->len == 0) {
    TextMid(c, F_BODY, tx, cy, placeholder, C_FAINT, room);
    if (on)
      Fill(c, tx, cy - 8, 2, 16, C_CYAN);
  } else {
    U8 shown[INPUT_MAX + 1];
    for (I64 i = 0; i <= f->len; i++)
      shown[i] = f->text[i];
    if (secret)
      for (I64 i = 0; i < f->len; i++)
        shown[i] = '*';
    U8 *start = shown;
    while (TextWidth(c, F_BODY, start) > room - 4 && start[0])
      start++;
    I64 end = TextMid(c, F_BODY, tx, cy, start, C_TEXT);
    if (on)
      Fill(c, end + 1, cy - 8, 2, 16, C_CYAN);
  }
  AddHit(a, x, y, w, h, H_FOCUS, fld);
}

// A selectable tile: a title and a short description under it.
U0 Choice(App *a, I64 x, I64 y, I64 w, I64 h, U8 *title, U8 *desc, Bool on, U32 dot, I64 id, I64 arg)
{
  Canvas *c = a->cv;
  U32 bg = C_BG, border = C_LINE2;
  if (on) {
    bg = Mix(C_CYAN, C_SURFACE, 30);
    border = C_CYAN;
  } else if (Hover(a, x, y, w, h)) {
    border = Mix(0xFFFFFFFF, C_LINE2, 30);
  }
  Box(c, x, y, w, h, 6, bg, border);
  I64 tx = x + 12;
  if (dot != 0) {
    Dot(c, x + 16, y + 18, 8, dot);
    tx = x + 26;
  }
  TextMid(c, F_SEMI, tx, y + 18, title, C_TEXT, w - (tx - x) - 8);
  if (desc != NULL)
    TextMid(c, F_SMALL, x + 12, y + 38, desc, C_MUTED, w - 20);
  AddHit(a, x, y, w, h, id, arg);
}

U0 PageHead(App *a, U8 *title, U8 *sub)
{
  Canvas *c = a->cv;
  Text(a->cv, F_H1, CX0, TOP_H + 18, title, C_TEXT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 260);
  if (sub != NULL)
    Text(c, F_BODY, CX0, TOP_H + 50, sub, C_MUTED, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 260);
}

// ---- frame: sidebar, top bar, control panel -------------------------------

U0 DrawSide(App *a)
{
  Canvas *c = a->cv;
  Log *log = a->st->log;
  Fill(c, 0, 0, SIDE_W, g_ch, C_PANEL);
  Fill(c, SIDE_W - 1, 0, 1, g_ch, C_LINE);
  Text(c, F_H1, 20, 18, "ARK", C_TEXT);
  Text(c, F_SMALL, 74, 26, "off-network incident log", C_FAINT);

  Text(c, F_LABEL, 20, 70, "INCIDENT", C_FAINT);
  U8 title[96];
  IncidentTitle(log, title);
  I64 starts[2], lens[2];
  I64 lines = Wrap(c, F_SEMI, title, SIDE_W - 40, starts, lens, 2);
  for (I64 i = 0; i < lines; i++)
    Text(c, F_SEMI, 20, 88 + i * 18, title + starts[i], C_TEXT, SIDE_W - 40, lens[i]);
  I64 day = (time(NULL) - OpenedAt(log)) / 86400 + 1;
  U8 line[64];
  snprintf(line, 64, "Day %ld", day);
  I64 y = 88 + lines * 18 + 16;
  I64 x = Text(c, F_SMALL, 20, y - 7, line, C_MUTED) + 10;
  Badge(a, x, y, g_phase_names[IncidentPhase(a)], C_CYAN);

  Clock clocks[RULES];
  I64 nclocks = Deadlines(log, clocks);
  CollectAssets(a);
  y = 176;
  for (I64 v = 0; v < VIEWS; v++) {
    if (v == V_GUIDE)
      y += 14;
    Bool on = a->view == v;
    if (on)
      Round(c, 12, y, SIDE_W - 24, 36, 6, C_RAISED);
    else if (Hover(a, 12, y, SIDE_W - 24, 36))
      Round(c, 12, y, SIDE_W - 24, 36, 6, Mix(C_RAISED, C_PANEL, 120));
    I64 f = F_MED;
    U32 fg = C_MUTED;
    if (on) {
      f = F_SEMI;
      fg = C_TEXT;
    }
    TextMid(c, f, 24, y + 18, g_view_names[v], fg);
    U8 badge[24];
    badge[0] = 0;
    U32 bcol = C_FAINT;
    if (v == V_LOG)
      Commas(log->count - EventCount(a), badge);
    if (v == V_SERVER && a->sus_open > 0) {
      snprintf(badge, 24, "%ld", a->sus_open);
      bcol = C_RED;
    } else if (v == V_SERVER && EventCount(a) > 0) {
      Commas(EventCount(a), badge);
    }
    if (v == V_SCOPE && a->asset_count > 0)
      snprintf(badge, 24, "%ld", a->asset_count);
    if (v == V_CLOCKS && nclocks > 0) {
      I64 left = clocks[0].due - time(NULL);
      if (left < 0)
        StrCpy(badge, "LATE");
      else if (left < 2 * 86400)
        snprintf(badge, 24, "%ldh", left / 3600);
      else
        snprintf(badge, 24, "%ldd", left / 86400);
      if (left < 72 * 3600)
        bcol = C_RED;
      else if (left < 7 * 86400)
        bcol = C_AMBER;
    }
    if (v == V_TEAM && a->team.join_pending) {
      StrCpy(badge, "+1");
      bcol = C_CYAN;
    }
    if (v == V_REPORT && a->report_state == RS_RUNNING)
      StrCpy(badge, "...");
    if (v == V_NETWORK && a->st->rejected > 0) {
      snprintf(badge, 24, "%ld", a->st->rejected);
      bcol = C_RED;
    }
    if (badge[0]) {
      I64 bw = TextWidth(c, F_LABEL, badge) + 12;
      U32 bbg = C_SURFACE, bfg = C_FAINT;
      if (bcol != C_FAINT) {
        bbg = Mix(bcol, C_PANEL, 44);
        bfg = LightOf(bcol);
      }
      Round(c, SIDE_W - 24 - bw - 8, y + 8, bw, 20, 4, bbg);
      TextMid(c, F_LABEL, SIDE_W - 24 - bw - 2, y + 18, badge, bfg);
    }
    AddHit(a, 12, y, SIDE_W - 24, 36, H_NAV, v);
    y += 40;
  }

  HLine(c, 0, g_ch - 92, SIDE_W - 1, C_LINE);
  Text(c, F_SEMI, 20, g_ch - 76, a->st->name, C_TEXT, SIDE_W - 40);
  if (IsAdmin(a->st))
    Text(c, F_SMALL, 20, g_ch - 56, "Manager, this station", C_MUTED);
  else
    Text(c, F_SMALL, 20, g_ch - 56, "Member, this station", C_MUTED);
  U8 fp[32], keyline[40];
  Fingerprint(a->st->pk, fp);
  snprintf(keyline, 40, "key %s", fp);
  Text(c, F_MONO, 20, g_ch - 36, keyline, C_FAINT);
}

// A status chip in the top bar: coloured dot and a short label.
U0 Chip(App *a, I64 x, I64 w, U8 *label, U32 color, I64 view)
{
  Canvas *c = a->cv;
  I64 y = 14, h = 36;
  U32 bg = Mix(color, C_BG, 30);
  if (Hover(a, x, y, w, h))
    bg = Mix(color, C_BG, 54);
  Box(c, x, y, w, h, 6, bg, Mix(color, C_BG, 110));
  Dot(c, x + 16, y + 18, 8, color);
  TextMid(c, F_MED, x + 28, y + 18, label, LightOf(color), w - 36);
  AddHit(a, x, y, w, h, H_NAV, view);
}

U0 DrawTop(App *a)
{
  Canvas *c = a->cv;
  Fill(c, MAIN_X, 0, g_cw - MAIN_X, TOP_H, C_BG);
  HLine(c, MAIN_X, TOP_H - 1, g_cw - MAIN_X, C_LINE);

  Input(a, FLD_SEARCH, CX0, 14, 220, 36, "Search  (Ctrl+F)");

  I64 phase = IncidentPhase(a);
  I64 x = CX0 + 236, w = 104;
  for (I64 p = 1; p <= 4; p++) {
    U32 bg = C_BG, border = C_LINE, fg = C_FAINT;
    if (p < phase) {
      border = C_LINE2;
      fg = C_MUTED;
    }
    if (p == phase) {
      bg = C_CYAN;
      border = C_CYAN;
      fg = C_BG;
    } else if (Hover(a, x, 14, w - 4, 36)) {
      border = Mix(0xFFFFFFFF, C_LINE2, 40);
    }
    Box(c, x, 14, w - 4, 36, 6, bg, border);
    U8 label[24];
    snprintf(label, 24, "%ld %s", p, g_phase_names[p]);
    I64 f = F_MED;
    if (p == phase)
      f = F_SEMI;
    TextMid(c, f, x + (w - 4 - TextWidth(c, f, label)) / 2, 32, label, fg);
    if (p != phase)
      AddHit(a, x, 14, w - 4, 36, H_PHASE, p);
    x += w;
  }

  I64 online = OnlineCount(a);
  U8 relay[48];
  U32 rc = C_GREEN;
  if (a->link.fd < 0) {
    StrCpy(relay, "No relay");
    rc = C_RED;
  } else if (online == 0) {
    StrCpy(relay, "Relay: alone");
    rc = C_AMBER;
  } else {
    snprintf(relay, 48, "Relay: %ld online", online);
  }
  I64 problems = ProblemCount(a);
  U8 integ[48];
  U32 ic = C_GREEN;
  if (problems > 0) {
    snprintf(integ, 48, "Log: %ld bad", problems);
    ic = C_RED;
  } else {
    StrCpy(integ, "Log intact");
  }
  Chip(a, g_cw - 16 - 136, 136, integ, ic, V_LOG);
  Chip(a, g_cw - 16 - 136 * 2 - 8, 136, relay, rc, V_NETWORK);
  if (IsCut(a))
    Chip(a, g_cw - 16 - 136 * 3 - 16, 136, "Internet: CUT", C_RED, V_NETWORK);
  else
    Chip(a, g_cw - 16 - 136 * 3 - 16, 136, "Internet: on", C_GREEN, V_NETWORK);
}

// One status light in the control panel.
U0 Light(App *a, I64 y, U8 *label, U8 *state, U32 color)
{
  Canvas *c = a->cv;
  Dot(c, (g_cw - PANEL_W) + 28, y, 12, color);
  TextMid(c, F_BODY, (g_cw - PANEL_W) + 44, y, label, C_MUTED);
  TextMid(c, F_SEMI, g_cw - 20 - TextWidth(c, F_SEMI, state), y, state, LightOf(color));
}

// A big hardware-style button: a darker lip under the face.
U0 PanelButton(App *a, I64 y, U8 *label, U8 *sub, U32 face, U32 lip, Bool on, I64 id)
{
  Canvas *c = a->cv;
  I64 x = (g_cw - PANEL_W) + 16, w = PANEL_W - 32;
  U32 fg = C_TEXT, sfg = Mix(C_TEXT, face, 190);
  if (!on) {
    face = Mix(face, C_PANEL, 70);
    lip = Mix(lip, C_PANEL, 70);
    fg = Mix(C_TEXT, C_PANEL, 120);
    sfg = fg;
  } else if (Hover(a, x, y, w, 66)) {
    face = Mix(0xFFFFFFFF, face, 24);
  }
  Round(c, x, y, w, 66, 10, lip);
  Round(c, x, y, w, 60, 10, face);
  TextMid(c, F_BTN, x + (w - TextWidth(c, F_BTN, label)) / 2, y + 22, label, fg);
  TextMid(c, F_SMALL, x + (w - TextWidth(c, F_SMALL, sub)) / 2, y + 42, sub, sfg);
  if (on)
    AddHit(a, x, y, w, 66, id);
}

U0 DrawPanel(App *a)
{
  Canvas *c = a->cv;
  Fill(c, (g_cw - PANEL_W), TOP_H, PANEL_W, g_ch - TOP_H, C_PANEL);
  Fill(c, (g_cw - PANEL_W), TOP_H, 1, g_ch - TOP_H, C_LINE);
  I64 x = (g_cw - PANEL_W) + 16, w = PANEL_W - 32;
  Text(c, F_LABEL, x, TOP_H + 20, "CONTROL PANEL", C_FAINT);
  if (a->panel_fd >= 0)
    TextRight(c, F_SMALL, x + w, TOP_H + 19, "hardware connected", C_GREEN_FG);
  else
    TextRight(c, F_SMALL, x + w, TOP_H + 19, "no hardware", C_FAINT);

  // What needs the manager now, most urgent first.
  I64 y = TOP_H + 44;
  I64 now = time(NULL);
  Bool cut = IsCut(a), admin = IsAdmin(a->st);
  Bool armed = a->cut_armed != 0 && now - a->cut_armed <= 3;
  Entry *alert = NewestAlert(a);
  U8 title[64], sub[160];
  U32 border = C_LINE, tint = C_PANEL, tc = C_TEXT;
  Bool ack = FALSE;
  if (armed) {
    StrCpy(title, "Cut the internet?");
    StrCpy(sub, "Press CUT NETWORK again within 3 seconds. ARK keeps working over the relay.");
    border = C_RED;
    tint = Mix(C_RED, C_PANEL, 26);
    tc = C_RED_FG;
  } else if (UnackedAlerts(a) > 0 && alert != NULL) {
    U8 name[NAME_MAX];
    NameOf(a->st->log, alert->author, name);
    snprintf(title, 64, "ALERT from %s", name);
    CopyText(sub, AlertText(alert->body), 160);
    for (I64 i = 0; sub[i]; i++)
      if (sub[i] < 32)
        sub[i] = ' ';
    border = C_RED;
    tint = Mix(C_RED, C_PANEL, 26);
    tc = C_RED_FG;
    ack = TRUE;
  } else if (cut) {
    U8 when[8];
    ClockText(LastNetwork(a, TRUE)->time, when);
    snprintf(title, 64, "Internet cut since %s", when);
    if (admin)
      StrCpy(sub, "Restore once systems are backed up and the attacker is removed.");
    else
      StrCpy(sub, "Only the manager can restore it.");
    border = Mix(C_RED, C_PANEL, 140);
  } else if (a->team.join_pending && admin) {
    I64 code = JoinCode(a->team.join_pk);
    snprintf(title, 64, "%s asks to join", a->team.join_name);
    snprintf(sub, 160, "Approve on the Team page if their screen shows %03ld %03ld.", code / 1000, code % 1000);
    border = C_CYAN;
    tint = Mix(C_CYAN, C_PANEL, 20);
    tc = C_CYAN_FG;
  } else {
    StrCpy(title, "No alerts");
    StrCpy(sub, "The buzzer sounds when a team member sends you an alert.");
  }
  I64 box_h = 92;
  if (ack)
    box_h = 134;
  Box(c, x, y, w, box_h, 8, tint, border);
  Text(c, F_SEMI, x + 14, y + 12, title, tc, w - 28);
  I64 starts[3], lens[3];
  I64 lines = 3;
  I64 n = Wrap(c, F_SMALL, sub, w - 28, starts, lens, lines);
  for (I64 i = 0; i < n; i++)
    Text(c, F_SMALL, x + 14, y + 34 + i * 16, sub + starts[i], C_MUTED, w - 28, lens[i]);
  if (ack) {
    Button(a, x + 14, y + box_h - 40, w - 28, 30, "Acknowledge", BTN_GHOST, H_ACK);
  }

  y += box_h + 16;
  if (cut)
    PanelButton(a, y, "NETWORK CUT", "this machine is offline", C_RED_BTN, C_RED_DK, FALSE, H_CUT);
  else
    PanelButton(a, y, "CUT NETWORK", "press twice: take this machine offline", C_RED_BTN, C_RED_DK, TRUE, H_CUT);
  y += 82;
  if (cut && admin)
    PanelButton(a, y, "RESTORE NETWORK", "after backups and cleanup", C_GREEN_BTN, C_GREEN_DK, TRUE, H_RESTORE);
  else if (cut)
    PanelButton(a, y, "RESTORE NETWORK", "manager only", C_GREEN_BTN, C_GREEN_DK, FALSE, H_RESTORE);
  else
    PanelButton(a, y, "RESTORE NETWORK", "internet is on", C_GREEN_BTN, C_GREEN_DK, FALSE, H_RESTORE);

  y += 96;
  Text(c, F_LABEL, x, y, "STATUS", C_FAINT);
  y += 30;
  if (cut)
    Light(a, y, "Internet", "CUT", C_RED);
  else
    Light(a, y, "Internet", "ON", C_GREEN);
  y += 32;
  I64 online = OnlineCount(a);
  if (a->link.fd < 0)
    Light(a, y, "Relay link", "NONE", C_RED);
  else if (online == 0)
    Light(a, y, "Relay link", "ALONE", C_AMBER);
  else
    Light(a, y, "Relay link", "OK", C_GREEN);
  y += 32;
  if (ProblemCount(a) > 0)
    Light(a, y, "Log integrity", "BROKEN", C_RED);
  else
    Light(a, y, "Log integrity", "OK", C_GREEN);
  y += 32;
  Clock clocks[RULES];
  I64 nclocks = Deadlines(a->st->log, clocks);
  I64 left = 1 << 40;
  if (nclocks > 0)
    left = clocks[0].due - now;
  if (left < 72 * 3600)
    Light(a, y, "Deadlines", "URGENT", C_RED);
  else if (left < 7 * 86400)
    Light(a, y, "Deadlines", "THIS WEEK", C_AMBER);
  else if (nclocks > 0)
    Light(a, y, "Deadlines", "RUNNING", C_CYAN);
  else
    Light(a, y, "Deadlines", "NONE", C_GREEN);

  HLine(c, (g_cw - PANEL_W) + 1, g_ch - 64, PANEL_W - 1, C_LINE);
  Bool lock_armed = a->lock_armed != 0 && now - a->lock_armed <= 3;
  U8 *lock = "Lock station  (F12 twice)";
  if (lock_armed)
    lock = "Press again to lock";
  Button(a, x, g_ch - 50, w, 34, lock, BTN_GHOST, H_LOCK);
}

// A short notice after an action, for six seconds, in the free space at
// the bottom of the sidebar where it covers nothing.
U0 DrawFlash(App *a)
{
  if (!a->msg[0] || time(NULL) - a->msg_time > 6)
    return;
  Canvas *c = a->cv;
  I64 starts[3], lens[3];
  I64 w = SIDE_W - 24;
  I64 n = Wrap(c, F_MED, a->msg, w - 24, starts, lens, 3);
  I64 h = 20 + n * 18;
  I64 y = g_ch - 92 - 16 - h;
  Box(c, 12, y, w, h, 6, Mix(a->msg_color, C_PANEL, 40), a->msg_color);
  for (I64 i = 0; i < n; i++)
    Text(c, F_MED, 24, y + 10 + i * 18, a->msg + starts[i], a->msg_color, w - 24, lens[i]);
}

// ---- composer -------------------------------------------------------------

U0 DrawComposer(App *a)
{
  Canvas *c = a->cv;
  I64 y = (g_ch - 20 - COMPOSE_H), x = CX0;
  Card(a, x, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), COMPOSE_H);
  I64 bx = x + 8;
  for (I64 k = 0; k < 3; k++) {
    I64 kind = KIND_NOTE;
    U8 *label = "Note";
    if (k == 1) {
      kind = KIND_CHAT;
      label = "Chat";
    } else if (k == 2) {
      kind = KIND_ALERT;
      label = "Alert";
    }
    Bool on = a->kind == kind;
    U32 bg = C_SURFACE, fg = C_MUTED;
    if (on && kind == KIND_ALERT) {
      bg = Mix(C_RED, C_SURFACE, 60);
      fg = C_RED_FG;
    } else if (on) {
      bg = C_RAISED;
      fg = C_TEXT;
    } else if (Hover(a, bx, y + 8, 64, 36)) {
      fg = C_TEXT;
    }
    Round(c, bx, y + 8, 64, 36, 6, bg);
    TextMid(c, F_SEMI, bx + (64 - TextWidth(c, F_SEMI, label)) / 2, y + 26, label, fg);
    AddHit(a, bx, y + 8, 64, 36, H_KIND, kind);
    bx += 68;
  }
  U8 hint[96];
  if (a->kind == KIND_NOTE)
    snprintf(hint, 96, "Note under %s: what you saw or did, and where", g_phase_names[IncidentPhase(a)]);
  else if (a->kind == KIND_ALERT)
    StrCpy(hint, "Alert the manager: what looks wrong and where. Their panel buzzes.");
  else
    StrCpy(hint, "Message the team. Chat is kept in the log too.");
  Input(a, FLD_COMPOSE, bx + 4, y + 8, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - (bx - x) - 4 - 100, 36, hint);
  Button(a, x + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 92, y + 8, 84, 36, "Send", BTN_PRIMARY, H_SEND);
}

// ---- pages ----------------------------------------------------------------

// One log entry as a row. Returns its height. With draw FALSE it only measures.
I64 LogRow(App *a, Entry *e, U8 *text, I64 x, I64 y, I64 w, Bool draw, I64 max_lines = 3)
{
  Canvas *c = a->cv;
  I64 tx = x + 262, tw = w - 262 - 16;
  if (e->status != ST_OK)
    tw -= 130;
  I64 starts[3], lens[3];
  I64 lines = Wrap(c, F_BODY, text, tw, starts, lens, max_lines);
  I64 h = 18 + lines * 18;
  if (!draw)
    return h;
  U8 clock[8], name[NAME_MAX], tag[24];
  ClockText(e->time, clock);
  NameOf(a->st->log, e->author, name);
  KindTag(e, tag);
  Text(c, F_MONO, x + 16, y + 10, clock, C_FAINT);
  Text(c, F_SEMI, x + 66, y + 9, name, C_TEXT, 84);
  Text(c, F_SMALL, x + 156, y + 10, tag, KindColor(e->kind), 100);
  U32 fg = C_TEXT;
  if (e->status != ST_OK)
    fg = C_FAINT;
  for (I64 i = 0; i < lines; i++)
    Text(c, F_BODY, tx, y + 9 + i * 18, text + starts[i], fg, tw, lens[i]);
  if (e->status != ST_OK)
    Badge(a, x + w - 16 - 120, y + 18, StatusName(e->status), C_RED);
  return h;
}

#define LIST_MAX 64

// Entries in time order, newest at the bottom like a chat. Only whole rows
// are drawn; when they don't fill the box they start at its top.
U0 LogList(App *a, I64 x, I64 y, I64 w, I64 h, I64 scroll, Bool filtered)
{
  Canvas *c = a->cv;
  Log *log = a->st->log;
  LogSorted(log, a->order);
  U8 *text = MAlloc(BODY_MAX + 128);
  I64 pick[LIST_MAX], heights[LIST_MAX];
  I64 n = 0, used = 0, skip = scroll;
  for (I64 k = log->count - 1; k >= 0 && n < LIST_MAX; k--) {
    Entry *e = &log->entries[a->order[k]];
    if (e->kind == KIND_EVENT)
      continue;
    EntryText(log, e, text);
    if (filtered && !PassesFilter(a, e, text))
      continue;
    if (skip > 0) {
      skip--;
      continue;
    }
    I64 rh = LogRow(a, e, text, x, 0, w, FALSE);
    if (used + rh > h - 4)
      break;
    pick[n] = a->order[k];
    heights[n] = rh;
    used += rh;
    n++;
  }
  I64 ry = y + 2;
  if (used >= h - 60)
    ry = y + h - 2 - used;
  for (I64 i = n - 1; i >= 0; i--) {
    Entry *e = &log->entries[pick[i]];
    EntryText(log, e, text);
    LogRow(a, e, text, x, ry, w, TRUE);
    if (i > 0)
      HLine(c, x + 1, ry + heights[i] - 1, w - 2, C_ROWLINE);
    ry += heights[i];
  }
  Free(text);
  if (n == 0 && log->count > 0)
    TextMid(c, F_BODY, x + 16, y + 30, "No entries match. Clear the search or pick All.", C_FAINT);
}

U0 DrawOverview(App *a)
{
  Canvas *c = a->cv;
  Log *log = a->st->log;
  U8 title[96], sub[160], admin[NAME_MAX], opened[32];
  IncidentTitle(log, title);
  NameOf(log, log->admin, admin);
  DateText(OpenedAt(log), opened);
  I64 day = (time(NULL) - OpenedAt(log)) / 86400 + 1;
  snprintf(sub, 160, "Opened by %s on %s. Day %ld of the response.", admin, opened, day);
  PageHead(a, title, sub);

  // The nearest legal deadline is what a manager asks about first.
  I64 y = TOP_H + 84;
  Clock clocks[RULES];
  I64 n = Deadlines(log, clocks);
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 108);
  if (n == 0) {
    Text(c, F_LABEL, CX0 + 20, y + 20, "LEGAL DEADLINES", C_FAINT);
    Text(c, F_H2, CX0 + 20, y + 42, "No notice clock is running", C_TEXT);
    Text(c, F_BODY, CX0 + 20, y + 68, "Clocks start when a system holding personal data is marked Exfiltrated or Encrypted.", C_MUTED, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 200);
    Button(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 160, y + 36, 140, 36, "Record scope", BTN_GHOST, H_SCOPE_OPEN);
  } else {
    I64 left = clocks[0].due - time(NULL);
    U8 rem[24], due[32], who[64];
    RemainingText(left, rem);
    DayDateText(clocks[0].due, due);
    Text(c, F_LABEL, CX0 + 20, y + 18, "NEXT LEGAL DEADLINE", C_FAINT);
    Text(c, F_BIG, CX0 + 18, y + 40, rem, RemainingColor(left));
    I64 mx = CX0 + 360;
    Fill(c, mx, y + 20, 1, 68, C_LINE);
    if (clocks[0].unsure)
      snprintf(who, 64, "Notify %s (if 250+ records)", g_rule_who[clocks[0].rule]);
    else
      snprintf(who, 64, "Notify %s", g_rule_who[clocks[0].rule]);
    Text(c, F_H2, mx + 24, y + 22, who, C_TEXT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 380 - 170);
    Text(c, F_MONO, mx + 24, y + 48, g_rule_cite[clocks[0].rule], C_FAINT);
    U8 dueline[48];
    snprintf(dueline, 48, "Due %s", due);
    Text(c, F_BODY, mx + 24, y + 72, dueline, C_MUTED);
    U8 more[32];
    if (n > 1)
      snprintf(more, 32, "All %ld clocks", n);
    else
      StrCpy(more, "Clock details");
    Button(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 150, y + 36, 130, 36, more, BTN_GHOST, H_NAV, V_CLOCKS);
  }

  // Affected systems on the left, things waiting on you on the right.
  y += 124;
  I64 lw = ((g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16) * 54 / 100, rw = (g_cw - SIDE_W - PANEL_W - 2 * PAD) - lw - 16, h = 212;
  Card(a, CX0, y, lw, h);
  CollectAssets(a);
  I64 hit = 0, records = 0;
  Bool unknown = FALSE;
  for (I64 i = 0; i < a->asset_count; i++) {
    Asset *as = &a->assets[i];
    if (StrCmp(as->status, "EXFILTRATED") == 0 || StrCmp(as->status, "ENCRYPTED") == 0) {
      hit++;
      if (StrCmp(as->records, "?") == 0)
        unknown = TRUE;
      else
        records += strtoll(as->records, NULL, 10);
    }
  }
  U8 note[48];
  snprintf(note, 48, "%ld recorded", a->asset_count);
  I64 ry = CardHead(a, CX0, y, lw, "Affected systems", note);
  if (a->asset_count == 0) {
    Text(c, F_BODY, CX0 + 16, ry + 16, "Nothing recorded yet. Add each server, database or", C_MUTED, lw - 32);
    Text(c, F_BODY, CX0 + 16, ry + 34, "file share as soon as you know it was touched.", C_MUTED, lw - 32);
    Button(a, CX0 + 16, ry + 66, 180, 36, "Add affected system", BTN_PRIMARY, H_SCOPE_OPEN);
  } else {
    U8 num[32], line[128];
    Commas(records, num);
    if (unknown)
      snprintf(line, 128, "%ld exfiltrated or encrypted, at least %s records, some counts unknown", hit, num);
    else
      snprintf(line, 128, "%ld exfiltrated or encrypted, %s records", hit, num);
    Text(c, F_SMALL, CX0 + 16, ry + 10, line, C_MUTED, lw - 32);
    ry += 30;
    for (I64 i = 0; i < a->asset_count && i < 4; i++) {
      Asset *as = &a->assets[i];
      Text(c, F_SEMI, CX0 + 16, ry + 7, as->name, C_TEXT, 170);
      U8 detail[64], cnt[24];
      if (StrCmp(as->records, "?") == 0)
        StrCpy(cnt, "? records");
      else {
        Commas(strtoll(as->records, NULL, 10), num);
        snprintf(cnt, 24, "%s records", num);
      }
      snprintf(detail, 64, "%s  %s", as->type, cnt);
      Text(c, F_SMALL, CX0 + 196, ry + 8, detail, C_MUTED, lw - 196 - 130);
      Badge(a, CX0 + lw - 16 - TextWidth(c, F_LABEL, as->status) - 14, ry + 16, as->status, StatusColor(as->status));
      ry += 32;
    }
    if (a->asset_count > 4) {
      U8 more[32];
      snprintf(more, 32, "+%ld more on the Scope page", a->asset_count - 4);
      Text(c, F_SMALL, CX0 + 16, ry + 2, more, C_FAINT);
    }
  }

  I64 rx = CX0 + lw + 16;
  Card(a, rx, y, rw, h);
  ry = CardHead(a, rx, y, rw, "Needs attention");
  I64 items = 0;
  if (UnackedAlerts(a) > 0) {
    U8 line[80];
    if (UnackedAlerts(a) == 1)
      StrCpy(line, "1 alert for the manager");
    else
      snprintf(line, 80, "%ld alerts for the manager", UnackedAlerts(a));
    Dot(c, rx + 20, ry + 20, 8, C_RED);
    Text(c, F_SEMI, rx + 32, ry + 11, line, C_RED_FG, rw - 172);
    Button(a, rx + rw - 136, ry + 4, 120, 30, "Acknowledge", BTN_GHOST, H_ACK);
    ry += 40;
    items++;
  }
  if (a->sus_open > 0 && !IsAdmin(a->st)) {
    U8 line[80];
    if (a->sus_open == 1)
      StrCpy(line, "1 suspicious server event to check");
    else
      snprintf(line, 80, "%ld suspicious server events to check", a->sus_open);
    Dot(c, rx + 20, ry + 20, 8, C_RED);
    Text(c, F_SEMI, rx + 32, ry + 11, line, C_RED_FG, rw - 140);
    Button(a, rx + rw - 92, ry + 4, 76, 30, "Review", BTN_GHOST, H_NAV, V_SERVER);
    ry += 40;
    items++;
  }
  if (IsCut(a)) {
    Dot(c, rx + 20, ry + 20, 8, C_RED);
    Text(c, F_BODY, rx + 32, ry + 11, "Internet cut on this machine. ARK runs on the relay.", C_TEXT, rw - 48);
    ry += 40;
    items++;
  }
  if (a->team.join_pending && IsAdmin(a->st)) {
    U8 line[80];
    snprintf(line, 80, "%s asks to join the team", a->team.join_name);
    Dot(c, rx + 20, ry + 20, 8, C_CYAN);
    Text(c, F_BODY, rx + 32, ry + 11, line, C_TEXT, rw - 130);
    Button(a, rx + rw - 92, ry + 4, 76, 30, "Review", BTN_GHOST, H_NAV, V_TEAM);
    ry += 40;
    items++;
  }
  I64 problems = ProblemCount(a);
  if (problems > 0) {
    U8 line[80];
    snprintf(line, 80, "%ld log problems: entries failed a check", problems);
    Dot(c, rx + 20, ry + 20, 8, C_RED);
    Text(c, F_BODY, rx + 32, ry + 11, line, C_RED_FG, rw - 48);
    ry += 40;
    items++;
  }
  for (I64 i = 0; i < n && items < 4; i++) {
    I64 left = clocks[i].due - time(NULL);
    if (left >= 7 * 86400)
      continue;
    U8 line[96], rem[24];
    RemainingText(left, rem);
    snprintf(line, 96, "%s: %s", g_rule_who[clocks[i].rule], rem);
    Dot(c, rx + 20, ry + 20, 8, C_AMBER);
    Text(c, F_BODY, rx + 32, ry + 11, line, C_TEXT, rw - 48);
    ry += 40;
    items++;
  }
  for (I64 i = 0; i < a->asset_count && items < 4; i++) {
    Asset *as = &a->assets[i];
    if (StrCmp(as->records, "?") != 0)
      continue;
    if (StrCmp(as->status, "EXFILTRATED") != 0 && StrCmp(as->status, "ENCRYPTED") != 0)
      continue;
    U8 line[96];
    snprintf(line, 96, "%s: record count unknown", as->name);
    Dot(c, rx + 20, ry + 20, 8, C_AMBER);
    Text(c, F_BODY, rx + 32, ry + 11, line, C_TEXT, rw - 48);
    ry += 40;
    items++;
  }
  if (items == 0) {
    Text(c, F_BODY, rx + 16, ry + 16, "Nothing is waiting on you.", C_MUTED);
    Text(c, F_SMALL, rx + 16, ry + 38, "Join requests, broken entries and close", C_FAINT);
    Text(c, F_SMALL, rx + 16, ry + 54, "deadlines show up here.", C_FAINT);
  }

  y += h + 16;
  I64 lh = (g_ch - 20 - COMPOSE_H) - 16 - y;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), lh);
  ry = CardHead(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), "Latest in the chat log");
  Button(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 112, y + 6, 100, 30, "Open chat", BTN_GHOST, H_NAV, V_LOG);
  if (log->count == 0)
    Text(c, F_BODY, CX0 + 16, ry + 16, "Nothing logged yet. Write the first note below.", C_FAINT);
  else
    LogList(a, CX0, ry, (g_cw - SIDE_W - PANEL_W - 2 * PAD), y + lh - ry, 0, FALSE);
  DrawComposer(a);
}

U0 DrawLogPage(App *a)
{
  Canvas *c = a->cv;
  Log *log = a->st->log;
  U8 sub[128], num[24];
  Commas(log->count - EventCount(a), num);
  snprintf(sub, 128, "%s entries: notes, chat, alerts and decisions. Each is signed and chained.", num);
  PageHead(a, "Chat log", sub);

  I64 x = CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD);
  for (I64 f = 4; f >= 0; f--) {
    I64 w = TextWidth(c, F_MED, g_filter_names[f]) + 26;
    x -= w;
    Bool on = a->filter == f;
    U32 bg = C_BG, border = C_LINE2, fg = C_MUTED;
    if (on) {
      bg = C_RAISED;
      border = C_CYAN;
      fg = C_TEXT;
    } else if (Hover(a, x, TOP_H + 22, w, 32)) {
      fg = C_TEXT;
    }
    Box(c, x, TOP_H + 22, w, 32, 6, bg, border);
    TextMid(c, F_MED, x + 13, TOP_H + 38, g_filter_names[f], fg);
    AddHit(a, x, TOP_H + 22, w, 32, H_FILTER, f);
    x -= 6;
  }

  I64 y = TOP_H + 84;
  Field *q = &a->fields[FLD_SEARCH];
  if (q->len > 0) {
    U8 line[256];
    snprintf(line, 256, "Showing entries that contain \"%s\"", q->text);
    Text(c, F_BODY, CX0, y + 2, line, C_CYAN_FG, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 140);
    Button(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 120, y - 6, 120, 30, "Clear search", BTN_GHOST, H_SEARCH_CLR);
    y += 34;
  }
  I64 h = (g_ch - 20 - COMPOSE_H) - 16 - y;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), h);
  if (log->count == 0) {
    Text(c, F_H2, CX0 + 20, y + 24, "Nothing logged yet", C_TEXT);
    Text(c, F_BODY, CX0 + 20, y + 50, "Write what was seen first, where and by whom. Times and names are added for you.", C_MUTED);
  } else {
    LogList(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), h, a->scroll, TRUE);
    if (a->scroll > 0) {
      U8 note[64];
      snprintf(note, 64, "Scrolled back %ld. PgDn or wheel for newer.", a->scroll);
      I64 nw = TextWidth(c, F_SMALL, note) + 20;
      Round(c, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - nw - 12, y + h - 34, nw, 24, 4, C_RAISED);
      TextMid(c, F_SMALL, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - nw - 2, y + h - 22, note, C_MUTED);
    }
  }
  DrawComposer(a);
}


#define ROW_H 34

U0 DrawServerPage(App *a)
{
  Canvas *c = a->cv;
  Log *log = a->st->log;
  U8 sub[160];
  I64 events = EventCount(a);
  if (a->sus_open == 1)
    StrCpy(sub, "1 suspicious event nobody has reported yet.");
  else if (a->sus_open > 1)
    snprintf(sub, 160, "%ld suspicious events nobody has reported yet.", a->sus_open);
  else
    StrCpy(sub, "Commands, logins and requests on the server, newest first.");
  PageHead(a, "Server log", sub);

  I64 x = CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD);
  for (I64 f = 4; f >= 0; f--) {
    I64 w = TextWidth(c, F_MED, g_sfilter_names[f]) + 26;
    x -= w;
    Bool on = a->server_filter == f;
    U32 bg = C_BG, border = C_LINE2, fg = C_MUTED;
    if (on && f == SF_SUS) {
      bg = Mix(C_RED, C_BG, 40);
      border = C_RED;
      fg = C_RED_FG;
    } else if (on) {
      bg = C_RAISED;
      border = C_CYAN;
      fg = C_TEXT;
    } else if (Hover(a, x, TOP_H + 22, w, 32)) {
      fg = C_TEXT;
    }
    Box(c, x, TOP_H + 22, w, 32, 6, bg, border);
    TextMid(c, F_MED, x + 13, TOP_H + 38, g_sfilter_names[f], fg);
    AddHit(a, x, TOP_H + 22, w, 32, H_SFILTER, f);
    x -= 6;
  }

  I64 y = TOP_H + 84;
  Field *q = &a->fields[FLD_SEARCH];
  if (q->len > 0) {
    U8 line[256];
    snprintf(line, 256, "Showing events that contain \"%s\"", q->text);
    Text(c, F_BODY, CX0, y + 2, line, C_CYAN_FG, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 140);
    Button(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 120, y - 6, 120, 30, "Clear search", BTN_GHOST, H_SEARCH_CLR);
    y += 34;
  }

  I64 detail_h = 150;
  I64 h = g_ch - 20 - detail_h - 16 - y;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), h);
  // Column header.
  I64 cw = CX0 + 16, cu = CX0 + 92, ct = CX0 + 262, cd = CX0 + 360, dw = (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 360 - 128;
  Text(c, F_LABEL, cw, y + 14, "TIME", C_FAINT);
  Text(c, F_LABEL, cu, y + 14, "WHO, WHERE", C_FAINT);
  Text(c, F_LABEL, ct, y + 14, "TYPE", C_FAINT);
  Text(c, F_LABEL, cd, y + 14, "COMMAND OR REQUEST", C_FAINT);
  TextRight(c, F_LABEL, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16, y + 14, "RISK", C_FAINT);
  HLine(c, CX0 + 1, y + 38, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, C_LINE);

  if (events == 0) {
    Text(c, F_H2, CX0 + 20, y + 60, "No server events yet", C_TEXT);
    Text(c, F_BODY, CX0 + 20, y + 88, "Start the watcher on the server this station runs on:", C_MUTED);
    U8 cmd[320];
    snprintf(cmd, 320, "tools/ark-watch %s", a->st->dir);
    Box(c, CX0 + 20, y + 114, MinI64((g_cw - SIDE_W - PANEL_W - 2 * PAD) - 40, TextWidth(c, F_MONO, cmd) + 28), 34, 6, C_BG, C_LINE2);
    TextMid(c, F_MONO, CX0 + 34, y + 131, cmd, C_CYAN_FG, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 68);
    Text(c, F_BODY, CX0 + 20, y + 166, "It sends shell commands, sudo, logins and failed logins here, signed by this station.", C_MUTED, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 40);
  }

  LogSorted(log, a->order);
  I64 ry = y + 39, skip = a->server_scroll, shown = 0;
  for (I64 k = log->count - 1; k >= 0; k--) {
    I64 idx = a->order[k];
    Entry *e = &log->entries[idx];
    Event ev;
    if (e->kind != KIND_EVENT || !EventFromBody(e->body, &ev))
      continue;
    if (!ServerPasses(a, idx, &ev))
      continue;
    if (skip > 0) {
      skip--;
      continue;
    }
    if (ry + ROW_H > y + h - 2)
      break;
    Bool sel = a->selected == idx;
    if (sel)
      Fill(c, CX0 + 1, ry, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, ROW_H - 1, C_RAISED);
    else if (Hover(a, CX0, ry, (g_cw - SIDE_W - PANEL_W - 2 * PAD), ROW_H))
      Fill(c, CX0 + 1, ry, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, ROW_H - 1, Mix(C_RAISED, C_SURFACE, 110));
    I64 cy = ry + ROW_H / 2;
    U8 clock[12], who[96];
    Tm tm;
    localtime_r(&e->time, &tm);
    snprintf(clock, 12, "%02d:%02d:%02d", tm.hour, tm.min, tm.sec);
    TextMid(c, F_MONO, cw, cy, clock, C_FAINT);
    if (StrCmp(ev.user, "-") == 0)
      CopyText(who, ev.host, 96);
    else
      snprintf(who, 96, "%s@%s", ev.user, ev.host);
    U32 wc = C_TEXT;
    if (StrCmp(ev.user, "root") == 0)
      wc = C_AMBER_FG;
    TextMid(c, F_SEMI, cu, cy, who, wc, ct - cu - 10);
    TextMid(c, F_SMALL, ct, cy, g_ev_label[ev.source], C_MUTED, cd - ct - 10);
    U32 dc = C_TEXT;
    if (a->risk[idx] == RISK_SUS)
      dc = C_RED_FG;
    TextMid(c, F_MONO, cd, cy, ev.detail, dc, dw);
    if (a->risk[idx] == RISK_SUS) {
      if (ReportOf(a, e) != NULL)
        Badge(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_LABEL, "REPORTED") - 14, cy, "REPORTED", C_PURPLE);
      else
        Badge(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_LABEL, "SUSPICIOUS") - 14, cy, "SUSPICIOUS", C_RED);
    } else if (a->risk[idx] == RISK_WATCH) {
      Badge(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_LABEL, "WATCH") - 14, cy, "WATCH", C_AMBER);
    }
    HLine(c, CX0 + 1, ry + ROW_H - 1, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, C_ROWLINE);
    AddHit(a, CX0, ry, (g_cw - SIDE_W - PANEL_W - 2 * PAD), ROW_H, H_EVENT, idx);
    ry += ROW_H;
    shown++;
  }
  if (shown == 0 && events > 0)
    TextMid(c, F_BODY, CX0 + 16, y + 64, "No events match. Clear the search or pick All.", C_FAINT);
  if (a->server_scroll > 0) {
    U8 note[64];
    snprintf(note, 64, "%ld newer above. PgUp or wheel up.", a->server_scroll);
    I64 nw = TextWidth(c, F_SMALL, note) + 20;
    Round(c, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - nw - 12, y + h - 34, nw, 24, 4, C_RAISED);
    TextMid(c, F_SMALL, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - nw - 2, y + h - 22, note, C_MUTED);
  }

  // The picked event in full, and the report button.
  I64 dy = y + h + 16;
  Entry *e = NULL;
  Event ev;
  if (a->selected >= 0 && a->selected < log->count) {
    e = &log->entries[a->selected];
    if (e->kind != KIND_EVENT || !EventFromBody(e->body, &ev))
      e = NULL;
  }
  if (e == NULL) {
    Card(a, CX0, dy, (g_cw - SIDE_W - PANEL_W - 2 * PAD), detail_h);
    Text(c, F_SEMI, CX0 + 20, dy + 22, "Pick an event", C_TEXT);
    Text(c, F_BODY, CX0 + 20, dy + 48, "Click a row to see the whole command, why it was flagged, and to report it to the manager.", C_MUTED, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 40);
    Text(c, F_SMALL, CX0 + 20, dy + 76, "SUSPICIOUS: matches a known attack step. WATCH: normal on its own, worth a look in a pattern.", C_FAINT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 40);
    return;
  }
  I64 risk = a->risk[a->selected];
  U32 edge = C_LINE2;
  if (risk == RISK_SUS)
    edge = C_RED;
  else if (risk == RISK_WATCH)
    edge = C_AMBER;
  Box(c, CX0, dy, (g_cw - SIDE_W - PANEL_W - 2 * PAD), detail_h, 8, C_SURFACE, edge);
  U8 head[200], when[32], station[NAME_MAX];
  DateText(e->time, when);
  NameOf(log, e->author, station);
  if (StrCmp(ev.user, "-") == 0)
    snprintf(head, 200, "%s to %s", g_ev_label[ev.source], ev.host);
  else
    snprintf(head, 200, "%s on %s, %s", ev.user, ev.host, g_ev_label[ev.source]);
  Text(c, F_H2, CX0 + 20, dy + 16, head, C_TEXT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 260);
  U8 meta[160];
  snprintf(meta, 160, "%s. Seen by %s's station, signed.", when, station);
  Text(c, F_SMALL, CX0 + 20, dy + 40, meta, C_FAINT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 260);
  I64 starts[2], lens[2];
  I64 n = Wrap(c, F_MONO, ev.detail, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 40, starts, lens, 2);
  Round(c, CX0 + 16, dy + 62, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 32, 16 + n * 18, 6, C_BG);
  for (I64 i = 0; i < n; i++)
    Text(c, F_MONO, CX0 + 26, dy + 70 + i * 18, ev.detail + starts[i], C_TEXT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 52, lens[i]);
  U8 why[160];
  if (risk == RISK_NONE)
    StrCpy(why, "Nothing about this matches the attack patterns ARK knows.");
  else
    snprintf(why, 160, "Flagged because it %s.", a->why[a->selected]);
  U32 wcol = C_MUTED;
  if (risk == RISK_SUS)
    wcol = C_RED_FG;
  else if (risk == RISK_WATCH)
    wcol = C_AMBER_FG;
  Text(c, F_SEMI, CX0 + 20, dy + detail_h - 30, why, wcol, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 260);

  Entry *rep = ReportOf(a, e);
  I64 bx = CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 216, bw = 196;
  if (rep != NULL) {
    U8 by[NAME_MAX], line[96], t[8];
    NameOf(log, rep->author, by);
    ClockText(rep->time, t);
    snprintf(line, 96, "Reported by %s at %s", by, t);
    TextRight(c, F_SEMI, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 20, dy + 22, line, C_PURPLE_FG);
  } else if (IsAdmin(a->st)) {
    TextRight(c, F_SMALL, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 20, dy + 22, "Your team reports events to you.", C_FAINT);
  } else {
    Button(a, bx, dy + 14, bw, 36, "Report to manager", BTN_RED, H_REPORT, a->selected);
  }
}

U0 DrawScopeForm(App *a, I64 y)
{
  Canvas *c = a->cv;
  I64 x = CX0, w = (g_cw - SIDE_W - PANEL_W - 2 * PAD);
  Box(c, x, y, w, 452, 8, C_SURFACE, C_CYAN);
  TextMid(c, F_H2, x + 20, y + 24, "Add an affected system or dataset", C_TEXT);
  TextMid(c, F_SMALL, x + w - 20 - TextWidth(c, F_SMALL, "Tab moves between fields. Esc cancels."), y + 24, "Tab moves between fields. Esc cancels.", C_FAINT);
  HLine(c, x + 1, y + 47, w - 2, C_LINE);

  I64 fy = y + 62;
  Text(c, F_SEMI, x + 20, fy, "System or dataset", C_TEXT);
  Input(a, FLD_ASSET, x + 20, fy + 22, 300, 38, "e.g. HR-DB or Payroll share");
  Text(c, F_SEMI, x + 352, fy, "Whose data: residents of", C_TEXT);
  Text(c, F_SMALL, x + 540, fy + 1, "decides which laws apply", C_FAINT);
  Input(a, FLD_WHERE, x + 352, fy + 22, 90, 38, "code");
  I64 bx = x + 452;
  Field *wf = &a->fields[FLD_WHERE];
  for (I64 i = 0; i < 5; i++) {
    Bool on = StrCmp(wf->text, g_where_picks[i]) == 0;
    U32 bg = C_BG, border = C_LINE2;
    if (on) {
      bg = Mix(C_CYAN, C_SURFACE, 30);
      border = C_CYAN;
    } else if (Hover(a, bx, fy + 22, 64, 38)) {
      border = Mix(0xFFFFFFFF, C_LINE2, 30);
    }
    Box(c, bx, fy + 22, 64, 38, 6, bg, border);
    TextMid(c, F_MED, bx + (64 - TextWidth(c, F_MED, g_where_labels[i])) / 2, fy + 41, g_where_labels[i], C_TEXT);
    AddHit(a, bx, fy + 22, 64, 38, H_WHERE, i);
    bx += 70;
  }

  fy += 76;
  Text(c, F_SEMI, x + 20, fy, "What kind of data it holds", C_TEXT);
  I64 tw = (w - 40 - 4 * 8) / 5;
  for (I64 i = 0; i < 5; i++)
    Choice(a, x + 20 + i * (tw + 8), fy + 22, tw, 54, g_data_types[i], g_type_short[i], a->scope_type == i, 0, H_TYPE, i);

  fy += 92;
  Text(c, F_SEMI, x + 20, fy, "How many people", C_TEXT);
  Input(a, FLD_RECORDS, x + 20, fy + 22, 160, 38, "e.g. 4120");
  Choice(a, x + 190, fy + 22, 120, 38, "Unknown", NULL, a->scope_unknown, 0, H_UNKNOWN, 0);
  Text(c, F_SMALL, x + 328, fy + 26, "An estimate is fine; you can update it later.", C_MUTED);
  Text(c, F_SMALL, x + 328, fy + 43, "250 or more Texans also means notifying the Texas Attorney General.", C_MUTED);

  fy += 76;
  Text(c, F_SEMI, x + 20, fy, "What happened to it", C_TEXT);
  Text(c, F_SMALL, x + 172, fy + 1, "Exfiltrated or Encrypted starts the legal clocks", C_FAINT);
  for (I64 i = 0; i < 5; i++)
    Choice(a, x + 20 + i * (tw + 8), fy + 22, tw, 54, g_scope_status[i], g_status_short[i], a->scope_status == i,
           StatusColor(g_scope_status[i]), H_STATUS, i);

  fy += 92;
  HLine(c, x + 1, fy - 2, w - 2, C_LINE);
  if (a->scope_error[0])
    TextMid(c, F_MED, x + 20, fy + 24, a->scope_error, C_RED_FG, w - 300);
  else
    TextMid(c, F_SMALL, x + 20, fy + 24, "Saving adds a signed entry. To change a system later, add it again with the same name.", C_FAINT, w - 300);
  Button(a, x + w - 20 - 140, fy + 6, 140, 36, "Save to log", BTN_PRIMARY, H_SCOPE_SAVE);
  Button(a, x + w - 20 - 140 - 10 - 96, fy + 6, 96, 36, "Cancel", BTN_GHOST, H_SCOPE_SHUT);
}

U0 DrawScopePage(App *a)
{
  Canvas *c = a->cv;
  PageHead(a, "Scope", "Systems that were hit and their latest status. Each change is a new log entry.");
  if (!a->scope_open)
    Button(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 190, TOP_H + 22, 190, 36, "Add affected system", BTN_PRIMARY, H_SCOPE_OPEN);
  I64 y = TOP_H + 84;
  if (a->scope_open) {
    DrawScopeForm(a, y);
    y += 468;
  }
  CollectAssets(a);
  I64 h = g_ch - 20 - y;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), h);
  I64 cols[6] = {16, 236, 336, 446, 556, 716};
  U8 *heads[6] = {"System", "Data", "Residents", "Records", "Status", "Updated"};
  for (I64 i = 0; i < 6; i++)
    TextMid(c, F_LABEL, CX0 + cols[i], y + 20, heads[i], C_FAINT);
  HLine(c, CX0 + 1, y + 40, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, C_LINE);
  if (a->asset_count == 0) {
    Text(c, F_BODY, CX0 + 16, y + 58, "No affected systems yet. Use Add affected system for each one you find.", C_FAINT);
    return;
  }
  Clip(c, CX0 + 1, y + 41, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, h - 42);
  I64 ry = y + 41;
  for (I64 i = 0; i < a->asset_count; i++) {
    Asset *as = &a->assets[i];
    I64 cy = ry + 22;
    TextMid(c, F_SEMI, CX0 + cols[0], cy, as->name, C_TEXT, 210);
    TextMid(c, F_BODY, CX0 + cols[1], cy, as->type, C_TEXT);
    U8 *where = as->where;
    if (StrCmp(where, "-") == 0)
      where = "none";
    TextMid(c, F_BODY, CX0 + cols[2], cy, where, C_TEXT);
    U8 num[32];
    if (StrCmp(as->records, "?") == 0)
      StrCpy(num, "unknown");
    else
      Commas(strtoll(as->records, NULL, 10), num);
    TextMid(c, F_BODY, CX0 + cols[3], cy, num, C_TEXT);
    Badge(a, CX0 + cols[4], cy, as->status, StatusColor(as->status));
    U8 when[32], name[NAME_MAX], line[64];
    DateText(as->time, when);
    NameOf(a->st->log, as->author, name);
    snprintf(line, 64, "%s, %s", when, name);
    TextMid(c, F_SMALL, CX0 + cols[5], cy, line, C_MUTED, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - cols[5] - 16);
    HLine(c, CX0 + 1, ry + 43, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, C_ROWLINE);
    ry += 44;
  }
  ClipAll(c);
}

U8 *g_rule_when[RULES] = {
  "TX residents' personal data", "250+ TX residents' personal data", "CA residents' personal data",
  "NY residents' personal data", "any personal data of EU residents", "health records (PHI), anyone"
};
U8 *g_rule_span[RULES] = {"60 days", "30 days", "30 days", "30 days", "72 hours", "60 days"};

U0 DrawClocksPage(App *a)
{
  Canvas *c = a->cv;
  PageHead(a, "Breach clocks", "Notice deadlines, counted from the first entry that marked matching data stolen or encrypted.");
  Log *log = a->st->log;
  Clock clocks[RULES];
  I64 n = Deadlines(log, clocks);
  I64 y = TOP_H + 84;

  I64 h = 43 + MaxI64(1, n) * 64 + 8;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), h);
  I64 ry = CardHead(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), "Running", "A reminder for counsel, not legal advice");
  if (n == 0) {
    Text(c, F_BODY, CX0 + 16, ry + 14, "None running. Marking a system Exfiltrated or Encrypted on the Scope page starts the matching clocks.", C_MUTED, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 32);
    Text(c, F_SMALL, CX0 + 16, ry + 36, "Suspected, Contained and Clean never start a clock.", C_FAINT);
  }
  I64 now = time(NULL);
  for (I64 i = 0; i < n; i++) {
    I64 left = clocks[i].due - now;
    U8 rem[24], due[32], start[32], who[96], dueline[48], startline[48];
    RemainingText(left, rem);
    DayDateText(clocks[i].due, due);
    DateText(clocks[i].due - g_rule_hours[clocks[i].rule] * 3600, start);
    Text(c, F_H1, CX0 + 16, ry + 18, rem, RemainingColor(left), 200);
    if (clocks[i].unsure)
      snprintf(who, 96, "Notify %s (only if 250+ records)", g_rule_who[clocks[i].rule]);
    else
      snprintf(who, 96, "Notify %s", g_rule_who[clocks[i].rule]);
    Text(c, F_SEMI, CX0 + 236, ry + 14, who, C_TEXT, 380);
    Text(c, F_MONO, CX0 + 236, ry + 36, g_rule_cite[clocks[i].rule], C_FAINT);
    snprintf(dueline, 48, "Due %s", due);
    snprintf(startline, 48, "Started %s", start);
    Text(c, F_BODY, CX0 + 640, ry + 14, dueline, C_TEXT);
    Text(c, F_SMALL, CX0 + 640, ry + 36, startline, C_FAINT);
    if (i < n - 1)
      HLine(c, CX0 + 1, ry + 63, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, C_ROWLINE);
    ry += 64;
  }

  y += h + 16;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 43 + RULES * 44 + 8);
  ry = CardHead(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), "Every rule ARK tracks");
  for (I64 r = 0; r < RULES; r++) {
    I64 cy = ry + 22;
    TextMid(c, F_SEMI, CX0 + 16, cy, g_rule_who[r], C_TEXT, 220);
    TextMid(c, F_MONO, CX0 + 246, cy, g_rule_cite[r], C_FAINT, 230);
    TextMid(c, F_BODY, CX0 + 486, cy, g_rule_span[r], C_TEXT);
    TextMid(c, F_SMALL, CX0 + 566, cy, g_rule_when[r], C_MUTED, 220);
    U8 *state = "NOT STARTED";
    U32 scol = C_FAINT;
    if (ClockStarted(clocks, n, r)) {
      state = "RUNNING";
      scol = C_AMBER;
    }
    Badge(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - 14 - TextWidth(c, F_LABEL, state), cy, state, scol);
    if (r < RULES - 1)
      HLine(c, CX0 + 1, ry + 43, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, C_ROWLINE);
    ry += 44;
  }
}

// The six-digit join code, large enough to read across a table.
U0 BigCode(App *a, I64 x, I64 y, I64 code, U32 color)
{
  U8 text[16];
  snprintf(text, 16, "%03ld %03ld", code / 1000, code % 1000);
  Canvas *c = a->cv;
  for (I64 i = 0; text[i]; i++) {
    U8 one[2];
    one[0] = text[i];
    one[1] = 0;
    Text(c, F_BIG, x, y, one, color);
    x += 34;
  }
}

U0 DrawTeamPage(App *a)
{
  Canvas *c = a->cv;
  PageHead(a, "Team", "Everyone admitted to this incident. Only the manager can admit people.");
  I64 y = TOP_H + 84;
  if (a->team.join_pending && IsAdmin(a->st)) {
    Box(c, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 150, 8, Mix(C_CYAN, C_SURFACE, 20), C_CYAN);
    U8 line[96];
    snprintf(line, 96, "%s asks to join", a->team.join_name);
    Text(c, F_H2, CX0 + 20, y + 18, line, C_TEXT);
    Text(c, F_BODY, CX0 + 20, y + 44, "Ask them to read the code on their screen out loud.", C_MUTED);
    BigCode(a, CX0 + 20, y + 70, JoinCode(a->team.join_pk), C_CYAN_FG);
    Text(c, F_BODY, CX0 + 300, y + 76, "Approve only if it matches exactly.", C_TEXT);
    Text(c, F_SMALL, CX0 + 300, y + 98, "A different code means a different device is asking. Don't approve it.", C_MUTED);
    Button(a, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 20 - 150, y + 20, 150, 40, "Approve", BTN_GREEN, H_APPROVE);
    y += 166;
  }
  CollectMembers(a);
  I64 h = 43 + MaxI64(1, a->member_count) * 48 + 8;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), h);
  I64 online = 0;
  for (I64 i = 0; i < a->member_count; i++)
    if (PeerOnline(a, a->members[i].pk))
      online++;
  U8 note[48];
  if (a->member_count == 1)
    snprintf(note, 48, "1 member, %ld online", online);
  else
    snprintf(note, 48, "%ld members, %ld online", a->member_count, online);
  I64 ry = CardHead(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), "Members", note);
  for (I64 i = 0; i < a->member_count; i++) {
    Member *m = &a->members[i];
    I64 cy = ry + 24;
    Bool on = PeerOnline(a, m->pk);
    U32 dot = C_FAINT;
    if (on)
      dot = C_GREEN;
    Dot(c, CX0 + 24, cy, 10, dot);
    I64 nx = TextMid(c, F_SEMI, CX0 + 40, cy, m->name, C_TEXT, 200);
    if (Same(m->pk, a->st->pk, PK_BYTES))
      TextMid(c, F_SMALL, nx + 8, cy, "you", C_FAINT);
    if (m->admin)
      Badge(a, CX0 + 260, cy, "MANAGER", C_CYAN);
    else
      Badge(a, CX0 + 260, cy, "MEMBER", C_FAINT);
    U8 when[32], line[48], fp[32];
    DateText(m->time, when);
    if (m->admin)
      snprintf(line, 48, "opened %s", when);
    else
      snprintf(line, 48, "admitted %s", when);
    TextMid(c, F_SMALL, CX0 + 370, cy, line, C_MUTED);
    Fingerprint(m->pk, fp);
    TextMid(c, F_MONO, CX0 + 560, cy, fp, C_FAINT);
    if (on)
      TextMid(c, F_SMALL, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_SMALL, "online"), cy, "online", C_GREEN_FG);
    else
      TextMid(c, F_SMALL, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_SMALL, "not heard"), cy, "not heard", C_FAINT);
    if (i < a->member_count - 1)
      HLine(c, CX0 + 1, ry + 47, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 2, C_ROWLINE);
    ry += 48;
  }

  y += h + 16;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 150);
  ry = CardHead(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), "Adding someone");
  Text(c, F_BODY, CX0 + 16, ry + 14, "1.  They start ARK on a clean laptop, pick a name and passphrase, then choose Join.", C_TEXT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 32);
  Text(c, F_BODY, CX0 + 16, ry + 38, "2.  A request appears here and the panel beeps. They read their six-digit code out loud.", C_TEXT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 32);
  Text(c, F_BODY, CX0 + 16, ry + 62, "3.  If it matches, the manager presses Approve. They get the team key and the whole log.", C_TEXT, (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 32);

  y += 166;
  I64 cw = g_cw - SIDE_W - PANEL_W - 2 * PAD;
  Card(a, CX0, y, cw, 96);
  Text(c, F_H2, CX0 + 20, y + 18, "Start over on this laptop", C_TEXT);
  Text(c, F_SMALL, CX0 + 20, y + 44, "Deletes this station's keys, log, reports and server feed here, then goes back to setup.", C_MUTED, cw - 240);
  Text(c, F_SMALL, CX0 + 20, y + 62, "Other stations keep their copy of the incident.", C_MUTED, cw - 240);
  U8 *label = "Clear this station";
  if (a->clear_armed != 0 && time(NULL) - a->clear_armed <= 3)
    label = "Press again";
  Button(a, CX0 + cw - 200, y + 28, 180, 40, label, BTN_RED, H_CLEAR);
}

U0 DrawNetworkPage(App *a)
{
  Canvas *c = a->cv;
  PageHead(a, "Network", "How entries travel between stations. The relay only forwards sealed envelopes.");
  I64 y = TOP_H + 84;
  I64 online = OnlineCount(a);
  Entry *net = LastNetwork(a, FALSE);
  if (net != NULL) {
    U8 name[NAME_MAX], when[32], head[128];
    NameOf(a->st->log, net->author, name);
    DateText(net->time, when);
    Bool cut = StrNCmp(net->body, "Cut", 3) == 0;
    U32 col = C_GREEN;
    if (cut)
      col = C_RED;
    snprintf(head, 128, "%s: %s", when, name);
    Box(c, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 60, 8, Mix(col, C_BG, 30), col);
    Text(c, F_SEMI, CX0 + 16, y + 12, head, LightOf(col));
    Text(c, F_SMALL, CX0 + 16, y + 34, net->body, LightOf(col), (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 32);
    y += 76;
  }
  if (a->link.fd < 0 || online == 0) {
    U32 col = C_AMBER;
    U8 *head = "No other station heard in the last 9 seconds";
    if (a->link.fd < 0) {
      col = C_RED;
      head = "This station has no relay port";
    }
    Box(c, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 60, 8, Mix(col, C_BG, 30), col);
    Text(c, F_SEMI, CX0 + 16, y + 12, head, LightOf(col));
    Text(c, F_SMALL, CX0 + 16, y + 34, "Keep working. Entries are signed and saved here, and other stations fetch them once the link is back.", LightOf(col), (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 32);
    y += 76;
  }

  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 172);
  I64 bw = 220, by = y + 28, bh = 116;
  // This station.
  Box(c, CX0 + 24, by, bw, bh, 10, C_BG, C_LINE2);
  Text(c, F_H2, CX0 + 40, by + 16, "This station", C_TEXT);
  Text(c, F_SMALL, CX0 + 40, by + 40, a->st->name, C_MUTED, bw - 32);
  Text(c, F_MONO, CX0 + 40, by + 60, a->port, C_FAINT, bw - 32);
  U8 count[32];
  snprintf(count, 32, "%ld ENTRIES", a->st->log->count);
  Badge(a, CX0 + 40, by + 92, count, C_GREEN);
  // Relay.
  I64 rx = CX0 + ((g_cw - SIDE_W - PANEL_W - 2 * PAD) - 240) / 2;
  Box(c, rx, by, 240, bh, 10, C_BG, C_PURPLE);
  Text(c, F_H2, rx + (240 - TextWidth(c, F_H2, "Untrusted relay")) / 2, by + 16, "Untrusted relay", C_TEXT);
  Text(c, F_SMALL, rx + (240 - TextWidth(c, F_SMALL, "Arduino UNO Q, own Wi-Fi")) / 2, by + 40, "Arduino UNO Q, own Wi-Fi", C_MUTED);
  I64 bx = rx + (240 - TextWidth(c, F_LABEL, "SEES ONLY CIPHERTEXT") - 14) / 2;
  Badge(a, bx, by + 78, "SEES ONLY CIPHERTEXT", C_PURPLE);
  // Other stations.
  I64 ox = CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 24 - bw;
  Box(c, ox, by, bw, bh, 10, C_BG, C_LINE2);
  Text(c, F_H2, ox + 16, by + 16, "Other stations", C_TEXT);
  I64 py = by + 46, shown = 0;
  I64 now = time(NULL);
  for (I64 i = 0; i < a->team.peer_count && shown < 3; i++) {
    Peer *p = &a->team.peers[i];
    Bool on = now - p->heard <= ONLINE_SECS;
    U32 dot = C_FAINT;
    if (on)
      dot = C_GREEN;
    Dot(c, ox + 22, py, 8, dot);
    TextMid(c, F_BODY, ox + 34, py, p->name, C_TEXT, bw - 50);
    py += 22;
    shown++;
  }
  if (shown == 0)
    TextMid(c, F_SMALL, ox + 16, py, "none heard yet", C_FAINT);
  // Links between them.
  U32 l1 = C_GREEN, l2 = C_GREEN;
  U8 *t1 = "sealed link", *t2 = "sealed link";
  if (a->link.fd < 0) {
    l1 = C_RED;
    t1 = "no link";
  }
  if (online == 0) {
    l2 = C_AMBER;
    t2 = "waiting";
  }
  I64 ax = CX0 + 24 + bw, aw = rx - ax;
  Fill(c, ax + 8, by + bh / 2, aw - 16, 3, l1);
  TextMid(c, F_SMALL, ax + (aw - TextWidth(c, F_SMALL, t1)) / 2, by + bh / 2 - 14, t1, LightOf(l1));
  I64 cx = rx + 240, cw = ox - cx;
  Fill(c, cx + 8, by + bh / 2, cw - 16, 3, l2);
  TextMid(c, F_SMALL, cx + (cw - TextWidth(c, F_SMALL, t2)) / 2, by + bh / 2 - 14, t2, LightOf(l2));

  y += 188;
  I64 hw = ((g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16) / 2;
  Card(a, CX0, y, hw, 132);
  I64 ry = CardHead(a, CX0, y, hw, "What the relay can see");
  Text(c, F_BODY, CX0 + 16, ry + 14, "Sealed envelopes, their size and when they", C_MUTED);
  Text(c, F_BODY, CX0 + 16, ry + 32, "were sent.", C_MUTED);
  Text(c, F_BODY, CX0 + 16, ry + 56, "Which connection each one came from.", C_MUTED);
  Card(a, CX0 + hw + 16, y, hw, 132);
  ry = CardHead(a, CX0 + hw + 16, y, hw, "What it can't see or do");
  Text(c, F_BODY, CX0 + hw + 32, ry + 14, "Messages, names, scope or record counts.", C_MUTED);
  Text(c, F_BODY, CX0 + hw + 32, ry + 38, "Your keys. It can't forge, change or replay", C_MUTED);
  Text(c, F_BODY, CX0 + hw + 32, ry + 56, "an entry without the other stations noticing.", C_MUTED);

  y += 148;
  Card(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), 43 + 4 * 40 + 8);
  ry = CardHead(a, CX0, y, (g_cw - SIDE_W - PANEL_W - 2 * PAD), "Checks on this station");
  U8 line[96];
  snprintf(line, 96, "%ld", a->st->rejected);
  TextMid(c, F_BODY, CX0 + 16, ry + 20, "Messages rejected (failed the seal or signature check)", C_MUTED);
  TextMid(c, F_SEMI, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_SEMI, line), ry + 20, line, C_TEXT);
  snprintf(line, 96, "%ld", a->st->log->problems);
  TextMid(c, F_BODY, CX0 + 16, ry + 60, "Entries with a broken chain, unknown author or fork", C_MUTED);
  TextMid(c, F_SEMI, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_SEMI, line), ry + 60, line, C_TEXT);
  if (IsCut(a))
    StrCpy(line, "cut");
  else
    StrCpy(line, "on");
  TextMid(c, F_BODY, CX0 + 16, ry + 100, "Internet on this machine (the relay link doesn't use it)", C_MUTED);
  TextMid(c, F_SEMI, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_SEMI, line), ry + 100, line, C_TEXT);
  ry += 40;
  if (a->panel_fd >= 0)
    snprintf(line, 96, "connected on %s", a->panel_port);
  else
    StrCpy(line, "not connected");
  TextMid(c, F_BODY, CX0 + 16, ry + 100, "Hardware panel", C_MUTED);
  TextMid(c, F_SEMI, CX0 + (g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16 - TextWidth(c, F_SEMI, line), ry + 100, line, C_TEXT);
}

U0 GuideBlock(App *a, I64 x, I64 *y, I64 w, U8 *head, U8 **lines)
{
  Canvas *c = a->cv;
  Text(c, F_SEMI, x, *y, head, C_TEXT);
  *y += 24;
  for (I64 i = 0; lines[i] != NULL; i++) {
    Text(c, F_BODY, x, *y, lines[i], C_MUTED, w);
    *y += 20;
  }
  *y += 18;
}

U8 *g_guide_what[] = {
  "A logbook for a cyber incident that never touches the",
  "company network. Every entry is signed by its author",
  "and chained to the one before, so nothing can be",
  "edited or removed later without it showing.", NULL
};
U8 *g_guide_write[] = {
  "Note: what you saw or did. Tagged with the phase.",
  "Chat: talk to the team. Kept in the log too.",
  "Alert: tell the manager something is wrong. Buzzes.",
  "Scope: a system that was hit and what happened to it.",
  "Type anywhere on Overview or Chat log to start a note.", NULL
};
U8 *g_guide_phases[] = {
  "DETECT     confirm what happened and how far it goes",
  "CONTAIN    stop the spread: isolate, block, reset",
  "ERADICATE  remove the attacker and their tools",
  "RECOVER    restore systems, watch for a return",
  "Clicking a phase at the top logs the change for all.", NULL
};
U8 *g_guide_badges[] = {
  "CHAIN BROKEN  an entry before it is missing or changed",
  "NOT A MEMBER  written by someone never admitted",
  "FORKED        one author signed two versions of it",
  "Rejected      messages that failed the seal check", NULL
};
U8 *g_guide_server[] = {
  "Every command typed on the watched server, sudo,",
  "logins and failed logins, and who did it. Rows that",
  "match an attack step are SUSPICIOUS. Click one and",
  "press Report to manager: their panel buzzes.", NULL
};
U8 *g_guide_keys[] = {
  "F1 guide    F2 note    F3 chat    F5 alert",
  "F4 add affected system    F6 server log",
  "F7 report: summary of the incident so far",
  "Ctrl+F search the page you're on",
  "F9 approve a join      F12 twice: lock station",
  "PgUp, PgDn or the wheel scroll the log.", NULL
};
U8 *g_guide_panel[] = {
  "Red CUT takes this machine off the internet, so a",
  "hacker loses any link through it. ARK keeps going",
  "over the relay. Green RESTORE turns it back on,",
  "manager only, after backups and cleanup. The",
  "lights show which state it's in; alerts buzz.", NULL
};

U0 DrawGuidePage(App *a)
{
  PageHead(a, "Guide", "What everything on this screen means.");
  I64 hw = ((g_cw - SIDE_W - PANEL_W - 2 * PAD) - 16) / 2;
  I64 y = TOP_H + 84;
  Card(a, CX0, y, hw, g_ch - 20 - y);
  Card(a, CX0 + hw + 16, y, hw, g_ch - 20 - y);
  I64 ly = y + 24, ry = y + 24;
  GuideBlock(a, CX0 + 20, &ly, hw - 40, "What ARK is", g_guide_what);
  GuideBlock(a, CX0 + 20, &ly, hw - 40, "Server log", g_guide_server);
  GuideBlock(a, CX0 + 20, &ly, hw - 40, "Writing", g_guide_write);
  GuideBlock(a, CX0 + 20, &ly, hw - 40, "Phases", g_guide_phases);
  GuideBlock(a, CX0 + hw + 36, &ry, hw - 40, "Warning badges", g_guide_badges);
  GuideBlock(a, CX0 + hw + 36, &ry, hw - 40, "Keys", g_guide_keys);
  GuideBlock(a, CX0 + hw + 36, &ry, hw - 40, "Hardware panel", g_guide_panel);
}

// ---- setup screens --------------------------------------------------------

U8 *g_steps[4] = {"Your name", "Passphrase", "Start or join", "Incident title"};

U0 DrawSetup(App *a)
{
  Canvas *c = a->cv;
  Fill(c, 0, 0, 520, g_ch, C_PANEL);
  Fill(c, 519, 0, 1, g_ch, C_LINE);
  Text(c, F_BIG, 56, 72, "ARK", C_TEXT);
  Text(c, F_H2, 56, 132, "An incident logbook that stays", C_MUTED);
  Text(c, F_H2, 56, 154, "off the company network.", C_MUTED);
  Text(c, F_BODY, 56, 204, "Entries are signed on this laptop and travel", C_FAINT);
  Text(c, F_BODY, 56, 222, "sealed through a relay that can't read them.", C_FAINT);

  I64 step = -1;
  if (a->mode == MODE_NEW_NAME)
    step = 0;
  else if (a->mode == MODE_NEW_PASS || a->mode == MODE_NEW_PASS2)
    step = 1;
  else if (a->mode == MODE_NEW_CHOICE)
    step = 2;
  else if (a->mode == MODE_NEW_TITLE)
    step = 3;
  if (step >= 0) {
    for (I64 i = 0; i < 4; i++) {
      I64 y = 300 + i * 52;
      U32 ring = C_LINE2, fg = C_FAINT;
      if (i < step) {
        ring = C_GREEN;
        fg = C_MUTED;
      }
      if (i == step) {
        ring = C_CYAN;
        fg = C_TEXT;
      }
      Box(c, 56, y, 28, 28, 14, C_PANEL, ring);
      U8 num[4];
      snprintf(num, 4, "%ld", i + 1);
      TextMid(c, F_SEMI, 70 - TextWidth(c, F_SEMI, num) / 2, y + 14, num, fg);
      TextMid(c, F_MED, 100, y + 14, g_steps[i], fg);
    }
  }

  I64 x = 600, y = 250, w = 560;
  U8 *title = "", *help = "", *button = "Continue", *hint = "";
  Bool secret = FALSE, field = TRUE;
  if (a->mode == MODE_NEW_NAME) {
    title = "What should the team call you?";
    help = "Shown next to everything you write. Use the name people know you by.";
    hint = "e.g. Dana Kessler";
  } else if (a->mode == MODE_NEW_PASS) {
    title = "Choose a passphrase";
    help = "It seals your keys on this laptop. At least 8 characters; a short sentence works well. Nobody can recover it.";
    secret = TRUE;
  } else if (a->mode == MODE_NEW_PASS2) {
    title = "Type it once more";
    help = "The same passphrase again, to catch typos.";
    secret = TRUE;
  } else if (a->mode == MODE_NEW_TITLE) {
    title = "Name this incident";
    help = "Short and specific. Everyone on the team sees it at the top of every page.";
    hint = "e.g. Ransomware on FS-01";
    button = "Open incident";
  } else if (a->mode == MODE_UNLOCK) {
    title = "This station is locked";
    help = "Enter your passphrase to open its keys and log.";
    secret = TRUE;
    button = "Unlock";
  } else {
    field = FALSE;
  }

  if (a->mode == MODE_NEW_CHOICE) {
    Text(c, F_H1, x, y, "Start an incident, or join one?", C_TEXT);
    Text(c, F_BODY, x, y + 36, "Station created. Its keys are sealed with your passphrase.", C_MUTED);
    I64 cy = y + 80;
    U32 b1 = C_LINE2, b2 = C_LINE2;
    if (Hover(a, x, cy, 270, 150))
      b1 = C_CYAN;
    if (Hover(a, x + 290, cy, 270, 150))
      b2 = C_CYAN;
    Box(c, x, cy, 270, 150, 10, C_SURFACE, b1);
    Text(c, F_H2, x + 20, cy + 22, "Start a new incident", C_TEXT);
    Text(c, F_BODY, x + 20, cy + 52, "You become its admin and", C_MUTED);
    Text(c, F_BODY, x + 20, cy + 70, "decide who joins.", C_MUTED);
    Text(c, F_SMALL, x + 20, cy + 118, "Press S", C_FAINT);
    AddHit(a, x, cy, 270, 150, H_START);
    Box(c, x + 290, cy, 270, 150, 10, C_SURFACE, b2);
    Text(c, F_H2, x + 310, cy + 22, "Join an incident", C_TEXT);
    Text(c, F_BODY, x + 310, cy + 52, "Someone else started it. They", C_MUTED);
    Text(c, F_BODY, x + 310, cy + 70, "admit you after a code check.", C_MUTED);
    Text(c, F_SMALL, x + 310, cy + 118, "Press J", C_FAINT);
    AddHit(a, x + 290, cy, 270, 150, H_JOIN);
  } else if (!field) {
    // Joined, waiting for the admin's key.
    Text(c, F_H1, x, y - 40, "Waiting for the admin", C_TEXT);
    Text(c, F_BODY, x, y - 4, "Read this code out loud to the incident admin:", C_MUTED);
    Box(c, x, y + 30, 300, 90, 10, C_SURFACE, C_CYAN);
    BigCode(a, x + 30, y + 52, JoinCode(a->st->pk), C_CYAN_FG);
    Text(c, F_BODY, x, y + 150, "They see the same code next to your name and approve you.", C_TEXT);
    Text(c, F_BODY, x, y + 172, "If their code is different, someone else is asking. Tell them.", C_MUTED);
    Text(c, F_SMALL, x, y + 214, "This screen moves on by itself once you're admitted.", C_FAINT);
    if (a->link.fd < 0)
      Text(c, F_SEMI, x, y + 250, "No relay port: the request can't go out. Check the cable or Wi-Fi.", C_RED_FG);
  } else {
    Text(c, F_H1, x, y, title, C_TEXT);
    I64 starts[3], lens[3];
    I64 n = Wrap(c, F_BODY, help, w, starts, lens, 3);
    for (I64 i = 0; i < n; i++)
      Text(c, F_BODY, x, y + 38 + i * 20, help + starts[i], C_MUTED, w, lens[i]);
    I64 fy = y + 48 + n * 20;
    Input(a, FLD_SETUP, x, fy, w, 46, hint, secret);
    Button(a, x, fy + 62, 150, 40, button, BTN_PRIMARY, H_CONTINUE);
    Text(c, F_SMALL, x + 166, fy + 75, "or press Enter", C_FAINT);
  }
  if (a->msg[0] && time(NULL) - a->msg_time <= 8)
    Text(c, F_MED, x, 700, a->msg, a->msg_color, w);

  // A way out: someone who opened an incident by mistake, or lost the
  // passphrase, can start over without deleting files by hand.
  I64 by = g_ch - 96;
  if (a->mode == MODE_NEW_PASS || a->mode == MODE_NEW_PASS2) {
    Button(a, x, by, 150, 36, "Start over", BTN_GHOST, H_BACK);
    Text(c, F_SMALL, x + 166, by + 11, "Back to the name. Nothing is saved yet.", C_FAINT);
  } else if (a->mode != MODE_NEW_NAME) {
    U8 *label = "Start over";
    U8 *why = "Deletes this station's keys and log on this laptop. Press twice.";
    if (a->mode == MODE_UNLOCK) {
      label = "Clear station";
      why = "Lost the passphrase? This deletes the station's keys and log here. Press twice.";
    }
    Bool armed = a->clear_armed != 0 && time(NULL) - a->clear_armed <= 3;
    if (armed) {
      label = "Press again";
      why = "Press again within 3 seconds to delete everything and start over.";
    }
    Button(a, x, by, 150, 36, label, BTN_GHOST, H_CLEAR);
    Text(c, F_SMALL, x + 166, by + 11, why, C_FAINT, w - 166);
  }
}

// ---- whole frame ----------------------------------------------------------


// ---- report ---------------------------------------------------------------
//
// The station exports its verified log to DIR/report/export.tsv, one record
// per line, tab separated, and runs tools/ark-report in the background. The
// tool writes DIR/report/report.md and DIR/report/status; PollReport waits
// for the status to say done.

extern "c" I32 rename(U8 *from, U8 *to);
extern "c" I32 unlink(U8 *path);

// Tabs and line breaks separate fields and records, so they become spaces.
U8 *Tsv(U8 *dst, U8 *src, I64 max)
{
  I64 n = 0;
  for (I64 i = 0; src[i] && n < max - 1; i++) {
    U8 ch = src[i];
    if (ch < 32)
      ch = ' ';
    dst[n++] = ch;
  }
  dst[n] = 0;
  return dst;
}

U0 PutLine(I32 fd, U8 *line)
{
  I64 n = StrLen(line);
  line[n] = '\n';
  WriteAll(fd, line, n + 1);
  line[n] = 0;
}

U8 *g_export_kind[9] = {"", "genesis", "note", "chat", "scope", "member", "alert", "network", "event"};

Bool ExportReport(App *a)
{
  Log *log = a->st->log;
  U8 *dir = StationPath(a->st, "report");
  mkdir(dir, MODE_DIR);
  Free(dir);
  U8 *tmp = StationPath(a->st, "report/export.tsv.tmp");
  I32 fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, MODE_FILE);
  if (fd < 0) {
    Free(tmp);
    return FALSE;
  }
  U8 *line = MAlloc(4096);
  U8 *text = MAlloc(BODY_MAX + 128);
  U8 *f1 = MAlloc(BODY_MAX + 128);
  U8 f2[NAME_MAX], f3[NAME_MAX], title[96];

  StrCpy(line, "ark-export\t1");
  PutLine(fd, line);
  IncidentTitle(log, title);
  snprintf(line, 4096, "incident\t%s", Tsv(f1, title, 200));
  PutLine(fd, line);
  snprintf(line, 4096, "opened\t%ld", OpenedAt(log));
  PutLine(fd, line);
  snprintf(line, 4096, "written\t%ld", time(NULL));
  PutLine(fd, line);
  U8 *role = "member";
  if (IsAdmin(a->st))
    role = "manager";
  snprintf(line, 4096, "station\t%s\t%s", Tsv(f1, a->st->name, NAME_MAX), role);
  PutLine(fd, line);
  snprintf(line, 4096, "phase\t%s", g_phase_names[IncidentPhase(a)]);
  PutLine(fd, line);
  snprintf(line, 4096, "integrity\t%ld\t%ld", log->problems, a->st->rejected);
  PutLine(fd, line);

  CollectMembers(a);
  for (I64 i = 0; i < a->member_count; i++) {
    role = "member";
    if (a->members[i].admin)
      role = "manager";
    snprintf(line, 4096, "member\t%ld\t%s\t%s", a->members[i].time, Tsv(f1, a->members[i].name, NAME_MAX), role);
    PutLine(fd, line);
  }
  CollectAssets(a);
  for (I64 i = 0; i < a->asset_count; i++) {
    Asset *as = &a->assets[i];
    snprintf(line, 4096, "asset\t%ld\t%s\t%s\t%s\t%s\t%s", as->time, Tsv(f1, as->name, 32), as->type, as->where,
             as->records, as->status);
    PutLine(fd, line);
  }
  Clock clocks[RULES];
  I64 nclocks = Deadlines(log, clocks);
  for (I64 i = 0; i < nclocks; i++) {
    I64 r = clocks[i].rule;
    snprintf(line, 4096, "clock\t%ld\t%s\t%s\t%ld\t%ld", clocks[i].due, g_rule_who[r], g_rule_cite[r],
             clocks[i].unsure, g_rule_hours[r]);
    PutLine(fd, line);
  }

  RefreshRisk(a);
  LogSorted(log, a->order);
  for (I64 k = 0; k < log->count; k++) {
    I64 idx = a->order[k];
    Entry *e = &log->entries[idx];
    if (e->status != ST_OK || e->kind < 1 || e->kind > 8)
      continue;
    NameOf(log, e->author, f2);
    Tsv(f2, f2, NAME_MAX);
    if (e->kind == KIND_EVENT) {
      Event ev;
      if (!EventFromBody(e->body, &ev))
        continue;
      U8 ref[12];
      EntryRef(e, ref);
      Entry *rep = ReportOf(a, e);
      I64 rep_time = 0;
      StrCpy(f3, "-");
      if (rep != NULL) {
        NameOf(log, rep->author, f3);
        Tsv(f3, f3, NAME_MAX);
        rep_time = rep->time;
      }
      snprintf(line, 4096, "event\t%ld\t%s\t%s\t%s\t%s\t%ld\t%s\t%s\t%ld\t%s", e->time, ref,
               g_ev_source[ev.source], ev.user, ev.host, a->risk[idx], a->why[idx], f3, rep_time,
               Tsv(f1, ev.detail, BODY_MAX));
    } else {
      U8 ref[12];
      StrCpy(ref, "-");
      if (e->kind == KIND_ALERT && AlertText(e->body) != e->body) {
        MemCpy(ref, e->body + 1, 8);
        ref[8] = 0;
      }
      EntryText(log, e, text);
      snprintf(line, 4096, "entry\t%ld\t%s\t%s\t%s\t%s\t%s", e->time, g_export_kind[e->kind],
               g_phase_names[MinI64(MaxI64(e->phase, 0), 4)], f2, ref, Tsv(f1, text, BODY_MAX));
    }
    PutLine(fd, line);
  }
  close(fd);
  U8 *path = StationPath(a->st, "report/export.tsv");
  Bool ok = rename(tmp, path) == 0;
  Free(path);
  Free(tmp);
  Free(line);
  Free(text);
  Free(f1);
  return ok;
}

I64 ReadSmall(U8 *path, U8 *buf, I64 max)
{
  I32 fd = open(path, O_RDONLY);
  if (fd < 0)
    return -1;
  I64 n = 0;
  while (n < max - 1) {
    I64 got = read(fd, buf + n, max - 1 - n);
    if (got <= 0)
      break;
    n += got;
  }
  close(fd);
  buf[n] = 0;
  return n;
}

Bool LoadReport(App *a)
{
  if (a->report_text == NULL)
    a->report_text = MAlloc(REPORT_MAX);
  U8 *path = StationPath(a->st, "report/report.md");
  a->report_len = ReadSmall(path, a->report_text, REPORT_MAX);
  Free(path);
  if (a->report_len < 0) {
    a->report_len = 0;
    a->report_text[0] = 0;
    return FALSE;
  }
  return TRUE;
}

U8 *ReportTool()
{
  U8 *cmd = getenv("ARK_REPORT_CMD");
  if (cmd == NULL || cmd[0] == 0)
    return "tools/ark-report";
  return cmd;
}

// Loads the model in the background the first time the Report page opens,
// so pressing Write report doesn't wait for it.
U0 WarmReport(App *a)
{
  if (a->report_text == NULL && a->report_state == RS_NONE && LoadReport(a)) {
    a->report_state = RS_DONE;
    StrCpy(a->report_msg, "Saved earlier. Write it again to include what has happened since.");
  }
  if (a->report_warmed)
    return;
  a->report_warmed = TRUE;
  U8 cmd[600];
  snprintf(cmd, 600, "%s --warm >/dev/null 2>&1 &", ReportTool());
  system(cmd);
}

U0 WriteReport(App *a)
{
  if (a->report_state == RS_RUNNING)
    return;
  if (strchr(a->st->dir, '\'') != NULL) {
    Say(a, "The station directory name has a quote in it; rename it to write a report.", C_RED_FG);
    return;
  }
  if (!ExportReport(a)) {
    a->report_state = RS_FAILED;
    StrCpy(a->report_msg, "Could not write the export into the station directory.");
    return;
  }
  U8 *status = StationPath(a->st, "report/status");
  unlink(status);
  Free(status);
  U8 cmd[900];
  snprintf(cmd, 900, "%s '%s' >'%s/report/run.log' 2>&1 &", ReportTool(), a->st->dir, a->st->dir);
  system(cmd);
  a->report_state = RS_RUNNING;
  a->report_started = time(NULL);
  a->report_warmed = TRUE;
  StrCpy(a->report_msg, "");
}

// Shows the PDF in the desktop's viewer. ARK_OPEN_CMD replaces xdg-open
// (tests set it to true).
U0 OpenReportPdf(App *a)
{
  U8 *open_cmd = getenv("ARK_OPEN_CMD");
  if (open_cmd == NULL || open_cmd[0] == 0)
    open_cmd = "xdg-open";
  U8 cmd[700];
  snprintf(cmd, 700, "%s '%s/report/report.pdf' >/dev/null 2>&1 &", open_cmd, a->st->dir);
  system(cmd);
}

// Checks whether tools/ark-report has finished.
U0 PollReport(App *a)
{
  if (a->report_state != RS_RUNNING)
    return;
  U8 buf[300];
  U8 *path = StationPath(a->st, "report/status");
  I64 n = ReadSmall(path, buf, 300);
  Free(path);
  if (n > 0 && buf[n - 1] == '\n')
    buf[--n] = 0;
  if (n > 5 && StrNCmp(buf, "done ", 5) == 0) {
    // "done SECONDS ai|figures pdf|md NOTE"
    U8 *words[4];
    I64 nw = 0;
    U8 *p = buf + 5;
    while (nw < 4 && p != NULL) {
      words[nw++] = p;
      p = strchr(p, ' ');
      if (p != NULL && nw < 4)
        *p++ = 0;
    }
    U8 *secs = "?";
    Bool ai = FALSE, pdf = FALSE;
    U8 *note = "";
    if (nw > 0)
      secs = words[0];
    if (nw > 1)
      ai = StrCmp(words[1], "ai") == 0;
    if (nw > 2)
      pdf = StrCmp(words[2], "pdf") == 0;
    if (nw > 3)
      note = words[3];
    if (ai && note[0])
      snprintf(a->report_msg, 256, "Written in %s s. Summary by the local model, figures from the log. %s", secs, note);
    else if (ai)
      snprintf(a->report_msg, 256, "Written in %s s. Summary by the local model, figures from the log.", secs);
    else
      snprintf(a->report_msg, 256, "Written in %s s from the figures only. %s", secs, note);
    LoadReport(a);
    if (pdf)
      OpenReportPdf(a);
    a->report_scroll = 0;
    a->report_state = RS_DONE;
    a->dirty = TRUE;
  } else if (n > 6 && StrNCmp(buf, "error ", 6) == 0) {
    snprintf(a->report_msg, 256, "The report failed: %s", buf + 6);
    a->report_state = RS_FAILED;
    a->dirty = TRUE;
  } else if (time(NULL) - a->report_started > 180) {
    U8 *log = "report/run.log";
    snprintf(a->report_msg, 256, "No answer from %s after 3 minutes. See %s/%s.", ReportTool(), a->st->dir, log);
    a->report_state = RS_FAILED;
    a->dirty = TRUE;
  }
}

// Draws one line of the report's markdown. Returns the height it takes.
I64 ReportLine(App *a, U8 *src, I64 len, I64 x, I64 y, I64 w, Bool draw)
{
  Canvas *c = a->cv;
  U8 line[1200];
  I64 n = 0;
  for (I64 i = 0; i < len && n < 1199; i++)
    if (src[i] != '`')
      line[n++] = src[i];
  line[n] = 0;
  if (n == 0)
    return 8;
  I64 starts[16], lens[16];
  if (n > 2 && line[0] == '#' && line[1] == ' ') {
    I64 rows = Wrap(c, F_H1, line + 2, w, starts, lens, 3);
    for (I64 i = 0; draw && i < rows; i++)
      Text(c, F_H1, x, y + i * 30, line + 2 + starts[i], C_TEXT, w, lens[i]);
    return rows * 30 + 6;
  }
  if (n > 3 && line[0] == '#' && line[1] == '#' && line[2] == ' ') {
    U8 *head = line + 3;
    U32 col = C_TEXT;
    U8 *model = strstr(head, " (local model)");
    if (draw) {
      I64 tx = Text(c, F_H2, x, y + 14, head, col, w, MaxI64(0, StrLen(head) - (model != NULL) * 14));
      if (model != NULL)
        Badge(a, tx + 10, y + 24, "LOCAL MODEL", C_PURPLE);
      HLine(c, x, y + 40, w, C_LINE);
    }
    return 50;
  }
  if (n > 2 && line[0] == '-' && line[1] == ' ') {
    I64 rows = Wrap(c, F_BODY, line + 2, w - 18, starts, lens, 16);
    if (draw) {
      Dot(c, x + 4, y + 10, 4, C_FAINT);
      for (I64 i = 0; i < rows; i++)
        Text(c, F_BODY, x + 18, y + i * 20, line + 2 + starts[i], C_TEXT, w - 18, lens[i]);
    }
    return rows * 20 + 4;
  }
  I64 rows = Wrap(c, F_BODY, line, w, starts, lens, 16);
  for (I64 i = 0; draw && i < rows; i++)
    Text(c, F_BODY, x, y + i * 20, line + starts[i], C_TEXT, w, lens[i]);
  return rows * 20 + 2;
}

U0 DrawReportPage(App *a)
{
  Canvas *c = a->cv;
  I64 cw = g_cw - SIDE_W - PANEL_W - 2 * PAD;
  PageHead(a, "Report", "For the company: what happened, what was lost and saved, the deadlines.");
  I64 y = TOP_H + 84;
  Card(a, CX0, y, cw, 76);
  U8 *head = "No report yet";
  U8 line[300];
  StrCpy(line, "Figures come from the signed log. A model running on this laptop writes the summary; nothing leaves it.");
  U32 hcol = C_TEXT;
  if (a->report_state == RS_RUNNING) {
    head = "Writing the report";
    snprintf(line, 300, "Working out the figures and asking the local model. %ld s so far.", time(NULL) - a->report_started);
    hcol = C_CYAN_FG;
  } else if (a->report_state == RS_DONE) {
    head = "Report written";
    CopyText(line, a->report_msg, 300);
    hcol = C_GREEN_FG;
  } else if (a->report_state == RS_FAILED) {
    head = "Report failed";
    CopyText(line, a->report_msg, 300);
    hcol = C_RED_FG;
  }
  Text(c, F_H2, CX0 + 20, y + 16, head, hcol, cw - 220);
  Text(c, F_SMALL, CX0 + 20, y + 44, line, C_MUTED, cw - 220);
  if (a->report_state == RS_RUNNING)
    Button(a, CX0 + cw - 180, y + 20, 160, 36, "Writing...", BTN_OFF, 0);
  else if (a->report_state == RS_DONE)
    Button(a, CX0 + cw - 180, y + 20, 160, 36, "Request again", BTN_GHOST, H_WRITE);
  else
    Button(a, CX0 + cw - 180, y + 20, 160, 36, "Request report", BTN_PRIMARY, H_WRITE);

  y += 92;
  I64 h = g_ch - 20 - y;
  Card(a, CX0, y, cw, h);
  if (a->report_len == 0) {
    TextMid(c, F_BODY, CX0 + 24, y + 40, "The report opens as a PDF and shows here. Both are saved in report/ in the station directory.", C_FAINT, cw - 48);
    a->report_max_scroll = 0;
    return;
  }
  I64 x = CX0 + 28, w = cw - 56;
  Clip(c, CX0 + 1, y + 1, cw - 2, h - 2);
  I64 ty = y + 24 - a->report_scroll;
  U8 *t = a->report_text;
  I64 start = 0;
  for (I64 i = 0; i <= a->report_len; i++) {
    if (i == a->report_len || t[i] == '\n') {
      Bool visible = ty < y + h && ty > y - 200;
      ty += ReportLine(a, t + start, i - start, x, ty, w, visible);
      start = i + 1;
    }
  }
  ClipAll(c);
  a->report_max_scroll = MaxI64(0, ty + a->report_scroll - (y + 24) - h + 48);
}

U0 Draw(App *a)
{
  Canvas *c = a->cv;
  ClipAll(c);
  a->hit_count = 0;
  Fill(c, 0, 0, g_cw, g_ch, C_BG);
  if (!Ready(a)) {
    DrawSetup(a);
  } else {
    RefreshRisk(a);
    if (a->view == V_OVERVIEW)
      DrawOverview(a);
    else if (a->view == V_SERVER)
      DrawServerPage(a);
    else if (a->view == V_LOG)
      DrawLogPage(a);
    else if (a->view == V_SCOPE)
      DrawScopePage(a);
    else if (a->view == V_CLOCKS)
      DrawClocksPage(a);
    else if (a->view == V_TEAM)
      DrawTeamPage(a);
    else if (a->view == V_NETWORK)
      DrawNetworkPage(a);
    else if (a->view == V_REPORT)
      DrawReportPage(a);
    else
      DrawGuidePage(a);
    DrawSide(a);
    DrawTop(a);
    DrawPanel(a);
    DrawFlash(a);
  }
}

// ---- actions --------------------------------------------------------------

// Wipes the keys from memory and quits. The sealed files stay on disk.
U0 Lock(App *a)
{
  if (a->lock_armed != 0 && time(NULL) - a->lock_armed <= 3) {
    StationWipe(a->st);
    a->quit = TRUE;
  } else {
    a->lock_armed = time(NULL);
  }
}

// Deletes the station directory and goes back to the first setup step.
// Two presses within 3 seconds, like the lock.
U0 ClearStation(App *a)
{
  if (a->clear_armed == 0 || time(NULL) - a->clear_armed > 3) {
    a->clear_armed = time(NULL);
    return;
  }
  a->clear_armed = 0;
  U8 dir[256];
  CopyText(dir, a->st->dir, 256);
  if (dir[0] == 0 || strchr(dir, '\'') != NULL) {
    Say(a, "Can't clear a station whose directory name has a quote in it.", C_RED_FG);
    return;
  }
  StationWipe(a->st);
  sodium_memzero(a->pass, 128);
  U8 cmd[600];
  snprintf(cmd, 600, "rm -rf -- '%s'", dir);
  if (system(cmd) != 0) {
    Say(a, "Could not delete the station directory.", C_RED_FG);
    return;
  }
  Free(a->st->log);
  StationInit(a->st, dir);
  MemSet(&a->team, 0, sizeof(Team));
  for (I64 i = 0; i < FIELDS; i++)
    ClearField(a, i);
  if (a->feed_fd >= 0)
    close(a->feed_fd);
  a->feed_fd = -1;
  a->feed_off = 0;
  a->feed_len = 0;
  a->risk_done = 0;
  a->selected = -1;
  a->alerts_acked = 0;
  a->panel_alerts = 0;
  a->panel_problems = 0;
  a->panel_join = FALSE;
  a->cut_armed = 0;
  a->lock_armed = 0;
  a->report_state = RS_NONE;
  a->report_len = 0;
  a->report_warmed = FALSE;
  a->scope_open = FALSE;
  a->view = V_OVERVIEW;
  a->mode = MODE_NEW_NAME;
  a->focus = FLD_SETUP;
  Say(a, "Station cleared. Start again with your name.", C_GREEN_FG);
}

// Runs the command in env var `env`, or `fallback`. Returns its exit code.
I64 RunSwitch(U8 *env, U8 *fallback)
{
  U8 *cmd = getenv(env);
  if (cmd == NULL || cmd[0] == 0)
    cmd = fallback;
  I64 status = system(cmd);
  if (status < 0)
    return 127;
  return (status >> 8) & 0xFF;
}

// Takes this machine off the internet. The relay link is USB or loopback
// to socat, which NetworkManager doesn't manage, so ARK keeps working.
U0 CutNetwork(App *a, U8 *how)
{
  if (IsCut(a))
    return;
  I64 rc = RunSwitch("ARK_CUT_CMD", "nmcli networking off");
  U8 body[200];
  if (rc == 0) {
    snprintf(body, 200, "Cut this machine off the internet (%s). Any link a hacker had through it is gone; the team continues over the relay.", how);
    Say(a, "Internet cut. ARK continues over the relay.", C_RED_FG);
  } else {
    snprintf(body, 200, "Tried to cut this machine off the internet (%s), but the command failed with exit code %ld.", how, rc);
    Say(a, "The cut command failed. The internet may still be on.", C_RED_FG);
  }
  PostAndSend(a, KIND_NETWORK, IncidentPhase(a), body, StrLen(body));
  a->cut_armed = 0;
}

U0 RestoreNetwork(App *a, U8 *how)
{
  if (!IsCut(a))
    return;
  if (!IsAdmin(a->st)) {
    Say(a, "Only the manager can restore the network.", C_AMBER_FG);
    return;
  }
  I64 rc = RunSwitch("ARK_RESTORE_CMD", "nmcli networking on");
  U8 body[200];
  if (rc == 0) {
    snprintf(body, 200, "Restored internet on this machine (%s).", how);
    Say(a, "Internet restored.", C_GREEN_FG);
  } else {
    snprintf(body, 200, "Cut still in place: the restore command failed with exit code %ld (%s).", rc, how);
    Say(a, "The restore command failed. Still offline.", C_RED_FG);
  }
  PostAndSend(a, KIND_NETWORK, IncidentPhase(a), body, StrLen(body));
}

// On screen the cut needs two presses; the hardware button is one.
U0 CutPressed(App *a)
{
  if (a->cut_armed != 0 && time(NULL) - a->cut_armed <= 3)
    CutNetwork(a, "on screen");
  else
    a->cut_armed = time(NULL);
}

U0 Approve(App *a)
{
  if (!a->team.join_pending || !IsAdmin(a->st))
    return;
  U8 name[NAME_MAX];
  CopyText(name, a->team.join_name, NAME_MAX);
  ApproveJoin(a->st, &a->team, &a->link);
  U8 line[96];
  snprintf(line, 96, "%s admitted. They now get the key and the whole log.", name);
  Say(a, line, C_GREEN_FG);
}


// Sends the manager an alert that names the event, so every station can
// show it as reported. The panel buzzes on the manager's station.
U0 ReportEvent(App *a, I64 idx)
{
  Log *log = a->st->log;
  if (idx < 0 || idx >= log->count)
    return;
  Entry *e = &log->entries[idx];
  Event ev;
  if (e->kind != KIND_EVENT || !EventFromBody(e->body, &ev) || ReportOf(a, e) != NULL)
    return;
  U8 ref[12], t[8], body[BODY_MAX];
  EntryRef(e, ref);
  ClockText(e->time, t);
  RefreshRisk(a);
  U8 *why = a->why[idx];
  if (why[0])
    snprintf(body, BODY_MAX, "[%s] %s on %s at %s: %s (it %s)", ref, ev.user, ev.host, t, ev.detail, why);
  else
    snprintf(body, BODY_MAX, "[%s] %s on %s at %s: %s", ref, ev.user, ev.host, t, ev.detail);
  if (PostAndSend(a, KIND_ALERT, IncidentPhase(a), body, StrLen(body)))
    Say(a, "Reported to the manager. Their panel buzzes.", C_RED_FG);
}

#define FEED_RATE   30   // events per window; more than that is summarised
#define FEED_WINDOW 10

U0 FeedEvent(App *a, U8 *line, I64 len)
{
  Event ev;
  if (!FeedLine(line, len, &ev))
    return;
  I64 now = time(NULL);
  if (now - a->feed_window >= FEED_WINDOW) {
    if (a->feed_dropped > 0) {
      U8 note[160];
      snprintf(note, 160, "request|ark-watch|-|%ld more events in %ld seconds were not logged (rate limit)",
               a->feed_dropped, FEED_WINDOW);
      PostAndSend(a, KIND_EVENT, IncidentPhase(a), note, StrLen(note));
    }
    a->feed_window = now;
    a->feed_posted = 0;
    a->feed_dropped = 0;
  }
  if (a->feed_posted >= FEED_RATE) {
    a->feed_dropped++;
    return;
  }
  U8 body[BODY_MAX];
  I64 n = EventBody(&ev, body);
  if (PostAndSend(a, KIND_EVENT, IncidentPhase(a), body, n))
    a->feed_posted++;
  a->dirty = TRUE;
}

// Reads lines tools/ark-watch appended to DIR/feed since the last call.
// Lines already in the file when the station started aren't logged again.
U0 PollFeed(App *a)
{
  if (!Ready(a) || a->st->epoch < 0)
    return;
  if (a->feed_fd < 0) {
    I64 now = time(NULL);
    if (now - a->feed_tried < 2)
      return;
    a->feed_tried = now;
    U8 *path = StationPath(a->st, "feed");
    a->feed_fd = open(path, O_RDONLY | O_NONBLOCK);
    Free(path);
    a->feed_off = 0;
    if (a->feed_fd < 0)
      return;
  }
  I64 size = lseek(a->feed_fd, 0, SEEK_END);
  if (size < a->feed_off) {
    a->feed_off = 0;
    a->feed_len = 0;
  }
  if (size == a->feed_off)
    return;
  lseek(a->feed_fd, a->feed_off, SEEK_SET);
  U8 buf[4096];
  I64 n = read(a->feed_fd, buf, 4096);
  if (n <= 0)
    return;
  a->feed_off += n;
  for (I64 i = 0; i < n; i++) {
    if (buf[i] == '\n') {
      a->feed_line[a->feed_len] = 0;
      FeedEvent(a, a->feed_line, a->feed_len);
      a->feed_len = 0;
    } else if (a->feed_len < 1099) {
      a->feed_line[a->feed_len++] = buf[i];
    }
  }
}

U0 SetPhase(App *a, I64 p)
{
  U8 body[96];
  snprintf(body, 96, "Moved the response to %s: %s.", g_phase_names[p], g_phase_help[p]);
  if (PostAndSend(a, KIND_NOTE, p, body, StrLen(body))) {
    U8 line[64];
    snprintf(line, 64, "Phase set to %s for everyone.", g_phase_names[p]);
    Say(a, line, C_CYAN_FG);
  }
}

U0 SendCompose(App *a)
{
  Field *f = &a->fields[FLD_COMPOSE];
  if (f->len == 0)
    return;
  if (PostAndSend(a, a->kind, IncidentPhase(a), f->text, f->len)) {
    ClearField(a, FLD_COMPOSE);
    if (a->kind == KIND_ALERT) {
      Say(a, "Alert sent to the manager.", C_RED_FG);
      a->kind = KIND_NOTE;
    }
  }
}

U0 OpenScope(App *a)
{
  a->view = V_SCOPE;
  a->scope_open = TRUE;
  a->scope_type = -1;
  a->scope_status = -1;
  a->scope_unknown = FALSE;
  a->scope_error[0] = 0;
  ClearField(a, FLD_ASSET);
  ClearField(a, FLD_WHERE);
  ClearField(a, FLD_RECORDS);
  a->focus = FLD_ASSET;
}

U0 SaveScope(App *a)
{
  Field *asset = &a->fields[FLD_ASSET], *where = &a->fields[FLD_WHERE], *rec = &a->fields[FLD_RECORDS];
  U8 *err = NULL;
  if (asset->len == 0 || asset->len > 24 || strchr(asset->text, '|') != NULL)
    err = "Name the system in 1 to 24 characters.";
  else if (a->scope_type < 0)
    err = "Pick what kind of data it holds.";
  else if (where->len > 4 || strchr(where->text, '|') != NULL)
    err = "Residents: a short code like TX or EU, or None.";
  else if (a->scope_status < 0)
    err = "Pick what happened to it.";
  U8 records[16];
  if (err == NULL) {
    if (a->scope_unknown || rec->len == 0) {
      StrCpy(records, "?");
    } else if (rec->len > 10) {
      err = "Records: a whole number, or mark it Unknown.";
    } else {
      for (I64 i = 0; i < rec->len; i++)
        if (rec->text[i] < '0' || rec->text[i] > '9')
          err = "Records: a whole number, or mark it Unknown.";
      CopyText(records, rec->text, 16);
    }
  }
  if (err != NULL) {
    CopyText(a->scope_error, err, 96);
    return;
  }
  U8 res[8];
  if (where->len == 0)
    StrCpy(res, "-");
  else
    CopyText(res, where->text, 8);
  for (I64 i = 0; res[i]; i++)
    if (res[i] >= 'a' && res[i] <= 'z')
      res[i] -= 32;
  U8 body[BODY_MAX];
  snprintf(body, BODY_MAX, "%s|%s|%s|%s|%s", asset->text, g_data_types[a->scope_type], res, records,
           g_scope_status[a->scope_status]);
  if (PostAndSend(a, KIND_SCOPE, IncidentPhase(a), body, StrLen(body))) {
    a->scope_open = FALSE;
    a->focus = -1;
    U8 line[96];
    snprintf(line, 96, "%s saved to the log.", asset->text);
    Say(a, line, C_GREEN_FG);
  }
}

U0 SubmitSetup(App *a)
{
  Field *f = &a->fields[FLD_SETUP];
  if (a->mode == MODE_NEW_NAME) {
    if (f->len == 0)
      return;
    CopyText(a->name, f->text, NAME_MAX);
    a->mode = MODE_NEW_PASS;
    a->msg[0] = 0;
  } else if (a->mode == MODE_NEW_PASS) {
    if (f->len < PASS_MIN) {
      Say(a, "Use at least 8 characters. A short sentence works well.", C_RED_FG);
      return;
    }
    CopyText(a->pass, f->text, 128);
    a->mode = MODE_NEW_PASS2;
    a->msg[0] = 0;
  } else if (a->mode == MODE_NEW_PASS2) {
    if (StrCmp(a->pass, f->text) != 0) {
      Say(a, "The two passphrases differ. Choose one again.", C_RED_FG);
      a->mode = MODE_NEW_PASS;
    } else if (StationCreate(a->st, a->st->dir, a->name, a->pass)) {
      a->mode = MODE_NEW_CHOICE;
      a->msg[0] = 0;
    } else {
      Say(a, "Could not write the station directory.", C_RED_FG);
    }
    sodium_memzero(a->pass, 128);
  } else if (a->mode == MODE_NEW_TITLE) {
    if (f->len == 0)
      return;
    U8 *msg = MAlloc(MSG_MAX);
    Send(a, msg, StartIncident(a->st, f->text, msg));
    Free(msg);
    a->mode = MODE_READY;
    a->view = V_OVERVIEW;
    a->focus = -1;
    Say(a, "Incident opened. You are the admin.", C_GREEN_FG);
  } else if (a->mode == MODE_UNLOCK) {
    U8 *dir = StrNew(a->st->dir);
    if (StationOpen(a->st, dir, f->text)) {
      a->mode = MODE_READY;
      a->focus = -1;
      a->alerts_acked = AlertCount(a);
      a->panel_alerts = a->alerts_acked;
      if (a->st->damaged_on_load > 0)
        Say(a, "The log file has damaged records. They are marked.", C_RED_FG);
      else
        Say(a, "Unlocked.", C_GREEN_FG);
    } else {
      StationInit(a->st, dir);
      Say(a, "Wrong passphrase.", C_RED_FG);
    }
    Free(dir);
  }
  ClearField(a, FLD_SETUP);
}

U0 Choose(App *a, Bool start)
{
  if (a->mode != MODE_NEW_CHOICE)
    return;
  if (start) {
    a->mode = MODE_NEW_TITLE;
    a->focus = FLD_SETUP;
  } else {
    a->mode = MODE_READY;
    a->focus = -1;
    Say(a, "Join request sent.", C_CYAN_FG);
  }
}

U0 Act(App *a, I64 id, I64 arg)
{
  if (id == H_NAV) {
    a->view = arg;
    a->scroll = 0;
    a->server_scroll = 0;
    if (arg == V_REPORT)
      WarmReport(a);
  } else if (id == H_FOCUS) {
    a->focus = arg;
  } else if (id == H_PHASE) {
    SetPhase(a, arg);
  } else if (id == H_SEND) {
    SendCompose(a);
  } else if (id == H_KIND) {
    a->kind = arg;
    a->focus = FLD_COMPOSE;
  } else if (id == H_FILTER) {
    a->filter = arg;
    a->scroll = 0;
  } else if (id == H_SCOPE_OPEN) {
    OpenScope(a);
  } else if (id == H_SCOPE_SHUT) {
    a->scope_open = FALSE;
    a->focus = -1;
  } else if (id == H_SCOPE_SAVE) {
    SaveScope(a);
  } else if (id == H_TYPE) {
    a->scope_type = arg;
  } else if (id == H_STATUS) {
    a->scope_status = arg;
  } else if (id == H_WHERE) {
    ClearField(a, FLD_WHERE);
    CopyText(a->fields[FLD_WHERE].text, g_where_picks[arg], INPUT_MAX);
    a->fields[FLD_WHERE].len = StrLen(g_where_picks[arg]);
  } else if (id == H_UNKNOWN) {
    a->scope_unknown = !a->scope_unknown;
    if (a->scope_unknown)
      ClearField(a, FLD_RECORDS);
  } else if (id == H_APPROVE) {
    Approve(a);
  } else if (id == H_CUT) {
    CutPressed(a);
  } else if (id == H_RESTORE) {
    RestoreNetwork(a, "on screen");
  } else if (id == H_ACK) {
    a->alerts_acked = AlertCount(a);
  } else if (id == H_LOCK) {
    Lock(a);
  } else if (id == H_START) {
    Choose(a, TRUE);
  } else if (id == H_JOIN) {
    Choose(a, FALSE);
  } else if (id == H_CONTINUE) {
    SubmitSetup(a);
  } else if (id == H_SEARCH_CLR) {
    ClearField(a, FLD_SEARCH);
  } else if (id == H_EVENT) {
    a->selected = arg;
  } else if (id == H_REPORT) {
    ReportEvent(a, arg);
  } else if (id == H_SFILTER) {
    a->server_filter = arg;
    a->server_scroll = 0;
  } else if (id == H_WRITE) {
    WriteReport(a);
  } else if (id == H_CLEAR) {
    ClearStation(a);
  } else if (id == H_BACK) {
    sodium_memzero(a->pass, 128);
    a->mode = MODE_NEW_NAME;
    a->focus = FLD_SETUP;
  }
}

U0 OnClick(App *a, I64 x, I64 y)
{
  I64 old_focus = a->focus;
  for (I64 i = a->hit_count - 1; i >= 0; i--) {
    Hit *t = &a->hits[i];
    if (x >= t->x && x < t->x + t->w && y >= t->y && y < t->y + t->h) {
      if (t->id != H_FOCUS && t->id != H_KIND && t->id != H_WHERE && t->id != H_UNKNOWN &&
          t->id != H_TYPE && t->id != H_STATUS)
        a->focus = -1;
      Act(a, t->id, t->arg);
      if (a->mode != MODE_READY && a->mode != MODE_NEW_CHOICE)
        a->focus = FLD_SETUP;
      return;
    }
  }
  if (Ready(a))
    a->focus = -1;
  else if (old_focus >= 0)
    a->focus = old_focus;
}

U0 OnText(App *a, U8 *text)
{
  if (a->mode == MODE_NEW_CHOICE) {
    if (text[0] == 's' || text[0] == 'S')
      Choose(a, TRUE);
    else if (text[0] == 'j' || text[0] == 'J')
      Choose(a, FALSE);
    return;
  }
  if (!Ready(a) && a->mode != MODE_READY)
    a->focus = FLD_SETUP;
  // Typing with nothing focused starts a note on the pages that have one.
  if (a->focus < 0 && Ready(a) && (a->view == V_OVERVIEW || a->view == V_LOG))
    a->focus = FLD_COMPOSE;
  if (a->focus < 0)
    return;
  Field *f = &a->fields[a->focus];
  I64 max = INPUT_MAX;
  if (a->focus == FLD_ASSET)
    max = 24;
  if (a->focus == FLD_WHERE)
    max = 4;
  if (a->focus == FLD_RECORDS) {
    max = 10;
    a->scope_unknown = FALSE;
  }
  for (I64 i = 0; text[i]; i++)
    if (text[i] >= 32 && text[i] < 127 && f->len < max)
      f->text[f->len++] = text[i];
  f->text[f->len] = 0;
  if (a->focus == FLD_SEARCH) {
    if (a->view != V_SERVER)
      a->view = V_LOG;
    a->scroll = 0;
    a->server_scroll = 0;
  }
}

U0 OnKey(App *a, I64 sym, I64 mod)
{
  if (sym == KEY_F12) {
    Lock(a);
    return;
  }
  if (sym == KEY_RETURN) {
    if (!Ready(a))
      SubmitSetup(a);
    else if (a->focus == FLD_COMPOSE)
      SendCompose(a);
    else if (a->scope_open && a->view == V_SCOPE && a->focus != FLD_SEARCH)
      SaveScope(a);
    return;
  }
  if (sym == KEY_BACKSPACE && a->focus >= 0) {
    Field *f = &a->fields[a->focus];
    if (f->len > 0)
      f->text[--f->len] = 0;
    return;
  }
  if (sym == KEY_ESCAPE) {
    if (!Ready(a)) {
      ClearField(a, FLD_SETUP);
    } else if (a->focus == FLD_SEARCH && a->fields[FLD_SEARCH].len > 0) {
      ClearField(a, FLD_SEARCH);
    } else if (a->scope_open) {
      a->scope_open = FALSE;
      a->focus = -1;
    } else {
      a->focus = -1;
    }
    return;
  }
  if (!Ready(a))
    return;
  if (sym == KEY_TAB && a->scope_open) {
    if (a->focus == FLD_ASSET)
      a->focus = FLD_WHERE;
    else if (a->focus == FLD_WHERE)
      a->focus = FLD_RECORDS;
    else
      a->focus = FLD_ASSET;
  } else if ((mod & KMOD_CTRL) != 0 && (sym == 'f' || sym == 'k')) {
    a->focus = FLD_SEARCH;
  } else if (sym == KEY_F1) {
    a->view = V_GUIDE;
  } else if (sym == KEY_F2 || sym == KEY_F3) {
    a->view = V_LOG;
    a->kind = KIND_NOTE;
    if (sym == KEY_F3)
      a->kind = KIND_CHAT;
    a->focus = FLD_COMPOSE;
  } else if (sym == KEY_F4) {
    OpenScope(a);
  } else if (sym == KEY_F5) {
    a->view = V_LOG;
    a->kind = KIND_ALERT;
    a->focus = FLD_COMPOSE;
  } else if (sym == KEY_F6) {
    a->view = V_SERVER;
  } else if (sym == KEY_F7) {
    a->view = V_REPORT;
    WarmReport(a);
  } else if (sym == KEY_F9) {
    Approve(a);
  } else if (a->view == V_REPORT && sym == KEY_PAGEUP) {
    a->report_scroll = MaxI64(0, a->report_scroll - 400);
  } else if (a->view == V_REPORT && sym == KEY_PAGEDOWN) {
    a->report_scroll = MinI64(a->report_scroll + 400, a->report_max_scroll);
  } else if (a->view == V_SERVER && sym == KEY_PAGEUP) {
    a->server_scroll = MaxI64(0, a->server_scroll - 10);
  } else if (a->view == V_SERVER && sym == KEY_PAGEDOWN) {
    a->server_scroll = MinI64(a->server_scroll + 10, MaxI64(0, EventCount(a) - 1));
  } else if (sym == KEY_PAGEUP) {
    a->view = V_LOG;
    a->scroll += 5;
  } else if (sym == KEY_PAGEDOWN) {
    a->scroll = MaxI64(0, a->scroll - 5);
  }
}

U0 OnWheel(App *a, I64 dy)
{
  if (Ready(a) && a->view == V_REPORT) {
    a->report_scroll = MaxI64(0, MinI64(a->report_scroll - dy * 60, a->report_max_scroll));
    return;
  }
  if (Ready(a) && a->view == V_SERVER) {
    a->server_scroll = MaxI64(0, MinI64(a->server_scroll - dy * 3, MaxI64(0, EventCount(a) - 1)));
    return;
  }
  if (!Ready(a) || a->view != V_LOG)
    return;
  a->scroll = MaxI64(0, MinI64(a->scroll + dy * 2, MaxI64(0, a->st->log->count - 1)));
}

// ---- panel --------------------------------------------------------------

U0 PanelSend(App *a, U8 *text)
{
  if (a->panel_fd >= 0)
    WriteAll(a->panel_fd, text, StrLen(text));
}

// The lights show whether this machine is on the internet. The buzzer
// gives three beeps for a new alert or a failed check and one for a join
// request. State is resent with every heartbeat, because opening the port
// resets the UNO and it misses whatever was sent while it booted.
U0 PanelUpdate(App *a, Bool resend)
{
  if (a->panel_fd < 0)
    return;
  I64 problems = ProblemCount(a);
  I64 alerts = AlertCount(a);
  if (alerts > a->panel_alerts || problems > a->panel_problems)
    PanelSend(a, "A\n");
  else if (a->team.join_pending && !a->panel_join)
    PanelSend(a, "B\n");
  a->panel_join = a->team.join_pending;
  a->panel_alerts = alerts;
  a->panel_problems = problems;
  Bool cut = IsCut(a);
  if (resend || cut != a->panel_cut) {
    if (cut)
      PanelSend(a, "R\n");
    else
      PanelSend(a, "G\n");
  }
  a->panel_cut = cut;
}

U0 PanelCommand(App *a, U8 *line)
{
  if (!Ready(a))
    return;
  if (StrCmp(line, "CUT") == 0)
    CutNetwork(a, "panel button");
  else if (StrCmp(line, "RESTORE") == 0)
    RestoreNetwork(a, "panel button");
  a->dirty = TRUE;
}

U0 PollPanel(App *a)
{
  if (a->panel_fd < 0)
    return;
  U8 ch;
  while (read(a->panel_fd, &ch, 1) == 1) {
    if (ch == '\r')
      continue;
    if (ch == '\n') {
      a->panel_line[a->panel_len] = 0;
      PanelCommand(a, a->panel_line);
      a->panel_len = 0;
    } else if (a->panel_len < 31) {
      a->panel_line[a->panel_len++] = ch;
    }
  }
}

// ---- link ---------------------------------------------------------------

U0 Heartbeat(App *a)
{
  I64 now = time(NULL);
  if (now - a->last_beat < BEAT_SECS || a->mode != MODE_READY)
    return;
  a->last_beat = now;
  PanelUpdate(a, TRUE);
  U8 *msg = MAlloc(MSG_MAX);
  if (a->st->epoch >= 0)
    Send(a, msg, MakeHeads(a->st, msg));
  else
    Send(a, msg, MakeJoin(a->st, msg));
  Free(msg);
  a->dirty = TRUE;
}

U0 PollLink(App *a)
{
  if (a->link.fd < 0 || a->mode != MODE_READY)
    return;
  U8 *msg = MAlloc(MSG_MAX);
  I64 n;
  while ((n = LinkPoll(&a->link, msg)) > 0) {
    TeamReceive(a->st, &a->team, &a->link, msg, n);
    a->dirty = TRUE;
  }
  Free(msg);
}

App *AppNew(U8 *dir, U8 *port, U8 *panel)
{
  App *a = CAlloc(sizeof(App));
  a->cv = CAlloc(sizeof(Canvas));
  a->st = MAlloc(sizeof(Station));
  StationInit(a->st, dir);
  CopyText(a->port, port, 256);
  a->kind = KIND_NOTE;
  a->focus = FLD_SETUP;
  a->panel_fd = -1;
  a->selected = -1;
  a->dirty = TRUE;
  U8 *feed = StationPath(a->st, "feed");
  a->feed_fd = open(feed, O_RDONLY | O_NONBLOCK);
  if (a->feed_fd >= 0)
    a->feed_off = lseek(a->feed_fd, 0, SEEK_END);
  Free(feed);
  if (!LinkOpen(&a->link, port))
    a->link.fd = -1;
  if (panel != NULL) {
    CopyText(a->panel_port, panel, 256);
    a->panel_fd = open(panel, O_RDWR | O_NOCTTY | O_NONBLOCK);
  }
  U8 *secrets = StationPath(a->st, "secrets");
  if (access(secrets, 0) == 0)
    a->mode = MODE_UNLOCK;
  else
    a->mode = MODE_NEW_NAME;
  Free(secrets);
  return a;
}
