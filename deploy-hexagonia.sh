#!/usr/bin/env bash
set -euo pipefail

# Ships the current tip of hexagonia's master to general-server.
#
# One command moves both halves. The flake input gives the Rust server and the
# built frontend, and both come from the revision this script locks, so the
# page and the server always run the same code. The game repository's own
# deploy.sh is retired.
#
# Nothing does this on its own. system.autoUpgrade updates nixpkgs only, and
# it builds from a store path frozen at deploy time.
#
#   ./deploy-hexagonia.sh            update the input, deploy, check the result
#   ./deploy-hexagonia.sh --no-bump  deploy the locked revision as it stands

cd "$(dirname "$(readlink -f "$0")")"

deploy_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

bump=1
[[ ${1-} == --no-bump ]] && { bump=0; shift; }

if (( bump )); then
  nix flake update hexagonia
  if ! git diff --quiet flake.lock; then
    rev=$(nix flake metadata --json \
      | jq -r '.locks.nodes.hexagonia.locked.rev[0:7]')
    git commit -q -m "chore(general-server): hexagonia to ${rev}" flake.lock
    echo "locked hexagonia at ${rev}"
  else
    echo "hexagonia is already at the tip of master"
  fi
fi

ssh mike@pifinder.eu "printf 'HX_DEPLOYED_AT=%s\\n' '$deploy_at' | sudo tee /var/lib/hexagonia/deploy.env >/dev/null"

# Finished games are written to /var/lib/hexagonia/hexagonia.db. Games in
# progress live in memory and end with the restart either way, but the
# finished ones are the only thing here that cannot be rebuilt.
#
# `.backup`, not cp. The database runs in WAL mode, so the recent games sit in
# hexagonia.db-wal and not in hexagonia.db: on 11 September 2026 the file was
# 4096 bytes beside a 2.2 MB WAL, and every cp backup taken until then held an
# empty database. `.backup` reads through the WAL and writes one whole file.
#
# sqlite3 is in the server's systemPackages (machines/general-server/1901.nix),
# so it is on PATH and needs no hunting through the store.
echo -n "backing up the database ... "
ssh mike@pifinder.eu "sudo sqlite3 /var/lib/hexagonia/hexagonia.db \
  \".backup '/var/lib/hexagonia/hexagonia.db.bak-$(date +%Y%m%d-%H%M%S)'\"" \
  && echo "done" || echo "FAILED — no backup was taken"

nixos-rebuild switch \
  --flake .#general-server \
  --target-host mike@pifinder.eu \
  --use-remote-sudo \
  "$@"

# The service is restarting as nixos-rebuild returns, so the first curl can
# land on a socket nobody is listening to yet. Hence the retries.
echo -n "checking https://hextopia.miker.be/healthz ... "
ok=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS --max-time 30 https://hextopia.miker.be/healthz > /dev/null 2>&1 \
    && { ok=1; break; }
  sleep 2
done
if (( ok == 0 )); then
  echo "no answer after 20s. The server is not up."
  exit 1
fi
echo "the server answers"

# Caddy serves the bundle from the store now, so a page that names a script
# Caddy cannot find means the two are out of step. The name is a content hash
# of the build, which is the whole point of this check.
echo -n "checking the page and its bundle ... "
page=$(curl -fsS --max-time 30 https://hextopia.miker.be/) || {
  echo "the page did not load"
  exit 1
}
script=$(grep -o '/assets/index-[A-Za-z0-9_-]*\.js' <<< "$page" | head -1)
if [[ -z ${script} ]]; then
  echo "the page names no /assets/index-*.js"
  exit 1
fi
# `try_files {path} /index.html` answers 200 with the page for anything it
# cannot find, so a status code proves nothing. The content type does.
type=$(curl -fsS --max-time 30 -o /dev/null -w '%{content_type}' \
  "https://hextopia.miker.be${script}") || {
  echo "the page asks for ${script}, which did not load"
  exit 1
}
if [[ ${type} != *javascript* ]]; then
  echo "the page asks for ${script}, and got ${type} back instead of JavaScript"
  exit 1
fi
echo "the page loads ${script}"
