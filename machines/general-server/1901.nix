{ config, pkgs, inputs, ... }:

# 1901 — a face-to-face Diplomacy adjudicator. Players give orders from their
# phones, the server resolves the turn. Served at https://1901.miker.be;
# Caddy proxies the vhost to 127.0.0.1:8190 (see caddy-service.nix).
#
# Source: github:mrosseel/1901, consumed as a flake package. The package
# wrapper already points SPADIR at the built frontend and PLACEMENTS at the
# map data, so only the state and the origin need setting here.

let
  package = inputs.diplomacy1901.packages.${pkgs.system}.default;
  port = 8190;
in
{
  users.users."d1901" = {
    isSystemUser = true;
    group = "d1901";
    home = "/var/lib/1901";
  };
  users.groups."d1901" = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/1901 0750 d1901 d1901 - -"
  ];

  systemd.services."1901" = {
    description = "1901 (Diplomacy adjudicator)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      ADDR = "127.0.0.1:${toString port}";
      DB = "/var/lib/1901/1901.db";
      # Links handed to players are generated server-side. Without this they
      # would carry the host LAN address, which no phone can reach.
      BASE_URL = "https://1901.miker.be";
    };

    serviceConfig = {
      User = "d1901";
      Group = "d1901";
      WorkingDirectory = "/var/lib/1901";
      ExecStart = "${package}/bin/1901";
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/1901" ];
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
    };
  };
}
