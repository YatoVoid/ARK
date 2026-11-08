// The incident log. Everything ARK knows is a list of entries: notes,
// chat lines, scope changes and membership changes.
//
// Each entry is signed by its author. Each author's entries are numbered
// 1, 2, 3... and each one carries the hash of that author's previous entry,
// so deleting or editing one breaks the chain at that point. Chains are
// per author rather than global so two stations can write at the same time
// without conflicts. The screen merges them in Lamport-clock order.
//
// Validity is recomputed from scratch over the whole log whenever it
// changes (LogCheck). The log holds hundreds of entries, not millions,
// and recomputing is much easier to get right than tracking state.
//
// Record layout, the bytes that get signed (little-endian):
//   0    kind        U8
//   1    phase       U8
//   2    epoch       U16   which team key this entry is sealed with
//   4    seq         U32   per author, starts at 1
//   8    lamport     U64
//   16   time        I64   unix seconds, as claimed by the author
//   24   author      32    Ed25519 public key
//   56   prev        32    hash of the author's previous record, zeros for seq 1
//   88   body_len    U16
//   90   body        body_len bytes
//   ..   sig         64    over everything above

#define KIND_GENESIS    1   // body: admin name '\n' incident title
#define KIND_NOTE       2   // body: text
#define KIND_CHAT       3   // body: text
#define KIND_SCOPE      4   // body: asset|data type|residency|records|status
#define KIND_MEMBER_ADD 5   // body: 32-byte public key, then name
#define KIND_ALERT      6   // body: text, sent to the manager
#define KIND_NETWORK    7   // body: "Cut ..." or "Restored ...", this station's internet

#define PHASE_NONE      0
#define PHASE_DETECT    1
#define PHASE_CONTAIN   2
#define PHASE_ERADICATE 3
#define PHASE_RECOVER   4

#define ST_OK          0
#define ST_BAD_CHAIN   1   // prev hash doesn't match, or an earlier entry is missing
#define ST_NOT_MEMBER  2   // author wasn't admitted by the admin
#define ST_FORK        3   // author signed two different entries with the same seq

#define HEAD_BYTES  90
#define BODY_MAX    1024
#define REC_MAX     (HEAD_BYTES + BODY_MAX + SIG_BYTES)
#define LOG_MAX     2048

class Entry
{
  I64 kind, phase, epoch, seq, body_len, status;
  U64 lamport;
  I64 time;
  U8 author[PK_BYTES];
  U8 prev[HASH_BYTES];
  U8 body[BODY_MAX + 1];   // always NUL terminated so text bodies print directly
  U8 sig[SIG_BYTES];
  U8 hash[HASH_BYTES];     // hash of the full record, signature included
};

class Log
{
  I64 count;
  Entry entries[LOG_MAX];
  U8 admin[PK_BYTES];      // author of the GENESIS entry
  Bool has_admin;
  I64 problems;            // entries whose status isn't ST_OK
};

U0 Put16(U8 *p, I64 v) { p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; }
U0 Put32(U8 *p, I64 v) { Put16(p, v); Put16(p + 2, v >> 16); }
U0 Put64(U8 *p, I64 v) { Put32(p, v); Put32(p + 4, v >> 32); }
I64 Get16(U8 *p) { return p[0] | (p[1] << 8); }
I64 Get32(U8 *p) { return Get16(p) | (Get16(p + 2) << 16); }
I64 Get64(U8 *p) { return Get32(p) | (Get32(p + 4) << 32); }

// Writes the record to out and returns its length.
I64 EntryPack(Entry *e, U8 *out)
{
  out[0] = e->kind;
  out[1] = e->phase;
  Put16(out + 2, e->epoch);
  Put32(out + 4, e->seq);
  Put64(out + 8, e->lamport);
  Put64(out + 16, e->time);
  MemCpy(out + 24, e->author, PK_BYTES);
  MemCpy(out + 56, e->prev, HASH_BYTES);
  Put16(out + 88, e->body_len);
  MemCpy(out + HEAD_BYTES, e->body, e->body_len);
  MemCpy(out + HEAD_BYTES + e->body_len, e->sig, SIG_BYTES);
  return HEAD_BYTES + e->body_len + SIG_BYTES;
}

// Reads a record. Checks the length adds up and the signature matches the
// author it names. Membership and the chain are LogCheck's job.
Bool EntryUnpack(U8 *rec, I64 len, Entry *e)
{
  if (len < HEAD_BYTES + SIG_BYTES)
    return FALSE;
  I64 body_len = Get16(rec + 88);
  if (body_len > BODY_MAX || len != HEAD_BYTES + body_len + SIG_BYTES)
    return FALSE;
  MemSet(e, 0, sizeof(Entry));
  e->kind = rec[0];
  e->phase = rec[1];
  e->epoch = Get16(rec + 2);
  e->seq = Get32(rec + 4);
  e->lamport = Get64(rec + 8);
  e->time = Get64(rec + 16);
  MemCpy(e->author, rec + 24, PK_BYTES);
  MemCpy(e->prev, rec + 56, HASH_BYTES);
  e->body_len = body_len;
  MemCpy(e->body, rec + HEAD_BYTES, body_len);
  e->body[body_len] = 0;
  MemCpy(e->sig, rec + HEAD_BYTES + body_len, SIG_BYTES);
  Hash(e->hash, rec, len);
  if (!Verify(e->sig, rec, HEAD_BYTES + body_len, e->author))
    return FALSE;
  return TRUE;
}

