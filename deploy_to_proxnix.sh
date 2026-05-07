#!/usr/bin/env bash
set -euo pipefail

# Deploys the proxnix configuration via nixos-rebuild's built-in
# remote-host support. Requires passwordless sudo on the target.
cd "$(dirname "$(readlink -f "$0")")"
exec nixos-rebuild switch \
  --flake .#proxnix \
  --target-host mike@proxnix \
  --use-remote-sudo \
  "$@"
