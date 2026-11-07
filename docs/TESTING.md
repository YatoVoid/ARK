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

| `tests/test_deadlines.HC` | which notification clocks start: suspected data starts none, Texas under and over 250 records, GDPR and HIPAA, soonest first, overdue and remaining text |

`test_link` also runs over the real relay. See `relay/README.md` for the two socat commands, then `./build/test_link /tmp/ark-a /tmp/ark-b`. Last run: passed, station B on Wi-Fi.

## Known gaps

- Nothing tests frame loss or reordering yet.
- `relay/hub.py` has no automated test of its own. It's covered end to end by `test_link` over the real relay.
