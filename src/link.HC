// The radio link: a serial port to the ESP32 relay, hex lines on the wire,
// and splitting messages into ESP-NOW sized frames and joining them again.
//
// Frame layout (at most 250 bytes, the ESP-NOW limit):
//   0      'A'
//   1..4   message id, random per message
//   5      part index
//   6      part count
//   7..    data, at most FRAME_DATA bytes
//
// The link moves sealed bytes and trusts none of them. A missing part means
// the message never arrives; a forged part fails the signature check later.

#define FRAME_MAX     250
#define FRAME_HEAD    7
#define FRAME_DATA    (FRAME_MAX - FRAME_HEAD)
#define MAX_PARTS     16
#define MSG_MAX       (MAX_PARTS * FRAME_DATA)
#define PENDING_SLOTS 8
#define LINE_MAX      (2 * FRAME_MAX + 8)

#define O_NOCTTY 0x100

class Pending
{
  U32 id;
  I64 count;
  I64 got;          // bitmask of parts received
  I64 lens[MAX_PARTS];
  I64 age;          // LinkPoll call count when last touched, for eviction
  U8 data[MSG_MAX];
};

class Link
{
  I32 fd;
  U8 line[LINE_MAX];
  I64 line_len;
  U8 info[128];     // last "I" or "E" line from the relay, for the status bar
  I64 ticks;
  Pending pending[PENDING_SLOTS];
};

Bool LinkOpen(Link *l, U8 *path)
{
  MemSet(l, 0, sizeof(Link));
  l->fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
  if (l->fd < 0)
    return FALSE;
  return TRUE;
}

U0 LinkClose(Link *l)
{
  if (l->fd >= 0)
    close(l->fd);
  l->fd = -1;
}

U0 WriteAll(I32 fd, U8 *buf, I64 len)
{
  I64 done = 0, tries = 0;
  while (done < len && tries < 100000) {
    I64 n = write(fd, buf + done, len - done);
    if (n > 0)
      done += n;
    else
      tries++;
  }
}

U8 HexDigit(I64 v)
{
  if (v < 10)
    return '0' + v;
  return 'a' + v - 10;
}

I64 HexValue(U8 c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

U0 SendFrame(Link *l, U8 *frame, I64 len)
{
  U8 out[LINE_MAX];
  out[0] = 'M';
  out[1] = ' ';
  for (I64 i = 0; i < len; i++) {
    out[2 + 2 * i] = HexDigit(frame[i] >> 4);
    out[3 + 2 * i] = HexDigit(frame[i] & 15);
  }
  out[2 + 2 * len] = '\n';
  WriteAll(l->fd, out, 3 + 2 * len);
}

Bool LinkSend(Link *l, U8 *msg, I64 len)
{
  if (len <= 0 || len > MSG_MAX)
    return FALSE;
  U32 id;
  randombytes_buf(&id, 4);
  I64 count = (len + FRAME_DATA - 1) / FRAME_DATA;
  U8 frame[FRAME_MAX];
  for (I64 part = 0; part < count; part++) {
    I64 start = part * FRAME_DATA;
    I64 n = MinI64(FRAME_DATA, len - start);
    frame[0] = 'A';
    MemCpy(frame + 1, &id, 4);
    frame[5] = part;
    frame[6] = count;
    MemCpy(frame + FRAME_HEAD, msg + start, n);
    SendFrame(l, frame, FRAME_HEAD + n);
  }
  return TRUE;
}

Pending *FindSlot(Link *l, U32 id, I64 count)
{
  Pending *oldest = &l->pending[0];
  for (I64 i = 0; i < PENDING_SLOTS; i++) {
    Pending *p = &l->pending[i];
    if (p->count != 0 && p->id == id)
      return p;
    if (p->age < oldest->age)
      oldest = p;
  }
  MemSet(oldest, 0, sizeof(Pending));
  oldest->id = id;
  oldest->count = count;
  return oldest;
}

// Takes one decoded frame. Returns the message length when this frame
// completed a message (copied to out), otherwise 0.
I64 TakeFrame(Link *l, U8 *frame, I64 len, U8 *out)
{
  if (len < FRAME_HEAD + 1 || frame[0] != 'A')
    return 0;
  U32 id;
  MemCpy(&id, frame + 1, 4);
  I64 part = frame[5], count = frame[6];
  if (count < 1 || count > MAX_PARTS || part >= count)
    return 0;

  Pending *p = FindSlot(l, id, count);
  if (p->count != count)
    return 0;
  p->age = l->ticks;
  I64 n = len - FRAME_HEAD;
  MemCpy(p->data + part * FRAME_DATA, frame + FRAME_HEAD, n);
  p->lens[part] = n;
  p->got |= 1 << part;
  if (p->got != (1 << count) - 1)
    return 0;

  // Every part but the last is full, so the total is easy to add up.
  I64 total = (count - 1) * FRAME_DATA + p->lens[count - 1];
  MemCpy(out, p->data, total);
  p->count = 0;
  return total;
}

I64 TakeLine(Link *l, U8 *out)
{
  U8 *s = l->line;
  I64 n = l->line_len;
  if (n >= 2 && (s[0] == 'I' || s[0] == 'E') && s[1] == ' ') {
    I64 copy = MinI64(n - 2, 127);
    MemCpy(l->info, s + 2, copy);
    l->info[copy] = 0;
    return 0;
  }
  if (n < 4 || s[0] != 'M' || s[1] != ' ' || (n - 2) % 2 != 0 || (n - 2) / 2 > FRAME_MAX)
    return 0;
  U8 frame[FRAME_MAX];
  I64 len = (n - 2) / 2;
  for (I64 i = 0; i < len; i++) {
    I64 hi = HexValue(s[2 + 2 * i]), lo = HexValue(s[3 + 2 * i]);
    if (hi < 0 || lo < 0)
      return 0;
    frame[i] = (hi << 4) | lo;
  }
  return TakeFrame(l, frame, len, out);
}

// Reads whatever the relay has sent. Returns the length of one complete
// message copied to out (which must hold MSG_MAX), or 0 if none is ready.
// Call it until it returns 0.
I64 LinkPoll(Link *l, U8 *out)
{
  l->ticks++;
  U8 ch;
  while (read(l->fd, &ch, 1) == 1) {
    if (ch == '\r')
      continue;
    if (ch == '\n') {
      I64 got = TakeLine(l, out);
      l->line_len = 0;
      if (got > 0)
        return got;
    } else if (l->line_len < LINE_MAX) {
      l->line[l->line_len++] = ch;
    }
  }
  return 0;
}
