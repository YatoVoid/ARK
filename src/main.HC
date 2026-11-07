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
#include "font.HC"
#include "screen.HC"

#define MODE_NEW_NAME   0
#define MODE_NEW_PASS   1
#define MODE_NEW_PASS2  2
#define MODE_NEW_CHOICE 3
#define MODE_NEW_TITLE  4
#define MODE_UNLOCK     5
#define MODE_READY      6

#define INPUT_MAX   200
#define BEAT_SECS   3
#define PASS_MIN    8

// Screen rows.
#define ROW_TITLE   0
#define ROW_KEYS    1
#define ROW_LOG     2
#define LOG_LINES   31
#define ROW_SCOPE   34
#define SCOPE_LINES 7
#define ROW_CLOCKS  41
#define CLOCK_LINES 3
#define ROW_CHOICES 41
#define ROW_INPUT   46
#define ROW_HELP    47
#define ROW_MSG     48
#define ROW_STATUS  49

U8 *g_phase_names[5] = {"", "DETECT", "CONTAIN", "ERADICATE", "RECOVER"};
U8 *g_data_types[5] = {"PII", "PHI", "PCI", "CRED", "OTHER"};
U8 *g_scope_status[5] = {"ENCRYPTED", "EXFILTRATED", "SUSPECTED", "CONTAINED", "CLEAN"};
U8 *g_scope_fields[5] = {"Asset", "Data type", "Residents of", "Records", "Status"};
U8 *g_scope_help[5] = {
  "The server, database or file share that was hit. Example: HR-DB",
  "What kind of data it holds. Type the number or click a line below.",
  "Where those people live: TX, CA, NY, EU, or -. Decides which laws apply.",
  "How many people. An estimate is fine, ? if unknown. 250+ Texans adds the AG.",
  "What happened to it. Exfiltrated or Encrypted starts the notice clocks."
};
U8 *g_type_lines[5] = {
  "1  PII    names together with SSN, license, ID or bank numbers",
  "2  PHI    health, medical or insurance records",
  "3  PCI    payment card numbers",
  "4  CRED   usernames together with passwords",
  "5  OTHER  anything else (still counts for EU residents)"
};
U8 *g_status_lines[5] = {
  "1  ENCRYPTED    locked by ransomware, may not have left the network",
  "2  EXFILTRATED  copied out by the attacker",
  "3  SUSPECTED    might be affected, not confirmed yet",
  "4  CONTAINED    the attacker's access to it is cut off",
  "5  CLEAN        checked and not affected"
};

class Tm
{
  I32 sec, min, hour, mday, mon, year, wday, yday, isdst, pad;
  I64 gmtoff;
  U8 *zone;
};
extern "c" Tm *localtime_r(I64 *t, Tm *out);
extern "c" I32 access(U8 *path, I32 mode);

class App
{
  Screen *scr;
  Station *st;
  Team team;
  Link link;
  U8 port[256];
  I64 mode;
  U8 input[INPUT_MAX + 1];
  I64 input_len;
  I64 kind;               // KIND_NOTE, KIND_CHAT or KIND_SCOPE
  I64 phase;
  I64 scope_step;
  U8 scope[5][64];
  U8 name[NAME_MAX];
  U8 pass[128];
  U8 msg[128];
  I64 msg_color;
  I64 scroll;
  I64 last_beat;
  I64 wipe_armed;         // time() of the first F12 press, 0 if not armed
  Bool quit;
  Bool help;
  I64 key_from[12];       // key bar items, for mouse clicks
  I64 key_to[12];
  I64 key_sym[12];
  I64 key_count;
  I32 panel_fd;           // -1 without a panel
  U8 panel_line[32];
  I64 panel_len;
  I64 panel_problems;     // problem count last reported, to beep on new ones
  Bool panel_join;        // join request already beeped for
  I64 order[LOG_MAX];
};

U0 Say(App *a, U8 *text, I64 color)
{
  CopyText(a->msg, text, 128);
  a->msg_color = color;
}

U0 ClockText(I64 t, U8 *out)
{
  Tm tm;
  localtime_r(&t, &tm);
  snprintf(out, 8, "%02d:%02d", tm.hour, tm.min);
}

U0 ClearInput(App *a)
{
  sodium_memzero(a->input, INPUT_MAX + 1);
  a->input_len = 0;
}

Bool IsAdmin(Station *s)
{
  if (s->log->has_admin && Same(s->log->admin, s->pk, PK_BYTES))
    return TRUE;
  return FALSE;
}

U0 Send(App *a, U8 *msg, I64 len)
{
  if (len > 0)
    LinkSend(&a->link, msg, len);
}

U0 PostAndSend(App *a, I64 kind, I64 phase, U8 *body, I64 len)
{
  U8 *msg = MAlloc(MSG_MAX);
  I64 n = Post(a->st, kind, phase, body, len, msg);
  if (n > 0) {
    Send(a, msg, n);
    a->scroll = 0;
  } else {
    Say(a, "Not posted: this station has no team key yet.", RED);
  }
  Free(msg);
}

// ---- input --------------------------------------------------------------

