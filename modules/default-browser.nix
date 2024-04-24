# modules/default-browser.nix

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brave
  ];
}

