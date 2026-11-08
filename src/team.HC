// Joining a team and staying in sync. Three more message types beside the
// 'E' entries in station.HC:
//
//   'J' pk(32) name(32)                  "please admit me", sent in the clear
//                                        every few seconds until a key arrives
//   'K' pk(32) epoch(U16) sealed key(80) the admin's answer: the team key,
//                                        sealed so only that pk can open it
//   'H' epoch(U16) Seal(heads)           "here is what I have", every few seconds
//
// heads, inside the seal: sender pk(32), sender name(32), count(U8), then
// count times (author pk(32), highest seq(U32)). When a station hears heads
// that are behind its own log, it sends the entries the other side is
// missing. A station that just joined sends empty heads and gets everything.
//
// The admin approves a join after both people read the same six-digit code
// off their screens. The code comes from the joiner's public key, so a
// different key on the air shows a different code.

#define MSG_JOIN   'J'
#define MSG_KEY    'K'
#define MSG_HEADS  'H'

#define JOIN_LEN   (1 + PK_BYTES + NAME_MAX)
#define GRANT_LEN  (1 + PK_BYTES + 2 + KEY_BYTES + SEAL_BYTES)
#define MAX_AUTHORS 32
#define MAX_PEERS   8
#define RESEND_CAP  24   // entries sent in answer to one heads message

class Peer
{
  U8 pk[PK_BYTES];
  U8 name[NAME_MAX];
  I64 heard;               // time() when its heads last arrived
  // Its last heads: what it holds, per author. This is what "Received by"
  // under a message is read from, so it's received, not read.
  U8 heads[MAX_AUTHORS * (PK_BYTES + 4)];
  I64 head_count;
};

class Team
{
  Bool join_pending;       // admin side: someone asked to join
  U8 join_pk[PK_BYTES];
  U8 join_name[NAME_MAX];
  Peer peers[MAX_PEERS];
  I64 peer_count;
  // Traffic on the relay tagged with a different incident: a station left
  // over from an incident that was cleared, or another team's. Not counted
  // as rejected, because it was never meant for this station.
  I64 other_lead_at;       // time() a lead of another incident was last heard
  I64 other_member_at;     // time() a member of another incident was last heard
  I64 other_count;
};

// The incident this station belongs to: the first TAG_LEN - 1 bytes of the
// lead's genesis entry hash. FALSE before the genesis has arrived.
Bool IncidentId(Station *s, U8 *out)
{
  Log *log = s->log;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_GENESIS && e->status == ST_OK && log->has_admin && Same(e->author, log->admin, PK_BYTES)) {
      MemCpy(out, e->hash, TAG_LEN - 1);
      return TRUE;
    }
  }
  return FALSE;
}

// Sets what the link stamps on everything this station sends.
U0 TagLink(Link *link, Station *s)
{
  MemSet(link->tag, 0, TAG_LEN);
  if (IncidentId(s, link->tag) && Same(s->log->admin, s->pk, PK_BYTES))
    link->tag[TAG_LEN - 1] = 1;
}

I64 JoinCode(U8 *pk)
{
  U8 h[HASH_BYTES];
  Hash(h, pk, PK_BYTES);
  return (h[0] | (h[1] << 8) | (h[2] << 16)) % 1000000;
}

// Name for an author key, from the GENESIS and MEMBER_ADD entries.
U0 NameOf(Log *log, U8 *pk, U8 *out)
{
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->status == ST_FORK || e->status == ST_BAD_CHAIN)
      continue;
    if (e->kind == KIND_GENESIS && Same(e->author, pk, PK_BYTES)) {
      I64 n = 0;
      while (n < NAME_MAX - 1 && e->body[n] && e->body[n] != '\n') {
        out[n] = e->body[n];
        n++;
      }
      out[n] = 0;
      return;
    }
    if (e->kind == KIND_MEMBER_ADD && e->body_len > PK_BYTES && Same(e->body, pk, PK_BYTES) &&
        log->has_admin && Same(e->author, log->admin, PK_BYTES)) {
      I64 n = 0;
      U8 *src = e->body + PK_BYTES;
      while (n < NAME_MAX - 1 && src[n] && src[n] != '\n') {
        out[n] = src[n];
        n++;
      }
      out[n] = 0;
      return;
    }
  }
  snprintf(out, NAME_MAX, "?%02x%02x", pk[0], pk[1]);
}

I64 MakeJoin(Station *s, U8 *out)
{
  out[0] = MSG_JOIN;
  MemCpy(out + 1, s->pk, PK_BYTES);
  MemSet(out + 1 + PK_BYTES, 0, NAME_MAX);
  CopyText(out + 1 + PK_BYTES, s->name, NAME_MAX);
  return JOIN_LEN;
}

