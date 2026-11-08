// One ARK station: who I am, which team keys I hold, the log, and the files
// that keep them between runs.
//
// Files in the station directory:
//   secrets   salt (16) + Seal(identity and team keys) under a key derived
//             from the passphrase with Argon2id. Rewritten when keys change.
//   log       every accepted message, as received: U32 length + bytes.
//             Loading the log is just receiving every message again.
//
// A message on the wire or on disk:
//   'E'  epoch U16  Seal(record)      a log entry, sealed with that epoch's team key

#define MAX_EPOCHS  16
#define NAME_MAX    32
#define SALT_BYTES  16

// File modes. HolyC has no octal literals: 0700 would be read as decimal 700.
#define MODE_DIR    0x1C0   // 0700
#define MODE_FILE   0x180   // 0600
#define MSG_ENTRY   'E'

#define RX_NEW      0
#define RX_DUP      1
#define RX_NO_KEY   2   // sealed with a team key this station doesn't have
#define RX_REJECTED 3   // didn't open, didn't parse, or bad signature

extern "c" I32 crypto_pwhash(U8 *out, U64 outlen, U8 *passwd, U64 passwdlen, U8 *salt,
                             U64 opslimit, I64 memlimit, I32 alg);
#define PWHASH_OPS  2          // crypto_pwhash_OPSLIMIT_INTERACTIVE
#define PWHASH_MEM  67108864   // crypto_pwhash_MEMLIMIT_INTERACTIVE, 64 MiB
#define PWHASH_ALG  2          // crypto_pwhash_ALG_ARGON2ID13

#define SECRETS_PLAIN (PK_BYTES + SK_BYTES + NAME_MAX + 8 + MAX_EPOCHS * (KEY_BYTES + 1))

class Station
{
  U8 dir[256];
  U8 pk[PK_BYTES];
  U8 sk[SK_BYTES];
  U8 name[NAME_MAX];
  U8 keys[MAX_EPOCHS][KEY_BYTES];
  Bool have_key[MAX_EPOCHS];
  I64 epoch;               // newest team key held, -1 before joining
  U8 file_key[KEY_BYTES];  // from the passphrase; seals the secrets file
  U8 salt[SALT_BYTES];
  Log *log;
  I64 rejected;            // messages that failed to open or verify
  I64 damaged_on_load;     // records in the log file that failed to open
};

U8 *StationPath(Station *s, U8 *file)
{
  return MStrPrint("%s/%s", s->dir, file);
}

Bool DeriveFileKey(Station *s, U8 *passphrase)
{
  if (crypto_pwhash(s->file_key, KEY_BYTES, passphrase, StrLen(passphrase), s->salt,
                    PWHASH_OPS, PWHASH_MEM, PWHASH_ALG) != 0)
    return FALSE;
  return TRUE;
}

Bool SaveSecrets(Station *s)
{
  U8 plain[SECRETS_PLAIN];
  MemSet(plain, 0, SECRETS_PLAIN);
  U8 *p = plain;
  MemCpy(p, s->pk, PK_BYTES);
  p += PK_BYTES;
  MemCpy(p, s->sk, SK_BYTES);
  p += SK_BYTES;
  MemCpy(p, s->name, NAME_MAX);
  p += NAME_MAX;
  Put64(p, s->epoch);
  p += 8;
  for (I64 i = 0; i < MAX_EPOCHS; i++) {
    p[0] = s->have_key[i];
    MemCpy(p + 1, s->keys[i], KEY_BYTES);
    p += KEY_BYTES + 1;
  }

  I64 size = SALT_BYTES + NONCE_BYTES + SECRETS_PLAIN + MAC_BYTES;
  U8 *file = MAlloc(size);
  MemCpy(file, s->salt, SALT_BYTES);
  Seal(file + SALT_BYTES, plain, SECRETS_PLAIN, s->file_key);
  sodium_memzero(plain, SECRETS_PLAIN);

  U8 *path = StationPath(s, "secrets");
  Bool ok = FALSE;
  I32 fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, MODE_FILE);
  if (fd >= 0) {
    if (write(fd, file, size) == size)
      ok = TRUE;
    close(fd);
  }
  Free(path);
  Free(file);
  return ok;
}

Bool LoadSecrets(Station *s, U8 *passphrase)
{
  U8 *path = StationPath(s, "secrets");
  I64 size = 0;
  U8 *file = FileRead(path, &size);
  Free(path);
  if (file == NULL)
    return FALSE;
  Bool ok = FALSE;
  U8 plain[SECRETS_PLAIN];
  if (size == SALT_BYTES + NONCE_BYTES + SECRETS_PLAIN + MAC_BYTES) {
    MemCpy(s->salt, file, SALT_BYTES);
    if (DeriveFileKey(s, passphrase) && Open(plain, file + SALT_BYTES, size - SALT_BYTES, s->file_key))
      ok = TRUE;
  }
  Free(file);
  if (!ok)
    return FALSE;

  U8 *p = plain;
  MemCpy(s->pk, p, PK_BYTES);
  p += PK_BYTES;
  MemCpy(s->sk, p, SK_BYTES);
  p += SK_BYTES;
  MemCpy(s->name, p, NAME_MAX);
  s->name[NAME_MAX - 1] = 0;
  p += NAME_MAX;
  s->epoch = Get64(p);
  p += 8;
  for (I64 i = 0; i < MAX_EPOCHS; i++) {
    s->have_key[i] = p[0];
    MemCpy(s->keys[i], p + 1, KEY_BYTES);
    p += KEY_BYTES + 1;
  }
  sodium_memzero(plain, SECRETS_PLAIN);
  return TRUE;
}

