{ config, pkgs, inputs, ... }:

# Hexagonia — a settlement game for three or four people. Served at
# https://hextopia.miker.be; Caddy hands the API paths to this process and
# every other path to the frontend bundle (see caddy-service.nix).
#
# Source: github:mrosseel/hexagonia, private, consumed as flake packages. The
# input gives two: the Rust server here, and hexagonia-web, the built bundle
# Caddy serves from the store. Both come from one revision, so the page and
# the server cannot drift apart.
#
# Deploy with /home/mike/nixos-config/deploy-hexagonia.sh.
#
# The server holds every running game in memory, so a restart still ends
# every game in progress. Finished games outlive it: they are written to
# /var/lib/hexagonia/hexagonia.db, which is the one thing here that cannot
# be rebuilt and the one thing worth backing up.

let
  package = inputs.hexagonia.packages.${pkgs.system}.default;
  port = 8191;
in
{
  users.users."hexagonia" = {
    isSystemUser = true;
    group = "hexagonia";
    home = "/var/lib/hexagonia";
  };
  users.groups."hexagonia" = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/hexagonia 0750 hexagonia hexagonia - -"
  ];

  # The key that signs a guest token. Without it the server makes one at
  # start, and every seat is forgotten on a restart, so a reload during a
  # game would lose the chair. LoadCredential keeps it out of the unit file
  # and out of the process table.
  systemd.services.hexagonia = {
    description = "Hexagonia (settlement game server)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "hexagonia";
      Group = "hexagonia";
      WorkingDirectory = "/var/lib/hexagonia";
      ExecStart = ''
        ${package}/bin/hexagonia-server \
          --bind 127.0.0.1:${toString port} \
          --cors-origin https://hextopia.miker.be \
          --db /var/lib/hexagonia/hexagonia.db
      '';
      # Two secrets are read from a file the deploy writes once.
      #
      # HEXAGONIA_SECRET signs guest tokens. Without it the server says so and
      # signs with a key of its own, so every seat is lost on a restart.
      #
      # HEXAGONIA_ADMIN_TOKEN is the admin key. A request sends it as the
      # header X-Admin-Token to delete a game, export the history or import a
      # file, and to see private games in every listing. Without it those
      # three calls answer 403 and no header opens them; the rest of the
      # server runs as before.
      #
      # A missing file is not fatal. The server starts and prints what it
      # lacks.
      EnvironmentFile = "-/var/lib/hexagonia/secret.env";
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/hexagonia" ];
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
