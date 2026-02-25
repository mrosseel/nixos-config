# modules/desktop.nix

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ferdium
    # webcord # discord alternative - temporarily disabled due to build failure
    (let
      epipeFixScript = pkgs.writeText "obsidian-epipe-fix.js" ''
        process.on('uncaughtException', (err) => {
          if (err.code === 'EPIPE') return;
          throw err;
        });
      '';
    in pkgs.symlinkJoin {
      name = "obsidian-wrapped";
      paths = [ obsidian ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/obsidian \
          --set NODE_OPTIONS "--require ${epipeFixScript}"
      '';
    })
    # google-drive-ocamlfuse
    vlc
    spotify
    # veracrypt
    orca-slicer
    bambu-studio
    bitwarden-desktop
    #libreoffice-qt
    dropbox
    keepassxc
  ];
  fonts.packages = [ pkgs.nerd-fonts.meslo-lg ];

  # Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
}