Bool ScopeStepOk(App *a, U8 *text)
{
  I64 step = a->scope_step;
  if (step == 0 && StrLen(text) > 0 && StrLen(text) <= 24 && strchr(text, '|') == NULL)
    return TRUE;
  if (step == 1) {
    if (StrLen(text) == 1 && text[0] >= '1' && text[0] <= '5') {
      StrCpy(text, g_data_types[text[0] - '1']);
      return TRUE;
    }
    for (I64 i = 0; i < 5; i++)
      if (strcasecmp(text, g_data_types[i]) == 0) {
        StrCpy(text, g_data_types[i]);
        return TRUE;
      }
    return FALSE;
  }
  if (step == 2 && StrLen(text) > 0 && StrLen(text) <= 4 && strchr(text, '|') == NULL) {
    for (I64 i = 0; text[i]; i++)
      if (text[i] >= 'a' && text[i] <= 'z')
        text[i] -= 32;
    return TRUE;
  }
  if (step == 3) {
    if (!StrCmp(text, "?"))
      return TRUE;
    if (StrLen(text) == 0 || StrLen(text) > 10)
      return FALSE;
    for (I64 i = 0; text[i]; i++)
      if (text[i] < '0' || text[i] > '9')
        return FALSE;
    return TRUE;
  }
  if (step == 4 && StrLen(text) == 1 && text[0] >= '1' && text[0] <= '5') {
    StrCpy(text, g_scope_status[text[0] - '1']);
    return TRUE;
  }
  return FALSE;
}

U0 SubmitReady(App *a)
{
  if (a->input_len == 0)
    return;
  if (a->kind == KIND_SCOPE) {
    if (!ScopeStepOk(a, a->input)) {
      Say(a, "That doesn't fit this field. See the line below the prompt.", RED);
      return;
    }
    CopyText(a->scope[a->scope_step], a->input, 64);
    ClearInput(a);
    a->scope_step++;
    if (a->scope_step == 5) {
      U8 body[BODY_MAX];
      snprintf(body, BODY_MAX, "%s|%s|%s|%s|%s", a->scope[0], a->scope[1], a->scope[2], a->scope[3], a->scope[4]);
      PostAndSend(a, KIND_SCOPE, a->phase, body, StrLen(body));
      a->scope_step = 0;
      Say(a, "Scope updated.", BLUE);
    }
    return;
  }
  PostAndSend(a, a->kind, a->phase, a->input, a->input_len);
  ClearInput(a);
  Say(a, "", BLUE);
}

U0 SubmitSetup(App *a)
{
  if (a->mode == MODE_NEW_NAME) {
    if (a->input_len == 0)
      return;
    CopyText(a->name, a->input, NAME_MAX);
    a->mode = MODE_NEW_PASS;
    Say(a, "", BLUE);
  } else if (a->mode == MODE_NEW_PASS) {
    if (a->input_len < PASS_MIN) {
      Say(a, "Use at least 8 characters. A short sentence works well.", RED);
      return;
    }
    CopyText(a->pass, a->input, 128);
    a->mode = MODE_NEW_PASS2;
    Say(a, "", BLUE);
  } else if (a->mode == MODE_NEW_PASS2) {
    if (StrCmp(a->pass, a->input)) {
      Say(a, "The two passphrases differ. Choose one again.", RED);
      a->mode = MODE_NEW_PASS;
    } else if (StationCreate(a->st, a->st->dir, a->name, a->pass)) {
      a->mode = MODE_NEW_CHOICE;
      Say(a, "Station created. Its keys are sealed with your passphrase.", BLUE);
    } else {
      Say(a, "Could not write the station directory.", RED);
    }
    sodium_memzero(a->pass, 128);
  } else if (a->mode == MODE_NEW_TITLE) {
    if (a->input_len == 0)
      return;
    U8 *msg = MAlloc(MSG_MAX);
    Send(a, msg, StartIncident(a->st, a->input, msg));
    Free(msg);
    a->mode = MODE_READY;
    Say(a, "Incident opened. You are the admin.", BLUE);
  } else if (a->mode == MODE_UNLOCK) {
    U8 *dir = StrNew(a->st->dir);
    if (StationOpen(a->st, dir, a->input)) {
      a->mode = MODE_READY;
      if (a->st->damaged_on_load > 0)
        Say(a, "Log file has damaged records. Affected entries are marked.", RED);
      else
        Say(a, "Unlocked.", BLUE);
    } else {
      StationInit(a->st, dir);
      Say(a, "Wrong passphrase.", RED);
    }
    Free(dir);
  }
  ClearInput(a);
}

U0 OnText(App *a, U8 *text)
{
  if (a->mode == MODE_NEW_CHOICE) {
    if (text[0] == 's' || text[0] == 'S') {
      a->mode = MODE_NEW_TITLE;
      Say(a, "", BLUE);
    } else if (text[0] == 'j' || text[0] == 'J') {
      a->mode = MODE_READY;
      Say(a, "Join request sent. Read your code to the admin.", BLUE);
    }
    return;
  }
  for (I64 i = 0; text[i]; i++)
    if (text[i] >= 32 && text[i] < 127 && a->input_len < INPUT_MAX)
      a->input[a->input_len++] = text[i];
  a->input[a->input_len] = 0;
}

