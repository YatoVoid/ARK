# Running the demo

![ARK demo: watcher, analyst report, manager cut and restore, report](demo.gif)

The GIF is drawn from the real code: `tests/render_demo.HC` runs both stations through the story below and `tools/make-demo-gif.py` lays out the screens with the hardware. The one difference from a live run is that the render hands messages between stations directly instead of through the relay.

## Who is who

| Machine | Role | What runs on it |
|---|---|---|
| Laptop A | manager (Dana) | `station-a`, `tools/ark-watch`, the Arduino UNO panel on USB |
| Laptop B | analyst (Marcus) | `station-b` |
| Arduino UNO Q | relay | `relay/hub.py` (forwards sealed messages), the ARK animation on its LED matrix |
| Arduino UNO | panel, plugged into laptop A | `firmware/panel`: red CUT, green RESTORE, two LEDs, buzzer |
| FS-01 | the watched server | in the demo, laptop A plays it: the shell hook and `tools/ark-watch` |
| Local model | writes the report's summary and next steps | Ollama with gemma3:4b on laptop A, offline |

Laptop A reaches the relay over USB. Laptop B reaches it over a Wi-Fi network the team controls (the UNO Q joins it), never the company network. For a one-laptop rehearsal both stations run on laptop A and both use USB.

## One-time setup

Everything below runs from the repo root.

```sh
# Build and test
hcc src/main.HC -o build/ark
./tests/run.sh

# Flash the panel (close the Arduino IDE first; its serial monitor holds the port)
arduino-cli compile --fqbn arduino:avr:uno firmware/panel
arduino-cli upload --fqbn arduino:avr:uno -p /dev/ttyUSB0 firmware/panel

# Copy the relay hub to the UNO Q
adb devices                                   # the UNO Q shows as a serial number
adb shell mkdir -p /home/arduino/ark
adb push relay/hub.py /home/arduino/ark/hub.py
```

The report's summary needs the model on laptop A (3.4 GB, once, while you still have internet):

```sh
ollama pull gemma3:4b
```

The LED matrix animation is set up once as described in [firmware/relay-matrix/README.md](../firmware/relay-matrix/README.md); it starts by itself at every boot.

## Clean slate before a demo

Close every ARK window, then:

```sh
rm -rf station-a station-b                    # identities, keys, logs, feeds
rm -rf build/tmp-*                            # test and render leftovers
```

This deletes the incident and both identities for good. Each station asks for a new name and passphrase on its next start.

## Start the model

```sh
curl -s 127.0.0.1:11434/api/tags >/dev/null || (setsid nohup ollama serve >/dev/null 2>&1 &)
tools/ark-report --warm                       # loads it into the GPU, about 10 s
```

The station also warms it the first time the Report page opens. Skip this and the report is written from the figures only.

## Start the relay

```sh
adb shell 'pgrep -f "^python3 hub.py" >/dev/null || (cd /home/arduino/ark && setsid nohup python3 hub.py > hub.log 2>&1 < /dev/null &)'
adb shell 'ss -ltn | grep 4210'               # should print a LISTEN line
```

The hub doesn't start at boot. Run this again after the UNO Q restarts or loses power.

## No hardware: hub on the laptop

The hub is plain Python and runs anywhere. Each command in its own terminal:

```sh
python3 relay/hub.py
ARK_CUT_CMD=true ARK_RESTORE_CMD=true ./station.sh station-a wifi 127.0.0.1   # manager
./station.sh station-b wifi 127.0.0.1                                          # analyst
```

Everything below works the same, minus the panel's buzzer and LEDs.

## Two stations on one laptop, with the relay

Each command in its own terminal:

```sh
ARK_COST_PER_RECORD=160 PANEL=/dev/ttyUSB0 ./station.sh station-a usb      # terminal 1: manager
./station.sh station-b usb                         # terminal 2: analyst
```

## Two laptops

Laptop A, with the UNO Q and the panel on USB:

```sh
ARK_COST_PER_RECORD=160 PANEL=/dev/ttyUSB0 ./station.sh station-a usb
```

`ARK_COST_PER_RECORD` is the dollar figure the report multiplies lost and protected records by. Use the number your insurer or counsel gives you; without it the report has no money figures.

Join the UNO Q to the team's Wi-Fi once, and find its address:

```sh
adb shell nmcli dev wifi connect SSID password PASSWORD
adb shell ip -4 addr show wlan0               # the inet address, e.g. 10.147.184.235
```

Laptop B, on the same Wi-Fi, with this repo cloned and built:

```sh
hcc src/main.HC -o build/ark
./station.sh station-b wifi 10.147.184.235
```

Laptop B has no CUT button: its link to the relay is Wi-Fi, so cutting its network would cut it off the team too. The kill switch is the manager's; B has **Alert the manager** instead.

## First start: incident and join

1. **Station A:** name, passphrase twice, **Start an incident**, title (e.g. `Ransomware on FS-01`).
2. **Station B:** name, passphrase twice, **Join an incident**. It shows a 6-digit code.
3. Station A's panel beeps once. On A's Team page, check the code matches what B shows, and press **Approve** (or F9).

B now has the team key and the whole log.

