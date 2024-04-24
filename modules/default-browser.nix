# modules/default-browser.nix

{ config, pkgs, ... }:

{
  programs.chromium = {
    enable = true;  # Enable Chromium
  };
}

