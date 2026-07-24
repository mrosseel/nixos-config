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
  dataDir = "/var/www/asterisms.miker.be/data";
  pyEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
    slowapi
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

  # Salt for the per-vote IP hash behind the anti-graffiti distinct-IP
  # aggregation. Only meaningful joined with an IP, so not a login secret — but
  # this repo is public, so it is generated on the host instead of committed.
  # Idempotent (ConditionPathExists), so the salt is stable across rebuilds;
  # deleting the file regenerates it and resets the distinct-IP buckets.
  systemd.services.asterisms-votes-secret = {
    description = "Generate asterisms-votes IP hash salt on first start";
    before = [ "asterisms-votes.service" ];
    wantedBy = [ "asterisms-votes.service" ];
    unitConfig.ConditionPathExists = "!/var/lib/asterisms-votes/env";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ openssl coreutils ];
    script = ''
      umask 077
      printf 'VOTES_IP_SALT="%s"\n' "$(openssl rand -hex 32)" \
        > /var/lib/asterisms-votes/env
      chown asterisms-votes:asterisms-votes /var/lib/asterisms-votes/env
      chmod 0400 /var/lib/asterisms-votes/env
    '';
  };

  systemd.services.asterisms-votes = {
    description = "asterisms-votes (FastAPI favorites + comments backend)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      VOTES_DB = "/var/lib/asterisms-votes/votes.db";
      PYTHONUNBUFFERED = "1";
      # VOTES_IP_SALT is NOT here — this repo is public. It comes from the
      # environmentFile below, generated once and kept out of the Nix store,
      # like the attic RS256 secret.
    };

    serviceConfig = {
      User = "asterisms-votes";
      Group = "asterisms-votes";
      WorkingDirectory = appDir;
      EnvironmentFile = "/var/lib/asterisms-votes/env";
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

  # Static totals snapshot: the frontend reads /data/totals.json (a cached static
  # file) instead of hitting /api/totals on every page load, so the read path
  # survives a flood without touching SQLite. Published every ~2 min from a
  # read-only DB connection; writes atomically (temp + rename).
  #
  # Runs as mike: owner of the web root (can write dataDir) and can read the
  # world-readable votes.db under the 0755 /var/lib/asterisms-votes dir.
  systemd.services.asterisms-totals-publish = {
    description = "Publish asterisms favourite-count snapshot to totals.json";
    after = [ "asterisms-votes.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "mike";
      ExecStart = "${pkgs.python3}/bin/python ${appDir}/publish_totals.py "
        + "--db /var/lib/asterisms-votes/votes.db --out ${dataDir}/totals.json";
    };
  };
  systemd.timers.asterisms-totals-publish = {
    description = "Refresh asterisms totals.json every 2 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
      Persistent = true;
    };
  };
}
