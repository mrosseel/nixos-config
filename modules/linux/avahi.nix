{ config, pkgs, ... }:

{
  services.avahi = {
    enable = true;
    # nss-mdns does its OWN per-lookup mDNS multicast on UDP 5353, which loses
    # the port to apps that grab it (Brave/Spotify for casting) → glibc `.local`
    # lookups fail with EBUSY ("Device or resource busy"). Hand `.local`
    # *resolution* to systemd-resolved (one persistent 5353 listener, see
    # MulticastDNS=resolve below); avahi stays on only to *publish* this host.
    nssmdns4 = false;
    nssmdns6 = false;

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