U0 OnKey(App *a, I64 sym)
{
  if (a->help) {
    if (sym == KEY_F1 || sym == KEY_ESCAPE)
      a->help = FALSE;
    return;
  }
  if (sym == KEY_F1 && a->mode == MODE_READY && a->st->epoch >= 0) {
    a->help = TRUE;
    return;
  }
  if (sym == KEY_RETURN) {
    if (a->mode == MODE_READY)
      SubmitReady(a);
    else
      SubmitSetup(a);
  } else if (sym == KEY_BACKSPACE && a->input_len > 0) {
    a->input[--a->input_len] = 0;
  } else if (sym == KEY_ESCAPE) {
    ClearInput(a);
    a->scope_step = 0;
    a->wipe_armed = 0;
    if (a->kind == KIND_SCOPE)
      a->kind = KIND_NOTE;
    Say(a, "", BLUE);
  } else if (sym == KEY_F12) {
    if (a->wipe_armed != 0 && time(NULL) - a->wipe_armed <= 3) {
      StationWipe(a->st);
      a->quit = TRUE;
    } else {
      a->wipe_armed = time(NULL);
      Say(a, "Press F12 again within 3 seconds to wipe the keys from memory and quit.", RED);
    }
  }
  if (a->mode != MODE_READY || a->st->epoch < 0)
    return;
  if (sym == KEY_F2 || sym == KEY_F3 || sym == KEY_F4) {
    if (sym == KEY_F2)
      a->kind = KIND_NOTE;
    if (sym == KEY_F3)
      a->kind = KIND_CHAT;
    if (sym == KEY_F4)
      a->kind = KIND_SCOPE;
    a->scope_step = 0;
    ClearInput(a);
  } else if (sym == KEY_F5) {
    a->phase = a->phase % 4 + 1;
  } else if (sym == KEY_F9 && a->team.join_pending) {
    ApproveJoin(a->st, &a->team, &a->link);
    Say(a, "Member admitted. They now get the team key and the whole log.", BLUE);
  } else if (sym == KEY_PAGEUP) {
    a->scroll += 10;
  } else if (sym == KEY_PAGEDOWN) {
    a->scroll = MaxI64(0, a->scroll - 10);
  }
}

// ---- drawing ------------------------------------------------------------

U0 IncidentTitle(Log *log, U8 *out)
{
  out[0] = 0;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_GENESIS && log->has_admin && Same(e->author, log->admin, PK_BYTES)) {
      U8 *nl = strchr(e->body, '\n');
      if (nl != NULL)
        CopyText(out, nl + 1, 60);
      return;
    }
  }
}

U0 DrawTitle(App *a)
{
  Screen *s = a->scr;
  FillCells(s, 0, ROW_TITLE, COLS, 1, BLUE);
  I64 col = PutText(s, 1, ROW_TITLE, "ARK", WHITE, BLUE);
  U8 title[64];
  IncidentTitle(a->st->log, title);
  if (title[0])
    PutText(s, col + 2, ROW_TITLE, title, YELLOW, BLUE, 50);
  U8 right[64], clock[8];
  ClockText(time(NULL), clock);
  if (a->st->name[0])
    snprintf(right, 64, "%s  %s", a->st->name, clock);
  else
    snprintf(right, 64, "%s", clock);
  PutText(s, COLS - 1 - StrLen(right), ROW_TITLE, right, WHITE, BLUE);
}

// One clickable key on the key bar. The active one is drawn inverted.
U0 KeyItem(App *a, I64 *col, U8 *label, I64 sym, I64 fg, I64 bg)
{
  U8 text[24];
  snprintf(text, 24, " %s ", label);
  I64 from = *col;
  *col = PutText(a->scr, from, ROW_KEYS, text, fg, bg);
  if (a->key_count < 12) {
    a->key_from[a->key_count] = from;
    a->key_to[a->key_count] = *col;
    a->key_sym[a->key_count] = sym;
    a->key_count++;
  }
}

U0 DrawKeys(App *a)
{
  Screen *s = a->scr;
  a->key_count = 0;
  FillCells(s, 0, ROW_KEYS, COLS, 1, LTGRAY);
  I64 col = 0;
  if (a->mode != MODE_READY || a->st->epoch < 0) {
    PutText(s, 1, ROW_KEYS, "Enter confirms   Esc clears   F12 twice wipes keys and quits", BLACK, LTGRAY);
    return;
  }
  if (a->help) {
    KeyItem(a, &col, "F1 Close help", KEY_F1, WHITE, BLUE);
    return;
  }
  KeyItem(a, &col, "F1 Help", KEY_F1, BLACK, LTGRAY);
  I64 bg = LTGRAY, fg = BLACK;
  if (a->kind == KIND_NOTE) { fg = WHITE; bg = BLUE; }
  KeyItem(a, &col, "F2 Note", KEY_F2, fg, bg);
  fg = BLACK; bg = LTGRAY;
  if (a->kind == KIND_CHAT) { fg = WHITE; bg = BLUE; }
  KeyItem(a, &col, "F3 Chat", KEY_F3, fg, bg);
  fg = BLACK; bg = LTGRAY;
  if (a->kind == KIND_SCOPE) { fg = WHITE; bg = BLUE; }
  KeyItem(a, &col, "F4 Scope", KEY_F4, fg, bg);
  KeyItem(a, &col, "F5 Phase", KEY_F5, BLACK, LTGRAY);
  KeyItem(a, &col, "PgUp", KEY_PAGEUP, BLACK, LTGRAY);
  KeyItem(a, &col, "PgDn", KEY_PAGEDOWN, BLACK, LTGRAY);
  KeyItem(a, &col, "F12 Wipe", KEY_F12, BLACK, LTGRAY);
  if (a->team.join_pending)
    KeyItem(a, &col, "F9 Admit", KEY_F9, WHITE, RED);
}

