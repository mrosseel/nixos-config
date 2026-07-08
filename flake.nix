{
  description = "Darwin system flake";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    # Main package set tracks nixpkgs-unstable (rolls fast, matches HM master).
    # When a specific package breaks here, override it from nixpkgs-vetted
    # (nixos-unstable: same channel, slower-vetted via Hydra) via an overlay.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-vetted.url = "github:NixOS/nixpkgs/nixos-unstable";
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

    claude-code.url = "github:sadjow/claude-code-nix";
    codex-cli-nix.url = "github:sadjow/codex-cli-nix";

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
        "ventoy-1.1.12"
        "electron-39.8.10"
      ];
      vivaldi = {
        proprietaryCodecs = true;
        enableWideVine = true;
      };
    };
    overlays = with inputs; [
      claude-code.overlays.default
      (import ./overlays/brave.nix)
    ];
    user = "mike";
    # Shared bits applied to every NixOS host (Darwin uses `configuration` below).
    nixosBase = {
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      # Trust the wheel group so closures built on another host (e.g. nixtop)
      # can be pushed here via `nixos-rebuild --target-host` without signing.
      nix.settings.trusted-users = [ "root" "@wheel" ];
      # Pull prebuilt binaries for flake-sourced packages that cache.nixos.org
      # doesn't have. Hyprland (+ its ecosystem) comes from the hyprland flake,
      # not nixpkgs, so without hyprland.cachix.org the whole stack compiles
      # locally on every bump. nix-community covers other common flake outputs.
      # These append to the default cache.nixos.org (extra-*, not a replacement).
      nix.settings.extra-substituters = [
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
      ];
      nix.settings.extra-trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzJ6jXYv+S+rfAoja0iy6vGm7A="
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
        # grower CLI for ad-hoc disk-growth checks. No scheduling on macOS —
        # run `grower scan` / `grower diff` by hand. Default scans the home
        # dir (no sudo/firmlink issues); `sudo grower scan --root /` does the
        # whole machine, and the excludes below already cover APFS firmlinks.
        ({ pkgs, inputs, ... }: {
          nixpkgs.overlays = [ inputs.grower.overlays.default ];
          environment.systemPackages = [ pkgs.grower ];
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
            terminal = "foot";
            seamless_boot = {
              enable = true;
              username = "mike";
            };
          };

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = { hostname = "nix270"; };
            users.${user} = {
              imports = [
                ./modules/home-manager
                omarchy-nix.homeManagerModules.default
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
            extraSpecialArgs = { hostname = "nixair"; };
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
        ./machines/general-server/phpfpm-joeri.nix
        ./machines/general-server/attic-service.nix
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
            extraSpecialArgs = { hostname = "general-server"; };
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
            terminal = "foot";
            seamless_boot = {
              enable = true;
              username = "mike";
            };
            voxtype.enable = true;
          };

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = { hostname = "nixtop"; };
            users.${user} = {
              imports = [
                ./modules/home-manager
                omarchy-nix.homeManagerModules.default
              ];

              # Override keyboard layout to Dvorak (omarchy-nix defaults to us)
              wayland.windowManager.hyprland.settings.input.kb_layout = "us";
              wayland.windowManager.hyprland.settings.input.kb_variant = "dvorak";

              # Capture full Hyprland logs to diagnose AMDGPU/SMU-induced renderer aborts
              wayland.windowManager.hyprland.settings.debug.disable_logs = false;

              # Hyprwhspr speech-to-text keybinding
              wayland.windowManager.hyprland.extraConfig = ''
                bindd = SUPER ALT, D, Speech-to-text, exec, bash -c 'if [[ -f ~/.config/hyprwhspr/recording_status && $(cat ~/.config/hyprwhspr/recording_status) == "true" ]]; then echo stop > ~/.config/hyprwhspr/recording_control; else echo start > ~/.config/hyprwhspr/recording_control; fi'

                # Override voxtype stop to reset Elgato mic profile after (ready for next recording)
                binddr = SUPER CTRL, X, Stop dictation, exec, bash -c 'voxtype record stop; for card in $(pactl list cards short 2>/dev/null | grep -i elgato | awk "{print \$2}"); do pactl set-card-profile "$card" off 2>/dev/null; sleep 0.1; pactl set-card-profile "$card" output:analog-stereo+input:mono-fallback 2>/dev/null; done'

                # Hard-recover the Wave:3 mic if its USB firmware hangs (-110); fix-wave3 lives in nixtop/config.nix
                bindd = SUPER CTRL, R, Fix Wave3 mic, exec, fix-wave3

                # Screenshots: save to file + copy to clipboard
                bindd = , Print, Screenshot region, exec, bash -c 'FILE=/home/mike/Downloads/screenshot-$(date +%Y%m%d-%H%M%S).png; grim -g "$(slurp)" - | tee "$FILE" | wl-copy -t image/png'
                bindd = SUPER, Print, Screenshot full screen, exec, bash -c 'FILE=/home/mike/Downloads/screenshot-$(date +%Y%m%d-%H%M%S).png; grim - | tee "$FILE" | wl-copy -t image/png'
              '';

              # Thunderbird email client
              programs.thunderbird = {
                enable = true;
                profiles = {
                  default = {
                    isDefault = true;
                  };
                };
              };

              # Email accounts for Thunderbird
              accounts.email = {
                accounts = {
                  pifinder = {
                    primary = true;
                    address = "info@pifinder.eu";
                    realName = "Mike Rosseel";
                    userName = "info@pifinder.eu";

                    imap = {
                      host = "mail.pifinder.eu";
                      port = 993;
                      tls = {
                        enable = true;
                        useStartTls = false;
                      };
                    };

                    smtp = {
                      host = "mail.pifinder.eu";
                      port = 465;
                      tls = {
                        enable = true;
                        useStartTls = false;
                      };
                    };

                    thunderbird = {
                      enable = true;
                      profiles = [ "default" ];
                    };
                  };

                  hackerspace = {
                    address = "board@hackerspace.gent";
                    realName = "Hackerspace.gent board";
                    userName = "board@hackerspace.gent";

                    imap = {
                      host = "mail.openminds.be";
                      port = 993;
                      tls = {
                        enable = true;
                        useStartTls = false;
                      };
                    };

                    smtp = {
                      host = "mail.openminds.be";
                      port = 587;
                      tls = {
                        enable = true;
                        useStartTls = true;
                      };
                    };

                    thunderbird = {
                      enable = true;
                      profiles = [ "default" ];
                    };
                  };
                };
              };
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
            extraSpecialArgs = { hostname = "proxnix"; };
            users.${user} = {
              imports = [ ./modules/home-manager ];
            };
          };
        }
      ];
    };
    homeManagerConfigurations."piDSC" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages."aarch64-linux";
      modules = [
        ./modules/home-manager
        {
          home.stateVersion = "23.11";
        }
      ];
    };
  };
}
