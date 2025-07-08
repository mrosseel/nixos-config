{
  description = "Darwin system flake";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    omarchy-nix = {
      # url = "github:henrysipp/omarchy-nix";
      url = "github:mrosseel/omarchy-nix";
      # url = "path:/home/mike/dev/omarchy-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    # pifinder = {
    #   url = "/Users/mike/dev/business/pifinder.eu/website";  # or use a git URL if it's in a repository
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # sketchybar config
    sketchybar = {
      url = "github:FelixKratz/dotfiles";
      flake = false;
    };
  };

  outputs = inputs@{ self, home-manager, nix-darwin, nixpkgs, nixpkgs-stable, omarchy-nix, ...}:
  let
    nixpkgsConfig = {
      allowUnfree = true;
      allowUnsupportedSystem = false;
      vivaldi = {
        proprietaryCodecs = true;
        enableWideVine = true;
      };
    };
    overlays = with inputs; [
    ];
    user = "mike";
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
      system = "aarch64-darwin";
      specialArgs = { inherit inputs home-manager;};
      modules = [ 
        configuration
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs;};
            users.${user} = {
              imports = [ ./modules/home-manager ];
              programs.tmux = {
                enable = true;
                shortcut = "a";  # Set your custom shortcut here
              };
            };
          };
        }
        ./modules/darwin
        ./modules/python.nix
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
        ./machines/nix270/configuration.nix
        ./machines/nix270/hardware-configuration.nix
	./modules/default-browser.nix
	./modules/desktop.nix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {};
            users.${user} = {
              imports = [ ./modules/home-manager ];
              programs.tmux = {
                enable = true;
                shortcut = "a";  # Set your custom shortcut here
              };
            };
          };
        }
      ];
    };
    # work in progress - now with omarchy-nix
    nixosConfigurations."nixair" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
	{
	  nixpkgs.config = nixpkgsConfig;
	}
        ./machines/nixair/configuration.nix
        ./machines/nixair/hardware-configuration.nix
	./modules/default-browser.nix
	./modules/desktop.nix
	./modules/openssh.nix
	./modules/ai.nix
        omarchy-nix.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          # Configure omarchy
          omarchy = {
            full_name = "Mike Rosseel";
            email_address = "mike.rosseel@gmail.com";
            theme = "tokyo-night";
            scale = 1;
          };
          
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = {};
	    # stateVersion = "25.05";
            users.${user} = {
              imports = [ 
                ./modules/home-manager
                omarchy-nix.homeManagerModules.default
              ];
	      home.stateVersion = "23.11";
              programs.tmux = {
                enable = true;
                shortcut = "a";  # Set your custom shortcut here
              };
            };
          };
        }
      ];
    };
    nixosConfigurations."general-server" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        ./machines/general-server/configuration.nix
        ./machines/general-server/hardware-configuration.nix
        ./machines/general-server/caddy-service.nix
        ./machines/general-server/auto-update.nix
        ./machines/general-server/systemd.nix
        ./modules/simple-mail-server.nix
        ./modules/python.nix
	./modules/openssh.nix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {};
            users.${user} = {
              imports = [ ./modules/home-manager ];
              programs.tmux = {
                enable = true;
                shortcut = "b";  # Set your custom shortcut here
              };
            };
          };
        }
      ];
    };
    homeManagerConfigurations."piDSC" = home-manager.lib.homeManagerConfiguration {
      specialArgs = { inherit inputs; };
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages."aarch64-linux";
      modules = [
        configuration
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {};
            users.mike.imports = [ ./modules/home-manager ];
            users.pifinder.imports = [ ./modules/home-manager ];
          };
        }
        ];
    };
  };
}