I64 KindColor(I64 kind)
{
  if (kind == KIND_CHAT)
    return PURPLE;
  if (kind == KIND_SCOPE)
    return BROWN;
  if (kind == KIND_MEMBER_ADD)
    return DKGRAY;
  return BLUE;
}

// The text shown for an entry after the time and name.
U0 EntryText(Log *log, Entry *e, U8 *out)
{
  if (e->kind == KIND_GENESIS) {
    U8 *nl = strchr(e->body, '\n');
    if (nl != NULL)
      snprintf(out, BODY_MAX + 128, "opened the incident: %s", nl + 1);
    else
      StrCpy(out, "opened the incident");
  } else if (e->kind == KIND_MEMBER_ADD) {
    U8 name[NAME_MAX];
    if (e->body_len >= PK_BYTES)
      NameOf(log, e->body, name);
    else
      StrCpy(name, "?");
    snprintf(out, BODY_MAX + 128, "admitted %s to the team", name);
  } else if (e->kind == KIND_SCOPE) {
    U8 body[BODY_MAX + 1];
    StrCpy(body, e->body);
    U8 *f[5];
    if (SplitScope(body, f)) {
      U8 *count = f[3], *where = f[2];
      if (!StrCmp(count, "?"))
        count = "unknown number of";
      if (!StrCmp(where, "-"))
        snprintf(out, BODY_MAX + 128, "scope: %s, %s %s records, %s", f[0], count, f[1], f[4]);
      else
        snprintf(out, BODY_MAX + 128, "scope: %s, %s %s records of %s residents, %s", f[0], count, f[1], where, f[4]);
    } else {
      snprintf(out, BODY_MAX + 128, "scope: %s", e->body);
    }
  } else if (e->kind == KIND_NOTE && e->phase >= 1 && e->phase <= 4) {
    snprintf(out, BODY_MAX + 128, "[%s] %s", g_phase_names[e->phase], e->body);
  } else {
    StrCpy(out, e->body);
  }
  for (I64 i = 0; out[i]; i++)
    if (out[i] < 32)
      out[i] = ' ';
}

#define TEXT_COL  16
#define TEXT_W    (COLS - TEXT_COL - 1)

U0 DrawLog(App *a)
{
  Screen *s = a->scr;
  Log *log = a->st->log;
  U8 head[80];
  snprintf(head, 80, "Log  %ld entries", log->count);
  I64 col = PutText(s, 1, ROW_LOG, head, BLUE, WHITE);
  if (log->problems > 0) {
    snprintf(head, 80, " %ld PROBLEMS ", log->problems);
    PutText(s, col + 2, ROW_LOG, head, WHITE, RED);
  }
  if (a->scroll > 0) {
    snprintf(head, 80, "scrolled back %ld lines", a->scroll);
    PutText(s, COLS - 1 - StrLen(head), ROW_LOG, head, DKGRAY, WHITE);
  }

  if (log->count == 0) {
    PutText(s, 3, ROW_LOG + 2, "Nothing logged yet. F2 writes the first note: what was seen, where, by whom.", DKGRAY, WHITE);
    return;
  }

  LogSorted(log, a->order);
  U8 *text = MAlloc(BODY_MAX + 128);
  I64 bottom = ROW_LOG + LOG_LINES;   // first row below the log
  I64 skip = a->scroll;
  I64 row = bottom;
  for (I64 k = log->count - 1; k >= 0 && row > ROW_LOG + 1; k--) {
    Entry *e = &log->entries[a->order[k]];
    EntryText(log, e, text);
    I64 badge_w = 0;
    if (e->status != ST_OK)
      badge_w = StrLen(StatusName(e->status)) + 3;
    I64 len = StrLen(text) + badge_w;
    I64 lines = MaxI64(1, (len + TEXT_W - 1) / TEXT_W);
    lines = MinI64(lines, 4);
    for (I64 line = lines - 1; line >= 0 && row > ROW_LOG + 1; line--) {
      if (skip > 0) {
        skip--;
        continue;
      }
      row--;
      I64 start = line * TEXT_W;
      I64 col_at = TEXT_COL;
      if (line == 0) {
        U8 clock[8], name[NAME_MAX];
        ClockText(e->time, clock);
        NameOf(log, e->author, name);
        PutText(s, 1, row, clock, DKGRAY, WHITE);
        PutText(s, 7, row, name, BLACK, WHITE, 8);
        if (badge_w > 0) {
          U8 badge[32];
          snprintf(badge, 32, " %s ", StatusName(e->status));
          col_at = PutText(s, TEXT_COL, row, badge, WHITE, RED) + 1;
        }
      } else {
        start -= badge_w;
      }
      I64 fg = KindColor(e->kind);
      if (e->status != ST_OK)
        fg = DKGRAY;
      if (start < StrLen(text))
        PutText(s, col_at, row, text + start, fg, WHITE, COLS - 1 - col_at);
    }
  }
  Free(text);
}

