{
  description = "Darwin system flake";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    # Main package set tracks nixpkgs-unstable (rolls fast, matches HM master).
    # When a specific package breaks here, override it from nixpkgs-vetted
    # (nixos-unstable: same channel, slower-vetted via Hydra) via an overlay.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-vetted.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Temporary: ollama 0.32.12+ only (see overlays/ollama.nix). Pinned to a rev
    # rather than the master branch to keep the lock stable. Drop this input and
    # the overlay once nixpkgs-unstable carries 0.32.12 or newer.
    nixpkgs-master.url = "github:NixOS/nixpkgs/4c1ce41ae6abea5c8895e698356ecb84ff4f5385";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    omarchy-nix = {
      # Default to upstream so hosts without a local checkout (servers, nixair)
      # evaluate cleanly. nixtop builds against the local dev checkout via
      # --override-input, baked into the nixsw/nixup aliases (hostname-gated in
      # modules/home-manager/default.nix). The override is ephemeral and never
      # touches flake.lock, so it can't leak the local path into commits.
      url = "github:mrosseel/omarchy-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    # home-manager.url = "github:nix-community/home-manager/release-24.05";
    # home-manager.inputs.nixpkgs.follows
    # pifinder = {
    #   url = "/Users/mike/dev/business/pifinder.eu/website";  # or use a git URL if it's in a repository
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # nixpkgs source for kernel + linux-firmware (kept separate from main nixpkgs
    # so we can roll the kernel independently when chasing Strix Halo amdgpu fixes).
    nixpkgs-kernel.url = "github:NixOS/nixpkgs/8c91a71d13451abc40eb9dae8910f972f979852f";

    copyparty.url = "github:9001/copyparty";

    nix-minecraft.url = "github:Infinidoge/nix-minecraft";

    # PiFinder server infra (attic cache + delta server) — own repo, consumed
    # as NixOS modules on general-server. Caddy vhosts stay in this repo; see
    # docs/caddy.md over there.
    pifinder-server = {
      url = "github:mrosseel/pifinder-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code.url = "github:sadjow/claude-code-nix";
    codex-cli-nix.url = "github:sadjow/codex-cli-nix";

    # hunk: review-first terminal diff viewer. Home-manager module wired in
    # modules/home-manager/hunk.nix (shared across all hosts).
    # hunk's flake enumerates x86_64-darwin in its systems list, and importing
    # its home-manager module forces flake-parts to evaluate that perSystem.
    # Our nixpkgs (26.11) and hunk's own pin both dropped x86_64-darwin, so
    # follow nixpkgs-stable (25.11), which still has it — hunk evals, and nixtop
    # only builds hunk's x86_64-linux package.
    hunk = {
      url = "github:modem-dev/hunk";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    # grower: daily directory-size inventory. Published so every host (incl.
    # the Mac) can fetch it. Override locally during dev with:
    #   --override-input grower path:/home/mike/dev/grower
    grower = {
      url = "github:mrosseel/grower";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sketchybar config
    sketchybar = {
      url = "github:FelixKratz/dotfiles";
      flake = false;
    };
  };

  outputs = inputs@{ self, home-manager, nix-darwin, nixpkgs, nixpkgs-stable, nixos-mailserver, omarchy-nix, disko, nixos-hardware, ...}:
  let
    nixpkgsConfig = {
      allowUnfree = true;
      allowUnsupportedSystem = false;
      permittedInsecurePackages = [
        "libsoup-2.74.3"
        "ventoy-1.1.17"
        "electron-39.8.10"
        "electron-40.10.5"  # vesktop 1.6.5 (Electron Discord client); EOL but low-risk
      ];
      vivaldi = {
        proprietaryCodecs = true;
        enableWideVine = true;
      };
    };
    overlays = with inputs; [
      claude-code.overlays.default
      (import ./overlays/brave.nix)
      (import ./overlays/ollama.nix nixpkgs-master)
    ];
    user = "mike";
    # Shared bits applied to every NixOS host (Darwin uses `configuration` below).
    nixosBase = {
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      # Trust the wheel group so closures built on another host (e.g. nixtop)
      # can be pushed here via `nixos-rebuild --target-host` without signing.
      nix.settings.trusted-users = [ "root" "@wheel" ];
      # Generic flake-output cache, wanted on every host. The Hyprland cache
      # lives in omarchy-nix instead (it owns the hyprland flake dependency),
      # so only omarchy hosts carry it. Appends to the default cache.nixos.org.
      nix.settings.extra-substituters = [
        "https://nix-community.cachix.org"
      ];
      nix.settings.extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [ pkgs.vim
        ];

      # Auto upgrade nix package and the daemon service.
      nix.enable = true;

      nix = {
        # enable flakes per default
        package = pkgs.nix;
        settings = {
          allowed-users = [ user ];
          experimental-features = [ "nix-command" "flakes" ];
        };
        # pin the flake registry https://yusef.napora.org/blog/pinning-nixpkgs-flake/
        registry.nixpkgs.flake = nixpkgs;
      };
      nixpkgs.config = nixpkgsConfig;
      nixpkgs.overlays = overlays;

      # Create /etc/zshrc that loads the nix-darwin environment.
      programs.zsh.enable = true; 

      home-manager.backupFileExtension = "backup";

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 4;
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#airelon
    darwinConfigurations.airelon = nix-darwin.lib.darwinSystem {
      specialArgs = { inherit inputs home-manager;};
      modules = [
        { nixpkgs.hostPlatform = "aarch64-darwin"; }
        configuration
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs; hostname = "airelon"; };
            users.${user} = {
              imports = [ ./modules/home-manager ];
            };
          };
        }
        ./modules/darwin
        ./modules/python.nix
        # grower: daily directory-size inventory. Default scans the home dir
        # (no sudo/firmlink issues); `sudo grower scan --root /` does the whole
        # machine, and the excludes below already cover APFS firmlinks.
        #
        # Scheduling on a laptop: launchd's StartCalendarInterval silently skips
        # runs that fall while the machine is asleep, which for a 04:00 slot is
        # most nights. StartInterval instead fires on wake once the interval has
        # elapsed, and `grower scan` is idempotent (at most one snapshot per
        # local day, no-op if today's already exists) — so a 6h tick lands
        # exactly one scan on the first wake of each day.
        ({ pkgs, inputs, ... }: {
          nixpkgs.overlays = [ inputs.grower.overlays.default ];
          environment.systemPackages = [ pkgs.grower ];
          launchd.user.agents.grower = {
            command = "${pkgs.grower}/bin/grower scan";
            serviceConfig = {
              StartInterval = 21600; # 6h; idempotency collapses this to 1/day
              RunAtLoad = true;
              LowPriorityIO = true;
              Nice = 10;
              StandardOutPath = "/Users/mike/.local/share/grower/scan.log";
              StandardErrorPath = "/Users/mike/.local/share/grower/scan.log";
            };
          };
          environment.etc."grower/config.toml".text = ''
            db_path = "/Users/mike/.local/share/grower/grower.db"
            roots = ["/Users/mike"]
            excludes = ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm", "/Users/mike/Library/Mobile Documents", "/Users/mike/.Trash"]
            threshold = "10MiB"
            one_filesystem = false
            follow_symlinks = false
            hostname = "airelon"
          '';
        })
        # inputs.pifinder.darwinModules.default
        # {
        #   services.pifinderWebServer = {
        #     enable = true;
        #     user = "mike";
        #     workingDirectory = "/Users/mike/dev/business/pifinder.eu/website";
        #   };
        # }
	# ./modules/desktop.nix
        ];
    };
    # Expose the package set, including overlays, for convenience.
    #darwinPackages = self.darwinConfigurations."airelon".pkgs;

    nixosConfigurations."nix270" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        nixosBase
        {
          nixpkgs.config = nixpkgsConfig;
          nixpkgs.overlays = overlays;
        }
        ./modules/nix-github-token.nix
        ./machines/nix270/configuration.nix
        ./machines/nix270/hardware-configuration.nix
	./modules/default-browser.nix
	./modules/desktop.nix
	./modules/openssh.nix
	./modules/printing.nix
        ./modules/linux/avahi.nix
        ./modules/automatic-nix-gc.nix
        { services.automatic-nix-gc.enable = true; }
        ./modules/rclone-gdrive.nix
        omarchy-nix.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          # Configure omarchy
          omarchy = {
            username = "mike";
            full_name = "Mike Rosseel";
            email_address = "mike.rosseel@gmail.com";
            theme = "tokyo-night";
            scale = 1;
            browser = "brave";
            terminal = "kitty";
            # Upstream went opt-in for the docker group (it is root-equivalent);
            # keep passwordless docker here. Remove to get the prompt-gated default.
            containers.sudoless_docker = true;
            seamless_boot = {
              enable = true;
              username = "mike";
            };
          };

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = { hostname = "nix270"; inherit inputs; };
            users.${user} = {
              imports = [
                ./modules/home-manager
                omarchy-nix.homeManagerModules.default
                ./machines/nix270/omarchy-idle.nix
              ];

              # Override keyboard layout to Dvorak (omarchy-nix defaults to us)
              wayland.windowManager.hyprland.settings.input.kb_layout = "us";
              wayland.windowManager.hyprland.settings.input.kb_variant = "dvorak";
            };
          };
        }
      ];
    };
    # nixair - plain GNOME desktop (Finn's machine)
    nixosConfigurations."nixair" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs nixpkgs-stable; };
      modules = [
        nixosBase
	{
	  nixpkgs.config = nixpkgsConfig;
	  nixpkgs.overlays = overlays;
	}
        ./modules/nix-github-token.nix
        ./machines/nixair/configuration.nix
        ./machines/nixair/hardware-configuration.nix
        ./modules/linux/avahi.nix
	./modules/default-browser.nix
	./modules/openssh.nix
        ./modules/python.nix
	./modules/ai.nix
	./modules/printing.nix
        ./modules/automatic-nix-gc.nix
        { services.automatic-nix-gc.enable = true; }
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = { hostname = "nixair"; inherit inputs; };
            users.${user} = {
              imports = [
                ./modules/home-manager
              ];
            };
          };
        }
      ];
    };
    nixosConfigurations."general-server" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        nixosBase
        nixos-mailserver.nixosModules.mailserver
        ./modules/nix-github-token.nix
        ./machines/general-server/configuration.nix
        ./machines/general-server/hardware-configuration.nix
        ./machines/general-server/caddy-service.nix
        ./machines/general-server/auto-update.nix
        ./machines/general-server/systemd.nix
        ./machines/general-server/monitoring.nix
        ./machines/general-server/asterisms-votes.nix
        ./machines/general-server/spain2026-weather.nix
        ./machines/general-server/phpfpm-joeri.nix
        inputs.pifinder-server.nixosModules.default
        ./modules/simple-mail-server.nix
        ./modules/python.nix
	./modules/openssh.nix
	./modules/fail2ban.nix
        ./modules/automatic-nix-gc.nix
        { services.automatic-nix-gc.enable = true; }
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = { hostname = "general-server"; inherit inputs; };
            users.${user} = {
              imports = [ ./modules/home-manager ];
            };
          };
        }
      ];
    };
    nixosConfigurations."nixtop" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        nixosBase
        {
          nixpkgs.config = nixpkgsConfig;
          nixpkgs.overlays = overlays;
        }
        ./modules/nix-github-token.nix
        ./machines/nixtop/configuration.nix
        ./machines/nixtop/config.nix
        disko.nixosModules.disko
        nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
        ./modules/default-browser.nix
        ./modules/desktop.nix
        ./modules/openssh.nix
        ./modules/python.nix
        ./modules/ai.nix
        ./modules/printing.nix
        ./modules/scanning.nix
        ./modules/games.nix
        ./modules/linux/avahi.nix
        ./modules/rclone-gdrive.nix
        ./modules/anydesk.nix
        ./modules/dropbox.nix
        ./modules/automatic-nix-gc.nix
        { services.automatic-nix-gc.enable = true; }
        { nixpkgs.overlays = [ inputs.grower.overlays.default ]; }
        inputs.grower.nixosModules.default
        {
          services.grower = {
            enable = true;
            # Run as mike (with CAP_DAC_READ_SEARCH from the module) so the DB
            # lives in mike's home and `grower report`/`diff` need no sudo.
            user = "mike";
            group = "users";
            dbDir = "/home/mike/.local/share/grower";
            # Whole machine, but skip what isn't local disk or would double-count.
            # one_filesystem stays false: btrfs gives each subvolume (/home, /nix,
            # /persist) a distinct st_dev, so excludes — not device boundaries —
            # are the right tool here.
            excludes = [
              "/proc" "/sys" "/dev" "/run"  # pseudo-filesystems
              "/.snapshots"                 # btrfs snapshots — would double-count live subvolumes
              "/mnt"                        # external/network/removable mounts (openclaw, rigel-music, pifinder, usb, sdcard, …)
              "/home/mike/GoogleDrive"      # rclone Google Drive (remote)
            ];
          };
        }
        omarchy-nix.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          # Configure omarchy
          omarchy = {
            username = "mike";
            full_name = "Mike Rosseel";
            email_address = "mike.rosseel@gmail.com";
            theme = "tokyo-night";
            scale = 1;
            browser = "brave";
            terminal = "kitty";
            # Upstream went opt-in for the docker group (it is root-equivalent);
            # keep passwordless docker here. Remove to get the prompt-gated default.
            containers.sudoless_docker = true;
            seamless_boot = {
              enable = true;
              username = "mike";
            };
            voxtype = {
              enable = true;
              # Personal dictation vocabulary (initial_prompt + replacements for
              # PiFinder, Hyprland, NixOS...). Seeded once; edits at runtime stick.
              config_file = ./machines/nixtop/voxtype.toml;
            };
            # Bound below as SUPER + F1..F10; this only teaches the bar to show them.
            shell.workspace_count = 20;
          };

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = { hostname = "nixtop"; inherit inputs; };
            users.${user} = {
              imports = [
                ./modules/home-manager
                ./modules/home-manager/thunderbird.nix
                omarchy-nix.homeManagerModules.default
              ];

              # Override keyboard layout to Dvorak (omarchy-nix defaults to us)
              wayland.windowManager.hyprland.settings.input.kb_layout = "us";
              wayland.windowManager.hyprland.settings.input.kb_variant = "dvorak";

              # Capture full Hyprland logs to diagnose AMDGPU/SMU-induced renderer aborts
              wayland.windowManager.hyprland.settings.debug.disable_logs = false;

              # Omarchy's capture flow owns Print; only redirect where it saves.
              wayland.windowManager.hyprland.settings.env = [ "OMARCHY_SCREENSHOT_DIR,/home/mike/Downloads" ];

              # Managing this file here makes it read-only, so the omarchy-menu
              # Setup > Monitors editor cannot write to it anymore.
              xdg.configFile."hypr/monitors.lua".text = ''
                -- See https://wiki.hypr.land/Configuring/Basics/Monitors/
                -- List current monitors and supported resolutions with: hyprctl monitors all

                local omarchy_gdk_scale = 1
                local omarchy_monitor_scale = 1

                hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
                hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

                -- Scratchpad override: cover 90% of the screen instead of the default 50%.
                -- This file loads after default/hypr/qconsole.lua, so these handlers run
                -- after its fit() on the same events and the rule written here wins.
                local share = 0.9
                local covering = nil

                local function cover(bottom)
                  if covering == bottom then
                    return
                  end
                  covering = bottom

                  hl.workspace_rule({
                    workspace = "special:scratchpad",
                    gaps_in = 0,
                    gaps_out = { top = 0, right = 0, bottom = bottom, left = 0 },
                    no_border = true,
                    on_created_empty = "[workspace special:scratchpad silent] omarchy-agent",
                  })
                end

                local function fit()
                  local monitor = hl.get_active_monitor()
                  if not monitor or not monitor.scale or monitor.scale <= 0 then
                    return
                  end

                  local reserved = monitor.reserved
                  local usable = monitor.height / monitor.scale - reserved.top - reserved.bottom

                  cover(math.max(0, math.floor(usable * (1 - share))))
                end

                fit()
                hl.on("monitor.layout_changed", fit)
                hl.on("monitor.focused", fit)
              '';

              # Hyprwhspr speech-to-text keybinding
              wayland.windowManager.hyprland.extraConfig = ''
                bindd = SUPER ALT, D, Speech-to-text, exec, bash -c 'if [[ -f ~/.config/hyprwhspr/recording_status && $(cat ~/.config/hyprwhspr/recording_status) == "true" ]]; then echo stop > ~/.config/hyprwhspr/recording_control; else echo start > ~/.config/hyprwhspr/recording_control; fi'

                # Override voxtype stop to reset Elgato mic profile after (ready for next recording).
                # The sleep lets the stop beep finish first: killing the card profile mid-beep leaves
                # voxtype spinning on a dead output stream (100% CPU, millions of ALSA errors in the log).
                binddr = SUPER CTRL, X, Stop dictation, exec, bash -c 'voxtype record stop; sleep 1; for card in $(pactl list cards short 2>/dev/null | grep -i elgato | awk "{print \$2}"); do pactl set-card-profile "$card" off 2>/dev/null; sleep 0.1; pactl set-card-profile "$card" output:analog-stereo+input:mono-fallback 2>/dev/null; done'

                # Hard-recover the Wave:3 mic if its USB firmware hangs (-110); fix-wave3 lives in nixtop/config.nix
                bindd = SUPER CTRL, R, Fix Wave3 mic, exec, fix-wave3

                # Second workspace bank. Omarchy binds SUPER + 1..0 to workspaces
                # 1-10 and ships no more, so the function row drives 11-20 with the
                # same three actions. Pairs with omarchy.shell.workspace_count = 20.
                bindd = SUPER, F1, Switch to workspace 11, workspace, 11
                bindd = SUPER SHIFT, F1, Move window to workspace 11, movetoworkspace, 11
                bindd = SUPER SHIFT ALT, F1, Move window silently to workspace 11, movetoworkspacesilent, 11
                bindd = SUPER, F2, Switch to workspace 12, workspace, 12
                bindd = SUPER SHIFT, F2, Move window to workspace 12, movetoworkspace, 12
                bindd = SUPER SHIFT ALT, F2, Move window silently to workspace 12, movetoworkspacesilent, 12
                bindd = SUPER, F3, Switch to workspace 13, workspace, 13
                bindd = SUPER SHIFT, F3, Move window to workspace 13, movetoworkspace, 13
                bindd = SUPER SHIFT ALT, F3, Move window silently to workspace 13, movetoworkspacesilent, 13
                bindd = SUPER, F4, Switch to workspace 14, workspace, 14
                bindd = SUPER SHIFT, F4, Move window to workspace 14, movetoworkspace, 14
                bindd = SUPER SHIFT ALT, F4, Move window silently to workspace 14, movetoworkspacesilent, 14
                bindd = SUPER, F5, Switch to workspace 15, workspace, 15
                bindd = SUPER SHIFT, F5, Move window to workspace 15, movetoworkspace, 15
                bindd = SUPER SHIFT ALT, F5, Move window silently to workspace 15, movetoworkspacesilent, 15
                bindd = SUPER, F6, Switch to workspace 16, workspace, 16
                bindd = SUPER SHIFT, F6, Move window to workspace 16, movetoworkspace, 16
                bindd = SUPER SHIFT ALT, F6, Move window silently to workspace 16, movetoworkspacesilent, 16
                bindd = SUPER, F7, Switch to workspace 17, workspace, 17
                bindd = SUPER SHIFT, F7, Move window to workspace 17, movetoworkspace, 17
                bindd = SUPER SHIFT ALT, F7, Move window silently to workspace 17, movetoworkspacesilent, 17
                bindd = SUPER, F8, Switch to workspace 18, workspace, 18
                bindd = SUPER SHIFT, F8, Move window to workspace 18, movetoworkspace, 18
                bindd = SUPER SHIFT ALT, F8, Move window silently to workspace 18, movetoworkspacesilent, 18
                bindd = SUPER, F9, Switch to workspace 19, workspace, 19
                bindd = SUPER SHIFT, F9, Move window to workspace 19, movetoworkspace, 19
                bindd = SUPER SHIFT ALT, F9, Move window silently to workspace 19, movetoworkspacesilent, 19
                bindd = SUPER, F10, Switch to workspace 20, workspace, 20
                bindd = SUPER SHIFT, F10, Move window to workspace 20, movetoworkspace, 20
                bindd = SUPER SHIFT ALT, F10, Move window silently to workspace 20, movetoworkspacesilent, 20
              '';
            };
          };
        }
      ];
    };
    nixosConfigurations."proxnix" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; copyparty = inputs.copyparty; };
      modules = [
        nixosBase
        ./modules/nix-github-token.nix
        ./machines/proxnix/configuration.nix
        ./machines/proxnix/config.nix
        ./machines/proxnix/copyparty.nix
        ./machines/proxnix/samba.nix
        ./machines/proxnix/couchdb.nix
        ./machines/proxnix/minecraft.nix
        ./machines/proxnix/homepage.nix
        inputs.nix-minecraft.nixosModules.minecraft-servers
        { nixpkgs.overlays = [ inputs.nix-minecraft.overlay ]; }
        ./modules/openssh.nix
        ./modules/fail2ban.nix
        ./modules/linux/avahi.nix
        ./modules/automatic-nix-gc.nix
        { services.automatic-nix-gc.enable = true; }
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = { hostname = "proxnix"; inherit inputs; };
            users.${user} = {
              imports = [ ./modules/home-manager ];
            };
          };
        }
      ];
    };
    homeManagerConfigurations."piDSC" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages."aarch64-linux";
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ./modules/home-manager
        {
          home.stateVersion = "23.11";
        }
      ];
    };
  };
}
