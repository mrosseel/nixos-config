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

      # TLS terminates at the reverse proxy, so trust its forwarded headers.
      # Without this, copyparty assumes http:// and cors-rejects the login POST
      # from https://files.miker.be.
      xff-src = "lan";
      rproxy = -1;
    };

    accounts = {
      mike.passwordFile = "/etc/copyparty/mike.passwd";
      # Shared login for people who need to drop a file off.
      guest.passwordFile = "/etc/copyparty/guest.passwd";
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
          # Write-only for the guest login: uploads work, listing and
          # downloading do not. Anonymous access is off.
          w = "guest";
          rwmda = "mike";
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
      "/music" = {
        path = "/srv/music";
        access = {
          rwmda = "mike";
        };
      };
    };
  };

  systemd.services.copyparty.serviceConfig.AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];

  systemd.tmpfiles.rules = [
    "d /srv/copyparty 0755 copyparty copyparty -"
    "d /srv/copyparty/public 0755 copyparty copyparty -"
    "d /srv/copyparty/dump 0755 copyparty copyparty -"
    "d /srv/copyparty/private 0700 copyparty copyparty -"
    "d /srv/music 0755 copyparty copyparty -"
  ];
}
