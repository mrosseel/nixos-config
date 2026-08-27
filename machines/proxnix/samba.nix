{ config, lib, pkgs, ... }:

{
  # SMB export of the music library, for Music Assistant and other LAN clients.
  # Read-only: the library is written by rsync and copyparty, not by clients.
  users.groups.musicro = { };
  users.users.musicro = {
    isSystemUser = true;
    group = "musicro";
    description = "Read-only SMB account for the music share";
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "proxnix";
        "security" = "user";
        "map to guest" = "never";
        "hosts allow" = "192.168.5.0/24 127.0.0.1";
        "hosts deny" = "0.0.0.0/0";
        "server min protocol" = "SMB3";
        "load printers" = "no";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";
      };
      music = {
        path = "/srv/music";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "no";
        "valid users" = "musicro";
      };
    };
  };

  # Advertise the share so it appears in network browsers.
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
