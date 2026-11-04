# overlays/anydesk.nix
#
# TEMPORARY. Builds anydesk with patchelf 0.15.2 from the nixpkgs-master input.
#
# Reason: patchelf 0.19.2 (nixpkgs 02c087f) makes a broken binary when one
# invocation sets the interpreter and the rpath (NixOS/patchelf#674,
# NixOS/nixpkgs#576412). The anydesk postFixup does exactly that, and the
# result crashes in ld.so (SEGV in dl_main) before any library loads. The
# old patchelf goes first in nativeBuildInputs, so it is first in PATH and
# wins over the patchelf of the stdenv. A build tool from another nixpkgs
# is fine here: nothing links against it.
#
# Remove this overlay and its import in flake.nix once nixpkgs has a patchelf
# without the bug, or splits the anydesk patchelf call in two.
#
# The src override is also TEMPORARY. AnyDesk replaced
# anydesk-8.1.0-amd64.tar.gz on its server on Nov 3 2026 under the same
# version, so the nixpkgs hash (sha256-ImFf...) no longer matches the download.
# Remove the override when nixpkgs has the new hash or a newer version.
master: final: prev: {
  anydesk = prev.anydesk.overrideAttrs (old: {
    src = prev.fetchurl {
      url = "https://download.anydesk.com/linux/anydesk-${old.version}-amd64.tar.gz";
      hash = "sha256-zS5P2eyTHZY7cBW8mQ2Q6M0lXcx9VZZTtpG3Bb6u7IQ=";
    };
    nativeBuildInputs = [
      master.legacyPackages.${prev.stdenv.hostPlatform.system}.patchelf
    ]
    ++ (old.nativeBuildInputs or [ ]);
  });
}
