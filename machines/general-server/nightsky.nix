{ pkgs, inputs, ... }:

# Nightsky.pics, an astronomy image website. The module comes from
# github:mrosseel/nightsky (nix/module.nix there). It runs Postgres, the
# FastAPI API on 127.0.0.1:8300 and the React Router SSR server on
# 127.0.0.1:8301. Caddy proxies the vhost (see caddy-service.nix).
#
# The first start writes the keys to /var/lib/nightsky/env. Add the SES SMTP,
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
    # Launch (2026-10-06): no test mode. New accounts confirm their email, there
    # is no test banner, and search engines may index the site (ADR 0011, 0071).
    testMode = false;
    # Amazon SES in eu-central-1 sends the app mail. The SMTP login is in
    # /var/lib/nightsky/env: NIGHTSKY_SMTP_USERNAME and NIGHTSKY_SMTP_PASSWORD.
    # Replies go to info@, which the pifinder.eu mailserver receives
    # (modules/nightsky-mail.nix).
    mailBackend = "smtp";
    mail = {
      from = "Nightsky.pics <no-reply@${domain}>";
      replyTo = "info@${domain}";
      smtp.host = "email-smtp.eu-central-1.amazonaws.com";
    };
    # Built on nixtop with backend/scripts/build_sky_atlas.py and copied here by hand
    # (see the nightsky README). About 180 MB.
    skyAtlasPath = "/var/lib/nightsky/sky-atlas.bin";
    basemapPath = "/var/lib/nightsky/world.pmtiles";
    # The Moon plate solver (2026-10-09, admin-only overlay). The data folder
    # (4.6 GB: the LOLA height map and its levels, the crater tiers, the albedo
    # map and the catalog) was copied from nixtop by hand; the steps are in
    # docs/moon-solver.md of the nightsky repo. The worker runs one solve at a
    # time with a 2048M limit; the limit also counts the page cache of the maps.
    moonWorker = {
      enable = true;
      dataDir = "/var/lib/nightsky/moon-data";
    };
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
