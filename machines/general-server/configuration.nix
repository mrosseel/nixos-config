{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  #boot.loader.grub.efiSupport = true;
  #boot.loader.grub.efiInstallAsRemovable = true;
  #boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.
  #boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "general-server"; # Define your hostname.
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" "2001:4860:4860::8888" ];

  # IPv6 configuration for Contabo VPS
  networking.interfaces.ens18.ipv6.addresses = [{
    address = "2a02:c207:2167:642::1";
    prefixLength = 64;
  }];
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "ens18";
  };
  environment.etc = {
    "resolv.conf".text = "nameserver 8.8.8.8\nnameserver 8.8.4.4";
  };
  #networking.hostName = "vmi1670642";
  #networking.domain = "contaboserver.net";
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.X11Forwarding = false;
    settings.PermitRootLogin = "no";
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvpuaWhiyWISrRYXtOpBLo6Fo/+NzZ0812RHlorSuNF mike.rosseel@gmail.com"
  ];
  users.users.mike.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvpuaWhiyWISrRYXtOpBLo6Fo/+NzZ0812RHlorSuNF mike.rosseel@gmail.com"
  ];

  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  services.postfix = {
    settings = {
      master = {
        smtp = {
          args = [ "-o" "smtp_helo_timeout=15" ];
        };
      };
      main = {
        inet_protocols = "all";
      };
    };
  };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  environment.systemPackages = with pkgs; [ gnumake gcc ];
  programs.zsh.enable = true;
  environment.shells = with pkgs; [ bash zsh ];
  users.groups.mike = {};
  users.users.mike = {
        home = "/home/mike";
        isNormalUser = true;  # Set to true for a regular user
        group = "mike";
        extraGroups = [ "wheel" ];  # Add the user to additional groups if needed, like 'wheel' for sudo access
        shell = pkgs.zsh;  # Set zsh as the default shell
        ignoreShellProgramCheck = true;
  };
  security.sudo.extraRules = [{
    users = [ "mike" ];
    commands = [
      { command = "/run/current-system/sw/bin/nix-store *"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/nix-env *"; options = [ "NOPASSWD" ]; }
      { command = "/nix/store/*/bin/switch-to-configuration *"; options = [ "NOPASSWD" ]; }
    ];
  }];

  system.stateVersion = "23.11"; # Did you read the comment?

}