// The latest valid SCOPE entry for each asset.
I64 ScopeColor(U8 *status, I64 *bg)
{
  *bg = WHITE;
  if (!StrCmp(status, "EXFILTRATED")) {
    *bg = RED;
    return WHITE;
  }
  if (!StrCmp(status, "ENCRYPTED")) {
    *bg = PURPLE;
    return WHITE;
  }
  if (!StrCmp(status, "SUSPECTED")) {
    *bg = YELLOW;
    return BLACK;
  }
  if (!StrCmp(status, "CONTAINED")) {
    *bg = CYAN;
    return BLACK;
  }
  if (!StrCmp(status, "CLEAN")) {
    *bg = GREEN;
    return BLACK;
  }
  return BLACK;
}

U0 DrawScope(App *a)
{
  Screen *s = a->scr;
  Log *log = a->st->log;
  RuleCells(s, 0, ROW_SCOPE - 1, COLS, LTGRAY);
  PutText(s, 1, ROW_SCOPE, "Scope  what data is affected, latest status per asset", BROWN, WHITE);
  PutText(s, 1, ROW_SCOPE + 1, "Asset                    Data   Resid. Records     Status", DKGRAY, WHITE);

  LogSorted(log, a->order);
  U8 seen[SCOPE_LINES][32];
  I64 rows = 0;
  U8 body[BODY_MAX + 1];
  for (I64 k = log->count - 1; k >= 0 && rows < SCOPE_LINES - 2; k--) {
    Entry *e = &log->entries[a->order[k]];
    if (e->kind != KIND_SCOPE || e->status != ST_OK)
      continue;
    StrCpy(body, e->body);
    U8 *f[5];
    if (!SplitScope(body, f))
      continue;
    Bool dup = FALSE;
    for (I64 i = 0; i < rows; i++)
      if (!StrCmp(seen[i], f[0]))
        dup = TRUE;
    if (dup)
      continue;
    CopyText(seen[rows], f[0], 32);
    I64 row = ROW_SCOPE + 2 + rows;
    PutText(s, 1, row, f[0], BLACK, WHITE, 24);
    PutText(s, 26, row, f[1], BLACK, WHITE, 6);
    PutText(s, 33, row, f[2], BLACK, WHITE, 6);
    PutText(s, 40, row, f[3], BLACK, WHITE, 11);
    I64 bg;
    I64 fg = ScopeColor(f[4], &bg);
    U8 badge[20];
    snprintf(badge, 20, " %s ", f[4]);
    PutText(s, 52, row, badge, fg, bg);
    rows++;
  }
  if (rows == 0)
    PutText(s, 3, ROW_SCOPE + 2, "No affected data recorded. F4 adds a system or dataset that was hit.", DKGRAY, WHITE);
}

U0 DrawClocks(App *a)
{
  Screen *s = a->scr;
  PutText(s, 1, ROW_CLOCKS, "Deadlines", BROWN, WHITE);
  PutText(s, 11, ROW_CLOCKS, "counted from the first affected entry. Not legal advice.", DKGRAY, WHITE);
  Clock clocks[RULES];
  I64 n = Deadlines(a->st->log, clocks);
  if (n == 0) {
    PutText(s, 3, ROW_CLOCKS + 1, "None running. A clock starts when data is marked exfiltrated or encrypted.", DKGRAY, WHITE);
    return;
  }
  I64 now = time(NULL);
  for (I64 i = 0; i < n && i < CLOCK_LINES; i++) {
    I64 row = ROW_CLOCKS + 1 + i;
    I64 left = clocks[i].due - now;
    U8 when[24];
    RemainingText(left, when);
    I64 fg = BLACK, bg = WHITE;
    if (left < 72 * 3600) {
      fg = WHITE;
      bg = RED;
    } else if (left < 7 * 86400) {
      fg = BLACK;
      bg = YELLOW;
    }
    U8 cell[24];
    snprintf(cell, 24, " %s ", when);
    PutText(s, 1, row, cell, fg, bg);
    U8 who[48];
    if (clocks[i].unsure)
      snprintf(who, 48, "%s (if 250+ records)", g_rule_who[clocks[i].rule]);
    else
      snprintf(who, 48, "%s", g_rule_who[clocks[i].rule]);
    PutText(s, 20, row, who, BLACK, WHITE, 30);
    PutText(s, 50, row, g_rule_cite[clocks[i].rule], DKGRAY, WHITE, 30);
  }
  if (n > CLOCK_LINES) {
    U8 more[24];
    snprintf(more, 24, "+%ld more", n - CLOCK_LINES);
    PutText(s, COLS - 1 - StrLen(more), ROW_CLOCKS, more, DKGRAY, WHITE);
  }
}

