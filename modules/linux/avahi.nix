{ config, pkgs, ... }:

{
  # Enable mDNS resolution
  services.avahi = {
    enable = true;
    nssmdns4 = true;  # Enable .local domain resolution for IPv4
    nssmdns6 = true;  # Enable .local domain resolution for IPv6
    
    # Publishing settings (optional - allows other devices to discover this machine)
    publish = {
      enable = true;
      addresses = true;        # Publish IP addresses
      workstation = true;      # Publish workstation service
      userServices = true;     # Allow users to publish services
      domain = true;           # Publish domain
      hinfo = true;            # Publish hardware info
    };
    
    # Additional options
    openFirewall = true;       # Open firewall for mDNS traffic
    ipv4 = true;              # Enable IPv4 support
    ipv6 = true;              # Enable IPv6 support
  };

  # Ensure NetworkManager is enabled if you're using it
  networking.networkmanager.enable = true;
}
