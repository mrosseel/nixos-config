{ pkgs, ... }:

let
  plugins = {
    EssentialsX = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/hXiIvTyT/versions/Oa9ZDzZq/EssentialsX-2.21.2.jar";
      sha256 = "1inz1c6zs4w3ckjil51yyz7r87rwvdk3cvw869y58g1gy0k90x8b";
    };
    CoreProtect = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Lu3KuzdV/versions/HD2IvrxS/CoreProtect-CE-23.1.jar";
      sha256 = "1qm2ircahprws0fxsx4ppbs8prn7qcfqm2kf3mp05n2ixjs84c41";
    };
    BlueMap = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/swbUV1cr/versions/rUyuQba7/bluemap-5.14-paper.jar";
      sha256 = "1zwy9zn1kp06y47hmpwv13xl5ligsxp244k8j4pwvdqyglc9ipc2";
    };
    Chunky = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/fALzjamp/versions/P3y2MXnd/Chunky-Bukkit-1.4.40.jar";
      sha256 = "08cpq11i83rc949b33dj4dvf2dmqpr6y676ybbhi447ph3y7fm1a";
    };
    ViaVersion = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/P1OZGk5p/versions/OGj9YIQN/ViaVersion-5.9.1.jar";
      sha256 = "00gbdwwbqf56s58p1n4ivcfxgi878gsiv79ihlf8xi9qc5ysjfis";
    };
    ViaBackwards = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/NpvuJQoq/versions/W890fNPl/ViaBackwards-5.9.1.jar";
      sha256 = "06fpfcjida94g8mg9w2lxwd2gfp42dvfflafli6vi2zsraxiirid";
    };
    Geyser = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/wKkoqHrH/versions/ZAMkISgL/Geyser-Spigot.jar";
      sha256 = "0nqd4dgrrl6cy2bmmc2hvkr2w5qxv72qqmfg9dbbh8xawr15nchq";
    };
    Floodgate = pkgs.fetchurl {
      url = "https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/132/downloads/spigot";
      sha256 = "0c0hibd33891rkgsfkq9b6ffrva7f6rcdwn225m50qvgk1xga7b5";
    };
  };

  pluginSymlinks = builtins.mapAttrs (name: drv: drv) (
    builtins.listToAttrs (
      map (name: {
        name = "plugins/${name}.jar";
        value = plugins.${name};
      }) (builtins.attrNames plugins)
    )
  );
in
{
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;

    servers.mine = {
      enable = true;
      package = pkgs.paperServers.paper-1_21_11;
      jvmOpts = "-Xmx3G -Xms2G";

      whitelist = {
        miker = "b2df8408-190c-456e-9801-d44432d5e657";
        hackerdroll = "3217baaa-225d-455d-a028-9136f45fd591";
        DarkShadowVerso = "8174bd79-6a58-4395-b17f-92a28670e12b";
        ".hackerdroll" = "00000000-0000-0000-0009-01f73ade46b1";
      };

      serverProperties = {
        server-port = 25565;
        motd = "Mike's Minecraft Server";
        max-players = 10;
        difficulty = "normal";
        gamemode = "survival";
        white-list = true;
        enable-rcon = true;
        "rcon.port" = 25575;
        "rcon.password" = "mc-rcon-proxnix";
        view-distance = 12;
        simulation-distance = 10;
      spawn-protection = 0;
      };

      symlinks = pluginSymlinks;
    };
  };

  environment.systemPackages = [ pkgs.mcrcon ];

  # Geyser (Bedrock) — UDP 19132
  networking.firewall.allowedUDPPorts = [ 19132 ];

  # RCON (25575) intentionally NOT opened in firewall — local/SSH access only

  # Minecraft backup — every 6 hours, keep 7 rolling backups
  systemd.tmpfiles.rules = [
    "d /srv/backups/minecraft 0755 root root -"
  ];

  systemd.services.minecraft-backup = {
    description = "Minecraft world backup";
    serviceConfig = {
      Type = "oneshot";
    };
    path = [ pkgs.gnutar pkgs.gzip pkgs.findutils ];
    script = ''
      BACKUP_DIR="/srv/backups/minecraft"
      TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
      # tar exits 1 when files change during archive (live server) — that's OK
      tar czf "$BACKUP_DIR/minecraft-$TIMESTAMP.tar.gz" \
        --exclude='cache' \
        --exclude='libraries' \
        --exclude='versions' \
        --exclude='.paper-remapped' \
        --exclude='bluemap/web' \
        --exclude='bluemap/minecraft-client-*' \
        -C /srv/minecraft/mine . || [ $? -eq 1 ]

      # Keep only the 7 most recent backups
      ls -t "$BACKUP_DIR"/minecraft-*.tar.gz | tail -n +8 | xargs -r rm -f
    '';
  };

  systemd.timers.minecraft-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00,06,12,18:00:00";
      Persistent = true;
    };
  };
}
