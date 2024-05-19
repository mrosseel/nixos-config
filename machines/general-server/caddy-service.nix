{ pkgs, ... }:

{
  # environment.etc."caddy/pifinder-eu" = {
  #   source = /home/mike/pifinder-eu;
  #   mode = "0777";  # Adjust the mode according to your security requirements
  # };
 services.caddy = {
    enable = true;
    virtualHosts."pifinder.eu".extraConfig = ''
      email = mike.rosseel@gmail.com;
      encode gzip
      file_server
      root * /var/www
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443];
}

