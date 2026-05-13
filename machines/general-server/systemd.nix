{ pkgs, inputs, ... }:
let
  pifinder-python = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    httpx
    apscheduler
    skyfield
    pandas
    requests
  ]);
  messier-python = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    astropy
    numpy
    cachetools
  ]);
  astro-python = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    ps.ephem
    httpx
    ps.python-dotenv
  ]);
  sun-python = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pandas
    numpy
    scikit-learn
    pyarrow
    httpx
    ps.python-dotenv
  ]);
in
{
  systemd.tmpfiles.rules = [
    "d /var/www/pifinder-catalogs 0755 mike mike -"
    "d /var/www/messier 0755 mike mike -"
    "d /var/www/miker.be 0755 mike mike -"
    "d /var/www/astro.miker.be 0755 mike mike -"
    "d /var/www/asterisms.miker.be 0755 mike mike -"
    "d /var/www/sun.miker.be 0755 mike mike -"
    "d /home/mike/sun.miker.be/backend/data/input 0755 mike mike -"
    "d /home/mike/sun.miker.be/backend/data/store 0755 mike mike -"
  ];

  systemd.services.pifinder-web-catalogs = {
    description = "PiFinder Web Catalogs API";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/pifinder_web_catalogs";
      ExecStart = "${pifinder-python}/bin/uvicorn backend.main:app --host 127.0.0.1 --port 8100";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = {
      PYTHONUNBUFFERED = "1";
    };
  };
  systemd.services.pifinderhtml = {
    description = "PiFinder FastHTML website";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/pifinder_shopping/";
      ExecStart = "${pkgs.nix}/bin/nix develop --command uv run shop_page.py --prod";
      Restart = "on-failure";
    };
  };

  systemd.services.messier-marathon = {
    description = "Messier Marathon Planner API";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/messier-marathon/backend";
      ExecStart = "${messier-python}/bin/uvicorn main:app --host 127.0.0.1 --port 8001";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = {
      PYTHONUNBUFFERED = "1";
    };
  };

  systemd.services.astro-miker = {
    description = "Astro Miker Backend API";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/astro.miker.be/backend";
      ExecStart = "${astro-python}/bin/uvicorn main:app --host 127.0.0.1 --port 8003";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = {
      PYTHONUNBUFFERED = "1";
    };
  };

  systemd.services.sun-backend = {
    description = "sun.miker.be — sunspot forecast FastAPI backend";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/sun.miker.be/backend";
      ExecStart = "${sun-python}/bin/uvicorn main:app --host 127.0.0.1 --port 8004";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = {
      PYTHONUNBUFFERED = "1";
    };
  };

  # Nightly: refresh SILSO daily SSN + derived smoothed series.
  # Niced so it doesn't compete with sun-backend or other sites for CPU/IO.
  systemd.services.sun-refresh-daily = {
    description = "sun.miker.be — refresh daily SILSO SSN";
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/sun.miker.be/backend";
      ExecStart = "${sun-python}/bin/python refresh_daily.py";
      Nice = 10;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "batch";
    };
    environment = {
      PYTHONUNBUFFERED = "1";
    };
  };
  systemd.timers.sun-refresh-daily = {
    description = "sun.miker.be — nightly SILSO refresh timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00 UTC";
      Persistent = true;
    };
  };

  # Monthly: fetch SIDC bulletin + run CORE4 + KF-CM, persist.
  # Bulletins drop early on the 1st; we try at 12:00 UTC then retry hourly
  # through 18:00 UTC. Persistent=true gives catch-up if the host was down.
  # Niced so the GBM retrain (~3-5s of CPU) yields to website traffic.
  systemd.services.sun-make-issue = {
    description = "sun.miker.be — monthly forecast issue";
    after = [ "network.target" "sun-refresh-daily.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/sun.miker.be/backend";
      ExecStart = "${sun-python}/bin/python make_issue.py";
      Nice = 10;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "batch";
    };
    environment = {
      PYTHONUNBUFFERED = "1";
    };
  };
  systemd.timers.sun-make-issue = {
    description = "sun.miker.be — monthly forecast issue timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = [
        "*-*-01 12:00:00 UTC"
        "*-*-01 13:00:00 UTC"
        "*-*-01 14:00:00 UTC"
        "*-*-01 15:00:00 UTC"
        "*-*-01 16:00:00 UTC"
        "*-*-01 17:00:00 UTC"
        "*-*-01 18:00:00 UTC"
      ];
      Persistent = true;
    };
  };

  systemd.services.starnightsshop = {
    description = "StarNights Shop";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      NODE_ENV = "production";
    };
    path = [ pkgs.bash pkgs.nodejs ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/starnights_shop/";
      ExecStart = "${pkgs.nodejs}/bin/node node_modules/.bin/tsx src/server/index.ts";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
