# modules/default-browser.nix

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brave
    spotify
  ];
  fonts.fontDir.enable = true; # DANGER
  fonts.fonts = [ (pkgs.nerdfonts.override { fonts = [ "Meslo" ]; }) ];
}

