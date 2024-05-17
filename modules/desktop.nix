# modules/desktop.nix

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ferdium
    discord
    obsidian
    google-drive-ocamlfuse
    vlc
    spotify
    veracrypt
    orca-slicer
    libreoffice-qt
  ];
  fonts.fontDir.enable = true; # DANGER
  fonts.fonts = [ (pkgs.nerdfonts.override { fonts = [ "Meslo" ]; }) ];
}
