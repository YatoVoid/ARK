// Which notification clocks start for which scope entries.

#include "../src/util.HC"
#include "../src/crypto.HC"
#include "../src/link.HC"
#include "../src/log.HC"
#include "../src/station.HC"
#include "../src/deadlines.HC"

I64 g_failed = 0;
U8 g_out[MSG_MAX];

U0 Check(Bool ok, U8 *name)
{
  if (ok) {
    "ok    %s\n", name;
  } else {
    "FAIL  %s\n", name;
    g_failed++;
  }
}

U0 Scope(Station *s, U8 *body)
{
  Post(s, KIND_SCOPE, PHASE_DETECT, body, StrLen(body), g_out);
}

Bool Has(Clock *c, I64 n, U8 *who)
{
  for (I64 i = 0; i < n; i++)
    if (!StrCmp(g_rule_who[c[i].rule], who))
      return TRUE;
  return FALSE;
}

I32 Main()
{
  CryptoInit();
  Station *s = MAlloc(sizeof(Station));
  StationCreate(s, "build/tmp-log/clocks", "Admin", "passphrase");
  StartIncident(s, "Test", g_out);
  Clock c[RULES];

  Scope(s, "HR-DB|PII|TX|100|SUSPECTED");
  Check(Deadlines(s->log, c) == 0, "suspected data starts no clock");

  Scope(s, "HR-DB|PII|TX|100|EXFILTRATED");
  I64 n = Deadlines(s->log, c);
  Check(n == 1 && Has(c, n, "Texas residents"), "Texas PII exfiltrated starts the 60-day clock");
  Check(!Has(c, n, "Texas Attorney General"), "under 250 records: no Attorney General clock");
  I64 left = c[0].due - time(NULL);
  Check(left > 59 * 86400 && left <= 60 * 86400, "Texas clock is 60 days");

  Scope(s, "PAYROLL|PII|TX|4120|ENCRYPTED");
  n = Deadlines(s->log, c);
  Check(Has(c, n, "Texas Attorney General"), "4120 records starts the Attorney General clock");
  Check(!StrCmp(g_rule_who[c[0].rule], "Texas Attorney General"), "the 30-day clock sorts first");

  Scope(s, "EU-CRM|OTHER|EU|?|EXFILTRATED");
  n = Deadlines(s->log, c);
  Check(!StrCmp(g_rule_who[c[0].rule], "EU supervisory authority"), "GDPR 72 hours sorts first");

  Scope(s, "CLINIC|PHI|CA|50|EXFILTRATED");
  n = Deadlines(s->log, c);
  Check(Has(c, n, "HIPAA: individuals") && Has(c, n, "California residents"), "PHI in CA starts HIPAA and California");
  Check(!Has(c, n, "New York residents"), "no New York data, no New York clock");

  U8 text[24];
  RemainingText(-90000, text);
  Check(!StrCmp(text, "OVERDUE 1d 1h"), "overdue text");
  RemainingText(3 * 3600 + 120, text);
  Check(!StrCmp(text, "3h 2m left"), "hours text");

  if (g_failed) {
    "%d failed\n", g_failed;
    return 1;
  }
  "all passed\n";
  return 0;
}