I64 MakeHeads(Station *s, U8 *out)
{
  U8 plain[PK_BYTES + NAME_MAX + 1 + MAX_AUTHORS * (PK_BYTES + 4)];
  MemCpy(plain, s->pk, PK_BYTES);
  MemSet(plain + PK_BYTES, 0, NAME_MAX);
  CopyText(plain + PK_BYTES, s->name, NAME_MAX);
  I64 count = 0;
  U8 *list = plain + PK_BYTES + NAME_MAX + 1;
  Log *log = s->log;
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    I64 j = 0;
    while (j < count && !Same(list + j * (PK_BYTES + 4), e->author, PK_BYTES))
      j++;
    if (j == count) {
      if (count == MAX_AUTHORS)
        continue;
      MemCpy(list + j * (PK_BYTES + 4), e->author, PK_BYTES);
      Put32(list + j * (PK_BYTES + 4) + PK_BYTES, 0);
      count++;
    }
    U8 *seq = list + j * (PK_BYTES + 4) + PK_BYTES;
    if (e->seq > Get32(seq))
      Put32(seq, e->seq);
  }
  plain[PK_BYTES + NAME_MAX] = count;
  I64 plain_len = PK_BYTES + NAME_MAX + 1 + count * (PK_BYTES + 4);
  out[0] = MSG_HEADS;
  Put16(out + 1, s->epoch);
  Seal(out + 3, plain, plain_len, s->keys[s->epoch]);
  return 3 + plain_len + NONCE_BYTES + MAC_BYTES;
}

// Does peer p hold author's entry number seq, going by its last heads?
Bool PeerHas(Peer *p, U8 *author, I64 seq)
{
  for (I64 j = 0; j < p->head_count; j++)
    if (Same(p->heads + j * (PK_BYTES + 4), author, PK_BYTES))
      return Get32(p->heads + j * (PK_BYTES + 4) + PK_BYTES) >= seq;
  return FALSE;
}

U0 NotePeer(Team *t, U8 *pk, U8 *name, U8 *list, I64 count)
{
  I64 i = 0;
  while (i < t->peer_count && !Same(t->peers[i].pk, pk, PK_BYTES))
    i++;
  if (i == t->peer_count) {
    if (t->peer_count == MAX_PEERS)
      return;
    t->peer_count++;
    MemCpy(t->peers[i].pk, pk, PK_BYTES);
  }
  CopyText(t->peers[i].name, name, NAME_MAX);
  t->peers[i].heard = time(NULL);
  if (count > MAX_AUTHORS)
    count = MAX_AUTHORS;
  MemCpy(t->peers[i].heads, list, count * (PK_BYTES + 4));
  t->peers[i].head_count = count;
}

// Seals team key epoch to pk and sends it.
U0 SendKey(Station *s, Link *link, U8 *pk, I64 epoch)
{
  U8 *msg = MAlloc(MSG_MAX);
  msg[0] = MSG_KEY;
  MemCpy(msg + 1, pk, PK_BYTES);
  Put16(msg + 1 + PK_BYTES, epoch);
  if (SealKeyTo(msg + 3 + PK_BYTES, s->keys[epoch], pk))
    LinkSend(link, msg, GRANT_LEN);
  Free(msg);
}

// Answers heads: sends every entry the other station is missing, oldest
// seq first, at most RESEND_CAP of them.
U0 AnswerHeads(Station *s, Link *link, U8 *list, I64 count)
{
  Log *log = s->log;
  U8 *msg = MAlloc(MSG_MAX);
  I64 sent = 0;
  for (I64 seq = 1; sent < RESEND_CAP; seq++) {
    Bool any = FALSE;
    for (I64 i = 0; i < log->count && sent < RESEND_CAP; i++) {
      Entry *e = &log->entries[i];
      if (e->seq < seq)
        continue;
      any = TRUE;
      if (e->seq != seq)
        continue;
      I64 theirs = 0;
      for (I64 j = 0; j < count; j++)
        if (Same(list + j * (PK_BYTES + 4), e->author, PK_BYTES))
          theirs = Get32(list + j * (PK_BYTES + 4) + PK_BYTES);
      if (seq > theirs && s->have_key[e->epoch]) {
        LinkSend(link, msg, MakeMessage(s, e, msg));
        sent++;
      }
    }
    if (!any)
      break;
  }
  Free(msg);
}

