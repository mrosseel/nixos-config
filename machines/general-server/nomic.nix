{ pkgs, ... }:

# Game store for nomic.miker.be. The service is nomic-server.py next to this
# file. See its docstring for the endpoints. Caddy sends /api/* to it.
#
# Each game is one JSON file in /var/lib/nomic/games. No backup copies this
# directory. Each device that opens a game also keeps a copy, and Export in
# the game saves a file.

{
  systemd.services.nomic = {
    description = "Nomic game store";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      GAME_DIR = "/var/lib/nomic/games";
      PORT = "8020";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./nomic-server.py}";
      User = "nomic";
      Group = "nomic";
      StateDirectory = "nomic";
      StateDirectoryMode = "0750";
      Restart = "always";
      RestartSec = 5;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      MemoryMax = "256M";
    };
  };

  users.users.nomic = {
    isSystemUser = true;
    group = "nomic";
    description = "Nomic game store";
  };
  users.groups.nomic = { };
}