// Fills in seq, prev and lamport from the log, signs, and hashes.
// The caller sets kind, phase, epoch, time and body first.
U0 EntrySign(Log *log, Entry *e, U8 *pk, U8 *sk)
{
  MemCpy(e->author, pk, PK_BYTES);
  e->seq = 1;
  MemSet(e->prev, 0, HASH_BYTES);
  U64 lamport = 0;
  for (I64 i = 0; i < log->count; i++) {
    Entry *o = &log->entries[i];
    if (o->lamport > lamport)
      lamport = o->lamport;
    if (Same(o->author, pk, PK_BYTES) && o->seq >= e->seq) {
      e->seq = o->seq + 1;
      MemCpy(e->prev, o->hash, HASH_BYTES);
    }
  }
  e->lamport = lamport + 1;

  U8 rec[REC_MAX];
  I64 unsigned_len = HEAD_BYTES + e->body_len;
  EntryPack(e, rec);
  Sign(e->sig, rec, unsigned_len, sk);
  MemCpy(rec + unsigned_len, e->sig, SIG_BYTES);
  Hash(e->hash, rec, unsigned_len + SIG_BYTES);
}

Entry *LogFind(Log *log, U8 *author, I64 seq)
{
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->seq == seq && Same(e->author, author, PK_BYTES))
      return e;
  }
  return NULL;
}

// Was pk admitted by the admin before this entry? The admin always is.
Bool IsMember(Log *log, U8 *pk)
{
  if (!log->has_admin)
    return FALSE;
  if (Same(pk, log->admin, PK_BYTES))
    return TRUE;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_MEMBER_ADD && e->status == ST_OK && e->body_len >= PK_BYTES &&
        Same(e->author, log->admin, PK_BYTES) && Same(e->body, pk, PK_BYTES))
      return TRUE;
  }
  return FALSE;
}

// Recomputes every entry's status. Membership can depend on entries that
// arrived later, so it runs twice: first chains and forks, then membership.
U0 LogCheck(Log *log)
{
  log->has_admin = FALSE;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_GENESIS && e->seq == 1) {
      MemCpy(log->admin, e->author, PK_BYTES);
      log->has_admin = TRUE;
      break;
    }
  }

  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    e->status = ST_OK;
    for (I64 j = 0; j < log->count; j++) {
      Entry *o = &log->entries[j];
      if (j != i && o->seq == e->seq && Same(o->author, e->author, PK_BYTES))
        e->status = ST_FORK;
    }
    if (e->status != ST_OK)
      continue;
    if (e->seq == 1) {
      U8 zero[HASH_BYTES];
      MemSet(zero, 0, HASH_BYTES);
      if (!Same(e->prev, zero, HASH_BYTES))
        e->status = ST_BAD_CHAIN;
    } else {
      Entry *before = LogFind(log, e->author, e->seq - 1);
      if (before == NULL || !Same(before->hash, e->prev, HASH_BYTES))
        e->status = ST_BAD_CHAIN;
    }
  }

  // A broken entry poisons everything after it in the same author's chain.
  for (I64 pass = 0; pass < 2; pass++) {
    for (I64 i = 0; i < log->count; i++) {
      Entry *e = &log->entries[i];
      if (e->status == ST_OK && e->seq > 1) {
        Entry *before = LogFind(log, e->author, e->seq - 1);
        if (before != NULL && before->status != ST_OK && before->status != ST_NOT_MEMBER)
          e->status = ST_BAD_CHAIN;
      }
      if (e->status == ST_OK && !IsMember(log, e->author))
        e->status = ST_NOT_MEMBER;
    }
  }

  log->problems = 0;
  for (I64 i = 0; i < log->count; i++)
    if (log->entries[i].status != ST_OK)
      log->problems++;
}

// Adds an entry unless an identical one is already there. Returns TRUE if
// it was new. A different entry with the same author and seq is kept, so
// LogCheck can show the fork.
Bool LogAdd(Log *log, Entry *e)
{
  for (I64 i = 0; i < log->count; i++)
    if (Same(log->entries[i].hash, e->hash, HASH_BYTES))
      return FALSE;
  if (log->count >= LOG_MAX)
    return FALSE;
  MemCpy(&log->entries[log->count], e, sizeof(Entry));
  log->count++;
  LogCheck(log);
  return TRUE;
}

// Which entry comes first on screen: Lamport clock, then author key, then seq.
I64 EntryOrder(Entry *a, Entry *b)
{
  if (a->lamport != b->lamport) {
    if (a->lamport < b->lamport)
      return -1;
    return 1;
  }
  I64 c = memcmp(a->author, b->author, PK_BYTES);
  if (c != 0)
    return c;
  return a->seq - b->seq;
}

// Fills order[] with entry indexes sorted for display. Insertion sort:
// the log is small and mostly arrives in order already.
U0 LogSorted(Log *log, I64 *order)
{
  for (I64 i = 0; i < log->count; i++) {
    I64 j = i;
    while (j > 0 && EntryOrder(&log->entries[order[j - 1]], &log->entries[i]) > 0) {
      order[j] = order[j - 1];
      j--;
    }
    order[j] = i;
  }
}

// Splits "a|b|c|d|e" into five fields in place. FALSE if the shape is wrong.
Bool SplitScope(U8 *body, U8 **fields)
{
  I64 n = 0;
  fields[n++] = body;
  for (I64 i = 0; body[i]; i++) {
    if (body[i] == '|') {
      if (n == 5)
        return FALSE;
      body[i] = 0;
      fields[n++] = body + i + 1;
    }
  }
  if (n == 5)
    return TRUE;
  return FALSE;
}

U8 *StatusName(I64 status)
{
  if (status == ST_OK) return "ok";
  if (status == ST_BAD_CHAIN) return "CHAIN BROKEN";
  if (status == ST_NOT_MEMBER) return "NOT A MEMBER";
  if (status == ST_FORK) return "FORKED";
  return "?";
}
