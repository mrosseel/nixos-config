{
  description = "Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.11";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    # Manages configs links things into your home directory
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # sketchybar config
    sketchybar = {
      url = "github:FelixKratz/dotfiles";
      flake = false;
    };
  };

  outputs = inputs@{ self, home-manager, nix-darwin, nixpkgs, nixpkgs-stable, ...}:
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
      services.nix-daemon.enable = true;

      nix = {
        # enable flakes per default
        package = pkgs.nixFlakes;
        settings = {
          allowed-users = [ user ];
          experimental-features = [ "nix-command" "flakes" ];
        };
        # pin the flake registry https://yusef.napora.org/blog/pinning-nixpkgs-flake/
        registry.nixpkgs.flake = nixpkgs-stable;
      };
      nixpkgs.config = nixpkgsConfig;
      nixpkgs.overlays = overlays;

      # Create /etc/zshrc that loads the nix-darwin environment.
      programs.zsh.enable = true; 
      # programs.fish.enable = true;

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
            users.${user}.imports = [ ./modules/home-manager ];
          };
        }
        ./modules/darwin
        ];
    };
    # Expose the package set, including overlays, for convenience.
    #darwinPackages = self.darwinConfigurations."airelon".pkgs;

    nixosConfigurations."nix270" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        ./machines/nix270/configuration.nix
        ./machines/nix270/hardware-configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {};
            users.mike.imports = [ ./modules/home-manager ];
          };
        }
      ];
    };
    nixosConfigurations.general-server = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        home-manager.nixosModules.home-manager
        ./machines/general-server/configuration.nix
        ./machines/general-server/hardware-configuration.nix
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {};
            users.mike.imports = [ ./modules/home-manager ];
          };
        }
      ];
    };
    homeConfigurations."pifinder" = home-manager.lib.homeManagerConfiguration {
        specialArgs = { inherit inputs; };
        pkgs = nixpkgs.legacyPackages."aarch6 -linux";
        defaultPackage."aarch64-linux" = home-manager.defaultPackage."aarch64-linux";
        modules = [
          ./modules/home-manager
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
