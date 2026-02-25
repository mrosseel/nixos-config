#!/usr/bin/env bash
set -euo pipefail

HOST="mike@192.168.5.12"

echo "Building proxnix system closure..."
nix build .#nixosConfigurations.proxnix.config.system.build.toplevel

SYSTEM_PATH=$(readlink -f ./result)
echo "Built: $SYSTEM_PATH"

echo "Copying closure to proxnix..."
nix-store --export $(nix-store -qR "$SYSTEM_PATH") | ssh "$HOST" 'sudo nix-store --import' > /dev/null

echo "Activating..."
ssh "$HOST" "sudo nix-env -p /nix/var/nix/profiles/system --set $SYSTEM_PATH && sudo $SYSTEM_PATH/bin/switch-to-configuration switch"

echo "Done."
