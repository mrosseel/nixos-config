{ config, lib, pkgs, ... }:

# Attic Nix binary cache for PiFinder NixOS distribution.
# Served at https://cache.pifinder.eu via Caddy reverse proxy (caddy-service.nix).
# See docs/adr/0004-attic-binary-cache.md in the PiFinder repo for the rationale.
#
# Post-deploy, runs once on the target via atticd-atticadm to create the
# public read-only cache and mint a long-lived CI push token:
#   sudo atticd-atticadm create-cache pifinder --public
#   sudo atticd-atticadm make-token --sub ci --validity 5y \
#     --pull pifinder --push pifinder
# The make-token output is the JWT that goes into the PiFinder repo's GH
# Actions secrets as ATTIC_TOKEN. Cache public key is then fetchable from
# https://cache.pifinder.eu/pifinder.

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
  # rebuilds. Wiping the env file invalidates every previously-minted
  # token, so don't.
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
}
