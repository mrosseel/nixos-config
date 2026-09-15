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

# The database is the only thing on the server that cannot be rebuilt. A
# migration that goes wrong, or a rollback across one, has nothing to go back
# to without this. Cheap, and the only line here that protects data rather
# than convenience.
#
# It has to be sqlite3's own .backup and not cp. The database runs in WAL
# mode, so 1901.db holds only what was last checkpointed and everything since
# lives in 1901.db-wal next to it. The server never closes the database (it
# ends at log.Fatal on SIGTERM), so nothing checkpoints on the way out. On
# 2026-09-15 the main file had not been written since 2026-09-02: the cp
# backup held 18 dead test games and not one live board.
#
# The verify is part of the backup, not decoration. A backup nobody counted
# is what produced that.
stamp=$(date +%Y%m%d-%H%M%S)
backup=/var/lib/1901/1901.db.bak-$stamp
echo -n "backing up the database ... "
if ssh mike@pifinder.eu "sudo -u d1901 sqlite3 /var/lib/1901/1901.db \".backup '$backup'\""; then
  live=$(ssh mike@pifinder.eu "sudo -u d1901 sqlite3 /var/lib/1901/1901.db 'SELECT count(*) FROM game;'")
  kept=$(ssh mike@pifinder.eu "sudo -u d1901 sqlite3 $backup 'SELECT count(*) FROM game;'")
  if [[ $kept == "$live" && $kept -gt 0 ]]; then
    echo "done, $kept games"
  else
    echo "the backup holds $kept games and the live database holds $live"
    exit 1
  fi
else
  echo "FAILED — no backup was taken"
  exit 1
fi

nixos-rebuild switch \
  --flake .#general-server \
  --target-host mike@pifinder.eu \
  --use-remote-sudo \
  "$@"

# The maps come from GENERATED_VARIANTS. When that breaks the server still
# answers 200 on every page and simply has no variants, so count them.
# The service is restarting as nixos-rebuild returns, so the first curl lands
# on a socket nobody is listening to yet. It printed 502 on two good deploys
# before this loop existed, which is a check that cries wolf and gets ignored.
echo -n "checking https://1901.miker.be/api/v1/variants ... "
count=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  count=$(curl -fsS --max-time 30 https://1901.miker.be/api/v1/variants 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
  (( count > 0 )) && break
  sleep 2
done
if (( count < 1 )); then
  echo "no variants after 20s. The board art did not reach the server."
  exit 1
fi
echo "${count} variants"
