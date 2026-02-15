{ config, lib, pkgs, copyparty, ... }:

{
  imports = [
    copyparty.nixosModules.default
  ];

  nixpkgs.overlays = [
    copyparty.overlays.default
  ];

  services.copyparty = {
    enable = true;
    package = pkgs.copyparty-full;

    settings = {
      i = "0.0.0.0";
      p = 80;
      http-only = true;
      no-robots = true;
      name = "Miker's Files";
      no-reload = true;
    };

    accounts = {
      mike.passwordFile = "/etc/copyparty/mike.passwd";
    };

    volumes = {
      "/public" = {
        path = "/srv/copyparty/public";
        access = {
          r = "*";
          rwmda = "mike";
        };
      };
      "/dump" = {
        path = "/srv/copyparty/dump";
        access = {
          rw = "*";
          mda = "mike";
        };
        flags = {
          maxb = "500m,300";
          rotn = "500,2";
        };
      };
      "/private" = {
        path = "/srv/copyparty/private";
        access = {
          rwmda = "mike";
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/copyparty 0755 copyparty copyparty -"
    "d /srv/copyparty/public 0755 copyparty copyparty -"
    "d /srv/copyparty/dump 0755 copyparty copyparty -"
    "d /srv/copyparty/private 0700 copyparty copyparty -"
  ];
}
