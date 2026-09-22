{ config, lib, pkgs, ... }:

# Testalon, the test deployment of Hexalon, served at https://beta.hexalon.io
# and https://testalon.miker.be. It replaces hextopia.miker.be, which was the
# same thing under an older name and an older deploy.
#
# What makes this host different from production: **a push deploys it.** A
# push to hexagonia's master wakes the runner in runner.nix, on this machine.
# It builds the server and the page and runs `testalon-deploy` below, which
# moves two pointers and restarts the unit. No key reaches this machine from
# outside.
#
# The package therefore does NOT come from a flake input. It is whatever
# store path the last deploy pointed `/var/lib/testalon/current` at, and a
# rebuild of this machine leaves that pointer alone. `nixos-rebuild` owns the
# machine, the runner owns two symlinks and one restart.

let
  port = 8192;
  # The name people are given, and the name the machine has answered to
  # since before that. The server refuses an origin it does not know, so
  # both are listed here and both are on the Caddy host.
  domains = [ "beta.hexalon.io" "testalon.miker.be" ];
  dataDir = "/var/lib/testalon";

  # The deploy: two store paths in, the pointers moved, the unit restarted.
  #
  # It runs as the runner. The one privileged act is the restart, and the
  # sudo rule below allows that and nothing else. A store path is checked
  # for shape and for existence before it is used, so an argument cannot
  # become a path outside the store or a shell word.
  deployScript = pkgs.writeShellApplication {
    name = "testalon-deploy";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      if [[ $# -ne 2 ]]; then
        echo "usage: testalon-deploy <server> <web>" >&2
        exit 1
      fi
      server=$1
      web=$2

      for path in "$server" "$web"; do
        if [[ $path != /nix/store/* || $path == *..* ]]; then
          echo "testalon: $path is not a store path" >&2
          exit 1
        fi
        if [[ ! -e $path ]]; then
          echo "testalon: $path is not here" >&2
          exit 1
        fi
      done

      # A garbage collection would otherwise take these away: nothing in the
      # system closure refers to them.
      ln -sfn "$server" /nix/var/nix/gcroots/testalon/server
      ln -sfn "$web" /nix/var/nix/gcroots/testalon/web

      ln -sfn "$server" ${dataDir}/current.tmp
      mv -T ${dataDir}/current.tmp ${dataDir}/current
      ln -sfn "$web" ${dataDir}/web.tmp
      mv -T ${dataDir}/web.tmp ${dataDir}/web

      /run/wrappers/bin/sudo \
        /run/current-system/sw/bin/systemctl restart testalon.service
      echo "testalon: $server"
    '';
  };
in
{
  # The group that may move the pointers. The runner is its one member.
  users.groups.testalon-deploy = { };

  # The runner calls it by name, and a person can too.
  environment.systemPackages = [ deployScript ];

  security.sudo.extraRules = [{
    users = [ "github-runner" ];
    commands = [{
      command = "/run/current-system/sw/bin/systemctl restart testalon.service";
      options = [ "NOPASSWD" ];
    }];
  }];

  users.users.testalon = {
    isSystemUser = true;
    group = "testalon";
    home = dataDir;
  };
  users.groups.testalon = { };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 2775 root testalon-deploy - -"
    "d ${dataDir}/state 0750 testalon testalon - -"
    "d /nix/var/nix/gcroots/testalon 2775 root testalon-deploy - -"
  ];

  # The unit starts from the pointer, not from a package in this closure. It
  # therefore fails to start until the first deploy has run, which is the
  # honest state of a machine nobody has deployed to yet.
  systemd.services.testalon = {
    description = "Testalon (the Hexalon test deployment)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "testalon";
      Group = "testalon";
      WorkingDirectory = "${dataDir}/state";
      ExecStart = ''
        ${dataDir}/current/bin/hexagonia-server \
          --bind 127.0.0.1:${toString port} \
          --cors-origin ${lib.concatMapStringsSep "," (d: "https://${d}") domains} \
          --db ${dataDir}/state/testalon.db
      '';
      # The same two files production reads: HEXAGONIA_SECRET signs guest
      # tokens, HEXAGONIA_ADMIN_EMAILS promotes an account to admin at its
      # first sign-in. Both are optional; the server says what it lacks.
      EnvironmentFile = [
        "-${dataDir}/state/secret.env"
        "-${dataDir}/state/deploy.env"
      ];
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "${dataDir}/state" ];
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
