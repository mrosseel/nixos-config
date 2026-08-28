{ config, lib, pkgs, ... }:

let
  rigel = "192.168.5.9";
  mirrorScript = pkgs.writeShellApplication {
    name = "music-mirror";
    runtimeInputs = with pkgs; [ rsync openssh iputils coreutils ];
    text = ''
      # rigel holds the authoritative library but is not powered on all day.
      # Skip quietly when it is asleep; the next run picks the changes up.
      if ! ping -c1 -W3 ${rigel} >/dev/null 2>&1; then
        echo "rigel is offline, nothing to mirror"
        exit 0
      fi

      opts=(-aH --delete --partial --no-perms --no-owner --no-group "--chmod=D755,F644")
      rsync "''${opts[@]}" "root@${rigel}:/mnt/user/content/content/music/" /srv/music/music/
      rsync "''${opts[@]}" "root@${rigel}:/mnt/user/content/backup/music/" /srv/music/archive-2011/
      chown -R copyparty:copyparty /srv/music/music /srv/music/archive-2011
      echo "mirror complete"
    '';
  };
in
{
  systemd.services.music-mirror = {
    description = "Mirror the music library from rigel";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe mirrorScript;
      # rsync over 1GbE saturates the link; keep it off the players' path.
      IOSchedulingClass = "idle";
      Nice = 10;
    };
  };

  systemd.timers.music-mirror = {
    description = "Periodically mirror the music library from rigel";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "5m";
      Persistent = true;
    };
  };

  environment.systemPackages = [ mirrorScript ];
}
