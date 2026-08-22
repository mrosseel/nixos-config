# overlays/ollama.nix
#
# TEMPORARY. Pulls ollama from a pinned nixpkgs master rev instead of the
# nixpkgs-unstable channel.
#
# Reason: qwen3.8 needs ollama 0.32.12 or newer. Older servers reject the pull
# with HTTP 412. As of 2026-08-16 nixpkgs-unstable is on 0.32.7 and master is
# on 0.32.13. The master build is in cache.nixos.org, so this substitutes and
# does not compile ROCm locally.
#
# Both attributes are overridden together: ollama-rocm is the server
# (services.ollama.package in modules/ai.nix) and ollama is the CLI client on
# PATH. Overriding only one leaves a client/server version skew.
#
# Remove this overlay, its import in flake.nix, and the nixpkgs-master input
# once nixpkgs-unstable reaches 0.32.12 or newer.
master: final: prev: {
  ollama = master.legacyPackages.${prev.system}.ollama;
  ollama-rocm = master.legacyPackages.${prev.system}.ollama-rocm;
}
