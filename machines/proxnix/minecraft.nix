{ pkgs, ... }:

{
  services.minecraft-server = {
    enable = true;
    eula = true;
    package = pkgs.papermc;
    jvmOpts = "-Xmx3G -Xms2G";
    declarative = true;
    whitelist = {
      miker = "b2df8408-190c-456e-9801-d44432d5e657";
      hackerdroll = "3217baaa-225d-455d-a028-9136f45fd591";
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
    };
  };

  environment.systemPackages = [ pkgs.mcrcon ];

  networking.firewall.allowedTCPPorts = [ 25565 ];
  # RCON (25575) intentionally NOT opened in firewall — local/SSH access only
}