U0 AppendToLogFile(Station *s, U8 *msg, I64 len)
{
  U8 *path = StationPath(s, "log");
  I32 fd = open(path, O_WRONLY | O_CREAT | O_APPEND, MODE_FILE);
  Free(path);
  if (fd < 0)
    return;
  U8 head[4];
  Put32(head, len);
  write(fd, head, 4);
  write(fd, msg, len);
  close(fd);
}

// Opens and verifies one message. Doesn't touch the log file.
I64 Receive(Station *s, U8 *msg, I64 len)
{
  if (len < 3 + NONCE_BYTES + MAC_BYTES || msg[0] != MSG_ENTRY)
    return RX_REJECTED;
  I64 epoch = Get16(msg + 1);
  if (epoch >= MAX_EPOCHS || !s->have_key[epoch])
    return RX_NO_KEY;

  I64 sealed_len = len - 3;
  I64 rec_len = sealed_len - NONCE_BYTES - MAC_BYTES;
  if (rec_len > REC_MAX)
    return RX_REJECTED;
  U8 rec[REC_MAX];
  Entry *e = MAlloc(sizeof(Entry));
  I64 result = RX_REJECTED;
  if (Open(rec, msg + 3, sealed_len, s->keys[epoch]) && EntryUnpack(rec, rec_len, e) &&
      e->epoch == epoch) {
    if (LogAdd(s->log, e))
      result = RX_NEW;
    else
      result = RX_DUP;
  }
  Free(e);
  return result;
}

// Receives a message from the relay, and keeps it on disk if it was new.
I64 StationReceive(Station *s, U8 *msg, I64 len)
{
  I64 r = Receive(s, msg, len);
  if (r == RX_NEW)
    AppendToLogFile(s, msg, len);
  if (r == RX_REJECTED)
    s->rejected++;
  return r;
}

// Seals an entry for the relay and the disk. out must hold MSG_MAX.
I64 MakeMessage(Station *s, Entry *e, U8 *out)
{
  U8 rec[REC_MAX];
  I64 rec_len = EntryPack(e, rec);
  out[0] = MSG_ENTRY;
  Put16(out + 1, e->epoch);
  Seal(out + 3, rec, rec_len, s->keys[e->epoch]);
  return 3 + rec_len + NONCE_BYTES + MAC_BYTES;
}

// Signs a new entry, adds it to the log and the log file, and writes the
// message to send into out (MSG_MAX bytes). Returns the message length,
// or 0 if this station can't post yet.
I64 Post(Station *s, I64 kind, I64 phase, U8 *body, I64 body_len, U8 *out)
{
  if (s->epoch < 0 || body_len > BODY_MAX)
    return 0;
  Entry *e = CAlloc(sizeof(Entry));
  e->kind = kind;
  e->phase = phase;
  e->epoch = s->epoch;
  e->time = time(NULL);
  e->body_len = body_len;
  MemCpy(e->body, body, body_len);
  EntrySign(s->log, e, s->pk, s->sk);
  I64 len = MakeMessage(s, e, out);
  LogAdd(s->log, e);
  AppendToLogFile(s, out, len);
  Free(e);
  return len;
}

U0 StationInit(Station *s, U8 *dir)
{
  // dir may point into s itself (s->dir), so copy it out before clearing s.
  U8 keep[256];
  CopyText(keep, dir, 256);
  MemSet(s, 0, sizeof(Station));
  CopyText(s->dir, keep, 256);
  s->epoch = -1;
  s->log = CAlloc(sizeof(Log));
}

// A new identity in an empty directory.
Bool StationCreate(Station *s, U8 *dir, U8 *name, U8 *passphrase)
{
  StationInit(s, dir);
  mkdir(dir, MODE_DIR);
  crypto_sign_keypair(s->pk, s->sk);
  CopyText(s->name, name, NAME_MAX);
  randombytes_buf(s->salt, SALT_BYTES);
  if (!DeriveFileKey(s, passphrase))
    return FALSE;
  return SaveSecrets(s);
}

// Unlocks an existing station and replays its log.
Bool StationOpen(Station *s, U8 *dir, U8 *passphrase)
{
  StationInit(s, dir);
  if (!LoadSecrets(s, passphrase))
    return FALSE;
  U8 *path = StationPath(s, "log");
  I64 size = 0;
  U8 *file = FileRead(path, &size);
  Free(path);
  if (file == NULL)
    return TRUE;
  I64 pos = 0;
  while (pos + 4 <= size) {
    I64 len = Get32(file + pos);
    pos += 4;
    if (len <= 0 || pos + len > size) {
      s->damaged_on_load++;
      break;
    }
    if (Receive(s, file + pos, len) == RX_REJECTED)
      s->damaged_on_load++;
    pos += len;
  }
  Free(file);
  return TRUE;
}

// The admin starts an incident: first team key, then the GENESIS entry.
I64 StartIncident(Station *s, U8 *title, U8 *out)
{
  randombytes_buf(s->keys[0], KEY_BYTES);
  s->have_key[0] = TRUE;
  s->epoch = 0;
  SaveSecrets(s);
  U8 *body = MStrPrint("%s\n%s", s->name, title);
  I64 len = Post(s, KIND_GENESIS, PHASE_DETECT, body, StrLen(body), out);
  Free(body);
  return len;
}

// Wipes every key from memory. The files on disk stay sealed under the
// passphrase.
U0 StationWipe(Station *s)
{
  sodium_memzero(s->sk, SK_BYTES);
  sodium_memzero(s->keys, MAX_EPOCHS * KEY_BYTES);
  sodium_memzero(s->file_key, KEY_BYTES);
}
