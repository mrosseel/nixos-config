{ inputs, ... }:

{
  # .default pins programs.hunk.package to the flake's own bun2nix build: one
  # derivation per npm dependency, ~555 of them, cached nowhere. .hunk is the
  # same module without that pin, so package falls back to pkgs.hunk, which
  # nixpkgs builds as a single fixed-output node_modules derivation and the
  # binary caches serve. Same version, no local build.
  imports = [ inputs.hunk.homeManagerModules.hunk ];

  programs.hunk = {
    enable = true;
    enableGitIntegration = true; # set hunk as default git pager
    settings = {
      theme = "graphite";
      mode = "split";
      line_numbers = true;
    };
  };
}
