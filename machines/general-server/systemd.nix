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
in
{
  systemd.tmpfiles.rules = [
    "d /var/www/pifinder-catalogs 0755 mike mike -"
    "d /var/www/messier 0755 mike mike -"
    "d /var/www/miker.be 0755 mike mike -"
    "d /var/www/astro.miker.be 0755 mike mike -"
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
      ExecStart = "${astro-python}/bin/uvicorn main:app --host 127.0.0.1 --port 8002";
      Restart = "on-failure";
      RestartSec = 5;
    };
    environment = {
      PYTHONUNBUFFERED = "1";
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
