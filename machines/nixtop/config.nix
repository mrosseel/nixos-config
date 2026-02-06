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

  # Enable aarch64 emulation for cross-building RPi images
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

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
    # Fix Elgato Wave 3: keep mic processing active to prevent silence when playback starts first
    # Also set pro-audio profile so mic works on connect
    wireplumber.extraConfig."51-elgato-wave" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "~alsa_input.usb-Elgato_Systems_Elgato_Wave_3_*"; }
          ];
          actions = {
            update-props = {
              "node.always-process" = true;
            };
          };
        }
      ];
    };
    # Audio output priorities: XM4 highest, HD Audio low, Elgato output lowest
    wireplumber.extraConfig."50-audio-priorities" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "~alsa_output.pci-*"; }
          ];
          actions = {
            update-props = {
              "priority.session" = 100;
            };
          };
        }
        {
          matches = [
            { "node.name" = "~alsa_output.usb-Elgato*"; }
          ];
          actions = {
            update-props = {
              "priority.session" = 50;
            };
          };
        }
      ];
      "monitor.bluez.rules" = [
        {
          matches = [
            { "device.name" = "~bluez_card.80_99_E7_8E_77_37"; }
          ];
          actions = {
            update-props = {
              "bluez5.auto-connect" = [ "a2dp_sink" ];
              "bluez5.profile" = "a2dp-sink";
            };
          };
        }
        {
          matches = [
            { "node.name" = "~bluez_output.80_99_E7_8E_77_37*"; }
          ];
          actions = {
            update-props = {
              "priority.session" = 2000;
            };
          };
        }
      ];
    };
  };

  # Enable Wayland support
  programs.xwayland.enable = true;

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable firmware for MediaTek MT7925 and other devices
  hardware.enableRedistributableFirmware = true;

  # User configuration
  programs.zsh.enable = true;  # Keep as fallback
  environment.shells = with pkgs; [ nushell zsh bash ];
  users.users.mike = {
    isNormalUser = true;
    description = "Mike Rosseel";
    extraGroups = [ "networkmanager" "wheel" "video" "input" "render" "plugdev" ];
    shell = pkgs.nushell;
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

  # Limit nix-daemon memory to prevent OOM during large builds (e.g. aarch64 cross-compilation)
  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "64G";
    MemoryHigh = "48G";
  };

  # Suppress "channels does not exist" warning (using flakes, not channels)
  nix.nixPath = [];

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

  # COMMENTED OUT: Script-based Elgato fix - replaced by WirePlumber config above
  # Uncomment if WirePlumber fix alone is insufficient
  #
  # systemd.user.services.elgato-audio-fix = {
  #   description = "Elgato Wave Audio Fix";
  #   after = [ "pipewire.service" "wireplumber.service" ];
  #   wantedBy = [ "graphical-session.target" ];
  #   path = [ pkgs.pulseaudio pkgs.gawk ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "/home/mike/.local/share/omarchy/bin/omarchy-fix-usb-audio";
  #   };
  # };
  #
  # systemd.services.elgato-audio-fix-trigger = {
  #   description = "Trigger Elgato Audio Fix for user";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.systemd}/bin/systemctl --user -M mike@ restart elgato-audio-fix.service";
  #   };
  # };

  # Restart services after resume from suspend
  powerManagement.resumeCommands = ''
    # Wait for USB devices to settle
    sleep 3

    # Reset Elgato USB devices (Wave:3 and StreamDeck) to recover from bad state
    for dev in /sys/bus/usb/devices/*/idVendor; do
      dir=$(dirname "$dev")
      if [ -f "$dir/idVendor" ] && [ "$(cat "$dir/idVendor" 2>/dev/null)" = "0fd9" ]; then
        echo 0 > "$dir/authorized" 2>/dev/null || true
        sleep 0.5
        echo 1 > "$dir/authorized" 2>/dev/null || true
      fi
    done

    sleep 2

    # Stop audio services cleanly first
    ${pkgs.systemd}/bin/systemctl --user -M mike@ stop pipewire-pulse wireplumber pipewire 2>/dev/null || true
    sleep 1

    # Start in correct order
    ${pkgs.systemd}/bin/systemctl --user -M mike@ start pipewire || true
    sleep 1
    ${pkgs.systemd}/bin/systemctl --user -M mike@ start wireplumber || true
    sleep 1
    ${pkgs.systemd}/bin/systemctl --user -M mike@ start pipewire-pulse || true

    # Restart StreamDeck daemon
    sleep 1
    ${pkgs.systemd}/bin/systemctl --user -M mike@ restart streamdeck-daemon || true
  '';

  # System packages
  programs.mosh.enable = true;

  environment.systemPackages = with pkgs; [
    azure-cli
    mullvad-browser

    lm_sensors
    darktable
    gimp
    image_optim
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
  # Also allow ALL for mike (needed for migration testing with loop devices)
  security.sudo.extraRules = [
    {
      users = [ "mike" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Elgato device udev rules (both Wave:3 and StreamDeck MK.2)
  # - Disable USB autosuspend to prevent random disconnects
  # - Restart services when devices are reconnected after power cycle
  services.udev.extraRules = ''
    # Elgato Wave:3 (0fd9:0070)
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0070", ATTR{power/autosuspend}="-1"
    ACTION=="add", SUBSYSTEM=="sound", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0070", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="elgato-audio-restart.service"

    # StreamDeck MK.2 (0fd9:0080)
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0fd9", ATTR{idProduct}=="0080", ATTR{power/autosuspend}="-1"
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", ATTRS{idProduct}=="0080", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="streamdeck-restart.service"
  '';

  # Service to fix Elgato Wave 3 audio on connect (follows omarchy-fix-usb-audio pattern)
  systemd.user.services.elgato-audio-restart = {
    description = "Fix Elgato Wave 3 audio";
    path = [ pkgs.pulseaudio pkgs.alsa-utils pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "fix-elgato-audio" ''
        sleep 2
        # Reset profile like omarchy-fix-usb-audio
        for card in $(pactl list cards short 2>/dev/null | grep -i elgato | awk '{print $2}'); do
          pactl set-card-profile "$card" off 2>/dev/null
          sleep 0.3
          pactl set-card-profile "$card" output:analog-stereo+input:mono-fallback 2>/dev/null
        done
        sleep 0.5
        # Set mic volume
        amixer -c Wave3 sset Mic 80% 2>/dev/null
        # Set as default source
        pactl set-default-source alsa_input.usb-Elgato_Systems_Elgato_Wave_3_BS33J1A02510-00.mono-fallback 2>/dev/null
      '';
    };
  };

  # Service to restart StreamDeck daemon when device is connected
  systemd.user.services.streamdeck-restart = {
    description = "Restart StreamDeck daemon";
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user restart streamdeck-daemon";
    };
  };

  # Tailscale VPN
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

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
