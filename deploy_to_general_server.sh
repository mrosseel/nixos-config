#!/usr/bin/env bash
set -euo pipefail

# Deploys the general-server configuration via nixos-rebuild's built-in
# remote-host support. Requires passwordless sudo on the target.
cd "$(dirname "$(readlink -f "$0")")"
exec nixos-rebuild switch \
  --flake .#general-server \
  --target-host mike@pifinder.eu \
  --use-remote-sudo \
  "$@"
