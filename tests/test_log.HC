// Log and station behaviour without a relay: messages are handed from one
// station to another directly. Uses build/tmp-log/ as scratch space.

#include "../src/util.HC"
#include "../src/crypto.HC"
#include "../src/link.HC"
#include "../src/log.HC"
#include "../src/station.HC"

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

// Messages kept so they can be delivered to other stations later.
#define KEEP 32
U8 *g_msg[KEEP];
I64 g_len[KEEP];
I64 g_kept = 0;
U8 out[MSG_MAX];

I64 Keep(U8 *msg, I64 len)
{
  g_msg[g_kept] = MAlloc(len);
  MemCpy(g_msg[g_kept], msg, len);
  g_len[g_kept] = len;
  return g_kept++;
}

I64 PostText(Station *s, I64 kind, U8 *text)
{

  I64 len = Post(s, kind, PHASE_CONTAIN, text, StrLen(text), out);
  return Keep(out, len);
}

U0 GiveKey(Station *from, Station *to)
{
  MemCpy(to->keys[0], from->keys[0], KEY_BYTES);
  to->have_key[0] = TRUE;
  to->epoch = 0;
}

I64 StatusOf(Station *s, U8 *author, I64 seq)
{
  Entry *e = LogFind(s->log, author, seq);
  if (e == NULL)
    return -1;
  return e->status;
}

