{ config, pkgs, ... }:
{
  # StreamDeck configuration - symlink to repo config
  home.file.".streamdeck_ui.json" = {
    source = ../../config/streamdeck/streamdeck_ui.json;
  };
}
