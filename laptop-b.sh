#!/usr/bin/env bash
# Laptop B, the analyst: checks packages, builds ARK and opens the
# analyst's window, talking to the relay over Wi-Fi.
#
#   ./laptop-b.sh RELAY_ADDRESS      e.g. ./laptop-b.sh 10.147.184.235
#
# laptop-a.sh prints the address to use. Join the same Wi-Fi as the UNO Q first.
set -euo pipefail
cd "$(dirname "$0")"

relay="${1:-${ARK_RELAY:-}}"
[ -n "$relay" ] || { echo "usage: ./laptop-b.sh RELAY_ADDRESS (laptop A prints it)" >&2; exit 2; }
station="${ARK_STATION:-station-b}"
mkdir -p build

need=$(pacman -T sdl2-compat sdl2_ttf libsodium socat || true)
if [ -n "$need" ]; then
  echo "installing: $need"
  sudo pacman -S --needed $need
fi
command -v hcc >/dev/null || { echo "hcc is not installed, see docs/BUILDING.md" >&2; exit 1; }

echo "building ARK"
hcc src/main.HC -o build/ark

echo "checking the relay at $relay"
if ! timeout 5 bash -c "exec 3<>/dev/tcp/$relay/4210" 2>/dev/null; then
  echo "can't reach the relay at $relay:4210. Is this laptop on the same Wi-Fi, and is laptop-a.sh running?" >&2
  exit 1
fi

exec ./station.sh "$station" wifi "$relay"
