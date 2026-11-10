# ARK

**An off-network incident command system: the response team's command center when the company network can't be trusted.**

During a cyber incident, you have to assume the attacker can read the company's email, chat, tickets and file shares. ARK gives the response team somewhere else to work: a shared, tamper-evident record of what happened, what data was hit, which legal deadlines are running and who decided what.

ARK combines software and hardware. Stations talk through a small relay on its own network, never the company's. Every entry is encrypted with a team key, signed by its author and hash-chained, so a compromised relay can drop messages but can't read or forge them. A physical panel lets the incident lead cut and restore the network with one button.

Built for **HackUTD 2026**, Winstead PC track (Cyber Incident Response Dashboard).

---

## Contents

- [Highlights](#highlights)
- [How it works](#how-it-works)
- [Security model](#security-model)
- [Screens](#screens)
- [Features](#features)
- [Quick start: one laptop](#quick-start-one-laptop)
- [Full demo with hardware](#full-demo-with-hardware)
- [Simulating an attack](#simulating-an-attack)
- [Incident report](#incident-report)
- [Configuration](#configuration)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Tests and generated assets](#tests-and-generated-assets)
- [Project status](#project-status)
- [Documentation](#documentation)
- [Team and credits](#team-and-credits)

---

## Highlights

- **Off-network by design.** Stations communicate through ARK's own relay over USB and a team-controlled Wi-Fi network, never the company network.
- **Untrusted relay.** Entries are encrypted and signed end to end. Taking over the relay gives an attacker only ciphertext.
- **Tamper-evident record.** Each author's entries are hash-chained, so edits, gaps and forks are detected on every station.
- **Physical kill switch.** An Arduino panel buzzes on alerts; red cuts the lead's laptop off the internet, green restores it. ARK keeps working throughout.
- **Minimal attack surface.** Written in HolyC with SDL2 and libsodium. No browser, no web server, no package manager, and small enough for one person to read in full.
- **Built for counsel.** Breach-notification clocks and a PDF report whose figures come from the signed log, never from the model.
- **Fully offline.** Even the report summary is written by a local model that refuses any remote host.

---

## How it works

```
                         ┌───────────────────────────────┐
                         │  Arduino UNO Q: relay         │
                         │  relay/hub.py                 │
                         │  forwards sealed lines only   │
                         └──────┬─────────────────┬──────┘
                          USB (adb)        team Wi-Fi (never the
                                │           company network)
                                │                 │
  ┌──────────────────┐   ┌──────┴───────┐   ┌─────┴────────┐
  │ Arduino Uno      │USB│ Laptop A     │   │ Laptop B     │
  │ panel: CUT /     ├───┤ incident lead│   │ analyst      │
  │ RESTORE, LEDs,   │   │ station-a    │   │ station-b    │
  │ buzzer           │   │ ark-watch    │   │              │
  └──────────────────┘   │ Ollama       │   └──────────────┘
                         └──────────────┘
```

| Machine | Role | Runs |
|---|---|---|
| Laptop A | Incident lead (manager) | `station-a`, `tools/ark-watch`, the Arduino Uno panel on USB, Ollama |
| Laptop B | Analyst | `station-b` |
| Arduino UNO Q | Relay | `relay/hub.py` and the ARK animation on its LED matrix |
| Arduino Uno | Lead's control panel | `firmware/panel`: red CUT, green RESTORE, two LEDs, buzzer |

**Stack:** HolyC (compiled with [hcc](https://github.com/Jamesbarford/holyc-lang)), SDL2 and SDL2_ttf for the window, libsodium for all cryptography, Python for the relay hub, the server watcher and the report builder.

---

## Security model

ARK assumes the attacker has access to every internal system, including, potentially, ARK's own relay.

| If an attacker… | ARK… |
|---|---|
| Reads company email, chat and files | Keeps the response off the company network entirely |
| Takes over the relay | Exposes only ciphertext; the relay can drop messages but can't read or forge them |
| Edits or removes log entries | Detects it through per-author hash chains, with fork and gap detection |
| Tries to join the team | Fails without a matching six-digit code checked by the lead in person |
| Compromises a responder's laptop | Lets the lead remove that member, which issues a new team key; later entries from it are flagged NOT A MEMBER |
| Steals a laptop | Finds identity and keys sealed with a passphrase; F12 twice wipes keys from memory |
| Plants text in server logs to mislead the report | Hides quoted strings from the model and drops any sentence citing figures that aren't in the log |
| Exfiltrates data | Can be cut off by the lead with one press of the physical kill switch |

The reasoning behind each choice is in [docs/DECISIONS.md](docs/DECISIONS.md).

---

## Screens
![An analyst reports a suspicious server command, the manager's panel buzzes, the manager cuts the internet, restores it, and writes the report](docs/demo.gif)

> "An idiot admires complexity, a genius admires simplicity."
> Terry A. Davis


The manager's window and an analyst's, right after the manager cut the internet. The window title says which is which.

![The manager's Overview: nearest legal deadline, affected systems, what needs attention, the latest log rows, and the control panel with CUT and RESTORE](docs/screens/manager-overview.png)

![The analyst's Overview: the same incident, with Alert the manager in place of the kill switch and a line saying Dana's laptop is offline](docs/screens/analyst-overview.png)

The Server log, with `cat /etc/shadow` picked and the reason it was flagged:

![Server log with suspicious commands in red and the picked event in full](docs/screens/server-log.png)

An analyst asked to move to ERADICATE. The manager's alert card has the button for it:

![Manager's control panel showing the request from Marcus Hale with Move to ERADICATE and Acknowledge](docs/screens/phase-request.png)

The Network page on the analyst's station while the manager's laptop is offline:

![Network page: this station, the untrusted relay and other stations, linked by sealed links](docs/screens/network.png)

The report after Request report, and the breach clocks:

![Report page with the model's summary citing key figures, and the numbered key figures](docs/screens/report.png)

![Breach clocks: running notification deadlines with the law behind each](docs/screens/breach-clocks.png)

---

## Features

**Roles and team conversation.** The station that starts the incident becomes the incident lead. Others join and are admitted after the lead checks a six-digit code, then assigned a role (for example, `ARK  Legal: Priya Shah` in the window title). Chat reads as a conversation, with avatars coloured by role, alerts in red, and "Received by" showing which stations hold each message.

**Two channels.** The floor (Security, IT) works the incident in **Floor**. Command (Legal, Executive, Comms, Insurer, HR) decides what the business does in **Command**, so leadership questions don't bury the engineers and legal discussion stays separate. The lead is in both. Command is excluded from the report data.

| | Lead | Security, IT | Legal, Executive | Comms, HR | Insurer |
|---|---|---|---|---|---|
| Overview, Scope, Breach clocks, Team | yes | yes | yes | yes | yes |
| Server log | yes | yes | yes | no | yes |
| Post notes, Floor, scope, server reports; request a phase | yes | yes | no, reads Floor | no | no |
| Command | yes | no | yes | yes | yes |
| Request report | yes | yes | yes | yes | no |
| Move phase, approve, change roles, remove | yes | no | no | no | no |
| Alert the lead, cut your own laptop | yes | yes | yes | yes | yes |

Permissions are enforced when an entry is added to the log, not only on screen: an entry its author's role doesn't allow is flagged NOT ALLOWED on every station. Every member holds the team key, so channel separation is need-to-know on screen, not encryption.

**Team changes.** The lead can change a role or remove a member at any time (Team, Manage). Removal rotates the team key and distributes the new one to everyone else.

**Starting over.** Every relay message carries an incident tag. If the lead starts a new incident, stations still on the old one are told so and offered **Clear this station**, and the new incident ignores their traffic without treating it as tampering.

**Server log.** `tools/ark-watch` reads sudo, SSH, su, account changes, typed shell commands and web requests on the watched server. Each event is signed into the log, and known attack steps are flagged SUSPICIOUS. An analyst escalates one with **Report to manager**.

**Kill switch.** The lead's Arduino panel buzzes when an alert arrives. Red cuts that laptop off the internet and green restores it, while ARK keeps working over the relay. The same controls are on screen.

**Phases.** DETECT, CONTAIN, ERADICATE, RECOVER. Only the lead moves the incident; an analyst's click sends the lead a request with a **Move to** button.

**Scope and breach clocks.** Record which systems were hit, what data they held and whether it was lost. Notification deadlines (Texas, Texas AG, California, New York, GDPR, HIPAA) start from that.

**Readable at a glance.** Red means act now (ALERT, CUT, ENCRYPTED, EXFILTRATED). Yellow means check it (SUSPECTED, WATCH). Green means safe (CLEAN, CONTAINED, RESTORED). Pages, phases, event types, data types, panel buttons and status lights each have a symbol in the same colours. The Guide (F1) has the key.

---

## Quick start: one laptop

No hardware needed: the relay hub runs locally and both stations connect to it.

**1. Install and build** (Arch shown; other distributions in [docs/BUILDING.md](docs/BUILDING.md); hcc is built from source):

```sh
sudo pacman -S sdl2-compat sdl2_ttf libsodium socat python-reportlab
hcc src/main.HC -o build/ark
./tests/run.sh                                 # ends with ALL TESTS PASSED
```

**2. Start the report model** (optional; without it the PDF contains figures and timeline only):

```sh
ollama pull gemma3:4b                          # once, 3.4 GB
curl -s 127.0.0.1:11434/api/tags >/dev/null || (setsid nohup ollama serve >/dev/null 2>&1 &)
tools/ark-report --warm                        # loads it into the GPU, about 10 s
```

**3. Start the relay and both stations**, each in its own terminal, in this order:

```sh
python3 relay/hub.py                                                          # terminal 1: relay
ARK_CUT_CMD=true ARK_RESTORE_CMD=true ./station.sh station-a wifi 127.0.0.1   # terminal 2: lead
./station.sh station-b wifi 127.0.0.1                                         # terminal 3: analyst
```

`ARK_CUT_CMD=true` and `ARK_RESTORE_CMD=true` stand in for `nmcli networking off/on`, so pressing CUT doesn't take your laptop offline. Omit them only when you mean it. The hub listens on port 4210 on every interface and only ever sees sealed lines.

**UI only, without the relay:** link the two stations with virtual serial ports:

```sh
socat pty,raw,echo=0,link=/tmp/ark-a pty,raw,echo=0,link=/tmp/ark-b &
ARK_CUT_CMD=true ARK_RESTORE_CMD=true ./build/ark station-a /tmp/ark-a   # lead
./build/ark station-b /tmp/ark-b                                         # analyst
```

**4. Run an incident:**

1. **Lead:** enter a name and a passphrase twice, choose **Start an incident**, and give it a title such as `Ransomware on FS-01`.
2. **Analyst:** enter a name and passphrase, choose **Join an incident**. A six-digit code appears.
3. **Lead:** open Team, confirm the code matches and press **Approve** (or F9). The analyst receives the team key and the full log.
4. **Lead:** record affected systems on Scope (F4), for example `FS-01`, PII, TX, 4120 records, ENCRYPTED, and `NAS-02`, OTHER, 18000, CLEAN.

**Start over:** close both windows, then permanently delete both identities and the incident:

```sh
rm -rf station-a station-b build/tmp-*
```

---

## Full demo with hardware

Laptop A reaches the relay over USB. Laptop B reaches it over a Wi-Fi network the team controls, never the company network.

**The short way.** Each laptop has one script that installs missing packages, builds ARK and opens its window:

```sh
./laptop-a.sh                    # laptop A: UNO Q and panel on USB; starts the model, relay and watcher, prints the relay's address
./laptop-b.sh 10.147.184.235     # laptop B: the address laptop A printed
```

`laptop-a.sh` keeps CUT and RESTORE as stand-ins unless `ARK_REAL_CUT=1` is set. If the UNO Q isn't on Wi-Fi yet, set `WIFI_SSID` and `WIFI_PASS`. A phone plugged in for tethering is ignored. The panel isn't flashed by the script; do that once as shown below.

**One-time setup, while you still have internet:**

```sh
sudo pacman -S arduino-cli android-tools
sudo usermod -aG uucp "$USER"                  # serial port access; log out and back in

# panel (close the Arduino IDE first; its serial monitor holds the port)
arduino-cli compile --fqbn arduino:avr:uno firmware/panel
arduino-cli upload --fqbn arduino:avr:uno -p /dev/ttyUSB0 firmware/panel

# relay hub onto the UNO Q
adb devices
adb shell mkdir -p /home/arduino/ark
adb push relay/hub.py /home/arduino/ark/hub.py
adb shell nmcli dev wifi connect SSID password PASSWORD   # the team's Wi-Fi
adb shell ip -4 addr show wlan0                           # note its address

# report model, 3.4 GB
ollama pull gemma3:4b
```

The LED matrix animation is set up once from [firmware/relay-matrix/README.md](firmware/relay-matrix/README.md).

**Start the model and the relay:**

```sh
curl -s 127.0.0.1:11434/api/tags >/dev/null || (setsid nohup ollama serve >/dev/null 2>&1 &)
tools/ark-report --warm                        # about 10 s
adb shell 'pgrep -f "^python3 hub.py" >/dev/null || (cd /home/arduino/ark && setsid nohup python3 hub.py > hub.log 2>&1 < /dev/null &)'
adb shell 'ss -ltn | grep 4210'                # should print a LISTEN line
```

The hub doesn't start at boot; run the `adb shell` line again after the UNO Q restarts.

**Laptop A** (lead, with the UNO Q and the panel on USB):

```sh
ARK_COST_PER_RECORD=160 PANEL=/dev/ttyUSB0 ./station.sh station-a usb
tools/ark-watch station-a                      # in another terminal
```

**Laptop B** (analyst, on the team's Wi-Fi):

```sh
hcc src/main.HC -o build/ark
./station.sh station-b wifi 10.147.184.235     # the UNO Q's address
```

Both stations can also run on laptop A: `./station.sh station-b usb` in a second terminal. To rehearse on real hardware without losing the internet, add `ARK_CUT_CMD=true ARK_RESTORE_CMD=true` to laptop A's command.

**Clean slate:** close every ARK window, then `rm -rf station-a station-b build/tmp-*`.

[docs/DEMO.md](docs/DEMO.md) has the full runbook and a troubleshooting table.

---

## Simulating an attack

`tools/ark-watch STATION_DIR` follows the systemd journal and hands each event to a running, unlocked station:

| Source | What it picks up | Needs |
|---|---|---|
| shell | commands typed in a shell | `source tools/hooks/ark-shell.{bash,zsh,fish}` in that shell |
| sudo | every sudo command, wrong sudo passwords | nothing |
| login | SSH and su logins | nothing |
| fail | failed SSH, su and sudo passwords | nothing |
| account | useradd, usermod, groupadd, passwd, chpasswd | nothing |
| request | web requests | `--access-log /var/log/nginx/access.log` |

```sh
tools/ark-watch station-a                      # send events to the lead's station
tools/ark-watch station-a --host FS-01         # name the server in the log
tools/ark-watch station-a --print              # print events instead of sending them
tools/drill.sh                                 # rehearsal intrusion, Enter per step; runs nothing
DRILL_GAP=5 tools/drill.sh                     # no prompts, five seconds apart
```

`tools/drill.sh` plays a ransomware intrusion step by step, writing to the journal through `logger --journald` what the watcher would see on each machine. It runs nothing. The flagging rules are `g_rules` in `src/events.HC`.

| Step | What the drill logs | ARK shows |
|---|---|---|
| 1 Phishing | nothing; the mail never touches a server | nothing |
| 2 Login as m.ortiz | SSH login from 203.0.113.47 on FIN-LAPTOP-07 | WATCH: login from an outside address |
| 3 Delete backups | `vssadmin delete shadows /all /quiet` | SUSPICIOUS: deletes the backup copies |
| 4 Clear logs | `wevtutil cl Security` | SUSPICIOUS: clears an event log |
| 5 Encrypt Finance | `lock --share \\FS-01\Finance ...` on FS-01 | SUSPICIOUS: encrypts a whole file share |
| 6 Steal HR data | `rclone copy \\HR-DB\Employees grayhound-drop:` on HR-DB | SUSPICIOUS: copies files out to cloud storage |

**Attacker console (demo prop).** [`attack/`](attack/) contains a separate Python console that plays the attacker's side of the same six steps for a presentation. It is not part of ARK and attacks nothing; its only real behaviour is noticing when its own laptop loses the network, so the "upload" freezes when the kill switch is pressed.

**By hand.** Load the shell hook and type commands. Every command in that shell is logged, and it does run:

```sh
source tools/hooks/ark-shell.zsh               # or ark-shell.bash / ark-shell.fish
cat /etc/shadow                                # fails without sudo, still logged and flagged
```

**The story to show:**

1. Rows appear on both stations' Server log (F6). Flagged ones are red, and the sidebar counts those nobody has reported.
2. **Analyst:** filter to Suspicious, select the `rclone copy` row, press **Report to manager**, and post in chat, for example `Backups deleted, logs wiped, Finance encrypted, HR-DB uploading. Isolate NOW.`
3. **Lead:** the alert appears at the top of the control panel. **Acknowledge**, then **CUT NETWORK** twice within 3 seconds (or press the red panel button). Both stations show the lead's laptop offline, and chat keeps working.
4. **Analyst:** click CONTAIN in the top bar. The lead gets a **Move to CONTAIN** request.
5. **Lead:** **RESTORE NETWORK** once systems are safe.
6. **Either station:** Report (F7), **Request report**. The PDF opens automatically.

Lock each station with F12 twice when finished. Stop the watcher and the hub with Ctrl+C.

---

## Incident report

**Request report** on the Report page (F7) is available to the lead and analysts. The station exports its verified log, and `tools/ark-report` builds a PDF in the background covering the timeline, records lost and protected, estimated cost, deadlines and next steps. It opens with `xdg-open` (or `ARK_OPEN_CMD`). Copies are kept in `station-a/report/` as PDF and Markdown, mode 0600.

- Every figure and the timeline are computed from the log.
- The model (gemma3:4b through Ollama, on 127.0.0.1 only) writes only the summary and next steps. Each sentence cites the figures and timeline rows it rests on. A sentence naming a number, address, account or system that isn't in its citations is dropped, and the report says so.
- The attacker's typed text reaches the model only with quoted strings hidden.
- Without Ollama, the report is built from the figures and timeline and says why.
- Money figures appear only when `ARK_COST_PER_RECORD` is set; ARK never estimates cost on its own.

```sh
tools/ark-report station-a                     # what the button runs; needs a fresh export
tools/ark-report station-a --no-ai             # figures and timeline only
tools/ark-report station-a --model qwen2.5:3b --cost-per-record 160
tools/ark-report --warm                        # load the model before a demo
```

About 7 to 8 seconds per report on an RTX 3050 Laptop GPU once the model is loaded.

---

## Configuration

| Variable | Default | Effect |
|---|---|---|
| `PANEL` | unset | Arduino panel port for `station.sh`, e.g. `/dev/ttyUSB0` |
| `ARK_CUT_CMD` | `nmcli networking off` | what CUT runs |
| `ARK_RESTORE_CMD` | `nmcli networking on` | what RESTORE runs |
| `ARK_COST_PER_RECORD` | unset | dollars per lost or protected record in the report |
| `ARK_REPORT_MODEL` | `gemma3:4b` | Ollama model for the report |
| `ARK_OPEN_CMD` | `xdg-open` | PDF viewer, e.g. `okular` |
| `ARK_REPORT_CMD` | `tools/ark-report` | report tool (the tests use a stand-in) |
| `OLLAMA_HOST` | `127.0.0.1:11434` | must point at this machine; anything else is refused |
| `DRILL_GAP` | unset | seconds between drill steps; unset means press Enter for each |

`./station.sh DIR usb [ADB_SERIAL]` reaches the relay over USB through an adb port forward. `./station.sh DIR wifi HOST` reaches it at HOST. Both start a socat bridge and build `build/ark` if it's missing.

---

## Keyboard shortcuts

| Key | Action |
|---|---|
| F1 | Guide |
| F2 / F3 / F5 | Write a note / chat / alert |
| F4 | Add an affected system |
| F6 | Server log |
| F7 | Report |
| F9 | Approve the waiting join request (lead) |
| F12 twice | Lock the station: wipe keys from memory and quit |
| Ctrl+F | Search the current page |
| PgUp / PgDn | Scroll the Server log and the report |
| Esc | Clear search, close the form |

---

## Tests and generated assets

```sh
./tests/run.sh                                 # full suite; ends with ALL TESTS PASSED
```

[docs/TESTING.md](docs/TESTING.md) lists what each test covers.

To regenerate the images in this README, run these in order. Warm the model first (`tools/ark-report --warm`) so the report frame has a summary. Rendering is offscreen, so no window opens.

```sh
python3 tools/make-icons.py                    # assets/icons from their SVG source (only after changing a symbol)
hcc tests/render_views.HC -o build/render_views && SDL_VIDEODRIVER=offscreen ./build/render_views
hcc tests/render_demo.HC -o build/render_demo && SDL_VIDEODRIVER=offscreen ./build/render_demo
python3 tools/make-demo-gif.py --mp4 demo.mp4  # docs/demo.gif and the same frames as a video
python3 tools/make-screens.py                  # docs/screens/*.png
```

---

## Project status

| Component | State |
|---|---|
| libsodium bindings (sign, secretbox, sealed box, hash) | Done, tested |
| Serial link and frame chunking | Done, tested over fake serial ports and the real relay |
| Incident log: signed entries, per-author hash chains, fork and gap detection | Done, tested |
| Passphrase-sealed identity and keys on disk | Done, tested |
| Relay hub on the Arduino UNO Q; stations over USB and Wi-Fi | Done, tested over real Wi-Fi |
| Station window: nine pages, control panel, resizable, crisp text at any resolution | Done, tested; rendered from 1366x768 to 2560x1440 |
| Server log from `tools/ark-watch`, attack-step rules, Report to manager | Done, tested; watcher run live on Arch |
| Lead-only phase changes; analysts request them | Done, tested |
| Arduino panel: red CUT, green RESTORE, LEDs, buzzer | Flashed; buttons, LEDs and buzzer checked by hand |
| Breach-notification clocks | Done, tested |
| PDF report with cited model sentences | Done, tested |
| Start over from setup, the unlock screen or the Team page | Done, tested |

**Known gaps:** no tests for frame loss or reordering; the hub has no dedicated test (it is covered by `test_link` over the real relay); and nothing verifies that the model's sentences are true, only that everything they name appears in what they cite.

**Roadmap:** drive the kill switch from network hardware so it isolates every machine at once; a content-free pager that wakes the team without revealing incident details; direct report export for counsel and insurers.

---

## Documentation

| Document | Contents |
|---|---|
| [DEMO.md](docs/DEMO.md) | Demo runbook and troubleshooting |
| [BUILDING.md](docs/BUILDING.md) | Dependencies, other distributions, hcc pitfalls |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the pieces fit together |
| [DECISIONS.md](docs/DECISIONS.md) | Why it's built this way |
| [TESTING.md](docs/TESTING.md) | What the tests cover |
| [DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) | What happened, in order |
| [TUTORIAL.md](docs/TUTORIAL.md) | The first three parts, step by step |

---

## Team and credits

Built at HackUTD 2026 by:

- [Wali Lambert](https://www.linkedin.com/in/wali-lambert-003621381/)
- [Drishya Shrestha](https://www.linkedin.com/in/drishya-shrestha/)
- [Yugal Limbu](https://www.linkedin.com/in/yugal-limbu-74615b204/)

**Credits**

- SDL2 bindings adapted from [YatoVoid/holyc-graphics-guide](https://github.com/YatoVoid/holyc-graphics-guide) (MIT).
- [Inter](https://rsms.me/inter/) by Rasmus Andersson, [Fira Sans](https://github.com/mozilla/Fira) by Carrois for Mozilla, and [JetBrains Mono](https://www.jetbrains.com/lp/mono/), all under the SIL Open Font License (`assets/fonts`).
- [libsodium](https://libsodium.org) for all cryptography.
- Icons and symbols in `assets/icons` are drawn by `tools/make-icons.py` for this project.

  ## License

  Released under the [MIT License](LICENSE).




