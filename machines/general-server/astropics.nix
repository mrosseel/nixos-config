{ pkgs, inputs, ... }:

# Astropics, an astronomy image website. The module comes from
# github:mrosseel/astropics (nix/module.nix there). It runs Postgres, the
# FastAPI API on 127.0.0.1:8300 and the React Router SSR server on
# 127.0.0.1:8301. Caddy proxies the vhost (see caddy-service.nix).
#
# The first start writes the keys to /var/lib/astropics/env. Add the Mailgun,
# Google and Discord keys to that file by hand. Admin commands:
#   sudo astropics-manage admin make-staff <email>
#   sudo astropics-manage seed

let
  # miker.be has a wildcard DNS record to this host, so a new name needs no
  # DNS change. Change the Caddy vhost in caddy-service.nix together with it.
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

  # This host had no Postgres before Astropics. Start on 17, the version of
  # the astropics dev shell. A later major change needs a dump and a restore.
  services.postgresql.package = pkgs.postgresql_17;

  # github:mrosseel/astropics is private, and this host has no GitHub token.
  # The nightly auto-upgrade evaluates the flake again and needs the source of
  # each input. With the source in the system closure it is already in the
  # store, so no fetch from GitHub is necessary. Deploys go from nixtop.
  system.extraDependencies = [ inputs.astropics.outPath ];
}
