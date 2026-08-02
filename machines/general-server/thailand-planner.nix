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

{
  systemd.services.thailand-planner = {
    description = "Thailand trip planner JSON store";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.git pkgs.openssh ];
    # The attrset form, not serviceConfig.Environment: systemd splits an
    # unquoted Environment= value on spaces, which silently mangles the ssh
    # command into a series of invalid assignments.
    environment = {
      PLAN_FILE = "/var/lib/thailand-planner/plan.json";
      PORT = "8010";
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
      ExecStart = "${pkgs.python3}/bin/python3 ${./plan-server.py}";
      LoadCredential = "deploy_key:/var/lib/thailand-planner-secrets/deploy_key";
      DynamicUser = true;
      StateDirectory = "thailand-planner";
      Restart = "on-failure";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };
}
