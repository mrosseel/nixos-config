{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "anki-wrapped" ''
      export XDG_DATA_DIRS="${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:$XDG_DATA_DIRS"
      exec ${pkgs.anki}/bin/anki "$@"
    '')
    (pkgs.makeDesktopItem {
      name = "anki";
      desktopName = "Anki";
      comment = "An intelligent spaced-repetition memory training program";
      genericName = "Flashcards";
      exec = "anki-wrapped %f";
      tryExec = "anki-wrapped";
      icon = "anki";
      categories = [ "Education" "Languages" "KDE" "Qt" ];
      terminal = false;
      type = "Application";
      mimeTypes = [ "application/x-apkg" "application/x-anki" "application/x-ankiaddon" ];
      extraConfig = {
        "X-GNOME-SingleWindow" = "true";
        "SingleMainWindow" = "true";
        "StartupWMClass" = "anki";
      };
    })
    anki
  ];

  # Ensure xdg portals are available for file chooser
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ 
      xdg-desktop-portal-gtk 
      xdg-desktop-portal-gnome
    ];
    config.common.default = "*";
  };
}
