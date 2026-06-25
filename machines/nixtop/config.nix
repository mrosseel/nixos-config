# User, services, and application configuration for nixtop
{ config, pkgs, ... }:

let
  # While a VNC client is connected, hold a logind idle-inhibitor so hypridle
  # can't power the display off mid-capture. That dpms-off tears down wayvnc's
  # cursor-capture session and intermittently segfaults Hyprland in the
  # CCursorshareSession path. With no client connected the inhibitor is
  # released, so the screen still sleeps when the machine is genuinely idle.
  wayvnc-idle-guard = pkgs.writeShellApplication {
    name = "wayvnc-idle-guard";
    runtimeInputs = [ pkgs.wayvnc pkgs.jq pkgs.systemd pkgs.coreutils ];
    text = ''
      inhibit_pid=""

      start_inhibit() {
        if [ -n "$inhibit_pid" ] && kill -0 "$inhibit_pid" 2>/dev/null; then
          return
        fi
        systemd-inhibit --what=idle --who=wayvnc \
          --why="VNC client connected" sleep infinity &
        inhibit_pid=$!
      }

      stop_inhibit() {
        if [ -n "$inhibit_pid" ]; then
          kill "$inhibit_pid" 2>/dev/null || true
          inhibit_pid=""
        fi
      }

      trap stop_inhibit EXIT

      # Re-sync if a client is already connected when this guard starts.
      if [ "$(wayvncctl -j client-list 2>/dev/null | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
        start_inhibit
      fi

      wayvncctl --wait --reconnect -j event-receive | while read -r line; do
        method=$(printf '%s' "$line" | jq -r '.method // empty' 2>/dev/null || true)
        count=$(printf '%s' "$line" | jq -r '.params.connection_count // .connection_count // empty' 2>/dev/null || true)
        # Fresh wayvnc control connection means no clients are attached yet.
        if [ "$method" = "wayvnc-startup" ]; then
          stop_inhibit
        fi
        if [ -n "$count" ]; then
          if [ "$count" -gt 0 ]; then start_inhibit; else stop_inhibit; fi
        fi
      done
    '';
  };

  # Hard-recover the Elgato Wave:3 mic when its USB firmware hangs (kernel logs
  # "usb_set_interface failed (-110)"). A wireplumber restart or the sysfs
  # authorized-toggle can't fix it because VBUS stays powered; only a real port
  # power-cycle resets the device. Wave:3 = hub 3-2.1.1 port 1, StreamDeck = port 3.
  fix-wave3 = pkgs.writeShellScriptBin "fix-wave3" ''
    export PATH="${pkgs.uhubctl}/bin:${pkgs.pulseaudio}/bin:${pkgs.alsa-utils}/bin:${pkgs.systemd}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin:${pkgs.libnotify}/bin:$PATH"

    echo "Power-cycling Elgato Wave:3 (hub 3-2.1.1 port 1; StreamDeck on port 3 untouched)..."
    sudo uhubctl -l 3-2.1.1 -p 1 -a cycle -d 3
    sleep 4

    systemctl --user restart wireplumber
    sleep 2

    # A real power-cycle re-mutes the mic in hardware and drops the card profile,
    # so restore both (mirrors elgato-audio-restart.service below).
    for card in $(pactl list cards short 2>/dev/null | grep -i elgato | awk '{print $2}'); do
      pactl set-card-profile "$card" off 2>/dev/null || true
      sleep 0.3
      pactl set-card-profile "$card" output:analog-stereo+input:mono-fallback 2>/dev/null || true
    done
    sleep 0.5
    amixer -c Wave3 sset Mic 80% 2>/dev/null || true

    src=$(pactl list sources short 2>/dev/null | grep -iE 'input.*wave' | awk '{print $2}' | head -1)
    if [ -n "$src" ]; then
      pactl set-source-mute "$src" 0 2>/dev/null || true
      pactl set-default-source "$src" 2>/dev/null || true
      echo "Wave:3 recovered. Default source: $src"
      notify-send -i audio-input-microphone "Wave:3 mic" "Recovered and set as default" 2>/dev/null || true
    else
      echo "Wave:3 power-cycled but no input source appeared yet - check 'pactl list sources short'." >&2
      notify-send -u critical -i audio-input-microphone "Wave:3 mic" "Power-cycled but no source appeared" 2>/dev/null || true
    fi
  '';
in

{
  # /bin/chmod symlink needed by VelociDrone patcher
  # Override x11.conf D! rule that deletes X11 sockets after 10d,
  # which breaks Steam/bubblewrap when XWayland socket gets cleaned
  systemd.tmpfiles.rules = [
    "L+ /bin/chmod - - - - ${pkgs.coreutils}/bin/chmod"
    "d /tmp/.X11-unix 1777 root root -"
  ];

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
    extraGroups = [ "networkmanager" "wheel" "video" "input" "render" "plugdev" "scanner" "dialout" ];
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
      Environment = "PYTHONUNBUFFERED=1";
      ExecStart = "${pkgs.python3.withPackages (ps: [ ps.aiohttp ps.pillow ps.streamdeck ])}/bin/python3 /home/mike/.local/bin/streamdeck-daemon.py";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # WayVNC remote desktop server
  systemd.user.services.wayvnc = {
    description = "WayVNC Server";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc 0.0.0.0 5900";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Holds an idle-inhibitor while a VNC client is connected (see wayvnc-idle-guard above)
  systemd.user.services.wayvnc-idle-guard = {
    description = "Inhibit idle while a wayvnc client is connected";
    after = [ "wayvnc.service" "graphical-session.target" ];
    wants = [ "wayvnc.service" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${wayvnc-idle-guard}/bin/wayvnc-idle-guard";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

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

    # Re-run Elgato audio fix now that pipewire is fully up
    sleep 2
    ${pkgs.systemd}/bin/systemctl --user -M mike@ start elgato-audio-restart || true
  '';

  # Extra nix-ld libraries for Python venvs (Qt, numpy, etc.) and Tauri apps (OpenCode)
  programs.nix-ld.libraries = with pkgs; [
    zlib
    glib
    libGL
    fontconfig
    freetype
    libx11
    libxext
    libxrender
    libxcb
    libxi
    dbus
    libxkbcommon
    wayland
    gtk2
    gtk3
    gdk-pixbuf
    cairo
    libsoup_3
    webkitgtk_4_1
    gsettings-desktop-schemas
    pango
  ];

  # System packages
  programs.mosh.enable = true;

  # GSettings schemas for GTK apps (OpenCode desktop, etc.)
  environment.sessionVariables.XDG_DATA_DIRS = ["${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"];
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  environment.systemPackages = with pkgs; [
    gsettings-desktop-schemas
    cifs-utils
    sqlite
    (azure-cli.withExtensions [ azure-cli.extensions.ssh ])
    mullvad-browser
    tor-browser
    xrandr

    lm_sensors
    darktable
    gimp
    image_optim
    playerctl
    grim
    slurp
    ventoy
    popsicle
    gscan2pdf
    wayvnc
    pulseaudio   # for pactl (hyprwhspr needs this)
    wtype        # for text input with Dvorak support (hyprwhspr needs this)
    wl-clipboard # for wl-copy/wl-paste (hyprwhspr needs this)
    vulkan-loader
    vulkan-tools # vulkaninfo, vkcube

    # ROCm for AMD GPU compute (voxtype parakeet, etc.)
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    rocmPackages.clr  # HIP runtime

    freecad-wayland
    calibre
    fix-wave3  # power-cycle recovery for the Wave:3 mic (USB -110 firmware hang)
  ];

  # Mullvad VPN (requires systemd-resolved)
  services.resolved.enable = true;
  # Resolve `.local` (mDNS) via resolved instead of nss-mdns's per-lookup
  # multicast, which races apps holding UDP 5353 (Brave/Spotify) → EBUSY.
  # "resolve" = look up mDNS but don't respond; avahi handles responding/publish.
  services.resolved.extraConfig = "MulticastDNS=resolve";
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
        # Set mic volume and unmute (USB reset causes hardware mute)
        amixer -c Wave3 sset Mic 80% 2>/dev/null
        pactl set-source-mute alsa_input.usb-Elgato_Systems_Elgato_Wave_3_BS33J1A02510-00.mono-fallback 0 2>/dev/null
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

  # OpenClaw Samba share automount
  fileSystems."/mnt/openclaw" = {
    device = "//openclaw.local/openclaw";
    fsType = "cifs";
    options = [
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "guest"
      "uid=1000"
      "gid=100"
      "file_mode=0664"
      "dir_mode=0775"
    ];
  };

  # Firmware updates (fwupdmgr)
  services.fwupd.enable = true;

  # Flatpak — for SplashMapper (xyz.splashmapper.Splash), which is not in
  # nixpkgs. xdg.portal is already provided by the omarchy/Hyprland module.
  services.flatpak.enable = true;

  # btrfs is mounted with discard=async, which continuously trims.
  # Disable the weekly fstrim timer to avoid redundant work.
  services.fstrim.enable = false;

  # Tailscale VPN
  services.tailscale.enable = true;
  services.tailscale.extraUpFlags = [ "--accept-routes" ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Prevent Tailscale from hijacking LAN traffic when on the same subnet
  # OPNsense advertises 192.168.5.0/24 for remote access, but when home
  # we need to use the local interface directly
  systemd.services.tailscale-lan-fix = {
    description = "Ensure LAN traffic bypasses Tailscale subnet routes";
    after = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.iproute2}/bin/ip rule del to 192.168.5.0/24 lookup main priority 100 2>/dev/null; ${pkgs.iproute2}/bin/ip rule add to 192.168.5.0/24 lookup main priority 100'";
      ExecStop = "${pkgs.iproute2}/bin/ip rule del to 192.168.5.0/24 lookup main priority 100";
    };
  };

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
