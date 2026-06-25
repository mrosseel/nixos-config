{ config, pkgs, ... }:

{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;

    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
      domain = true;
      hinfo = true;
    };

    openFirewall = true;
    ipv4 = true;
    ipv6 = true;
  };
}
