{ pkgs, ... }:

let
  plugins = {
    EssentialsX = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/hXiIvTyT/versions/nY6VN1XH/EssentialsX-2.22.0.jar";
      sha256 = "1rjqmkyrpr9qdwih62ir0g8mn9r4mpqaj84q40pclzwp0m8ni95x";
    };
    CoreProtect = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Lu3KuzdV/versions/6W2ad1iI/CoreProtect-CE-23.2.jar";
      sha256 = "0nwj0hmkxv9y4xf1jlycib8whciincn05y3xbg4xdqxln3lbny1d";
    };
    BlueMap = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/swbUV1cr/versions/Vb2ZE8bR/bluemap-5.16-paper.jar";
      sha256 = "1jkn8sggpvyc9yq60a2amrca3g1gna5cx2sgc9bbsbakc2raxnvr";
    };
    Chunky = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/fALzjamp/versions/P3y2MXnd/Chunky-Bukkit-1.4.40.jar";
      sha256 = "08cpq11i83rc949b33dj4dvf2dmqpr6y676ybbhi447ph3y7fm1a";
    };
    ViaVersion = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/P1OZGk5p/versions/ruzmiBqe/ViaVersion-5.10.0.jar";
      sha256 = "0wnr95qnvazkfgz84ncms8hrjl0y00kgcvhaw0dwsx4d3633z9p5";
    };
    ViaBackwards = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/NpvuJQoq/versions/YjpKsm6j/ViaBackwards-5.10.0.jar";
      sha256 = "0ay6x6bcynnzdh2j1rjz2bvxf8qc4pvpcwk26g6li01qvpfvd6a6";
    };
    Geyser = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/wKkoqHrH/versions/xd9KQBCh/Geyser-Spigot.jar";
      sha256 = "00jv588y584a1qzdl5bdlg32y78wvcgfgm1pnawhdp0b3y53p33b";
    };
    Floodgate = pkgs.fetchurl {
      url = "https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/138/downloads/spigot";
      sha256 = "1lbb3j78xaancawcyi4qb9aj2nk2i823scfmfjwz2kzvw84bkga4";
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
