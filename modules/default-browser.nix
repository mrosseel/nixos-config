# modules/default-browser.nix
# Brave's Wayland flags are applied via the overlay in ./overlays/brave.nix.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brave
  ];
}