// Handles one message from the link. Entries go to StationReceive; the
// rest is handled here.
U0 TeamReceive(Station *s, Team *t, Link *link, U8 *msg, I64 len)
{
  if (len < 1)
    return;
  // From a station in a different incident: note it and stop there. A zero
  // tag is a station not in any incident yet (asking to join, or waiting
  // for the log after its key arrived).
  U8 mine[TAG_LEN], zero[TAG_LEN];
  MemSet(zero, 0, TAG_LEN);
  if (IncidentId(s, mine) && !Same(link->rx_tag, zero, TAG_LEN - 1) && !Same(link->rx_tag, mine, TAG_LEN - 1)) {
    if (link->rx_tag[TAG_LEN - 1] == 1)
      t->other_lead_at = time(NULL);
    else
      t->other_member_at = time(NULL);
    t->other_count++;
    return;
  }
  if (msg[0] == MSG_ENTRY) {
    StationReceive(s, msg, len);
    return;
  }

  if (msg[0] == MSG_JOIN && len == JOIN_LEN) {
    Bool i_am_admin = s->log->has_admin && Same(s->log->admin, s->pk, PK_BYTES);
    if (i_am_admin && !IsMember(s->log, msg + 1)) {
      t->join_pending = TRUE;
      MemCpy(t->join_pk, msg + 1, PK_BYTES);
      CopyText(t->join_name, msg + 1 + PK_BYTES, NAME_MAX);
    }
    return;
  }

  if (msg[0] == MSG_KEY && len == GRANT_LEN && Same(msg + 1, s->pk, PK_BYTES)) {
    I64 epoch = Get16(msg + 1 + PK_BYTES);
    if (epoch < MAX_EPOCHS && !s->have_key[epoch] &&
        OpenSealedKey(s->keys[epoch], msg + 3 + PK_BYTES, s->pk, s->sk)) {
      s->have_key[epoch] = TRUE;
      if (epoch > s->epoch)
        s->epoch = epoch;
      SaveSecrets(s);
      U8 *heads = MAlloc(MSG_MAX);
      LinkSend(link, heads, MakeHeads(s, heads));
      Free(heads);
    }
    return;
  }

  if (msg[0] == MSG_HEADS && len > 3 + NONCE_BYTES + MAC_BYTES) {
    I64 epoch = Get16(msg + 1);
    if (epoch >= MAX_EPOCHS || !s->have_key[epoch])
      return;
    I64 plain_len = len - 3 - NONCE_BYTES - MAC_BYTES;
    if (plain_len < PK_BYTES + NAME_MAX + 1 || plain_len > MSG_MAX)
      return;
    U8 *plain = MAlloc(plain_len);
    if (Open(plain, msg + 3, len - 3, s->keys[epoch])) {
      I64 count = plain[PK_BYTES + NAME_MAX];
      if (PK_BYTES + NAME_MAX + 1 + count * (PK_BYTES + 4) == plain_len) {
        U8 name[NAME_MAX];
        CopyText(name, plain + PK_BYTES, NAME_MAX);
        NotePeer(t, plain, name, plain + PK_BYTES + NAME_MAX + 1, count);
        // A member still on an older key missed a key change: send the
        // newer ones. A removed station isn't a member, so it gets nothing.
        Bool i_admin = s->log->has_admin && Same(s->log->admin, s->pk, PK_BYTES);
        if (i_admin && epoch < s->epoch && !Same(plain, s->pk, PK_BYTES) && IsMember(s->log, plain))
          for (I64 ep = epoch + 1; ep <= s->epoch; ep++)
            if (s->have_key[ep])
              SendKey(s, link, plain, ep);
        AnswerHeads(s, link, plain + PK_BYTES + NAME_MAX + 1, count);
      }
    } else {
      s->rejected++;
    }
    Free(plain);
  }
}

// Admin approves the pending join: a MEMBER_ADD entry for everyone, and
// the team key sealed to the new member.
// Manager only: removes pk from the team, then starts a new team key and
// sends it to everyone still in. From then on the removed person can't
// read new entries; what they already had stays readable to them.
Bool RemoveMember(Station *s, Link *link, U8 *pk)
{
  Log *log = s->log;
  if (!log->has_admin || !Same(log->admin, s->pk, PK_BYTES) || Same(pk, s->pk, PK_BYTES) || !IsMember(log, pk))
    return FALSE;
  I64 next = s->epoch + 1;
  if (next >= MAX_EPOCHS)
    return FALSE;
  U8 *msg = MAlloc(MSG_MAX);
  LinkSend(link, msg, Post(s, KIND_REMOVE, PHASE_NONE, pk, PK_BYTES, msg));
  Free(msg);
  randombytes_buf(s->keys[next], KEY_BYTES);
  s->have_key[next] = TRUE;
  s->epoch = next;
  SaveSecrets(s);
  for (I64 i = 0; i < log->count; i++) {
    Entry *e = &log->entries[i];
    if (e->kind == KIND_MEMBER_ADD && e->status == ST_OK && e->body_len >= PK_BYTES && IsMember(log, e->body))
      SendKey(s, link, e->body, next);
  }
  return TRUE;
}

// role, if given, follows the name after a newline.
U0 ApproveJoin(Station *s, Team *t, Link *link, U8 *role = NULL)
{
  if (!t->join_pending)
    return;
  U8 *msg = MAlloc(MSG_MAX);
  U8 body[PK_BYTES + 2 * NAME_MAX + 1];
  MemCpy(body, t->join_pk, PK_BYTES);
  I64 len = PK_BYTES + StrLen(t->join_name);
  MemCpy(body + PK_BYTES, t->join_name, len - PK_BYTES);
  if (role != NULL && role[0]) {
    body[len++] = '\n';
    I64 rl = MinI64(StrLen(role), NAME_MAX - 1);
    MemCpy(body + len, role, rl);
    len += rl;
  }
  LinkSend(link, msg, Post(s, KIND_MEMBER_ADD, PHASE_NONE, body, len, msg));

  // Every key so far, so they can read entries from before a removal too.
  for (I64 ep = 0; ep <= s->epoch; ep++)
    if (s->have_key[ep])
      SendKey(s, link, t->join_pk, ep);
  t->join_pending = FALSE;
  Free(msg);
}
