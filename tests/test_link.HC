// Sends messages of several sizes from one port and checks they arrive
// intact on the other. Run through tests/run.sh, which links two fake
// serial ports with socat, or point it at two real relays.

#include "../src/util.HC"
#include "../src/crypto.HC"
#include "../src/link.HC"

I64 g_failed = 0;

Bool SendAndReceive(Link *a, Link *b, I64 len)
{
  U8 *msg = MAlloc(len), *got = MAlloc(MSG_MAX);
  for (I64 i = 0; i < len; i++)
    msg[i] = (i * 7 + len) & 0xFF;
  LinkSend(a, msg, len);

  Bool ok = FALSE;
  for (I64 tries = 0; tries < 2000; tries++) {
    I64 n = LinkPoll(b, got);
    if (n > 0) {
      if (n == len && memcmp(got, msg, len) == 0)
        ok = TRUE;
      break;
    }
    usleep(1000);
  }
  Free(msg);
  Free(got);
  return ok;
}

I32 Main(I32 argc, U8 **argv)
{
  if (argc < 3) {
    "usage: test_link PORT_A PORT_B\n";
    return 2;
  }
  Link *a = MAlloc(sizeof(Link)), *b = MAlloc(sizeof(Link));
  if (!LinkOpen(a, argv[1]) || !LinkOpen(b, argv[2])) {
    "could not open ports\n";
    return 2;
  }
  I64 sizes[5] = {1, 100, FRAME_DATA, FRAME_DATA + 1, 1000};
  for (I64 i = 0; i < 5; i++) {
    if (SendAndReceive(a, b, sizes[i])) {
      "ok    %d bytes A -> B\n", sizes[i];
    } else {
      "FAIL  %d bytes A -> B\n", sizes[i];
      g_failed++;
    }
  }
  if (SendAndReceive(b, a, 600)) {
    "ok    600 bytes B -> A\n";
  } else {
    "FAIL  600 bytes B -> A\n";
    g_failed++;
  }
  if (g_failed) {
    "%d failed\n", g_failed;
    return 1;
  }
  "all passed\n";
  return 0;
}
