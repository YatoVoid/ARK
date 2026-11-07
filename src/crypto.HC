// libsodium, declared for HolyC. Every function used here takes plain
// byte buffers, so no C structs have to be mirrored.

#link <sodium>

#define PK_BYTES     32  // Ed25519 public key
#define SK_BYTES     64  // Ed25519 secret key (seed + public key)
#define SIG_BYTES    64
#define KEY_BYTES    32  // team key for secretbox
#define NONCE_BYTES  24
#define MAC_BYTES    16
#define HASH_BYTES   32
#define XPK_BYTES    32  // X25519 public key, for sealed boxes
#define XSK_BYTES    32
#define SEAL_BYTES   48  // overhead of crypto_box_seal

extern "c" I32 sodium_init();
extern "c" U0 randombytes_buf(U0 *buf, I64 size);
extern "c" U0 sodium_memzero(U0 *buf, I64 size);
extern "c" I32 sodium_memcmp(U0 *a, U0 *b, I64 size);

extern "c" I32 crypto_sign_keypair(U8 *pk, U8 *sk);
extern "c" I32 crypto_sign_detached(U8 *sig, U64 *siglen, U8 *m, U64 mlen, U8 *sk);
extern "c" I32 crypto_sign_verify_detached(U8 *sig, U8 *m, U64 mlen, U8 *pk);
extern "c" I32 crypto_sign_ed25519_pk_to_curve25519(U8 *xpk, U8 *pk);
extern "c" I32 crypto_sign_ed25519_sk_to_curve25519(U8 *xsk, U8 *sk);

extern "c" I32 crypto_secretbox_easy(U8 *c, U8 *m, U64 mlen, U8 *n, U8 *k);
extern "c" I32 crypto_secretbox_open_easy(U8 *m, U8 *c, U64 clen, U8 *n, U8 *k);

extern "c" I32 crypto_box_seal(U8 *c, U8 *m, U64 mlen, U8 *xpk);
extern "c" I32 crypto_box_seal_open(U8 *m, U8 *c, U64 clen, U8 *xpk, U8 *xsk);

extern "c" I32 crypto_generichash(U8 *out, I64 outlen, U8 *in, U64 inlen, U8 *key, I64 keylen);

Bool CryptoInit()
{
  // 1 means "already initialised", which is fine.
  if (sodium_init() < 0)
    return FALSE;
  return TRUE;
}

U0 Sign(U8 *sig, U8 *msg, I64 len, U8 *sk)
{
  crypto_sign_detached(sig, NULL, msg, len, sk);
}

Bool Verify(U8 *sig, U8 *msg, I64 len, U8 *pk)
{
  if (crypto_sign_verify_detached(sig, msg, len, pk) == 0)
    return TRUE;
  return FALSE;
}

// out must hold len + NONCE_BYTES + MAC_BYTES. The nonce is random and
// stored in front of the ciphertext.
U0 Seal(U8 *out, U8 *msg, I64 len, U8 *key)
{
  randombytes_buf(out, NONCE_BYTES);
  crypto_secretbox_easy(out + NONCE_BYTES, msg, len, out, key);
}

// in is what Seal wrote, in_len its full size. out must hold
// in_len - NONCE_BYTES - MAC_BYTES. FALSE if the key is wrong or a byte
// was changed.
Bool Open(U8 *out, U8 *in, I64 in_len, U8 *key)
{
  if (in_len < NONCE_BYTES + MAC_BYTES)
    return FALSE;
  if (crypto_secretbox_open_easy(out, in + NONCE_BYTES, in_len - NONCE_BYTES, in, key) == 0)
    return TRUE;
  return FALSE;
}

U0 Hash(U8 *out, U8 *in, I64 len)
{
  crypto_generichash(out, HASH_BYTES, in, len, NULL, 0);
}

// Seals a team key to one member's signing key. out holds KEY_BYTES + SEAL_BYTES.
Bool SealKeyTo(U8 *out, U8 *team_key, U8 *member_pk)
{
  U8 xpk[XPK_BYTES];
  if (crypto_sign_ed25519_pk_to_curve25519(xpk, member_pk) != 0)
    return FALSE;
  crypto_box_seal(out, team_key, KEY_BYTES, xpk);
  return TRUE;
}

Bool OpenSealedKey(U8 *team_key, U8 *in, U8 *my_pk, U8 *my_sk)
{
  U8 xpk[XPK_BYTES], xsk[XSK_BYTES];
  Bool ok = FALSE;
  if (crypto_sign_ed25519_pk_to_curve25519(xpk, my_pk) == 0 &&
      crypto_sign_ed25519_sk_to_curve25519(xsk, my_sk) == 0 &&
      crypto_box_seal_open(team_key, in, KEY_BYTES + SEAL_BYTES, xpk, xsk) == 0)
    ok = TRUE;
  sodium_memzero(xsk, XSK_BYTES);
  return ok;
}

// Constant-time, so comparing hashes or keys doesn't leak timing.
Bool Same(U8 *a, U8 *b, I64 len)
{
  if (sodium_memcmp(a, b, len) == 0)
    return TRUE;
  return FALSE;
}
