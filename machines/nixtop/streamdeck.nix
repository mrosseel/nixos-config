# StreamDeck configuration for nixtop
{ config, pkgs, ... }:

{
  programs.streamdeck-ui = {
    enable = true;
    autoStart = true;
  };
}
