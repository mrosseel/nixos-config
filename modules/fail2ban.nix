{ pkgs, ... }:
{
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "10m";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # 1 week
      overalljails = true;
    };
    ignoreIP = [
      "127.0.0.0/8"
      "::1"
      "192.168.5.0/24"
      # Astropolis warpspeed VPS — pushes daily snapshots + a litestream
      # WAL stream over SFTP. Should never trip the SSH jail; whitelisted
      # so a transient auth blip can't lock out the backup pipeline.
      "45.92.10.215"
    ];
    jails = {
      sshd.settings = {
        enabled = true;
        port = "ssh";
        filter = "sshd";
        maxretry = 5;
        findtime = "10m";
        bantime = "1h";
      };
    };
  };
}
