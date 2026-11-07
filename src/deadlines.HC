// Breach-notification clocks. Each rule says: if data of this type, from
// these people, was exfiltrated or encrypted, someone must be told within
// this many hours. The clock starts at the first valid SCOPE entry that
// matches, which is ARK's best record of when the breach was discovered.
//
// This is a reminder, not legal advice. Whether a breach legally happened,
// and when the clock really started, is counsel's decision. The screen says
// so next to the clocks. Sources, checked November 2026, are in
// docs/DECISIONS.md.

#define RULES 6

U8 *g_rule_who[RULES] = {
  "Texas residents", "Texas Attorney General", "California residents",
  "New York residents", "EU supervisory authority", "HIPAA: individuals"
};
U8 *g_rule_cite[RULES] = {
  "Tex. Bus. & Com. Code 521.053", "Tex. Bus. & Com. Code 521.053",
  "Cal. Civ. Code 1798.82", "N.Y. Gen. Bus. Law 899-aa",
  "GDPR Art. 33", "45 CFR 164.404"
};
U8 *g_rule_where[RULES] = {"TX", "TX", "CA", "NY", "EU", "*"};
// Data types the rule covers, space separated with spaces at both ends.
U8 *g_rule_types[RULES] = {
  " PII PCI CRED PHI ", " PII PCI CRED PHI ", " PII PCI CRED PHI ",
  " PII PCI CRED PHI ", " PII PCI CRED PHI OTHER ", " PHI "
};
I64 g_rule_min_records[RULES] = {0, 250, 0, 0, 0, 0};
I64 g_rule_hours[RULES] = {60 * 24, 30 * 24, 30 * 24, 30 * 24, 72, 60 * 24};

class Clock
{
  I64 rule;
  I64 due;         // unix seconds
  Bool unsure;     // records were "?", so a size threshold may not apply
};

Bool RuleMatches(I64 r, U8 **f)
{
  if (StrCmp(g_rule_where[r], "*") != 0 && StrCmp(g_rule_where[r], f[2]) != 0)
    return FALSE;
  U8 type[16];
  snprintf(type, 16, " %s ", f[1]);
  if (strstr(g_rule_types[r], type) == NULL)
    return FALSE;
  if (StrCmp(f[4], "EXFILTRATED") != 0 && StrCmp(f[4], "ENCRYPTED") != 0)
    return FALSE;
  if (g_rule_min_records[r] > 0 && StrCmp(f[3], "?") != 0 && strtoll(f[3], NULL, 10) < g_rule_min_records[r])
    return FALSE;
  return TRUE;
}

// Fills clocks with every rule that has started, soonest first. Returns how many.
I64 Deadlines(Log *log, Clock *clocks)
{
  I64 n = 0;
  U8 body[BODY_MAX + 1];
  for (I64 r = 0; r < RULES; r++) {
    I64 start = -1;
    Bool unsure = FALSE;
    for (I64 i = 0; i < log->count; i++) {
      Entry *e = &log->entries[i];
      if (e->kind != KIND_SCOPE || e->status != ST_OK)
        continue;
      StrCpy(body, e->body);
      U8 *f[5];
      if (!SplitScope(body, f) || !RuleMatches(r, f))
        continue;
      if (start < 0 || e->time < start) {
        start = e->time;
        unsure = g_rule_min_records[r] > 0 && !StrCmp(f[3], "?");
      }
    }
    if (start < 0)
      continue;
    I64 j = n;
    I64 due = start + g_rule_hours[r] * 3600;
    while (j > 0 && clocks[j - 1].due > due) {
      MemCpy(&clocks[j], &clocks[j - 1], sizeof(Clock));
      j--;
    }
    clocks[j].rule = r;
    clocks[j].due = due;
    clocks[j].unsure = unsure;
    n++;
  }
  return n;
}

U0 RemainingText(I64 seconds, U8 *out)
{
  if (seconds < 0) {
    I64 late = -seconds;
    if (late >= 86400)
      snprintf(out, 24, "OVERDUE %ldd %ldh", late / 86400, late % 86400 / 3600);
    else
      snprintf(out, 24, "OVERDUE %ldh %ldm", late / 3600, late % 3600 / 60);
  } else if (seconds >= 86400) {
    snprintf(out, 24, "%ldd %ldh left", seconds / 86400, seconds % 86400 / 3600);
  } else {
    snprintf(out, 24, "%ldh %ldm left", seconds / 3600, seconds % 3600 / 60);
  }
}
