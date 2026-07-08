# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
	imports =
		[ # Include the results of the hardware scan.
		./hardware-configuration.nix
			./anki.nix
		];

# Bootloader.
	boot.loader.systemd-boot.enable = true;
	boot.loader.efi.canTouchEfiVariables = true;
	boot.loader.systemd-boot.configurationLimit = 5;

	networking.hostName = "nix270"; # Define your hostname.
# networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

# Configure network proxy if necessary
# networking.proxy.default = "http://user:password@proxy:port/";
# networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

# Enable networking
		networking.networkmanager.enable = true;

# omarchy-nix defaults NetworkManager to the iwd backend, which rejects valid
# Wi-Fi passwords on this hardware. Use the reliable wpa_supplicant backend.
		networking.networkmanager.wifi.backend = lib.mkForce "wpa_supplicant";
		networking.wireless.iwd.enable = lib.mkForce false;

# Set your time zone.
	time.timeZone = "Europe/Brussels";

# Select internationalisation properties.
	i18n.defaultLocale = "en_US.UTF-8";

# Desktop is provided by omarchy-nix (Hyprland/Wayland); GNOME/X11 disabled.

# Intel GPU hardware acceleration for Wayland.
	hardware.graphics = {
		enable = true;
		enable32Bit = true;
	};
	programs.xwayland.enable = true;

# Configure console keymap
	console.keyMap = "dvorak";

# Syncthing — devices/folders managed via the GUI/API (like nixtop), not
# declaratively. Used to sync ~/dev/3dprinting with nixtop.
	services.syncthing = {
		enable = true;
		user = "mike";
		dataDir = "/home/mike";
		configDir = "/home/mike/.config/syncthing";
		overrideDevices = false;
		overrideFolders = false;
	};

# Enable CUPS to print documents.
	services.printing.enable = true;

# Enable sound with pipewire.
	services.pulseaudio.enable = false;
	security.rtkit.enable = true;
	services.pipewire = {
		enable = true;
		alsa.enable = true;
		alsa.support32Bit = true;
		pulse.enable = true;
# If you want to use JACK applications, uncomment this
#jack.enable = true;

# use the example session manager (no others are packaged yet so this is enabled by default,
# no need to redefine it in your config for now)
#media-session.enable = true;
	};

# Enable touchpad support (enabled default in most desktopManager).
# services.xserver.libinput.enable = true;

# Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mike = {
    isNormalUser = true;
    description = "Mike";
    extraGroups = [ "networkmanager" "wheel" "video" "input" "render" ];
    shell = pkgs.nushell;
    ignoreShellProgramCheck = true;
  };

  # Passwordless sudo for wheel so nixtop can deploy here non-interactively
  # via `nixos-rebuild --target-host` (the remote steps run as nix-env /
  # switch-to-configuration, not nixos-rebuild, so a command-scoped rule
  # wouldn't cover them). Personal laptop; acceptable tradeoff.
  security.sudo.wheelNeedsPassword = false;

  # Create /bin/bash symlink for compatibility with Omarchy scripts
  # (many use #!/bin/bash).
  system.activationScripts.binbash = {
    deps = [ "binsh" ];
    text = ''
      ln -sf ${pkgs.bash}/bin/bash /bin/bash
    '';
  };

  # Allow unfree packages (handled in flake.nix)

  services.printing.drivers = with pkgs; [ hplip ];

  networking.firewall = {
    allowedTCPPorts = [ 631 ];
    allowedUDPPorts = [ 631 ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    claude-code  # lightweight; the heavy AI/GPU tooling (modules/ai.nix) stays off nix270
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}
