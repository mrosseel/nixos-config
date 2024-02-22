{ pkgs, ... }:

{
  services.caddy = {
  enable = true;
  virtualHosts."pifinder.eu".extraConfig = ''
    encode gzip
    file_server
    root * ${
      pkgs.runCommand "testdir" {} ''
        mkdir "$out"
        echo hello world > "$out/index.html"
      ''
    }
  '';
  }; 
  networking.firewall.allowedTCPPorts = [ 80 443];
}

