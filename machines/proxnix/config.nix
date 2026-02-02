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
    exports = ''
      /srv/nfs/pifinder 192.168.5.0/24(ro,no_root_squash,no_subtree_check)
    '';
  };

  # iSCSI target — phase 2, configure manually with tgt/targetcli after NFS works

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      2049  # NFS
      3260  # iSCSI (phase 2)
    ];
    allowedUDPPorts = [
      69    # TFTP
    ];
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
  ];
}
