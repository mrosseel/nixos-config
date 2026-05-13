{ config, pkgs, lib, ... }:

# asterisms-votes — small FastAPI service powering favorites + comments on
# https://asterisms.miker.be . SQLite at /var/lib/asterisms-votes/votes.db.
# Caddy patches /api/* through to localhost:8002 (see caddy-service.nix).
#
# Source lives in the asterisms repo at votes_backend/. Deploy by syncing
# /home/mike/dev/amateur_astro/py-asterisms/votes_backend/ → /var/lib/asterisms-votes/app/
# (handled by deploy_site.sh after this is in place).

let
  appDir = "/var/lib/asterisms-votes/app";
  pyEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
  ]);
in {
  systemd.tmpfiles.rules = [
    # Service-owned root: holds the SQLite db, restrictive perms.
    "d /var/lib/asterisms-votes 0755 asterisms-votes asterisms-votes - -"
    # App source dir owned by mike so deploy_site.sh can rsync straight in
    # without sudo. asterisms-votes (member of mike's group via supplementaryGroups)
    # only needs read access.
    "d ${appDir} 0755 mike users - -"
  ];

  users.users.asterisms-votes = {
    isSystemUser = true;
    group = "asterisms-votes";
    home = "/var/lib/asterisms-votes";
  };
  users.groups.asterisms-votes = { };

  systemd.services.asterisms-votes = {
    description = "asterisms-votes (FastAPI favorites + comments backend)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      VOTES_DB = "/var/lib/asterisms-votes/votes.db";
      PYTHONUNBUFFERED = "1";
    };

    serviceConfig = {
      User = "asterisms-votes";
      Group = "asterisms-votes";
      WorkingDirectory = appDir;
      ExecStart = "${pyEnv}/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8002";
      Restart = "on-failure";
      RestartSec = 5;

      # Sandboxing — gives container-grade isolation without a container.
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/asterisms-votes" ];
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
