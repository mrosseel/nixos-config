#!/usr/bin/env bash
set -euo pipefail

# Deploys the nixair (Finn's GNOME box) configuration via nixos-rebuild's
# built-in remote-host support. The closure is built locally (nixair's R9 290
# box is slow) and pushed to the target.
#
# Target is root@ on purpose: root is a trusted Nix user, so it accepts the
# unsigned local build, and it needs no sudo password. The deployed config
# authorizes mike@nixtop for root, so no manually-installed key is required.
#
# nixair publishes its name over mDNS (modules/linux/avahi.nix), so we address
# it as nixair.local. If that ever fails to resolve, fall back to the LAN IP:
#   NIXAIR_HOST=192.168.5.106 ./deploy_to_nixair.sh
# (Note: mDNS publishing only takes effect after the first deploy that includes
# the avahi module, so bootstrap that first run with the IP override.)
cd "$(dirname "$(readlink -f "$0")")"

NIXAIR_HOST="${NIXAIR_HOST:-nixair.local}"

# nixair's sshd is sluggish to send its banner; be patient and keep-alive.
export NIX_SSHOPTS="${NIX_SSHOPTS:--o ConnectTimeout=60 -o ServerAliveInterval=20 -o ServerAliveCountMax=10}"

exec nixos-rebuild switch \
  --flake ".#nixair" \
  --target-host "root@${NIXAIR_HOST}" \
  --build-host localhost \
  "$@"
