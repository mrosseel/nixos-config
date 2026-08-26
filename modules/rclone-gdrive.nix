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

  # Systemd service to mount Google Drive.
  # The remote uses a private OAuth client id, so it no longer shares the throttled
  # default rclone quota. The pacer can therefore run at 10ms instead of the 100ms
  # default. dir-cache-time is long because --poll-interval picks up remote changes.
  systemd.user.services.rclone-gdrive = {
    description = "RClone mount for Google Drive";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "notify";
      # -uz = lazy unmount: also removes stale/dead mounts (plain -u fails on them,
      # which left the service stuck in a "directory already mounted" restart loop).
      # Must use the setuid wrapper: ${pkgs.fuse}/bin/fusermount is not setuid, so
      # unmounting fails with "Operation not permitted" whatever flags are passed.
      ExecStartPre = "-/run/wrappers/bin/fusermount -uz /home/mike/GoogleDrive";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount gdrive: /home/mike/GoogleDrive \
          --vfs-cache-mode full \
          --vfs-cache-max-age 24h \
          --vfs-read-chunk-size 128M \
          --vfs-read-chunk-size-limit off \
          --buffer-size 64M \
          --dir-cache-time 1000h \
          --attr-timeout 1m \
          --allow-other \
          --poll-interval 15s \
          --vfs-fast-fingerprint \
          --drive-pacer-min-sleep 10ms \
          --drive-pacer-burst 200 \
          --drive-acknowledge-abuse \
          --log-level INFO
      '';
      ExecStop = "-/run/wrappers/bin/fusermount -uz /home/mike/GoogleDrive";
      Restart = "on-failure";
      RestartSec = "10s";
      User = "mike";
      Group = "users";
      Environment = [ "PATH=/run/wrappers/bin:${pkgs.fuse}/bin" ];
    };
  };
}
