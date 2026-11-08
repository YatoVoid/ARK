# ARK

An incident command center that runs off the network it is protecting.

During a cyber incident you have to assume the attacker can read the company's email, chat, ticketing and file shares. ARK gives the response team a place to record the incident, track what data was hit and talk to each other, without touching any of that. Stations talk through a relay box on its own Wi-Fi. Every entry is encrypted with a team key and signed by its author, and the log is hash-chained, so a relay that has been tampered with can drop messages but can't read them or forge them.

ARK is written in HolyC (compiled with [hcc](https://github.com/Jamesbarford/holyc-lang)) with SDL2 and SDL2_ttf for the window and libsodium for the cryptography. It's kept small enough for one person to read all of it.

> "An idiot admires complexity, a genius admires simplicity."
> Terry A. Davis

![A worker reports a suspicious server command, the manager's panel buzzes, the manager cuts the internet, restores it, and writes the report](docs/demo.gif)

How to run this yourself, from a clean slate: [docs/DEMO.md](docs/DEMO.md).

## Status

Built for HackUTD (Winstead PC track: Cyber Incident Response Dashboard), November 2026. Work in progress.

| Part | State |
|---|---|
| libsodium bindings (sign, secretbox, sealed box, hash) | done, tested |
| Serial link + frame chunking | done, tested over fake serial ports |
| Incident log: signed entries, per-author hash chains, fork and gap detection | done, tested |
| Passphrase-sealed identity and keys on disk | done, tested |
| Relay hub on an Arduino UNO Q, stations over USB and Wi-Fi | done, tested over real Wi-Fi |
| Station window: overview, server log, chat log, scope form, breach clocks, team, network, guide, on-screen control panel; resizable, text drawn at screen resolution | done, tested (`test_ui`), rendered at 1366x768 to 2560x1440 |
| Server log: shell commands, sudo, logins, failed logins and web requests from `tools/ark-watch`, flagged by attack-step rules, reported to the manager in one click | done, tested (`test_ui`, `test_watch`); watcher tested live on Arch |
| Arduino panel: red CUT takes the machine off the internet, green RESTORE (manager only) brings it back, LEDs show which, buzzer for alerts | flashed; beeps and LEDs checked by hand, real `nmcli` cut not yet run |
| Breach-notification clocks (TX, TX AG, CA, NY, GDPR, HIPAA) | done, tested |
| Report for the company: what happened, lost and protected, money at a cost per record, deadlines; figures from the log, summary from a local model (gemma3:4b through Ollama, offline) | done, tested (`test_report`, `test_ui`); about 7 s per report on an RTX 3050 |

## Hardware

- One laptop running Linux.
- An Arduino UNO Q running `relay/hub.py`. One station connects over USB, the others over Wi-Fi.
- Optional: an Arduino UNO (or clone) running `firmware/panel`: the manager's internet kill switch (red), restore (green) and alert buzzer.
- `socat` on the laptop, to turn a TCP connection into the serial port the station expects.

## Quick start

See [docs/BUILDING.md](docs/BUILDING.md).

```sh
./tests/run.sh
```

## Watching a server

Run on the server the station sits on (the demo uses the same laptop):

```sh
source tools/hooks/ark-shell.zsh      # or .bash / .fish: logs each typed command
tools/ark-watch station-a             # sudo, ssh, su, account changes, and the hook
tools/ark-watch station-a --access-log /var/log/nginx/access.log   # web requests too
tools/drill.sh                        # rehearsal intrusion: logs attacker-style commands, runs none
```

Events show on every station's Server log within a second.

## Report

The Report page (F7) writes a report for the company from the station's log: what happened, what was lost and what was protected, money at a cost per record you set, deadlines and next steps. Every figure is computed from the signed log. A model on the same laptop writes the summary paragraphs; nothing is sent anywhere, and any sentence it writes with a number that isn't in the log is dropped.

```sh
ollama pull gemma3:4b                                    # once
ARK_COST_PER_RECORD=160 PANEL=/dev/ttyUSB0 ./station.sh station-a usb
tools/ark-report station-a --no-ai                       # figures only, from the command line
```

Without Ollama the report is still written, from the figures alone. Saved to `station-a/report/report.md`.

## Docs

- [docs/DEMO.md](docs/DEMO.md): every command for setup, a clean demo, one or two laptops, and the story to show
- [docs/BUILDING.md](docs/BUILDING.md): dependencies, building, flashing
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the pieces fit
- [docs/DECISIONS.md](docs/DECISIONS.md): why it is built this way
- [docs/TESTING.md](docs/TESTING.md): what the tests cover
- [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md): what happened, in order
- [docs/TUTORIAL.md](docs/TUTORIAL.md): build it yourself, step by step

## Credits

- SDL2 bindings adapted from [YatoVoid/holyc-graphics-guide](https://github.com/YatoVoid/holyc-graphics-guide) (MIT).
- [Inter](https://rsms.me/inter/) by Rasmus Andersson and [JetBrains Mono](https://www.jetbrains.com/lp/mono/), both under the SIL Open Font License (`assets/fonts`).
- [libsodium](https://libsodium.org) for all cryptography.

## License

MIT
