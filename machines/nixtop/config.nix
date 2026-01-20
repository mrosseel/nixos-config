# User, services, and application configuration for nixtop
{ config, pkgs, ... }:

{
  # Time zone and locale
  time.timeZone = "Europe/Brussels";
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "nl_BE.UTF-8";
    LC_IDENTIFICATION = "nl_BE.UTF-8";
    LC_MEASUREMENT = "nl_BE.UTF-8";
    LC_MONETARY = "nl_BE.UTF-8";
    LC_NAME = "nl_BE.UTF-8";
    LC_NUMERIC = "nl_BE.UTF-8";
    LC_PAPER = "nl_BE.UTF-8";
    LC_TELEPHONE = "nl_BE.UTF-8";
    LC_TIME = "nl_BE.UTF-8";
  };

  # Console keyboard
  console.keyMap = "dvorak";

  # Increase inotify limits for Electron apps (Obsidian, Claude Code, Spotify, etc.)
  boot.kernel.sysctl."fs.inotify.max_user_watches" = 1048576;
  boot.kernel.sysctl."fs.inotify.max_user_instances" = 8192;

  # Sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable Wayland support
  programs.xwayland.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable firmware for MediaTek MT7925 and other devices
  hardware.enableRedistributableFirmware = true;

  # User configuration
  programs.zsh.enable = true;
  users.users.mike = {
    isNormalUser = true;
    description = "Mike Rosseel";
    extraGroups = [ "networkmanager" "wheel" "video" "input" "render" "plugdev" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local"
    ];
  };

  # Root user SSH keys
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local"
  ];

  # Trusted users for devenv caching
  nix.settings.trusted-users = [ "root" "mike" ];

  # Firefox
  programs.firefox.enable = true;

  # StreamDeck custom daemon with HA integration
  # Direct hardware control with real-time Home Assistant updates via websocket
  systemd.user.services.streamdeck-daemon = {
    description = "StreamDeck Daemon";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    path = with pkgs; [
      curl
      playerctl
      wireplumber
      grim
      slurp
      wl-clipboard
      systemd
      libnotify
    ];
    serviceConfig = {
      ExecStart = "${pkgs.python3.withPackages (ps: [ ps.aiohttp ps.pillow ps.streamdeck ])}/bin/python3 /home/mike/.local/bin/streamdeck-daemon.py";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # Restart services after resume from suspend (USB audio and streamdeck reconnects)
  powerManagement.resumeCommands = ''
    sleep 2
    ${pkgs.systemd}/bin/systemctl --user -M mike@ restart pipewire pipewire-pulse wireplumber || true
    sleep 1
    # Reset Elgato Wave 3 profile to fix mic capture after suspend
    ${pkgs.pulseaudio}/bin/pactl set-card-profile alsa_card.usb-Elgato_Systems_Elgato_Wave_3_BS33J1A02510-00 off || true
    sleep 0.5
    ${pkgs.pulseaudio}/bin/pactl set-card-profile alsa_card.usb-Elgato_Systems_Elgato_Wave_3_BS33J1A02510-00 output:analog-stereo+input:mono-fallback || true
    ${pkgs.systemd}/bin/systemctl --user -M mike@ restart streamdeck-daemon || true
  '';

  # System packages
  environment.systemPackages = with pkgs; [
    azure-cli
    mullvad-browser
    anydesk
    lm_sensors
    darktable
    playerctl
    grim
    slurp
    ventoy
    popsicle
    pulseaudio   # for pactl (hyprwhspr needs this)
    wtype        # for text input with Dvorak support (hyprwhspr needs this)
    wl-clipboard # for wl-copy/wl-paste (hyprwhspr needs this)
    vulkan-loader
    vulkan-tools # vulkaninfo, vkcube
  ];

  # Mullvad VPN (requires systemd-resolved)
  services.resolved.enable = true;
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  # Syncthing
  services.syncthing = {
    enable = true;
    user = "mike";
    dataDir = "/home/mike/Documents";
    configDir = "/home/mike/.config/syncthing";
    overrideDevices = false;  # Let Syncthing manage devices
    overrideFolders = false;  # Let Syncthing manage folders
    settings = {
      options = {
        # Optimize for LAN performance
        relaysEnabled = true;
        localAnnounceEnabled = true;
        globalAnnounceEnabled = true;
        # Aggressive performance settings for LAN
        maxSendKbps = 0;  # No upload limit
        maxRecvKbps = 0;  # No download limit
        reconnectionIntervalS = 10;
        databaseTuning = "auto";  # Let Syncthing optimize DB
      };
      defaults.folder = {
        # Aggressive performance settings for fast LAN sync
        copiers = 16;  # More parallel file copy operations
        hashers = 16;  # More parallel hash operations (use those CPU cores!)
        weakHashThresholdPct = 25;  # Use weak hashing for speed
        # Increase scanning performance
        fsWatcherEnabled = true;
        fsWatcherDelayS = 1;
      };
    };
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.X11Forwarding = true;
    settings.PermitRootLogin = "yes";
  };

  # Allow passwordless sudo for GPU VRAM management
  security.sudo.extraRules = [
    {
      users = [ "mike" ];
      commands = [
        {
          command = "${pkgs.kmod}/bin/modprobe";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Disable USB autosuspend for Elgato Wave:3 (fixes mic randomly stopping)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0070", ATTR{power/autosuspend}="-1"
  '';

  # Firewall
  networking.firewall.allowedTCPPorts = [
    24800  # Barrier
    22000  # Syncthing sync
    8888   # Jupyter notebook
  ];
  networking.firewall.allowedUDPPorts = [
    21027  # Syncthing discovery
  ];
}