// While adding an asset the scope table makes room for a form that shows
// every field, what each one means, and the choices where there are some.
U0 DrawScopeForm(App *a)
{
  Screen *s = a->scr;
  RuleCells(s, 0, ROW_SCOPE - 1, COLS, LTGRAY);
  U8 head[80];
  snprintf(head, 80, "Add an affected system or dataset, field %ld of 5", a->scope_step + 1);
  PutText(s, 1, ROW_SCOPE, head, BROWN, WHITE);
  PutText(s, 58, ROW_SCOPE, "Esc cancels", DKGRAY, WHITE);
  for (I64 i = 0; i < 5; i++) {
    I64 row = ROW_SCOPE + 1 + i;
    if (i == a->scope_step) {
      FillCells(s, 0, row, COLS, 1, LTGRAY);
      PutText(s, 1, row, ">", BLUE, LTGRAY);
      PutText(s, 3, row, g_scope_fields[i], BLACK, LTGRAY);
      PutText(s, 17, row, a->input, BLUE, LTGRAY, 60);
    } else {
      PutText(s, 3, row, g_scope_fields[i], DKGRAY, WHITE);
      if (i < a->scope_step)
        PutText(s, 17, row, a->scope[i], BLACK, WHITE, 60);
    }
  }
  PutText(s, 1, ROW_CHOICES - 1, g_scope_help[a->scope_step], BLUE, WHITE);
  U8 **lines = NULL;
  if (a->scope_step == 1)
    lines = g_type_lines;
  if (a->scope_step == 4)
    lines = g_status_lines;
  if (lines != NULL)
    for (I64 i = 0; i < 5; i++)
      PutText(s, 3, ROW_CHOICES + i, lines[i], BLACK, WHITE);
}

U8 *g_help[] = {
  "What ARK is",
  "  A logbook for a cyber incident that never touches the company network.",
  "  Every line is signed by the person who wrote it. Nobody can edit it later.",
  "",
  "Writing",
  "  F2 Note   what happened or what was done, tagged with the current phase",
  "  F3 Chat   talk to the team. Chat is kept in the log too.",
  "  F4 Scope  record a system or dataset that was hit and what happened to it",
  "  F5 Phase  which stage of the response your notes belong to:",
  "              DETECT     confirming what happened and how far it reaches",
  "              CONTAIN    stopping the spread: isolate, block, reset passwords",
  "              ERADICATE  removing the attacker and their tools",
  "              RECOVER    restoring systems and watching for a return",
  "",
  "Reading the screen",
  "  Deadlines     legal notice clocks. An Exfiltrated or Encrypted asset starts",
  "                them. They are a reminder for counsel, not legal advice.",
  "  CHAIN BROKEN  an entry before this one is missing or was changed",
  "  NOT A MEMBER  written by someone the admin never admitted",
  "  FORKED        one person signed two different versions of the same entry",
  "  REJECTED      messages that failed the seal or signature check",
  "",
  "Team",
  "  A new person starts ARK, presses J, and reads out the 6-digit code.",
  "  The admin checks that it matches and presses F9 or the panel's green button.",
  "",
  "Panic",
  "  F12 twice, or the panel's red button: keys are wiped and ARK quits.",
  "  The log on disk stays sealed. Your passphrase opens it again.",
  "",
  "The mouse works on the key bar above and on the numbered choices.",
  NULL
};

U0 DrawHelp(App *a)
{
  Screen *s = a->scr;
  for (I64 i = 0; g_help[i] != NULL; i++) {
    I64 fg = BLACK;
    if (g_help[i][0] != ' ')
      fg = BLUE;
    PutText(a->scr, 2, ROW_LOG + 1 + i, g_help[i], fg, WHITE);
  }
}

U0 DrawPhases(App *a)
{
  Screen *s = a->scr;
  I64 col = PutText(s, 1, ROW_HELP, "F5 phase:", DKGRAY, WHITE) + 1;
  for (I64 p = 1; p <= 4; p++) {
    U8 name[16];
    snprintf(name, 16, " %s ", g_phase_names[p]);
    if (p == a->phase)
      col = PutText(s, col, ROW_HELP, name, WHITE, BLUE);
    else
      col = PutText(s, col, ROW_HELP, name, DKGRAY, WHITE);
  }
}

U0 DrawPrompt(App *a, U8 *label, U8 *help, Bool secret)
{
  Screen *s = a->scr;
  RuleCells(s, 0, ROW_INPUT - 1, COLS, LTGRAY);
  U8 tag[64];
  snprintf(tag, 64, " %s ", label);
  I64 col = PutText(s, 0, ROW_INPUT, tag, WHITE, BLUE) + 1;
  I64 room = COLS - col - 1;
  I64 start = MaxI64(0, a->input_len - room + 1);
  for (I64 i = start; i < a->input_len; i++) {
    U8 ch = a->input[i];
    if (secret)
      ch = '*';
    PutChar(s, col++, ROW_INPUT, ch, BLACK, WHITE);
  }
  PutChar(s, col, ROW_INPUT, ' ', WHITE, BLUE);
  PutText(s, 1, ROW_HELP, help, DKGRAY, WHITE);
}