## Feeding the Server log

On laptop A, in one terminal:

```sh
tools/ark-watch station-a
```

In another, either be the intruder by hand in a shell with the hook loaded:

```sh
source tools/hooks/ark-shell.zsh              # or .bash / .fish
cat /etc/shadow                               # fails without sudo, still logged
```

or run the rehearsal, which logs attacker-style commands without running them:

```sh
tools/drill.sh                                # Enter per step; DRILL_GAP=5 for no prompts
```

sudo commands, SSH and su logins and failed passwords are picked up from the journal without the hook. Add `--access-log /var/log/nginx/access.log` to `ark-watch` for web requests.

## The story, step by step

1. **Run the drill**, pressing Enter as the attacker reaches each step: login, delete backups, clear logs, encrypt Finance, steal HR data (the README has the table). Rows appear on both stations' Server log. SUSPICIOUS ones are red; the sidebar counts the ones nobody has reported.
2. **On B,** filter to Suspicious and click the `rclone copy` row. The panel underneath shows who ran it, where, and why it was flagged.
3. **On B,** press **Report to manager**. A's panel beeps three times and the alert sits at the top of A's control panel. B shows the row as REPORTED.
4. **On A,** press **Acknowledge**, then the red button. The red LED lights, A's status reads **Internet CUT**, and a signed entry tells everyone. B's control panel shows A's laptop as offline. Chat between A and B keeps working.
5. **On B,** click CONTAIN in the top bar. Only the manager moves the phase, so this sends A a request; A's panel beeps and the alert card has **Move to CONTAIN**.
6. **On A,** press green once "backups are done". The green LED lights and the internet comes back. Only the manager's station has the kill switch, so only it restores.
7. **On A (or B),** open **Report** (F7) and press **Request report**. In about 8 seconds the PDF opens: summary, timeline, records lost and protected, the money estimate, deadlines and next steps. The summary and next steps were written by gemma3:4b on the laptop, and each sentence ends with the key figures and timeline rows it cites; everything else comes straight from the log. Saved as `station-a/report/report.pdf`.

Before the steps, record what was hit on the Scope page (F4), for example `FS-01`, PII, TX, 4120, ENCRYPTED and `NAS-02`, OTHER, 18000, CLEAN. The report's lost and protected figures come from there.

### Rehearsing without losing the internet

The red button runs `nmcli networking off` for real. To rehearse, give the station stand-in commands:

```sh
ARK_CUT_CMD=true ARK_RESTORE_CMD=true PANEL=/dev/ttyUSB0 ./station.sh station-a usb
```

Everything looks and logs the same, but the network stays up. Drop the two variables for the real thing. If `nmcli` asks for a password when run from the station, the logged-in user lacks NetworkManager rights; run the demo from a desktop session of a user in `wheel`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `stty: /dev/ttyUSB0: Device or resource busy` | The Arduino IDE (its serial monitor) has the port. Quit the IDE fully, then start station A again. |
| `could not reach the relay at TCP:127.0.0.1:4210` | UNO Q not on USB, or the hub isn't running. Check `adb devices`, then start the relay. |
| Top bar says **Relay: alone** | The other station isn't connected yet, or the hub restarted. Restart that station. |
| A station shows the unlock screen and the passphrase is lost | There's no recovery. Press **Clear station** twice on the unlock screen and set it up again. |
| Someone pressed Start instead of Join (or the other way round) | **Start over** on the setup screen, or **Clear this station** on the Team page, twice. It deletes that station's data on this laptop only. |
| The PDF doesn't open | It's saved in `station-a/report/report.pdf`. ARK opens it with `xdg-open`; set `ARK_OPEN_CMD=okular` (or another viewer) if that does nothing. |
| Server log stays empty | `ark-watch` must point at the station directory of a running, unlocked station (`station-a`). Commands typed in a shell show only with the hook sourced in that shell. |
| Report says "No local model summary: Ollama isn't running" | `ollama serve`, then Request again. |
| Report says "the model isn't installed" | `ollama pull gemma3:4b` (needs the internet). |
| Report takes 20 s or more | The model wasn't loaded. Run `tools/ark-report --warm` before the demo. |
| Panel doesn't beep or light | Reflash `firmware/panel`. Station A must be started with `PANEL=/dev/ttyUSB0`. |

## Remaking the GIF

```sh
hcc tests/render_demo.HC -o build/render_demo
SDL_VIDEODRIVER=offscreen ./build/render_demo
python3 tools/make-demo-gif.py                # writes docs/demo.gif
python3 tools/make-demo-gif.py --mp4 demo.mp4 # and a video of the same frames
```

Step 6 runs the real `tools/ark-report`, so start the model first; without it that frame shows a figures-only report.

## Shutting down

Close both windows (each wipes its keys from memory), stop `ark-watch` with Ctrl+C, then:

```sh
adb shell 'pkill -f "^python3 hub.py"'
curl -s 127.0.0.1:11434/api/generate -d '{"model":"gemma3:4b","keep_alive":0}' >/dev/null   # frees the GPU
```

`station-a/report/` keeps every report written, as PDF and markdown. Delete it with the station directory when the incident is closed.
