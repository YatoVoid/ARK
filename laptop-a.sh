#!/usr/bin/env bash
# Laptop A, the manager: checks packages, builds ARK, starts the report
# model and the relay hub on the UNO Q, then opens the manager's window.
#
#   ./laptop-a.sh
#
# Plug in the UNO Q and the UNO panel first. CUT and RESTORE only pretend
# unless ARK_REAL_CUT=1 is set. If the UNO Q is not on Wi-Fi yet, set
# WIFI_SSID and WIFI_PASS and it joins that network.
set -euo pipefail
cd "$(dirname "$0")"

station="${ARK_STATION:-station-a}"
mkdir -p build

need=$(pacman -T sdl2-compat sdl2_ttf libsodium socat python-reportlab android-tools || true)
if [ -n "$need" ]; then
  echo "installing: $need"
  sudo pacman -S --needed $need
fi
command -v hcc >/dev/null || { echo "hcc is not installed, see docs/BUILDING.md" >&2; exit 1; }

echo "building ARK"
hcc src/main.HC -o build/ark

if command -v ollama >/dev/null; then
  curl -s -m 2 127.0.0.1:11434/api/tags >/dev/null || (setsid nohup ollama serve >/dev/null 2>&1 &)
  echo "warming the report model in the background (build/warm.log)"
  (sleep 3; tools/ark-report --warm) > build/warm.log 2>&1 &
else
  echo "ollama not found: reports will have figures and timeline only"
fi

# a phone used for tethering also shows up in adb; the UNO Q is the one with /home/arduino
echo "looking for the UNO Q on USB"
uno="${ADB_SERIAL:-}"
for _ in $(seq 20); do
  [ -n "$uno" ] && break
  for s in $(adb devices | awk 'NR > 1 && $2 == "device" {print $1}'); do
    if adb -s "$s" shell test -d /home/arduino 2>/dev/null; then uno=$s; break; fi
  done
  [ -n "$uno" ] || sleep 1
done
[ -n "$uno" ] || { echo "no UNO Q found: check the USB cable and 'adb devices'" >&2; exit 1; }
q() { adb -s "$uno" "$@"; }

q shell mkdir -p /home/arduino/ark
q push relay/hub.py /home/arduino/ark/hub.py >/dev/null 2>&1
if [ -n "${WIFI_SSID:-}" ]; then
  q shell nmcli dev wifi connect "$WIFI_SSID" password "${WIFI_PASS:-}" >/dev/null
fi
# adb can keep the session open after the hub detaches; the port check below is what counts
timeout 5 adb -s "$uno" shell 'pgrep -f "^python3 hub.py" >/dev/null || (cd /home/arduino/ark && setsid nohup python3 hub.py > hub.log 2>&1 < /dev/null &)' || true
for _ in $(seq 20); do
  q shell 'ss -ltn | grep -q :4210' && break
  sleep 0.5
done
q shell 'ss -ltn | grep -q :4210' || { echo "the relay did not start on the UNO Q, see /home/arduino/ark/hub.log" >&2; exit 1; }

relay=$(q shell "ip -4 -o addr show wlan0" | awk '{print $4}' | cut -d/ -f1)
if [ -n "$relay" ]; then
  echo
  echo "relay is up. On laptop B run:  ./laptop-b.sh $relay"
  echo
else
  echo "relay is up, but the UNO Q has no Wi-Fi address: laptop B can't reach it yet"
fi

if [ -z "${PANEL:-}" ] && [ -e /dev/ttyUSB0 ]; then
  if stty -F /dev/ttyUSB0 9600 raw -echo -hupcl 2>/dev/null; then
    export PANEL=/dev/ttyUSB0
  else
    echo "panel port /dev/ttyUSB0 is busy (Arduino IDE serial monitor?): starting without the panel"
  fi
fi

if [ "${ARK_REAL_CUT:-}" != 1 ]; then
  export ARK_CUT_CMD=true ARK_RESTORE_CMD=true
fi
export ARK_COST_PER_RECORD="${ARK_COST_PER_RECORD:-160}"

exec ./station.sh "$station" usb "$uno"
