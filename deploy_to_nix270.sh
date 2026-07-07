#!/usr/bin/env bash
set -euo pipefail

# Deploys the nix270 configuration via nixos-rebuild's built-in remote-host
# support. The closure is built locally (nix270's disk is too small to build
# the full system) and pushed to the target. nix270 trusts @wheel, so the
# unsigned local build is accepted. Prompts for the target's sudo password.
cd "$(dirname "$(readlink -f "$0")")"
exec nixos-rebuild switch \
  --flake .#nix270 \
  --target-host mike@nix270.local \
  --use-remote-sudo \
  --ask-elevate-password \
  "$@"
