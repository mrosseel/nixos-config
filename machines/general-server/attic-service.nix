{ config, lib, pkgs, ... }:

# Attic Nix binary cache for PiFinder NixOS distribution.
# Served at https://cache.pifinder.eu via Caddy reverse proxy (caddy-service.nix).
# See docs/adr/0004-attic-binary-cache.md in the PiFinder repo for the rationale.
#
# Three systemd oneshots make this fully declarative — no manual SSH
# atticadm steps. Each runs at most once, guarded by ConditionPathExists:
#
#   atticd-bootstrap-secret  →  generates the RS256 JWT secret
#                               at /var/lib/atticd/env
#   atticd-bootstrap-cache   →  creates the public 'pifinder' cache
#   atticd-bootstrap-token   →  mints a 5-year CI push/pull JWT and
#                               writes it to /var/lib/atticd/ci-token
#
# After deploy, the one-and-only manual step is to read the CI token
# (sudo cat /var/lib/atticd/ci-token) and paste it into the PiFinder
# repo's GitHub Actions secrets as ATTIC_TOKEN. Cache public key is
# fetchable from https://cache.pifinder.eu/pifinder.
#
# Wiping any of the marker files (.pifinder-cache-bootstrapped,
# .pifinder-token-bootstrapped) re-runs the corresponding step, which
# would mint a NEW token and invalidate the old one. So don't.

{
  services.atticd = {
    enable = true;
    environmentFile = "/var/lib/atticd/env";

    settings = {
      listen = "127.0.0.1:8080";

      # Public URL clients use — must match the Caddy vhost. Attic embeds
      # this in cache-info responses and signed URLs.
      api-endpoint = "https://cache.pifinder.eu/";

      # Default chunking thresholds from the upstream nixosModule (16K min,
      # 64K avg, 256K max) are appropriate for our closure sizes; left at
      # the module defaults.
    };
  };

  # Bootstrap the RS256 JWT secret on first start. Idempotent: only runs
  # when /var/lib/atticd/env is missing, so existing tokens survive
  # rebuilds.
  systemd.services.atticd-bootstrap-secret = {
    description = "Generate atticd RS256 JWT secret on first start";
    before = [ "atticd.service" ];
    wantedBy = [ "atticd.service" ];
    unitConfig.ConditionPathExists = "!/var/lib/atticd/env";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ openssl coreutils ];
    script = ''
      install -d -m 0700 -o root -g root /var/lib/atticd
      umask 077
      SECRET=$(openssl genrsa -traditional 4096 2>/dev/null | base64 -w0)
      printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="%s"\n' "$SECRET" \
        > /var/lib/atticd/env
      chown root:root /var/lib/atticd/env
      chmod 0600 /var/lib/atticd/env
    '';
  };

  # Create the public 'pifinder' cache on first start, after atticd is
  # listening. atticd-atticadm uses systemd-run to enter atticd's
  # DynamicUser context, so we just need it on PATH.
  systemd.services.atticd-bootstrap-cache = {
    description = "Create the pifinder cache on first start";
    after = [ "atticd.service" ];
    requires = [ "atticd.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/atticd/.pifinder-cache-bootstrapped";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ curl coreutils ];
    script = ''
      set -euo pipefail
      # Wait for atticd to bind 127.0.0.1:8080.
      for i in $(seq 1 60); do
        if curl -fsS http://127.0.0.1:8080/ > /dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      # Idempotent under re-runs: atticadm exits non-zero if the cache
      # already exists, which is fine when this marker has been wiped.
      /run/current-system/sw/bin/atticd-atticadm create-cache pifinder --public || true
      touch /var/lib/atticd/.pifinder-cache-bootstrapped
    '';
  };

  # Mint a long-lived CI token on first start and write it to a
  # root-readable file. Operator reads it once via `sudo cat` and pastes
  # into the PiFinder repo's GitHub Actions secrets as ATTIC_TOKEN.
  systemd.services.atticd-bootstrap-token = {
    description = "Mint the CI push/pull token on first start";
    after = [ "atticd-bootstrap-cache.service" ];
    requires = [ "atticd-bootstrap-cache.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/atticd/.pifinder-token-bootstrapped";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ coreutils ];
    script = ''
      set -euo pipefail
      umask 077
      /run/current-system/sw/bin/atticd-atticadm make-token \
        --sub ci \
        --validity 5y \
        --pull pifinder \
        --push pifinder \
        > /var/lib/atticd/ci-token
      chown root:root /var/lib/atticd/ci-token
      chmod 0600 /var/lib/atticd/ci-token
      touch /var/lib/atticd/.pifinder-token-bootstrapped
    '';
  };
}
