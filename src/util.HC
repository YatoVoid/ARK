I64 MinI64(I64 a, I64 b)
{
  if (a < b)
    return a;
  return b;
}

I64 MaxI64(I64 a, I64 b)
{
  if (a > b)
    return a;
  return b;
}

extern "c" I32 usleep(U32 usec);
extern "c" I64 time(I64 *t);

// Copies at most size - 1 bytes and always NUL terminates.
U0 CopyText(U8 *dst, U8 *src, I64 size)
{
  I64 i = 0;
  while (src[i] && i < size - 1) {
    dst[i] = src[i];
    i++;
  }
  dst[i] = 0;
}
