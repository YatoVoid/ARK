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
| `tests/test_ui.HC` | the window driven like a user: setup with a short and a mismatched passphrase, typing on the Overview starts a note, phase click logs a change, chat, scope form (empty form refused, typed fields, quick picks, Unknown), search, Approve only clickable with a request waiting, CUT and RESTORE with stand-in commands (two presses on screen, one on the panel, manager-only restore, failed commands), alerts from a member and acknowledging them, two-press lock zeroes the key, every page draws |
| `tests/test_deadlines.HC` | which notification clocks start: suspected data starts none, Texas under and over 250 records, GDPR and HIPAA, soonest first, overdue and remaining text |

`test_link` also runs over the real relay. See `relay/README.md` for the two socat commands, then `./build/test_link /tmp/ark-a /tmp/ark-b`. Last run: passed, station B on Wi-Fi.

## Known gaps

- `test_ui` checks behaviour, not looks. Layout is checked by reading the images from `tests/render_views.HC`.

- Nothing tests frame loss or reordering yet.
- `relay/hub.py` has no automated test of its own. It's covered end to end by `test_link` over the real relay.
