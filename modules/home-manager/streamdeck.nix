{ config, pkgs, ... }:
{
  # StreamDeck scripts
  home.file.".local/bin/toggle-office-trv.sh" = {
    source = ../../config/scripts/toggle-office-trv.sh;
    executable = true;
  };

  home.file.".local/bin/ha-call.sh" = {
    source = ../../config/scripts/ha-call.sh;
    executable = true;
  };

  home.file.".local/bin/streamdeck-daemon.py" = {
    source = ../../config/scripts/streamdeck-daemon.py;
    executable = true;
  };
}