U0 DrawJoinWait(App *a)
{
  Screen *s = a->scr;
  U8 code[32];
  I64 c = JoinCode(a->st->pk);
  snprintf(code, 32, "%03ld %03ld", c / 1000, c % 1000);
  PutText(s, 6, 10, "Waiting to be admitted to an incident.", BLUE, WHITE);
  PutText(s, 6, 13, "Read this code out loud to the admin:", BLACK, WHITE);
  // Each digit drawn 3x larger so it can be read across a table.
  for (I64 i = 0; code[i]; i++) {
    I64 index = code[i];
    U8 *g = &sys_font_std[index * 8];
    for (I64 y = 0; y < 8; y++)
      for (I64 x = 0; x < 8; x++)
        if (g[y] & (1 << x))
          FillCells(s, 6 + i * 9 + x, 16 + y, 1, 1, BLUE);
  }
  PutText(s, 6, 27, "The admin sees the same code next to your name.", BLACK, WHITE);
  PutText(s, 6, 28, "If the codes differ, someone else is asking to join. Say so.", BLACK, WHITE);
}

U0 DrawJoinRequest(App *a)
{
  Screen *s = a->scr;
  U8 line[96];
  I64 c = JoinCode(a->team.join_pk);
  snprintf(line, 96, " %s asks to join. Code %03ld %03ld. Codes match? F9 admits. ", a->team.join_name, c / 1000, c % 1000);
  PutText(s, 0, ROW_HELP, line, WHITE, RED);
}

U0 DrawStatus(App *a)
{
  Screen *s = a->scr;
  FillCells(s, 0, ROW_STATUS, COLS, 1, LTGRAY);
  U8 line[128];
  I64 col = 1;
  if (a->link.fd < 0) {
    col = PutText(s, col, ROW_STATUS, " NO RELAY ", WHITE, RED) + 1;
  } else {
    snprintf(line, 128, "Relay %s", a->port);
    col = PutText(s, col, ROW_STATUS, line, BLACK, LTGRAY, 24) + 2;
  }
  if (a->panel_fd >= 0)
    col = PutText(s, col, ROW_STATUS, "Panel", BLACK, LTGRAY) + 2;
  I64 now = time(NULL);
  for (I64 i = 0; i < a->team.peer_count; i++) {
    Peer *p = &a->team.peers[i];
    if (now - p->heard > 3 * BEAT_SECS)
      continue;
    col = PutText(s, col, ROW_STATUS, p->name, BLUE, LTGRAY, 10) + 1;
  }
  if (a->st->rejected > 0) {
    snprintf(line, 128, " %ld REJECTED ", a->st->rejected);
    PutText(s, COLS - 1 - StrLen(line), ROW_STATUS, line, WHITE, RED);
  }
}

U0 Draw(App *a)
{
  Screen *s = a->scr;
  FillCells(s, 0, 0, COLS, ROWS, WHITE);
  DrawTitle(a);
  DrawKeys(a);

  if (a->mode == MODE_NEW_NAME) {
    PutText(s, 6, 10, "New station.", BLUE, WHITE);
    PutText(s, 6, 12, "Everything this station writes is signed with a key made here", BLACK, WHITE);
    PutText(s, 6, 13, "and sealed on disk with your passphrase.", BLACK, WHITE);
    DrawPrompt(a, "Your name", "The name other stations will see next to your entries.", FALSE);
  } else if (a->mode == MODE_NEW_PASS) {
    DrawPrompt(a, "Passphrase", "At least 8 characters. Nobody can recover it for you.", TRUE);
  } else if (a->mode == MODE_NEW_PASS2) {
    DrawPrompt(a, "Again", "Type the same passphrase again.", TRUE);
  } else if (a->mode == MODE_NEW_CHOICE) {
    PutText(s, 6, 12, "S  start a new incident (you become its admin)", BLUE, WHITE);
    PutText(s, 6, 14, "J  join an incident someone else started", BLUE, WHITE);
    DrawPrompt(a, "S or J", "", FALSE);
  } else if (a->mode == MODE_NEW_TITLE) {
    DrawPrompt(a, "Incident title", "Short and specific, for example: Ransomware on FS-01", FALSE);
  } else if (a->mode == MODE_UNLOCK) {
    PutText(s, 6, 12, "This station is locked.", BLUE, WHITE);
    DrawPrompt(a, "Passphrase", "", TRUE);
  } else if (a->st->epoch < 0) {
    DrawJoinWait(a);
  } else if (a->help) {
    DrawHelp(a);
  } else {
    DrawLog(a);
    U8 label[48];
    if (a->kind == KIND_SCOPE) {
      DrawScopeForm(a);
      snprintf(label, 48, "%s", g_scope_fields[a->scope_step]);
      DrawPrompt(a, label, "Enter goes to the next field.", FALSE);
    } else {
      DrawScope(a);
      DrawClocks(a);
      if (a->kind == KIND_CHAT) {
        DrawPrompt(a, "Chat", "Talk to the team. Enter sends.", FALSE);
      } else {
        snprintf(label, 48, "Note %s", g_phase_names[a->phase]);
        DrawPrompt(a, label, "", FALSE);
        DrawPhases(a);
      }
    }
    if (a->team.join_pending)
      DrawJoinRequest(a);
  }
  PutText(s, 1, ROW_MSG, a->msg, a->msg_color, WHITE);
  DrawStatus(a);
  ScreenPresent(s);
}

