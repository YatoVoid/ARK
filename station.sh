#!/usr/bin/env bash
# Starts one ARK station and the socat bridge it talks through.
#
#   ./station.sh DIR usb [ADB_SERIAL]   relay reached over USB (adb port forward)
#   ./station.sh DIR wifi HOST          relay reached over Wi-Fi at HOST
#
# With PANEL=/dev/ttyUSB0 set, the Arduino panel on that port is used too.
set -euo pipefail
cd "$(dirname "$0")"

dir="${1:?station directory}"
how="${2:?usb or wifi}"
port_file="/tmp/ark-$(basename "$dir")"

case "$how" in
  usb)
    serial="${3:-}"
    adb ${serial:+-s "$serial"} forward tcp:4210 tcp:4210 >/dev/null
    target="TCP:127.0.0.1:4210"
    ;;
  wifi)
    target="TCP:${3:?relay address}:4210"
    ;;
  *)
    echo "second argument must be usb or wifi" >&2
    exit 2
    ;;
esac

[ -x build/ark ] || { mkdir -p build && hcc src/main.HC -o build/ark; }

socat "pty,raw,echo=0,link=$port_file" "$target" &
bridge=$!
trap 'kill $bridge 2>/dev/null' EXIT
for _ in $(seq 30); do [ -e "$port_file" ] && break; sleep 0.1; done
[ -e "$port_file" ] || { echo "could not reach the relay at $target" >&2; exit 1; }

if [ -n "${PANEL:-}" ]; then
  stty -F "$PANEL" 9600 raw -echo -hupcl
  ./build/ark "$dir" "$port_file" "$PANEL"
else
  ./build/ark "$dir" "$port_file"
fi
