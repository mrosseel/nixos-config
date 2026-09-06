#!/usr/bin/env bash
set -euo pipefail

# Temporary low-bandwidth deploy: use the local 1901 working tree as the
# diplomacy1901 flake input, but download dependencies and build on the server.

NIXOS_CONFIG="${NIXOS_CONFIG:-/home/mike/nixos-config}"
SOURCE="${SOURCE:-/home/mike/dev/1901}"
SERVER="${SERVER:-mike@pifinder.eu}"

[[ -f "${NIXOS_CONFIG}/flake.nix" ]] || {
  echo "deploy1901-server-build.sh: no flake.nix in ${NIXOS_CONFIG}" >&2
  exit 1
}
[[ -f "${SOURCE}/flake.nix" ]] || {
  echo "deploy1901-server-build.sh: no 1901 flake.nix in ${SOURCE}" >&2
  exit 1
}

echo -n "backing up the database ... "
backup_stamp=$(date +%Y%m%d-%H%M%S)
ssh "${SERVER}" \
  "sudo cp -a /var/lib/1901/1901.db /var/lib/1901/1901.db.bak-${backup_stamp}" \
  && echo "done" || echo "FAILED — no backup was taken"

echo "building on ${SERVER} and deploying ${SOURCE} ..."
nixos-rebuild switch \
  --flake "${NIXOS_CONFIG}#general-server" \
  --override-input diplomacy1901 "path:${SOURCE}" \
  --no-write-lock-file \
  --build-host "${SERVER}" \
  --target-host "${SERVER}" \
  --use-remote-sudo \
  --use-substitutes \
  "$@"

echo -n "checking https://1901.miker.be/api/v1/variants ... "
count=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  count=$(curl -fsS --max-time 30 https://1901.miker.be/api/v1/variants 2>/dev/null \
    | jq 'length' 2>/dev/null || echo 0)
  (( count > 0 )) && break
  sleep 2
done
if (( count < 1 )); then
  echo "no variants after 20s. The board art did not reach the server."
  exit 1
fi
echo "${count} variants"
