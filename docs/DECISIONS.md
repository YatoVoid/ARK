# Decisions

Short records of choices that shaped ARK. Newest last.

## 1. Off-network radio instead of the corporate LAN

*Updated in decision 7: one ESP32, its own access point.*

The Winstead brief says to assume the attacker has every internal system. So stations never use the LAN, Wi-Fi infrastructure or the internet. Each station has its own ESP32, and the ESP32s broadcast to each other with ESP-NOW, which needs no access point.

Considered: a server on the LAN with TLS. Rejected, because the attacker owns the LAN, the DNS and maybe the CA.

## 2. The relay is untrusted

The ESP32 only ever sees ciphertext. Sealing, signing and verifying all happen on the station. A compromised or cloned relay can drop or inject frames, and the station rejects any injected frame because it fails the signature check.

## 3. libsodium through `extern "c"`, no hand-written crypto

Every function ARK needs takes plain byte buffers, so the bindings are one line each and no C structs are mirrored. Primitives: Ed25519 signatures per author, XSalsa20-Poly1305 secretbox with a shared team key, sealed boxes (X25519) to hand a new team key to each member, BLAKE2b for the log's hash chain.

## 4. Hex lines over serial

The station writes `M <hex>\n` and the relay answers in the same format. It's twice the bytes of a binary protocol, but you can watch traffic with `cat /dev/ttyUSB0` and there's no framing or escaping to get wrong. At 115200 baud a full 250-byte frame takes about 45 ms, which is fine for typing speed.

## 5. Chunking on the station, not the relay

ESP-NOW frames carry at most 250 bytes. The station splits messages into frames with a 7-byte header (magic, message id, part, count) and joins them on the way in. That keeps the relay firmware to about 100 lines with nothing in it worth attacking. Limit: 16 parts, so 3888 bytes per message. A lost frame loses the whole message. Sync (see the architecture doc) re-requests anything that's missing.

## 6. SDL2_ttf with a bundled font (replaced by decision 11)

The holyc-graphics-guide 5x7 bitmap font only has uppercase letters. People reading under stress need mixed case at a decent size. `SDL_Color` is passed by value, and on x86_64 a 4-byte struct travels in one register, so it's declared as a `U32`. Verified on screen in `tests/spike_window.HC`.

## 7. One relay with its own access point instead of an ESP-NOW mesh

Only one ESP32 was available. The relay now runs a Wi-Fi access point that belongs to the response team, not the company, and has no route anywhere. A station connects over USB serial or over that Wi-Fi with UDP. On Linux, `socat` turns the UDP side into a pseudo-terminal, so the station code only ever deals with a serial port. ESP-NOW between several relays would extend range, but it can't be tested with one board, so it isn't in the code.

The Wi-Fi password is in `firmware/relay/config.h` (not committed). It only keeps strangers off the air. Security comes from the sealing and signatures, not from WPA2.

## 8. Per-author hash chains, recomputed validity

A single global chain would need the stations to agree on order, which is consensus, which is too much. Each author chains their own entries, and the screen merges them by Lamport clock. `LogCheck` recomputes every entry's status from scratch, O(n^2) over a log of a few hundred entries. That's microseconds of work, and there's no incremental state to get wrong.

## 9. Passphrase-sealed secrets

The identity key and team keys are stored in one file sealed with a key derived from a passphrase (Argon2id). A stolen laptop or a copied station directory gives an attacker nothing without the passphrase. The panic switch wipes the keys from memory, which leaves only the sealed file behind.

## 10. The UNO Q replaces the ESP32 as the relay

The ESP32 couldn't be used: no working data cable at the venue. The Arduino UNO Q runs Debian on its own processor and has Wi-Fi, so it took over the relay job. It runs `relay/hub.py`, a Python TCP hub of about 100 lines. This replaces decision 7 (ESP32 access point with UDP), and the ESP32 firmware has been removed. It was never flashed, and keeping untested code around would only mislead.

TCP instead of UDP: TCP doesn't drop frames, and a phone hotspot (used while developing) may block broadcast between clients. The hub is still untrusted. It passes sealed lines and nothing else, and drops anything that isn't an `M` line or is too long.

The 250-byte frames from decision 5 stay. TCP doesn't need them, but they cap the line length, which gives the hub a simple rule for rejecting garbage.

## 11. TempleOS look: white, 16 colors, 8x8 font, 80x50 grid (replaced by decision 13)

