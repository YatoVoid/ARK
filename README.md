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
| Report for the company as a PDF: timeline, lost and protected, money at a cost per record, deadlines; figures from the log, summary and next steps from a local model (gemma3:4b through Ollama, offline), every sentence citing its source | done, tested (`test_report`, `test_ui`); about 7 to 8 s per report on an RTX 3050 |
| Start over: clear a station from setup, the unlock screen or the Team page (two presses) | done, tested (`test_ui`) |

## Hardware

- One laptop running Linux.
- An Arduino UNO Q running `relay/hub.py`. One station connects over USB, the others over Wi-Fi.
- Optional: an Arduino UNO (or clone) running `firmware/panel`: the manager's internet kill switch (red), restore (green) and alert buzzer.
- `socat` on the laptop, to turn a TCP connection into the serial port the station expects.

## Running the demo

Every command, in order. [docs/DEMO.md](docs/DEMO.md) explains each step and has troubleshooting.

**Install and build** (Arch; other distros in [docs/BUILDING.md](docs/BUILDING.md); hcc is built from source):

```sh
sudo pacman -S sdl2-compat sdl2_ttf libsodium socat arduino-cli android-tools python-reportlab
hcc src/main.HC -o build/ark
./tests/run.sh
```

**Once, while you still have internet:**

```sh
# panel (close the Arduino IDE first; its serial monitor holds the port)
arduino-cli compile --fqbn arduino:avr:uno firmware/panel
arduino-cli upload --fqbn arduino:avr:uno -p /dev/ttyUSB0 firmware/panel

# relay hub onto the UNO Q
adb devices
adb shell mkdir -p /home/arduino/ark
adb push relay/hub.py /home/arduino/ark/hub.py

# report model, 3.4 GB
ollama pull gemma3:4b
```

The LED matrix animation is set up once from [firmware/relay-matrix/README.md](firmware/relay-matrix/README.md).

**Clean slate** (close every ARK window first; this deletes both identities and the incident):

```sh
rm -rf station-a station-b build/tmp-*
```

**Start the model and the relay:**

```sh
curl -s 127.0.0.1:11434/api/tags >/dev/null || (setsid nohup ollama serve >/dev/null 2>&1 &)
tools/ark-report --warm
adb shell 'pgrep -f "^python3 hub.py" >/dev/null || (cd /home/arduino/ark && setsid nohup python3 hub.py > hub.log 2>&1 < /dev/null &)'
adb shell 'ss -ltn | grep 4210'               # should print a LISTEN line
```

**Stations, on one laptop** (each in its own terminal):

```sh
ARK_COST_PER_RECORD=160 PANEL=/dev/ttyUSB0 ./station.sh station-a usb   # manager
./station.sh station-b usb                                              # worker
```

**Or on two laptops.** Laptop A has the UNO Q and the panel on USB; laptop B is on the team's Wi-Fi:

```sh
# laptop A
ARK_COST_PER_RECORD=160 PANEL=/dev/ttyUSB0 ./station.sh station-a usb
adb shell nmcli dev wifi connect SSID password PASSWORD   # once: UNO Q joins the team Wi-Fi
adb shell ip -4 addr show wlan0                           # its address

# laptop B
hcc src/main.HC -o build/ark
./station.sh station-b wifi 10.147.184.235                # the UNO Q's address
```

**To rehearse without losing the internet**, start station A with stand-ins for the cut and restore:

```sh
ARK_CUT_CMD=true ARK_RESTORE_CMD=true PANEL=/dev/ttyUSB0 ./station.sh station-a usb
```

**In the windows:** A starts an incident, B joins and shows a 6-digit code, A approves it on the Team page (F9). Record what was hit on Scope (F4).

**Feed the Server log** on laptop A:

```sh
tools/ark-watch station-a                     # sudo, ssh, su, account changes, typed commands
tools/ark-watch station-a --access-log /var/log/nginx/access.log   # web requests too
source tools/hooks/ark-shell.zsh              # or .bash / .fish, in the "attacker" shell
tools/drill.sh                                # rehearsal intrusion: logs attacker-style commands, runs none
DRILL_GAP=5 tools/drill.sh                    # same, slower
```

**The story:** B reports `cat /etc/shadow` to the manager, A's panel buzzes, A presses red (internet cut), then green (restored), then Request report on the Report page (F7). The PDF opens by itself.

**Report from the command line:**

```sh
tools/ark-report station-a                    # what the button runs (needs a fresh export from the station)
tools/ark-report station-a --no-ai            # figures and timeline only
ARK_REPORT_MODEL=qwen2.5:3b ARK_OPEN_CMD=okular ./station.sh station-a usb   # other model, other PDF viewer
```

**Remake the GIF and screenshots:**

```sh
hcc tests/render_demo.HC -o build/render_demo && SDL_VIDEODRIVER=offscreen ./build/render_demo
python3 tools/make-demo-gif.py                # writes docs/demo.gif
hcc tests/render_views.HC -o build/render_views && SDL_VIDEODRIVER=offscreen ./build/render_views
```

**Shut down:** close both windows (each wipes its keys from memory), Ctrl+C `ark-watch`, then:

```sh
adb shell 'pkill -f "^python3 hub.py"'
curl -s 127.0.0.1:11434/api/generate -d '{"model":"gemma3:4b","keep_alive":0}' >/dev/null   # frees the GPU
```

## Report

The Report page (F7) has a **Request report** button, for the manager and analysts alike. A few seconds later a PDF opens: what happened, a timeline, what was lost and what was protected, money at a cost per record you set, deadlines and next steps. Every figure and the timeline are computed from the signed log. A model on the same laptop writes only the summary and next steps, and each of its sentences has to cite the figures and timeline rows it rests on; a sentence that names anything not in what it cites is dropped. Nothing is sent anywhere.

Without Ollama the report is still written, from the figures and timeline. Saved to `station-a/report/report.pdf` and `report.md`.

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
