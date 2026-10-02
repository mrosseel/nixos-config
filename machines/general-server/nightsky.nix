{ pkgs, inputs, ... }:

# Nightsky.pics, an astronomy image website. The module comes from
# github:mrosseel/nightsky (nix/module.nix there). It runs Postgres, the
# FastAPI API on 127.0.0.1:8300 and the React Router SSR server on
# 127.0.0.1:8301. Caddy proxies the vhost (see caddy-service.nix).
#
# The first start writes the keys to /var/lib/nightsky/env. Add the Mailgun,
# Google and Discord keys to that file by hand. Admin commands:
#   sudo nightsky-manage admin make-staff <email>
#   sudo nightsky-manage seed

let
  # The official name since 2026-09-30, behind the Cloudflare proxy. The old
  # name astropics.miker.be redirects to it (caddy-service.nix). Change the
  # Caddy vhost together with it.
  domain = "nightsky.pics";
in
{
  services.nightsky = {
    enable = true;
    publicUrl = "https://${domain}";
    # Test server: new accounts need no mail confirmation.
    testMode = true;
    # Mails go to the journal until Mailgun is set up.
    mailBackend = "console";
    # Built on nixtop with backend/scripts/build_sky_atlas.py and copied here by hand
    # (see the nightsky README). About 180 MB.
    skyAtlasPath = "/var/lib/nightsky/sky-atlas.bin";
    basemapPath = "/var/lib/nightsky/world.pmtiles";
    # The image files are in Cloudflare R2 since 2026-10-02 (ADR 0064), in the
    # account Parsec vzw. The keys NIGHTSKY_R2_ACCESS_KEY_ID and
    # NIGHTSKY_R2_SECRET_ACCESS_KEY are in /var/lib/nightsky/env. The old local
    # files are in /var/lib/nightsky/media-local-2026-10-02 until the backup
    # runs (ADR 0087).
    storage = {
      backend = "r2";
      r2 = {
        accountId = "226f32054ee675c64ab9e320f9c3bc68";
        publicBucket = "nightsky-public";
        privateBucket = "nightsky-private";
        publicUrl = "https://media.nightsky.pics";
      };
    };
  };

  # The service user keeps the uid and the gid of the old user "astropics"
  # (rename of 2026-09-30), so the copied files in /var/lib/nightsky keep
  # their owner.
  users.users.nightsky.uid = 975;
  users.groups.nightsky.gid = 969;

  # This host had no Postgres before Nightsky.pics. Start on 17, the version of
  # the nightsky dev shell. A later major change needs a dump and a restore.
  services.postgresql.package = pkgs.postgresql_17;

  # github:mrosseel/nightsky is private, and this host has no GitHub token.
  # The nightly auto-upgrade evaluates the flake again and needs the source of
  # each input. With the source in the system closure it is already in the
  # store, so no fetch from GitHub is necessary. Deploys go from nixtop.
  system.extraDependencies = [ inputs.nightsky.outPath ];
}
