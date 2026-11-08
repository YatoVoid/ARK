# Architecture

```
station A (HolyC)                                  station B (HolyC)
  window, log, keys                                  window, log, keys
      | pty                                              | pty
    socat --TCP over USB (adb)--> UNO Q hub <--TCP over Wi-Fi-- socat
                                  relay/hub.py
```

Each station is one HolyC program that thinks it's talking to a serial port. socat connects that port to the hub. The hub sends every `M <hex>` line it receives to all the other stations, and it never holds a key. Without the UNO Q, `python3 relay/hub.py` on a laptop does the same job and both stations connect to 127.0.0.1.

## Source files

| File | Job | State |
|---|---|---|
| `src/util.HC` | `MinI64`, `MaxI64`, `usleep` | built |
| `src/crypto.HC` | libsodium bindings and the wrappers `Sign`, `Verify`, `Seal`, `Open`, `Hash`, `SealKeyTo`, `OpenSealedKey`, `Same` | built, tested |
| `src/link.HC` | serial port, hex lines, splitting and joining frames | built, tested |
| `src/sdl2.HC` | SDL2 bindings: window, events, key codes | built |
| `relay/hub.py` | UNO Q: TCP line hub | built, tested over Wi-Fi |
| `src/log.HC` | entries, per-author hash chains, validity check, display order | built, tested |
| `src/station.HC` | identity, team keys, passphrase-sealed secrets file, log file, posting and receiving | built, tested |
| `src/main.HC` | arguments, font lookup, the event loop | built |
| `src/app.HC` | the station window: setup screens, nine pages, control panel, input, actions, panel, feed and link polling, the report export | built, tested (`test_ui`) |
| `src/events.HC` | server events: feed-line parsing, event bodies, the rules that flag suspicious commands | built, tested (`test_ui`) |
| `src/canvas.HC` | a pixel buffer the size of the window, layout units scaled to pixels, rounded boxes, text from glyphs SDL2_ttf renders at the current scale, icons from `assets/icons` | built |
| `src/team.HC` | join requests, key grants, heads/sync, peer list | built, tested by hand |
| `src/deadlines.HC` | breach-notification clocks | built, tested |
| `tools/ark-watch` | follows the journal (and optionally a web access log) and appends events to a station's feed | tested (`test_watch.py`), run live |
| `tools/ark-report` | after-incident report as PDF and markdown: figures and timeline from the station's export, summary and next steps from a local model through Ollama, each sentence citing what it rests on | tested (`test_report.py`), run with gemma3:4b |
| `tools/hooks/ark-shell.*` | bash, zsh and fish hooks that log each typed command to the journal | tested by hand |
| `tests/render_demo.HC`, `tools/make-demo-gif.py` | run both stations through the demo story and turn the screens into `docs/demo.gif` (and a video with `--mp4`) | run |
| `tools/make-screens.py` | puts renders in a window frame titled with the role, for `docs/screens` | run |
| `tools/drill.sh` | a rehearsal intrusion for demos: logs attacker-style commands without running them | run |
| `tools/make-icons.py` | draws the Network page icons as SVG and converts them to the raw RGBA files the station loads | run |
| `firmware/panel/panel.ino` | Arduino UNO: red CUT and green RESTORE buttons, LEDs for internet on/cut, buzzer for alerts | compiles; earlier version tested on hardware |

## Link layer (built)

A message is split into frames of up to 250 bytes:

```
0      'A'          magic
1..4   message id   random
5      part         0-based
6      count        1..16
7..    data         up to 243 bytes
```

Each frame goes to the relay as `M <hex>\n`. The receiving station keeps 8 half-finished messages. When all parts of one have arrived it hands back the joined bytes. When all 8 slots are busy, the least recently touched message is dropped.

## The log (built)

Everything is an entry: GENESIS (the admin starts the incident), NOTE, CHAT, SCOPE, MEMBER_ADD. An entry is a record of fixed header fields plus a body, signed by its author:

```
kind phase epoch seq lamport time author(32) prev(32) body_len body sig(64)
```

