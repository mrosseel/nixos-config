#!/usr/bin/env bash
set -euo pipefail

HOST="mike@pifinder.eu"

echo "Building general-server system closure..."
nix build .#nixosConfigurations.general-server.config.system.build.toplevel

SYSTEM_PATH=$(readlink -f ./result)
echo "Built: $SYSTEM_PATH"

echo "Copying closure to general-server..."
nix-store --export $(nix-store -qR "$SYSTEM_PATH") | ssh "$HOST" 'sudo /run/current-system/sw/bin/nix-store --import' > /dev/null

echo "Activating..."
ssh "$HOST" "sudo /run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set $SYSTEM_PATH && sudo $SYSTEM_PATH/bin/switch-to-configuration switch"

echo "Done."
