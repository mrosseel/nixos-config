{ pkgs, ... }:

# Persistence backend for the family trip planner (thailand.miker.be).
# The service itself is plan-server.py next to this file; see its docstring for
# the endpoints. Access is gated by Caddy basic_auth on the vhost.
#
# The state directory is a git repository and every burst of editing is pushed
# to a private remote. That remote is the version history the UI browses AND the
# only off-site copy of the trip, so it is worth checking it still receives
# pushes:
#
#   sudo journalctl -u thailand-planner | grep -i 'push failed'
#
# The deploy key is deliberately not in the nix store. Create it once, on the
# server, and give the public half write access on the history repo:
#
#   sudo install -d -m 0700 /var/lib/thailand-planner-secrets
#   sudo ssh-keygen -t ed25519 -N '' -C thailand-planner \
#        -f /var/lib/thailand-planner-secrets/deploy_key
#   sudo cat /var/lib/thailand-planner-secrets/deploy_key.pub
#
# systemd reads it as root and hands the unit a private 0400 copy, so the key
# itself stays root-only on disk.
#
# The notifications to the phones of the family at home need a VAPID key
# pair. The unit thailand-planner-vapid makes it once, in the same secrets
# directory, before the service starts. A new key means every phone must
# subscribe again.

let
  # pywebpush sends the notifications. Everything else is the stdlib.
  python = pkgs.python3.withPackages (ps: [ ps.pywebpush ]);
in
{
  systemd.services.thailand-planner-vapid = {
    description = "VAPID key for the trip planner notifications";
    before = [ "thailand-planner.service" ];
    requiredBy = [ "thailand-planner.service" ];
    path = [ pkgs.openssl ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 0700 /var/lib/thailand-planner-secrets
      if [ ! -f /var/lib/thailand-planner-secrets/vapid.pem ]; then
        umask 077
        openssl ecparam -name prime256v1 -genkey -noout \
          -out /var/lib/thailand-planner-secrets/vapid.pem
      fi
    '';
  };

  systemd.services.thailand-planner = {
    description = "Thailand trip planner JSON store";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # Nobody is at home to start it by hand while the family travels. Keep
    # trying for ever, not five times and then give up.
    startLimitIntervalSec = 0;
    path = [ pkgs.git pkgs.openssh ];
    # The attrset form, not serviceConfig.Environment: systemd splits an
    # unquoted Environment= value on spaces, which silently mangles the ssh
    # command into a series of invalid assignments.
    environment = {
      PLAN_FILE = "/var/lib/thailand-planner/plan.json";
      PORT = "8010";
      # The view link sees where the family is only on these days, in UTC+7.
      # The planner sees it always.
      PEOPLE_FROM = "2026-10-22";
      PEOPLE_UNTIL = "2026-12-30";
      # The credential below, as the unit sees it.
      VAPID_PRIVATE_KEY = "%d/vapid.pem";
      PLAN_GIT_REMOTE = "git@github.com:mrosseel/thailand-plan-history.git";
      # git needs a HOME for its config lookups; StateDirectory is the only
      # writable path this unit has.
      HOME = "/var/lib/thailand-planner";
      # $CREDENTIALS_DIRECTORY is expanded by the shell git runs this through,
      # not by systemd.
      GIT_SSH_COMMAND = "ssh -i $CREDENTIALS_DIRECTORY/deploy_key"
        + " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        + " -o UserKnownHostsFile=/var/lib/thailand-planner/known_hosts";
    };
    serviceConfig = {
      ExecStart = "${python}/bin/python3 ${./plan-server.py}";
      LoadCredential = [
        "deploy_key:/var/lib/thailand-planner-secrets/deploy_key"
        "vapid.pem:/var/lib/thailand-planner-secrets/vapid.pem"
      ];
      # A fixed user rather than DynamicUser: the state directory is a git repo
      # you sometimes want to inspect, and the Drive exporter has to read it.
      # DynamicUser hid it behind /var/lib/private under an unpredictable uid.
      User = "thailand-planner";
      Group = "thailand-planner";
      StateDirectory = "thailand-planner";
      StateDirectoryMode = "0750";
      Restart = "always";
      RestartSec = 5;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };

  users.users.thailand-planner = {
    isSystemUser = true;
    group = "thailand-planner";
    description = "Thailand trip planner store";
  };
  users.groups.thailand-planner = { };
}
