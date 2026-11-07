# Architecture

```
station A (HolyC)                                  station B (HolyC)
  window, log, keys                                  window, log, keys
      | pty                                              | pty
    socat --TCP over USB (adb)--> UNO Q hub <--TCP over Wi-Fi-- socat
                                  relay/hub.py
```

Each station is one HolyC program that thinks it's talking to a serial port. socat connects that port to the hub. The hub sends every `M <hex>` line it receives to all the other stations, and it never holds a key.

## Source files

| File | Job | State |
|---|---|---|
| `src/util.HC` | `MinI64`, `MaxI64`, `usleep` | built |
| `src/crypto.HC` | libsodium bindings and the wrappers `Sign`, `Verify`, `Seal`, `Open`, `Hash`, `SealKeyTo`, `OpenSealedKey`, `Same` | built, tested |
| `src/link.HC` | serial port, hex lines, splitting and joining frames | built, tested |
| `src/sdl2.HC` | SDL2 and SDL2_ttf bindings | built |
| `relay/hub.py` | UNO Q: TCP line hub | built, tested over Wi-Fi |
| `src/log.HC` | entries, per-author hash chains, validity check, display order | built, tested |
| `src/station.HC` | identity, team keys, passphrase-sealed secrets file, log file, posting and receiving | built, tested |
| `src/team.HC` | enrollment, roles, key rotation | planned |
| `src/main.HC` | the station: setup, unlock, screen, input, network loop, panel | built, tested by hand |
| `src/screen.HC` | 80x50 text grid in the 16 VGA colors, scaled to the window | built |
| `src/font.HC` | TempleOS 8x8 system font as bytes | built |
| `src/team.HC` | join requests, key grants, heads/sync, peer list | built, tested by hand |
| `src/deadlines.HC` | breach-notification clocks | built, tested |
| `firmware/panel/panel.ino` | Arduino UNO: approve and panic buttons, green/red LEDs, buzzer | approve button and LEDs tested |

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
| `log` | every accepted message exactly as received, each with a 4-byte length. Loading replays them through the same receive path as the radio. |

A flipped byte in `log` makes that record fail to decrypt, so it's counted as damaged. The rest of that author's chain then shows `CHAIN BROKEN`, so the screen points at where the damage starts.
