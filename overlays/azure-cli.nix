# overlays/azure-cli.nix
#
# TEMPORARY. Takes azure-cli from nixpkgs-stable (25.11) instead of
# nixos-unstable.
#
# Reason: azure-cli needs the python module fabric. On nixos-unstable fabric
# 3.2.3 is marked broken, because invoke is at 3.0.3 and fabric does not work
# with invoke 3 (https://github.com/fabric/fabric/issues/2376). The nixtop
# evaluation stops with "Refusing to evaluate package python3.14-fabric".
# nixpkgs-stable has invoke 2.2.0, so its fabric and azure-cli build, and
# both are in cache.nixos.org.
#
# Remove this overlay and its import in flake.nix once nixos-unstable has a
# fabric that is not broken.
stable: final: prev: {
  azure-cli = stable.legacyPackages.${prev.stdenv.hostPlatform.system}.azure-cli;
}
