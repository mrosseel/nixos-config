# modules/desktop.nix

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ferdium
    # webcord # discord alternative - temporarily disabled due to build failure
    obsidian
    # google-drive-ocamlfuse
    vlc
    spotify
    # veracrypt
    orca-slicer
    bambu-studio
    #libreoffice-qt
    dropbox
  ];
  fonts.packages = [ pkgs.nerd-fonts.meslo-lg ];
}