- **Chains are per author.** Alice's entries are numbered 1, 2, 3, and each holds the hash of her previous one. Two stations can write at the same moment without fighting over a single global chain.
- **Order on screen** comes from a Lamport clock (one more than the highest seen), with author key and seq as tie-breaks.
- **Validity is recomputed from scratch** (`LogCheck`) whenever an entry arrives. Statuses: `ok`, `CHAIN BROKEN` (previous entry missing or doesn't hash to `prev`), `NOT A MEMBER` (author never admitted by the admin), `FORKED` (author signed two different entries with the same seq). A bad entry poisons the rest of its author's chain.
- **Rejected outright** and never stored: anything that fails to decrypt, fails to parse, or whose signature doesn't match the author it names.

On the wire and on disk an entry travels as `'E' epoch(U16) Seal(record)`, sealed with that epoch's team key.

## Station files

| File | Contents |
|---|---|
| `secrets` | salt + secretbox(identity keypair, name, team keys), key from the passphrase via Argon2id (libsodium interactive limits, 64 MiB). Mode 0600. |
| `log` | every accepted message exactly as received, each with a 4-byte length. Loading replays them through the same receive path as the relay. |
| `feed` | written by `tools/ark-watch`: one server event per line, read by the station. Mode 0600. |
| `report/report.pdf`, `report/report.md` | the last report, plus a timestamped copy of each one. Mode 0600. `report/export.tsv` exists only while `ark-report` reads it. |

A flipped byte in `log` makes that record fail to decrypt, so it's counted as damaged. The rest of that author's chain then shows `CHAIN BROKEN`, so the screen points at where the damage starts.

## Station window

The layout is written in units for a window at least 1360x900 units. The pixel buffer matches the window's real size, and the scale is the largest that still fits those units, so text is rendered at the size it is shown instead of being stretched. A bigger window gives the main column more room. Fonts are re-rendered when the size changes. It is redrawn from scratch when something happens (input, a message, the panel) and once a second otherwise, so remaining times and who is online stay current.

| Area | What it shows |
|---|---|
| Window title | the role and name, `ARK  Manager: Dana Kessler` or `ARK  Analyst: Marcus Hale`, so two stations on one desktop can be told apart |
| Sidebar | incident title, day, phase; pages with counts (entries, systems, nearest deadline, pending join); your name, role and key fingerprint |
| Top bar | search for the page you're on and the four phases. The manager's click moves the incident; an analyst's click asks the manager |
| Control panel | manager: the newest alert with Acknowledge (and Move to for a phase request), CUT NETWORK, RESTORE NETWORK. Analyst: Alert the manager and the state of the manager's laptop. Both: status lights and Lock station |
| Pages | Overview, Server log, Chat log, Scope, Breach clocks, Team, Network, Report, Guide |

Log rows always show time and author, then a tag coloured by what it means: red for ALERT and CUT, the phase colour for a phase note, the status colour for a scope entry, grey text for chat and team news. Status and phase words inside the text get the same colours, so a row can be skimmed.

Every frame records the clickable regions it drew. A click looks them up, newest first, so whatever was drawn on top wins. `tests/test_ui.HC` uses the same lookup to click through setup, posting, scope, search, approval, the kill switch and phase requests.

## Alerts and the internet switch

Two entry kinds carry them, so both are signed and in the record:

| Kind | Body | Effect |
|---|---|---|
| `KIND_ALERT` (6) | text from an analyst | on other stations: the panel gives three beeps, the control panel and Overview show it until acknowledged. "Asks to move the response to PHASE." is a phase request, and the manager's alert card offers Move to PHASE |
| `KIND_NETWORK` (7) | "Cut ...", "Restored ..." or "Tried to cut ..." | written by the station that ran the switch; its newest one says whether that machine is cut. Every station also reads the manager's newest one to show the manager's laptop state |

CUT runs `ARK_CUT_CMD` (default `nmcli networking off`) and only on the manager's station: an analyst's link to the relay is usually Wi-Fi, so cutting their laptop would cut them off the team. RESTORE runs `ARK_RESTORE_CMD` (default `nmcli networking on`) on whichever station is cut, which in practice is the manager's. A failed command is logged as a failure and doesn't change the state. The relay link survives the cut: station A reaches the UNO Q over USB (adb) and loopback to socat, which NetworkManager doesn't manage.

## Server log

```
server: shell hook / sudo / sshd / su / useradd -> journald
                                                     |
tools/ark-watch (journalctl -f -o json) ---------> DIR/feed (one line per event)
                                                     |
station: PollFeed -> KIND_EVENT entry, signed -> relay -> every station
```

- **Feed lines** are `source TAB user TAB host TAB detail`. `FeedLine` keeps printable ASCII, turns `|` into `/`, caps the fields and drops lines with an unknown source. Lines already in the file when the station starts aren't logged again.
- **Rate limit:** 30 events per 10 seconds. The rest are counted and logged as one entry, so a flood can't fill the log (2048 entries).
- **Risk** is worked out by each station when it draws, from `g_rules` in `events.HC`: SUSPICIOUS for known attack steps (reading `/etc/shadow`, clearing history, uploading with curl, adding SSH keys, new users), WATCH for things that matter in a pattern (failed logins, plain downloads, sudo). Changing the rules doesn't touch the log.
- **Reporting** posts a `KIND_ALERT` whose body starts with `[ref]`, the first 4 bytes of the event's hash. Every station matches it back to the event and shows it as REPORTED; the manager's panel buzzes as for any alert.
- The chat log shows everything except server events.

## Report

```
station: Request report -> ExportReport -> DIR/report/export.tsv (verified entries, decrypted)
                        -> tools/ark-report DIR &      (background, the window keeps running)
ark-report: key figures F1..Fn and timeline T1..Tn, all from the export
            prompt (F + T, attacker's quoted text hidden) -> Ollama on 127.0.0.1 (gemma3:4b)
            summary + next steps, each sentence citing F/T -> citation check
            -> report.pdf and report.md
station: PollReport reads DIR/report/status -> opens report.pdf, shows report.md on the page
```

- **The export** is one record per line, tab separated: `incident`, `opened`, `station`, `phase`, `integrity`, then `member`, `asset` (latest state per system), `clock`, `entry` and `event` (with its risk, why it was flagged and who reported it). Only entries that passed their checks go in. Risk and deadlines are worked out by the station, so the tool uses the same rules as the screen.
- **Figures** (F1, F2...) are computed in Python: first suspicious event, report, cut and restore with the time between them, records lost (EXFILTRATED, ENCRYPTED), protected (CLEAN, CONTAINED) and not confirmed (SUSPECTED), public addresses, deadlines. Money is records times `ARK_COST_PER_RECORD`; without it there are no money figures.
- **The timeline** (T1, T2...) is written by code: suspicious events, events by the accounts behind them, logins from outside addresses, and what the team did (reports, scope, cut, restore). Staff logins from inside aren't in it.
- **The model writes two things:** a 3-sentence summary and 3 or 4 next steps. Each sentence ends with the F and T numbers it rests on, like `[F4, T12]`. The PDF prints that as "(key figure 4; timeline 12)" and numbers both lists 1, 2, 3. The JSON shape is flat (lists of strings), because gemma3:4b loops inside arrays of objects.
- **The citation check** drops a sentence that cites nothing or an item that doesn't exist, or that holds a number, domain, address, account, host or system that isn't in the items it cites. Ordinals ("December 7th") are read as numbers; digits inside a name (FS-01) are checked as part of the name.
- **Attacker text** reaches the model only as timeline rows, with quoted strings replaced by `<quoted text>`. The report's own timeline shows the full command.
- **The PDF** is built with reportlab: stat boxes, summary, timeline, lost and protected tables, money, deadlines, next steps, the numbered figures. Sections the model wrote say so in their heading. Without reportlab only report.md is written.
- **Without a model** (Ollama down, model missing, more than 90 s) the report is written from the figures and timeline and says why.
- `ark-report --warm` loads the model and runs one token through it. The station runs it the first time the Report page opens, so the button doesn't wait for a cold load (about 10 s from disk).
