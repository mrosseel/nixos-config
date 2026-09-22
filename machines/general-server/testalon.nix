{ config, lib, pkgs, ... }:

# Testalon — the test deployment of Hexalon, served at
# https://testalon.miker.be. It replaces hextopia.miker.be, which was the
# same thing under an older name and an older deploy.
#
# What makes this host different from production: **GitHub deploys it.** A
# push to hexagonia's master builds the server and the page on a GitHub
# runner, copies both closures here, and restarts the unit below. Production
# (hexalon.io, its own machine) is still shipped by hand and is not reachable
# from here.
#
# The package therefore does NOT come from a flake input. It is whatever
# store path the last deploy pointed `/var/lib/testalon/current` at, and a
# rebuild of this machine leaves that pointer alone. That is deliberate: it
# is what keeps the GitHub key from being able to change anything else here.
# `nixos-rebuild` owns the machine, GitHub owns one symlink and one unit.
#
# The whole of what the GitHub key may do is in `deployScript` below. Read it
# before you widen the sudo rule or the authorized_keys line.

let
  port = 8192;
  # The name people are given, and the name the machine has answered to
  # since before that. The server refuses an origin it does not know, so
  # both are listed here and both are on the Caddy host.
  domains = [ "beta.hexalon.io" "testalon.miker.be" ];
  dataDir = "/var/lib/testalon";

  # The public half of the key GitHub holds. Its private half is a repository
  # secret of mrosseel/hexagonia, used by .github/workflows/testalon.yml.
  # Replace this line to rotate the key; nothing else here changes.
  deployKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGajKYdFxG8VkfIagza26cikTuQWG4LXhejEhU2I58nG testalon-deploy@github";

  # The one command that key may run.
  #
  # SSH runs this instead of whatever the client asked for, and the client's
  # own words are only readable in SSH_ORIGINAL_COMMAND. Two shapes are
  # allowed and nothing else:
  #
  #   nix-store --serve --write     `nix copy --to ssh://...` speaks this to
  #                                 hand over the closures. It can write to
  #                                 the store and do nothing else.
  #   testalon <server> <web>       the deploy itself: two store paths, the
  #                                 pointers moved, the unit restarted.
  #
  # A store path is checked for shape and for existence before it is used, so
  # the argument cannot become a path outside the store or a shell word.
  deployScript = pkgs.writeShellApplication {
    name = "testalon-deploy";
    runtimeInputs = [ pkgs.nix pkgs.coreutils ];
    text = ''
      set -euo pipefail

      case "''${SSH_ORIGINAL_COMMAND:-}" in
        "nix-store --serve --write")
          exec nix-store --serve --write
          ;;
      esac

      read -r -a words <<< "''${SSH_ORIGINAL_COMMAND:-}"
      if [[ ''${#words[@]} -ne 3 || ''${words[0]} != testalon ]]; then
        echo "testalon: this key deploys testalon and does nothing else" >&2
        exit 1
      fi

      server=''${words[1]}
      web=''${words[2]}

      for path in "$server" "$web"; do
        if [[ $path != /nix/store/* || $path == *..* ]]; then
          echo "testalon: $path is not a store path" >&2
          exit 1
        fi
        if [[ ! -e $path ]]; then
          echo "testalon: $path is not here; copy it first" >&2
          exit 1
        fi
      done

      # A garbage collection would otherwise take these away: nothing in the
      # system closure refers to them. The roots live in a directory this
      # user owns, so no privilege is needed to keep them.
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
  # The account the key logs in as. It owns its own state directory and its
  # own garbage collection roots, and it holds no other rights on this
  # machine. A login shell is pointless under a forced command, so it has
  # none.
  users.users.testalon-deploy = {
    isSystemUser = true;
    group = "testalon-deploy";
    home = dataDir;
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [
      ("command=\"${lib.getExe deployScript}\""
        + ",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty "
        + deployKey)
    ];
  };
  users.groups.testalon-deploy = { };

  # An unsigned store path is refused unless the user handing it over is
  # trusted. GitHub builds the closures, so nothing it sends carries this
  # machine's signature.
  #
  # This is the one real privilege the key holds: it may put any store path
  # here. It cannot run one. Only the unit below runs, as the testalon user,
  # and only from the pointer the script moves.
  nix.settings.trusted-users = [ "testalon-deploy" ];

  security.sudo.extraRules = [{
    users = [ "testalon-deploy" ];
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
    "d ${dataDir} 0755 testalon-deploy testalon-deploy - -"
    "d ${dataDir}/state 0750 testalon testalon - -"
    "d /nix/var/nix/gcroots/testalon 0755 testalon-deploy testalon-deploy - -"
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
