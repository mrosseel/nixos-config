{ config, lib, pkgs, ... }:

let
  configSrc = ./homepage;
in
{
  # Sync version-controlled YAML to a writable runtime dir on each rebuild.
  # Homepage hot-reloads; the container also writes /app/config/logs/.
  # install -D creates parent dirs; activation may run before tmpfiles.
  systemd.tmpfiles.rules = [
    "d /var/lib/homepage      0755 root root -"
    "d /var/lib/homepage/logs 0755 root root -"
  ];

  system.activationScripts.homepageConfig = lib.stringAfter [ "var" ] ''
    install -D -m 0644 ${configSrc}/settings.yaml  /var/lib/homepage/settings.yaml
    install -D -m 0644 ${configSrc}/services.yaml  /var/lib/homepage/services.yaml
    install -D -m 0644 ${configSrc}/bookmarks.yaml /var/lib/homepage/bookmarks.yaml
    install -D -m 0644 ${configSrc}/widgets.yaml   /var/lib/homepage/widgets.yaml
    install -d -m 0755 /var/lib/homepage/logs
    : > /var/lib/homepage/docker.yaml
    : > /var/lib/homepage/kubernetes.yaml
    : > /var/lib/homepage/custom.css
    : > /var/lib/homepage/custom.js
  '';

  virtualisation.oci-containers.containers.homepage = {
    image = "ghcr.io/gethomepage/homepage:latest";
    autoStart = true;
    environment = {
      HOMEPAGE_ALLOWED_HOSTS = "192.168.5.12:3000,proxnix.local:3000,proxnix:3000";
    };
    volumes = [
      "/var/lib/homepage:/app/config"
    ];
    extraOptions = [ "--network=host" ];
  };

  networking.firewall.extraCommands = lib.mkAfter ''
    iptables -A nixos-fw -s 192.168.5.0/24 -p tcp --dport 3000 -j nixos-fw-accept
    iptables -A nixos-fw -i tailscale0   -p tcp --dport 3000 -j nixos-fw-accept
  '';
}
