// Server events: what happened on the watched server, one per log entry.
//
// tools/ark-watch reads the server's journal (shell commands, sudo, SSH
// logins, failed logins) and optionally a web access log, and appends one
// line per event to DIR/feed:
//
//   source TAB user TAB host TAB detail NEWLINE
//
// The station turns each line into a KIND_EVENT entry, body
// "source|user|host|detail", signs it and sends it to the team. Risk is
// worked out by each station from the body, so the rules can change
// without rewriting the log.

extern "c" U8 *strstr(U8 *hay, U8 *needle);
extern "c" U8 *strcasestr(U8 *hay, U8 *needle);

#define EV_SHELL     0   // a command typed at a shell
#define EV_SUDO      1   // a command run through sudo
#define EV_LOGIN     2   // a successful login
#define EV_FAIL      3   // a failed login or su/sudo password
#define EV_REQUEST   4   // a web request
#define EV_ACCOUNT   5   // a user or group created or changed
#define EV_SOURCES   6

#define RISK_NONE    0
#define RISK_WATCH   1
#define RISK_SUS     2

#define EV_USER_MAX   32
#define EV_HOST_MAX   48
#define EV_DETAIL_MAX 600

U8 *g_ev_source[EV_SOURCES] = {"shell", "sudo", "login", "fail", "request", "account"};
U8 *g_ev_label[EV_SOURCES] = {"Command", "sudo", "Login", "Failed login", "Request", "Account"};

class Event
{
  I64 source;
  U8 user[EV_USER_MAX + 1];
  U8 host[EV_HOST_MAX + 1];
  U8 detail[EV_DETAIL_MAX + 1];
};

I64 SourceOf(U8 *name)
{
  for (I64 i = 0; i < EV_SOURCES; i++)
    if (StrCmp(name, g_ev_source[i]) == 0)
      return i;
  return -1;
}

// Copies at most max bytes of src into dst, keeping printable ASCII only.
// '|' separates body fields, so it becomes '/'. Returns the length.
I64 CleanField(U8 *dst, U8 *src, I64 src_len, I64 max)
{
  I64 n = 0;
  for (I64 i = 0; i < src_len && n < max; i++) {
    U8 ch = src[i];
    if (ch == '|')
      ch = '/';
    if (ch < 32 || ch > 126)
      ch = ' ';
    dst[n++] = ch;
  }
  while (n > 0 && dst[n - 1] == ' ')
    n--;
  dst[n] = 0;
  return n;
}

// Parses one feed line (no newline). FALSE if it isn't four fields with a
// known source, a user and a detail.
Bool FeedLine(U8 *line, I64 len, Event *ev)
{
  I64 starts[4], lens[4], n = 0, start = 0;
  for (I64 i = 0; i <= len && n < 4; i++) {
    if (i == len || line[i] == '\t') {
      starts[n] = start;
      lens[n] = i - start;
      n++;
      start = i + 1;
    }
  }
  if (n != 4)
    return FALSE;
  // A fifth field means the detail held a tab: keep the rest of the line.
  lens[3] = len - starts[3];
  U8 src[16];
  if (lens[0] >= 16)
    return FALSE;
  CleanField(src, line + starts[0], lens[0], 15);
  ev->source = SourceOf(src);
  if (ev->source < 0)
    return FALSE;
  if (CleanField(ev->user, line + starts[1], lens[1], EV_USER_MAX) == 0)
    return FALSE;
  if (CleanField(ev->host, line + starts[2], lens[2], EV_HOST_MAX) == 0)
    StrCpy(ev->host, "?");
  if (CleanField(ev->detail, line + starts[3], lens[3], EV_DETAIL_MAX) == 0)
    return FALSE;
  return TRUE;
}

I64 EventBody(Event *ev, U8 *out)
{
  snprintf(out, BODY_MAX, "%s|%s|%s|%s", g_ev_source[ev->source], ev->user, ev->host, ev->detail);
  return StrLen(out);
}

// Splits a KIND_EVENT body. The detail is everything after the third '|'.
Bool EventFromBody(U8 *body, Event *ev)
{
  I64 bars[3], n = 0;
  for (I64 i = 0; body[i] && n < 3; i++)
    if (body[i] == '|')
      bars[n++] = i;
  if (n < 3)
    return FALSE;
  U8 src[16];
  if (bars[0] >= 16)
    return FALSE;
  MemCpy(src, body, bars[0]);
  src[bars[0]] = 0;
  ev->source = SourceOf(src);
  if (ev->source < 0)
    return FALSE;
  CleanField(ev->user, body + bars[0] + 1, bars[1] - bars[0] - 1, EV_USER_MAX);
  CleanField(ev->host, body + bars[1] + 1, bars[2] - bars[1] - 1, EV_HOST_MAX);
  CopyText(ev->detail, body + bars[2] + 1, EV_DETAIL_MAX + 1);
  return TRUE;
}

