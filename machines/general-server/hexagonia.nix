{ config, pkgs, inputs, ... }:

# Hexagonia — a settlement game for three or four people. Served at
# https://hextopia.miker.be; Caddy hands the API paths to this process and
# every other path to the built frontend in /var/www (see caddy-service.nix).
#
# Source: github:mrosseel/hexagonia, private, consumed as a flake package.
# The package is the Rust server only. The frontend is static files, shipped
# by ./deploy-hexagonia.sh in the game's own repository, because it is built
# with npm and wasm-pack rather than by this flake.
#
# The server holds every running game in memory. A restart therefore ends
# every game in progress, which is what the game already survives: a room
# that no longer answers tells its clients so, and nobody loses an account,
# because there are no accounts yet.

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
    "d /var/www/hextopia.miker.be 0755 mike users - -"
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
          --cors-origin https://hextopia.miker.be
      '';
      # The secret is read from a file the deploy writes once. A missing file
      # is not fatal: the server says so and signs with a key of its own.
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
