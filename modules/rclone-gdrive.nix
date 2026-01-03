{ config, pkgs, lib, ... }:

{
  # Install rclone
  environment.systemPackages = with pkgs; [
    rclone
  ];

  # Enable FUSE for user mounts
  programs.fuse.userAllowOther = true;

  # Create mount point
  systemd.tmpfiles.rules = [
    "d /home/mike/GoogleDrive 0755 mike users -"
  ];

  # Systemd service to mount Google Drive
  systemd.user.services.rclone-gdrive = {
    description = "RClone mount for Google Drive";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "notify";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount gdrive: /home/mike/GoogleDrive \
          --vfs-cache-mode writes \
          --vfs-cache-max-age 24h \
          --vfs-read-chunk-size 128M \
          --vfs-read-chunk-size-limit off \
          --buffer-size 64M \
          --allow-other \
          --poll-interval 15s \
          --drive-acknowledge-abuse \
          --log-level INFO
      '';
      ExecStop = "${pkgs.fuse}/bin/fusermount -u /home/mike/GoogleDrive";
      Restart = "on-failure";
      RestartSec = "10s";
      User = "mike";
      Group = "users";
      Environment = [ "PATH=${pkgs.fuse}/bin:/run/wrappers/bin" ];
    };
  };
}