// ---- panel --------------------------------------------------------------

U0 PanelSend(App *a, U8 *text)
{
  if (a->panel_fd >= 0)
    WriteAll(a->panel_fd, text, StrLen(text));
}

I64 ProblemCount(App *a)
{
  return a->st->log->problems + a->st->rejected + a->st->damaged_on_load;
}

// Lights and beeps follow the log. The state is resent with every
// heartbeat, because opening the port resets the UNO and it misses
// whatever was sent while it booted.
U0 PanelUpdate(App *a, Bool resend)
{
  if (a->panel_fd < 0)
    return;
  I64 problems = ProblemCount(a);
  if (problems > a->panel_problems)
    PanelSend(a, "B\n");
  if (a->team.join_pending && !a->panel_join)
    PanelSend(a, "B\n");
  a->panel_join = a->team.join_pending;
  if (resend || problems != a->panel_problems) {
    if (problems > 0)
      PanelSend(a, "R\n");
    else
      PanelSend(a, "G\n");
  }
  a->panel_problems = problems;
}

U0 PanelCommand(App *a, U8 *line)
{
  if (!StrCmp(line, "PANIC")) {
    StationWipe(a->st);
    a->quit = TRUE;
  } else if (!StrCmp(line, "APPROVE") && a->mode == MODE_READY && a->team.join_pending) {
    ApproveJoin(a->st, &a->team, &a->link);
    Say(a, "Member admitted from the panel.", BLUE);
  }
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

// ---- main loop ----------------------------------------------------------

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
}

U0 OnClick(App *a, I64 col, I64 row)
{
  if (row == ROW_KEYS) {
    for (I64 i = 0; i < a->key_count; i++)
      if (col >= a->key_from[i] && col < a->key_to[i])
        OnKey(a, a->key_sym[i]);
    return;
  }
  Bool choices = a->kind == KIND_SCOPE && (a->scope_step == 1 || a->scope_step == 4);
  if (a->mode == MODE_READY && !a->help && choices && row >= ROW_CHOICES && row < ROW_CHOICES + 5) {
    ClearInput(a);
    a->input[0] = '1' + row - ROW_CHOICES;
    a->input[1] = 0;
    a->input_len = 1;
    SubmitReady(a);
  }
}

U0 PollLink(App *a)
{
  if (a->link.fd < 0 || a->mode != MODE_READY)
    return;
  U8 *msg = MAlloc(MSG_MAX);
  I64 n;
  while ((n = LinkPoll(&a->link, msg)) > 0)
    TeamReceive(a->st, &a->team, &a->link, msg, n);
  Free(msg);
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
  App *a = CAlloc(sizeof(App));
  a->scr = CAlloc(sizeof(Screen));
  a->st = MAlloc(sizeof(Station));
  StationInit(a->st, argv[1]);
  CopyText(a->port, argv[2], 256);
  a->kind = KIND_NOTE;
  a->phase = PHASE_DETECT;
  if (!LinkOpen(&a->link, argv[2]))
    a->link.fd = -1;
  a->panel_fd = -1;
  if (argc > 3)
    a->panel_fd = open(argv[3], O_RDWR | O_NOCTTY | O_NONBLOCK);

  U8 *secrets = StationPath(a->st, "secrets");
  if (access(secrets, 0) == 0)
    a->mode = MODE_UNLOCK;
  else
    a->mode = MODE_NEW_NAME;
  Free(secrets);

  U8 *title = MStrPrint("ARK  %s", argv[1]);
  if (!ScreenOpen(a->scr, title, 2)) {
    "could not open a window: %s\n", SDL_GetError();
    return 1;
  }
  Free(title);

  U8 ev[SDL_EVENT_BYTES];
  while (!a->quit) {
    if (SDL_WaitEventTimeout(ev, 50)) {
      do {
        U32 type = *(ev(U32 *));
        if (type == SDL_QUIT)
          a->quit = TRUE;
        else if (type == SDL_TEXTINPUT)
          OnText(a, ev + EV_TEXT);
        else if (type == SDL_KEYDOWN)
          OnKey(a, *((ev + EV_KEY_SYM)(I32 *)));
        else if (type == SDL_MOUSEBUTTONDOWN) {
          I64 col, row;
          if (ScreenCell(a->scr, *((ev + EV_MOUSE_X)(I32 *)), *((ev + EV_MOUSE_Y)(I32 *)), &col, &row))
            OnClick(a, col, row);
        }
      } while (SDL_PollEvent(ev));
    }
    PollLink(a);
    PollPanel(a);
    PanelUpdate(a, FALSE);
    Heartbeat(a);
    Draw(a);
  }
  StationWipe(a->st);
  ScreenClose(a->scr);
  return 0;
}
