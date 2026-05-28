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

  # Create the public 'pifinder' cache on first start.
  #
  # atticadm itself only has `make-token` and `help` subcommands — cache
  # creation is done by the `attic` *client* against the running atticd
  # API. So we mint a one-shot setup token with create_cache /
  # configure_cache rights, log into the local loopback endpoint with it,
  # and run `attic cache create … --public`. The setup token expires in
  # 5 minutes and is never written to disk.
  #
  # Marker is `-v2` because v1 (which ran `atticadm create-cache`, a
  # non-existent subcommand) silently no-op'd; renaming forces this
  # corrected service to run on the next rebuild.
  systemd.services.atticd-bootstrap-cache = {
    description = "Create the pifinder cache on first start";
    after = [ "atticd.service" ];
    requires = [ "atticd.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/atticd/.pifinder-cache-bootstrapped-v2";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ curl coreutils attic-client ];
    script = ''
      set -euo pipefail
      # Wait for atticd to bind 127.0.0.1:8080.
      for i in $(seq 1 60); do
        if curl -fsS -o /dev/null http://127.0.0.1:8080/ ; then
          break
        fi
        sleep 1
      done
      SETUP_TOKEN=$(/run/current-system/sw/bin/atticd-atticadm make-token \
        --sub bootstrap \
        --validity 5m \
        --create-cache pifinder \
        --configure-cache pifinder \
        --push pifinder \
        --pull pifinder)
      # Keep attic client state out of root's $HOME — fresh per run.
      export ATTIC_CONFIG_DIR=$(mktemp -d)
      trap 'rm -rf "$ATTIC_CONFIG_DIR"' EXIT
      attic login local http://127.0.0.1:8080 "$SETUP_TOKEN"
      # `cache create` errors if it already exists — tolerate so re-runs
      # remain idempotent. `cache configure --public` then enforces the
      # desired state regardless of whether create or configure ran.
      attic cache create local:pifinder --public || true
      attic cache configure local:pifinder --public
      touch /var/lib/atticd/.pifinder-cache-bootstrapped-v2
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
