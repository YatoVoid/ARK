#include "../src/crypto.HC"

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

I32 Main()
{
  Check(CryptoInit(), "sodium_init");

  U8 pk[PK_BYTES], sk[SK_BYTES], sig[SIG_BYTES];
  crypto_sign_keypair(pk, sk);
  U8 *msg = "containment: isolated HR-DB-02";
  I64 len = StrLen(msg);

  Sign(sig, msg, len, sk);
  Check(Verify(sig, msg, len, pk), "signature verifies");

  U8 copy[64];
  MemCpy(copy, msg, len);
  copy[0] = 'C';
  Check(!Verify(sig, copy, len, pk), "changed message fails verify");

  U8 pk2[PK_BYTES], sk2[SK_BYTES];
  crypto_sign_keypair(pk2, sk2);
  Check(!Verify(sig, msg, len, pk2), "wrong author fails verify");

  U8 key[KEY_BYTES], key2[KEY_BYTES];
  randombytes_buf(key, KEY_BYTES);
  randombytes_buf(key2, KEY_BYTES);
  U8 box[128], plain[128];
  I64 box_len = len + NONCE_BYTES + MAC_BYTES;
  Seal(box, msg, len, key);
  MemSet(plain, 0, 128);
  Check(Open(plain, box, box_len, key), "secretbox opens");
  Check(Same(plain, msg, len), "secretbox round trip matches");
  Check(!Open(plain, box, box_len, key2), "wrong team key fails");
  box[NONCE_BYTES + 3] ^= 1;
  Check(!Open(plain, box, box_len, key), "flipped ciphertext byte fails");

  U8 h1[HASH_BYTES], h2[HASH_BYTES];
  Hash(h1, msg, len);
  Hash(h2, copy, len);
  Check(!Same(h1, h2, HASH_BYTES), "hashes differ for different input");

  U8 sealed[KEY_BYTES + SEAL_BYTES], got[KEY_BYTES];
  Check(SealKeyTo(sealed, key, pk2), "seal team key to member");
  Check(OpenSealedKey(got, sealed, pk2, sk2), "member opens sealed key");
  Check(Same(got, key, KEY_BYTES), "sealed key matches");
  Check(!OpenSealedKey(got, sealed, pk, sk), "non-recipient cannot open sealed key");

  if (g_failed) {
    "%d failed\n", g_failed;
    return 1;
  }
  "all passed\n";
  return 0;
}