The screen copies TempleOS: a white background, the VGA palette, and Terry's system font on a fixed 80x50 grid, scaled to whatever size the window is. Reasons:
- **Readable under stress.** Dark blue on white is about 12:1 contrast. Status colors are only used as backgrounds behind black or white text, because VGA green and cyan as text on white fail WCAG AA.
- **Fixed layout.** The log, scope table and input line never move, so people under stress build muscle memory fast.
- **No rendering library to trust.** Text is drawn by a 15-line function from a public-domain byte table. SDL2_ttf and the bundled font are gone.

The cost: 80 columns is narrow, so long entries wrap to at most four lines.

## 12. Breach-notification clocks

A clock starts when a scope entry marks data EXFILTRATED or ENCRYPTED. It counts from that entry's time, which is the closest thing ARK has to "discovery". Rules, checked November 2026:

| Rule | Deadline | Source |
|---|---|---|
| Texas residents | 60 days | Tex. Bus. & Com. Code 521.053 |
| Texas Attorney General, 250+ Texans | 30 days | same section, as amended by SB 768 (2023), effective 2023-09-01 |
| California residents | 30 days from discovery | Cal. Civ. Code 1798.82(a)(2), as amended by SB 446 (2025), effective 2026-01-01 |
| New York residents | 30 days from discovery | N.Y. Gen. Bus. Law 899-aa, as amended December 2024 |
| EU supervisory authority | 72 hours | GDPR Art. 33 |
| HIPAA, individuals | 60 days | 45 CFR 164.404 |

Most of these were confirmed from law-firm summaries and bill text rather than the current consolidated statutes. Before relying on them, check the official text: capitol.texas.gov for SB 768, leginfo.legislature.ca.gov for 1798.82.

Left out on purpose:
- California's Attorney General notice. It runs 15 days from consumer notice, not from discovery, so it needs a different start event.
- SEC Form 8-K Item 1.05. It starts at a materiality decision, which ARK doesn't record.

Treating ENCRYPTED as a trigger is a cautious choice. Whether ransomware encryption without exfiltration counts as a breach depends on the law and the facts. The screen says "Not legal advice" next to the clocks.

## 13. A dashboard for managers instead of the TempleOS screen

The TempleOS screen tested well for looks and badly for use. People couldn't tell what to type, and the information a manager wants first (the nearest legal deadline, what was hit, who is online) was spread over a dense text grid. The new window follows a Figma design made for ARK: navy background, Inter and JetBrains Mono, a sidebar of pages and a control panel that mirrors the hardware.

- **Dark on purpose.** Incident rooms run at night and on projectors. Body text is #E6EBF5 on #0B1020, above 15:1. Secondary text is #A3AEC6, above 8:1.
- **The deadline comes first.** The Overview opens on the nearest notice deadline in large type, then affected systems and a short list of things waiting on you.
- **Forms instead of prompts.** Adding a system is one form with every field and its choices visible, each explained in a line.
- **The phase belongs to the incident.** Clicking a phase posts a signed note, so every station shows the same phase and the change is in the record.
- **Fonts are bundled** (SIL OFL, in `assets/fonts`), so the window looks the same on any laptop. SDL2_ttf renders each glyph once at startup; drawing is then plain pixel copies.

What this gives up: decision 11's "no rendering library to trust". SDL2_ttf and FreeType are back. They only ever see ARK's own strings and the bundled fonts, never network input as font data.

## 14. The panel is an internet kill switch, not a panic button

The scenario the panel serves: an analyst reading logs suspects someone is in the system and tampering with files. They send the manager an alert from ARK, and the manager's panel buzzes. The manager presses red, which takes the machine off the internet so any link the attacker had through it is gone. The team keeps working in ARK over the relay, encrypted end to end. When systems are backed up and the attacker is out, the manager presses green to restore.

- **Cut on the machine with the panel only.** Cutting every station's internet from one button would also cut stations that reach the relay over Wi-Fi. Each cut is logged, so every station sees who cut what and when.
- **Restore is manager-only; cut isn't.** Isolating early is the safe mistake. Reconnecting too early is the dangerous one.
- **On screen, CUT takes two presses within 3 seconds**, so a stray click can't drop the internet. The hardware button is one press, because it's an emergency control in the manager's hand.
- **Commands are environment variables** (`ARK_CUT_CMD`, `ARK_RESTORE_CMD`) so a deployment can block a firewall zone or drop a VPN instead of turning NetworkManager off.
- **Wiping keys moved to "Lock station"** (on screen, or F12 twice). Join approval is on the Team page and F9.
