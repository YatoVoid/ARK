#!/usr/bin/env bash
# Builds and runs every test. The link test uses two fake serial ports
# made by socat, so no ESP32 is needed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
failed=0

run() {
  echo "== $1"
  hcc "tests/$1.HC" -o "build/$1"
  shift_args=("${@:2}")
  "./build/$1" ${shift_args[@]+"${shift_args[@]}"} || failed=1
}

run test_crypto

rm -rf build/tmp-log && mkdir -p build/tmp-log
run test_log
run test_deadlines

tmp=$(mktemp -d)
socat "pty,raw,echo=0,link=$tmp/a" "pty,raw,echo=0,link=$tmp/b" &
socat_pid=$!
trap 'kill $socat_pid 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do [ -e "$tmp/b" ] && break; sleep 0.1; done
run test_link "$tmp/a" "$tmp/b"

if [ "$failed" = 1 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
