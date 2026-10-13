{ lib, options, ... }:
let
  # The omarchy home-manager module defines config.omarchy.*; nixair and the
  # servers pull modules/home-manager without it.
  hasOmarchy = options ? omarchy;
in
{
  # omarchy-nix links ~/.config/chromium/Default/Preferences to a read-only
  # file in /nix/store to set dark mode. Chromium writes its own settings into
  # this file, so it replaces the link with a real file. Each switch then backs
  # up the real file as Preferences.backup. When that backup already exists,
  # Home Manager stops and the activation fails.
  #
  # Chromium keeps the dark mode setting in its own file, so Home Manager does
  # not need to manage the file.
  xdg.configFile = lib.mkIf hasOmarchy {
    "chromium/Default/Preferences".enable = lib.mkForce false;
  };
}
