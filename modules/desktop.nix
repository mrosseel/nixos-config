# modules/desktop.nix

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # ferdium
    discord
    obsidian
    # google-drive-ocamlfuse
    vlc-bin
    spotify
    # veracrypt
    orca-slicer
    libreoffice-qt
    dropbox
  ];
  fonts.packages = [ (pkgs.nerdfonts.override { fonts = [ "Meslo" ]; }) ];
}
