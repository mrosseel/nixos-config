{ pkgs, ... }:

# Astropics, an astronomy image website. The module comes from
# github:mrosseel/astropics (nix/module.nix there). It runs Postgres, the
# FastAPI API on 127.0.0.1:8300 and the React Router SSR server on
# 127.0.0.1:8301. Caddy proxies the vhost (see caddy-service.nix).
#
# The first start writes the keys to /var/lib/astropics/env. Add the Mailgun,
# Google and Discord keys to that file by hand.

let
  # The DNS A record for this name must point to this host before Caddy can
  # get a certificate. Change the Caddy vhost in caddy-service.nix together
  # with this name.
  domain = "astropics.miker.be";
in
{
  services.astropics = {
    enable = true;
    publicUrl = "https://${domain}";
    # Test server: new accounts need no mail confirmation.
    testMode = true;
    # Mails go to the journal until Mailgun is set up.
    mailBackend = "console";
  };

  # This host had no Postgres before Astropics. Without a package, the
  # stateVersion 23.11 gives Postgres 15. Start on 17, the version of the
  # astropics dev shell. A later major change needs a dump and a restore.
  services.postgresql.package = pkgs.postgresql_17;

  # postgresql.service is ready before postgresql-setup.service makes the
  # astropics role and database. postgresql.target includes both. Remove
  # this when the astropics module orders the API after that target.
  systemd.services.astropics-api = {
    after = [ "postgresql.target" ];
    requires = [ "postgresql.target" ];
  };
}
