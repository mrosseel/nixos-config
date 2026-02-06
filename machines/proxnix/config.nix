{ config, lib, pkgs, ... }:

{
  time.timeZone = "Europe/Brussels";

  programs.zsh.enable = true;
  environment.shells = with pkgs; [ bash zsh ];

  users.groups.mike = {};
  users.users.mike = {
    home = "/home/mike";
    isNormalUser = true;
    group = "mike";
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    ignoreShellProgramCheck = true;
  };

  security.sudo.wheelNeedsPassword = false;

  # Docker
  virtualisation.docker.enable = true;

  # TFTP server
  services.atftpd = {
    enable = true;
    root = "/srv/tftp";
  };

  # NFS server
  services.nfs.server = {
    enable = true;
    lockdPort = 4001;
    statdPort = 4000;
    mountdPort = 20048;
    exports = ''
      /srv/nfs/pifinder 192.168.5.0/24(rw,no_root_squash,no_subtree_check,sync)
    '';
  };

  # iSCSI target — phase 2, configure manually with tgt/targetcli after NFS works

  # Firewall — only allow LAN access to services
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ]; # SSH from anywhere
    extraCommands = ''
      iptables -A nixos-fw -s 192.168.5.0/24 -p tcp -m multiport --dports 111,2049,3260,4000,4001,20048 -j nixos-fw-accept
      iptables -A nixos-fw -s 192.168.5.0/24 -p udp -m multiport --dports 69,111,4000,4001,20048 -j nixos-fw-accept
    '';
  };

  # Create service directories
  systemd.tmpfiles.rules = [
    "d /srv/tftp 0755 root root -"
    "d /srv/nfs/pifinder 0755 root root -"
    "d /srv/iscsi 0755 root root -"
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    rsync
    nfs-utils
    tcpdump
  ];
}