I32 Main()
{
  CryptoInit();
  Station *a = MAlloc(sizeof(Station)), *b = MAlloc(sizeof(Station));
  Station *c = MAlloc(sizeof(Station)), *d = MAlloc(sizeof(Station));
  Check(StationCreate(a, "build/tmp-log/a", "Admin", "correct horse"), "create admin station");
  StationCreate(b, "build/tmp-log/b", "Bea", "pw-b");
  StationCreate(c, "build/tmp-log/c", "Intruder", "pw-c");
  StationCreate(d, "build/tmp-log/d", "Dev", "pw-d");

  // The screen passes the station's own dir field back in.
  Station *e = MAlloc(sizeof(Station));
  StationInit(e, "build/tmp-log/e");
  Check(StationCreate(e, e->dir, "Eve", "pw-e"), "create with the station's own dir field");


  I64 genesis = Keep(out, StartIncident(a, "Ransomware on file server", out));
  Check(a->log->count == 1 && a->log->problems == 0, "genesis entry is valid");
  Check(a->log->has_admin && Same(a->log->admin, a->pk, PK_BYTES), "genesis author is admin");

  U8 add[PK_BYTES + NAME_MAX];
  MemCpy(add, b->pk, PK_BYTES);
  MemCpy(add + PK_BYTES, "Bea", 3);
  I64 add_b = Keep(out, Post(a, KIND_MEMBER_ADD, PHASE_NONE, add, PK_BYTES + 3, out));
  I64 note1 = PostText(a, KIND_NOTE, "Isolated FS-01 from the network");

  GiveKey(a, b);
  for (I64 i = 0; i < g_kept; i++)
    Check(StationReceive(b, g_msg[i], g_len[i]) == RX_NEW, "member receives admin entry");
  Check(b->log->count == 3 && b->log->problems == 0, "member's copy has no problems");

  I64 chat = PostText(b, KIND_CHAT, "Backups on tape are clean");
  Check(StationReceive(a, g_msg[chat], g_len[chat]) == RX_NEW, "admin receives member chat");
  Check(StatusOf(a, b->pk, 1) == ST_OK, "admitted member's entry is ok");
  Check(StationReceive(a, g_msg[chat], g_len[chat]) == RX_DUP, "same message twice is a duplicate");

  U8 bad[MSG_MAX];
  MemCpy(bad, g_msg[note1], g_len[note1]);
  bad[g_len[note1] - 5] ^= 0x40;
  Check(StationReceive(b, bad, g_len[note1]) == RX_REJECTED, "flipped byte on the wire is rejected");

  // C has the team key (say it was stolen) but was never admitted.
  GiveKey(a, c);
  for (I64 i = 0; i < g_kept; i++)
    StationReceive(c, g_msg[i], g_len[i]);
  I64 intruder = PostText(c, KIND_NOTE, "All clear, restore from backup now");
  StationReceive(a, g_msg[intruder], g_len[intruder]);
  Check(StatusOf(a, c->pk, 1) == ST_NOT_MEMBER, "entry from non-member is flagged");

  // C forges an entry that claims to be from the admin.
  Entry *forged = CAlloc(sizeof(Entry));
  forged->kind = KIND_NOTE;
  forged->time = time(NULL);
  StrCpy(forged->body, "Admin says: pay the ransom");
  forged->body_len = StrLen(forged->body);
  EntrySign(a->log, forged, a->pk, c->sk);
  I64 forged_len = MakeMessage(c, forged, out);
  Check(StationReceive(b, out, forged_len) == RX_REJECTED, "entry signed with the wrong key is rejected");

  // B signs two different entries as its seq 2: a fork.
  Log *old = MAlloc(sizeof(Log));
  MemCpy(old, b->log, sizeof(Log));
  I64 fork1 = PostText(b, KIND_NOTE, "FS-01 wiped");
  Entry *other = CAlloc(sizeof(Entry));
  other->kind = KIND_NOTE;
  other->epoch = 0;
  other->time = time(NULL);
  StrCpy(other->body, "FS-01 not wiped");
  other->body_len = StrLen(other->body);
  EntrySign(old, other, b->pk, b->sk);
  I64 fork2 = Keep(out, MakeMessage(b, other, out));
  StationReceive(a, g_msg[fork1], g_len[fork1]);
  StationReceive(a, g_msg[fork2], g_len[fork2]);
  Check(StatusOf(a, b->pk, 2) == ST_FORK, "two entries with the same seq are flagged as a fork");

  // D gets admin entries 1, 2 and 4 but never 3: the gap breaks the chain.
  I64 note2 = PostText(a, KIND_NOTE, "Notified insurer");
  GiveKey(a, d);
  StationReceive(d, g_msg[genesis], g_len[genesis]);
  StationReceive(d, g_msg[add_b], g_len[add_b]);
  StationReceive(d, g_msg[note2], g_len[note2]);
  Check(StatusOf(d, a->pk, 4) == ST_BAD_CHAIN, "missing entry breaks the chain after it");
  StationReceive(d, g_msg[note1], g_len[note1]);
  Check(StatusOf(d, a->pk, 4) == ST_OK, "chain heals when the missing entry arrives");

  // Reload the admin station from disk.
  I64 count = a->log->count;
  Station *a2 = MAlloc(sizeof(Station));
  Check(!StationOpen(a2, "build/tmp-log/a", "wrong passphrase"), "wrong passphrase does not open");
  Check(StationOpen(a2, "build/tmp-log/a", "correct horse"), "right passphrase opens");
  Check(a2->log->count == count && a2->damaged_on_load == 0, "reloaded log has every entry");
  Check(Same(a2->sk, a->sk, SK_BYTES), "reloaded identity matches");

  // Flip a byte inside the third record of the log file.
  I64 size = 0;
  U8 *file = FileRead("build/tmp-log/a/log", &size);
  Check(file != NULL, "log file exists");
  if (file == NULL)
    return 1;
  I64 pos = 0;
  for (I64 i = 0; i < 2; i++)
    pos += 4 + Get32(file + pos);
  file[pos + 4 + 40] ^= 1;
  FileWrite("build/tmp-log/a/log", file, size, O_CREAT | O_RDWR | O_TRUNC);
  Station *a3 = MAlloc(sizeof(Station));
  StationOpen(a3, "build/tmp-log/a", "correct horse");
  Check(a3->damaged_on_load == 1, "edited record in the log file is detected");
  Check(StatusOf(a3, a->pk, 4) == ST_BAD_CHAIN, "entries after the edited record are flagged");

  if (g_failed) {
    "%d failed\n", g_failed;
    return 1;
  }
  "all passed\n";
  return 0;
}
