{ config, pkgs, lib, ... }:

{
  # Dropbox package is already in desktop.nix, but we add the service here

  # Systemd service to auto-start Dropbox
  systemd.user.services.dropbox = {
    description = "Dropbox daemon";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.dropbox}/bin/dropbox";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      KillMode = "control-group";
      Restart = "on-failure";
      RestartSec = "10s";
      PrivateTmp = true;
      ProtectSystem = "full";
      Nice = 10;
    };

    # Only start if Dropbox directory exists (user has logged in at least once)
    unitConfig = {
      ConditionPathExists = "/home/mike/.dropbox";
    };
  };
}
