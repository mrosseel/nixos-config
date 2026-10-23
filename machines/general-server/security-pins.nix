{ inputs, ... }:

# TEMPORARY. Security fixes that nixos-unstable does not carry yet.
#
# The 2026-10-21 releases fixed remote code execution in PHP (CVE-2026-109618,
# CVE-2026-109619; fixed in 8.3.36) and in the Node.js Brotli decoder
# (CVE-2026-111497; fixed in 24.22.1 and 22.23.4). general-server runs
# php-fpm for joeri.miker.be, node 24 for starnightsshop and node 22 for
# nightsky-web.
#
# - php83 comes from a pinned nixpkgs master rev (input nixpkgs-php). The
#   master build is in cache.nixos.org.
# - Node keeps the nixpkgs build recipe and only changes the source. The
#   nixpkgs patches are the same for both versions. Node compiles on the
#   build host (about 30 minutes per version on nixtop).
#
#   In nixpkgs the node binary lives in nodejs-slim_NN. nodejs_NN is only a
#   symlink wrapper (symlink.nix) that adds npm. The bump must go on the
#   slim package, and the wrapper must be re-pointed at it.
#
#   The Brotli bug is in libbrotli itself. nixpkgs links node against the
#   system brotli (--shared-brotli), and the fixed node sources need the
#   brotli 1.2.1 headers (BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH). Staging
#   bumps brotli to 1.2.1 for the whole package set. Here only the two node
#   builds get brotli 1.2.1. Other brotli users (curl, ...) keep 1.2.0 until
#   nixos-unstable carries the staging bump.
#
# The node 24 fix is a new attribute, not an override of nodejs_24. Many
# Python packages use nodejs_24 at build time (torch -> fsspec -> aiohttp ->
# furo -> nodejs). An override of nodejs_24 rebuilds torch and friends, which
# takes hours. starnightsshop in systemd.nix uses nodejs_24_security. The
# nightsky module reads pkgs.nodejs_22 and cannot be pointed at another
# attribute, so nodejs_22 is overridden. Only nightsky depends on it here.
#
# These overlays apply only to general-server. A global overlay would rebuild
# every package that depends on nodejs on every host.
#
# Remove each pin, and the nixpkgs-php input, when nixos-unstable has the
# fixed version. Check with:
#   nix eval --raw .#nixosConfigurations.general-server.pkgs --apply \
#     'p: "${p.php83.version} ${p.nodejs_22.version} ${p.nodejs_24.version}"'
let
  bumpNodejs =
    prev: pkg: version: sha256:
    pkg.overrideAttrs (_: {
      inherit version;
      src = prev.fetchurl {
        url = "https://nodejs.org/dist/v${version}/node-v${version}.tar.xz";
        inherit sha256;
      };
    });
  # v22.nix and v24.nix take `callPackage` and call nodejs.nix with it.
  # A callPackage with brotli in scope gives node that brotli and nothing else.
  withBrotli =
    prev: brotli: pkg:
    pkg.override { callPackage = prev.newScope { inherit brotli; }; };
in
{
  nixpkgs.overlays = [
    (final: prev: {
      php83 = inputs.nixpkgs-php.legacyPackages.${prev.stdenv.hostPlatform.system}.php83;

      brotli_1_2_1 = prev.brotli.overrideAttrs (_: rec {
        version = "1.2.1";
        src = prev.fetchFromGitHub {
          owner = "google";
          repo = "brotli";
          tag = "v${version}";
          hash = "sha256-llY72cYffDv0ugsH0p89xIPEbElV4L8u7U/Fe8hT3gI=";
        };
      });

      nodejs-slim_24_security = bumpNodejs prev
        (withBrotli prev final.brotli_1_2_1 prev.nodejs-slim_24) "24.22.1"
        "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
      nodejs_24_security = prev.nodejs_24.override {
        nodejs-slim = final.nodejs-slim_24_security;
      };

      nodejs-slim_22 = bumpNodejs prev
        (withBrotli prev final.brotli_1_2_1 prev.nodejs-slim_22) "22.23.4"
        "7b9adc82d612d0a2a863d96c46de2292552e250cee51956ebbe0146c42aacae9";
      nodejs_22 = prev.nodejs_22.override { nodejs-slim = final.nodejs-slim_22; };
    })
  ];
}