// One rule per string: risk (2 suspicious, 1 watch), TAB, text matched
// case-insensitively anywhere in the detail, TAB, why it matters. The
// first match wins, so the specific patterns come first.
#define RULES_N 43
U8 *g_rules[RULES_N] = {
  "2\t/etc/shadow\treads or changes the password hashes",
  "2\thistory -c\tclears the shell history",
  "2\tunset histfile\tturns off shell history",
  "2\thistfile=/dev/null\tturns off shell history",
  "2\tshred \tdestroys files beyond recovery",
  "2\trm -rf\tdeletes a tree of files",
  "2\trm -fr\tdeletes a tree of files",
  "2\t| sh\tpipes a download straight into a shell",
  "2\t|sh\tpipes a download straight into a shell",
  "2\t| bash\tpipes a download straight into a shell",
  "2\t|bash\tpipes a download straight into a shell",
  "2\tnc -e\topens a reverse shell",
  "2\tncat \topens a raw network connection",
  "2\t/dev/tcp/\topens a reverse shell",
  "2\tbase64 -d\tdecodes a hidden payload",
  "2\topenssl enc\tencrypts files",
  "2\tgpg -c\tencrypts files",
  "2\tauthorized_keys\tadds an SSH key for later access",
  "2\tcrontab\tschedules a command to come back",
  "2\tuseradd\tcreates a user",
  "2\tusermod\tchanges a user's groups",
  "2\tpasswd\tchanges a password",
  "2\tchmod 777\topens files to everyone",
  "2\tchmod +s\tmakes a program run as its owner",
  "2\tiptables -f\tdrops every firewall rule",
  "2\tsystemctl stop\tstops a service",
  "2\tmysqldump\tdumps a database",
  "2\tpg_dump\tdumps a database",
  "2\txmrig\truns a crypto miner",
  "2\t.lck\ttouches ransomware-locked files",
  "2\t/wp-admin\tprobes for an admin page",
  "2\t/.env\tprobes for secret config",
  "2\t../\ttries to escape the web root",
  "2\tunion select\ttries SQL injection",
  "2\t<script\ttries script injection",
  "2\tcurl -t \tuploads files off the server",
  "2\tcurl --upload\tuploads files off the server",
  "2\ttransfer.sh\tuploads files off the server",
  "1\tcurl \tdownloads or uploads data",
  "1\twget \tdownloads data",
  "1\tscp \tcopies files to another machine",
  "1\trsync \tcopies files to another machine",
  "1\ttar \tpacks files into an archive"
};

// How worrying an event is, and in a few words why. hour is the local hour
// it happened, for flagging logins in the middle of the night.
I64 EventRisk(Event *ev, I64 hour, U8 **why)
{
  for (I64 i = 0; i < RULES_N; i++) {
    U8 *rule = g_rules[i];
    U8 *tab = strchr(rule + 2, '\t');
    U8 needle[48];
    CopyText(needle, rule + 2, MinI64(48, tab - (rule + 2) + 1));
    if (strcasestr(ev->detail, needle) != NULL) {
      *why = tab + 1;
      return rule[0] - '0';
    }
  }
  if (ev->source == EV_ACCOUNT) {
    *why = "an account changed";
    return RISK_SUS;
  }
  if (ev->source == EV_FAIL) {
    *why = "a wrong password";
    return RISK_WATCH;
  }
  if (ev->source == EV_LOGIN && StrCmp(ev->user, "root") == 0) {
    *why = "someone logged in as root";
    return RISK_SUS;
  }
  if (ev->source == EV_LOGIN && (hour < 6 || hour >= 22)) {
    *why = "a login outside working hours";
    return RISK_WATCH;
  }
  if (ev->source == EV_SUDO) {
    *why = "a command run as root";
    return RISK_WATCH;
  }
  if (ev->source == EV_REQUEST && (strstr(ev->detail, " 401") != NULL || strstr(ev->detail, " 403") != NULL)) {
    *why = "a refused request";
    return RISK_WATCH;
  }
  *why = "";
  return RISK_NONE;
}

// Eight hex characters naming an entry, used by alerts that report one.
U0 EntryRef(Entry *e, U8 *out)
{
  snprintf(out, 12, "%02x%02x%02x%02x", e->hash[0], e->hash[1], e->hash[2], e->hash[3]);
}
