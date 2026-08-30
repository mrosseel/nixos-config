#!/usr/bin/env bash
set -euo pipefail

# Ships the current tip of 1901's master to general-server.
#
# Nothing does this on its own. system.autoUpgrade updates nixpkgs only, and
# it builds from a store path frozen at deploy time, so neither new 1901
# commits nor new nixos-config commits reach the server without this script.
#
#   ./deploy1901.sh            update the input, deploy, check the result
#   ./deploy1901.sh --no-bump  deploy the locked revision as it stands

cd "$(dirname "$(readlink -f "$0")")"

bump=1
[[ ${1-} == --no-bump ]] && { bump=0; shift; }

if (( bump )); then
  nix flake update diplomacy1901
  if ! git diff --quiet flake.lock; then
    rev=$(nix flake metadata --json \
      | jq -r '.locks.nodes.diplomacy1901.locked.rev[0:7]')
    git commit -q -m "chore(general-server): 1901 to ${rev}" flake.lock
    echo "locked 1901 at ${rev}"
  else
    echo "1901 is already at the tip of master"
  fi
fi

nixos-rebuild switch \
  --flake .#general-server \
  --target-host mike@pifinder.eu \
  --use-remote-sudo \
  "$@"

# The maps come from GENERATED_VARIANTS. When that breaks the server still
# answers 200 on every page and simply has no variants, so count them.
echo -n "checking https://1901.miker.be/variants ... "
count=$(curl -fsS --max-time 30 https://1901.miker.be/variants | jq 'length')
if (( count < 1 )); then
  echo "no variants. The board art did not reach the server."
  exit 1
fi
echo "${count} variants"
