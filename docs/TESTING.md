# Testing

```sh
./tests/run.sh
```

Builds each test with hcc and runs it. Exit code 0 means everything passed.

| Test | Covers |
|---|---|
| `tests/test_crypto.HC` | sign/verify, a changed message and the wrong author both rejected, secretbox round trip, wrong key and flipped byte both rejected, sealed team key opens only for its recipient |
| `tests/test_link.HC` | messages of 1, 100, 243, 244 and 1000 bytes (one frame, the frame boundary, several frames) both ways over two fake serial ports linked by socat |
| `tests/test_log.HC` | stations handing messages to each other directly: genesis and admin, member admitted by admin, duplicates ignored, flipped byte on the wire rejected, non-member flagged, entry signed with the wrong key rejected, fork (two entries with one seq) flagged, gap breaks the chain and heals when the entry arrives, passphrase-sealed secrets reload (and the wrong passphrase fails), edited byte in the log file detected and everything after it flagged |
| `tests/test_ui.HC` | the window driven like a user: setup with a short and a mismatched passphrase, typing on the Overview starts a note, phase click logs a change, chat, scope form (empty form refused, typed fields, quick picks, Unknown), search, Approve only clickable with a request waiting, CUT and RESTORE with stand-in commands (two presses on screen, one on the panel, manager-only restore, failed commands), alerts from a member and acknowledging them, feed lines (bad ones skipped, half lines held, burst rate-limited), risk rules, server events kept out of the chat log, Suspicious filter, a member reporting an event and the manager seeing it as reported, the report export (events, systems, the cut) and the Report page running a stand-in tool in the background and showing its result, two-press lock zeroes the key, every page draws |
| `tests/test_watch.py` | `tools/ark-watch` parsing real journal message formats (shell hook, sudo command and wrong password, ssh accepted and failed, su, useradd), nginx access lines, control characters and tabs stripped, feed file mode 0600 |
| `tests/test_report.py` | `tools/ark-report` on an export written by `render_demo`: records lost and protected, money, time from first suspicious event to report and cut, public addresses only; the number guard keeps log figures and drops invented amounts and domains; a command with "ignore all previous instructions ... $5,000,000 saved" changes no figure and can't be repeated by the model; only a model on 127.0.0.1 is used; with no model the report is still written and says why; a fake model that invents an amount and a next step has both dropped and the drop noted |
| `tests/test_deadlines.HC` | which notification clocks start: suspected data starts none, Texas under and over 250 records, GDPR and HIPAA, soonest first, overdue and remaining text |

`test_link` also runs over the real relay. See `relay/README.md` for the two socat commands, then `./build/test_link /tmp/ark-a /tmp/ark-b`. Last run: passed, station B on Wi-Fi.

## Known gaps

- `test_ui` checks behaviour, not looks. Layout is checked by reading the images from `tests/render_views.HC`.

- Nothing tests frame loss or reordering yet.
- Nothing checks that the model's sentences are true, only that their numbers and addresses come from the log. The report marks those paragraphs and says to check them.
- `relay/hub.py` has no automated test of its own. It's covered end to end by `test_link` over the real relay.
