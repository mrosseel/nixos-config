# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];
  nix.settings.experimental-features = ["nix-command" "flakes"]; 
  boot.kernelParams = [ "radeon.cik_support=0" "amdgpu.cik_support=1" ];
  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "nixair"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Brussels";

  # Select internationalisation properties.
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

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  # services.displayManager.gdm.enable = true;
  # services.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  # services.xserver.xkb = {
  #   layout = "us";
  #   variant = "dvorak";
  # };


  # Configure console keymap
  console.keyMap = "dvorak";

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
  
  programs.zsh.enable = true;
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mike = {
    isNormalUser = true;
    description = "Mike Rosseel";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh ;
    packages = with pkgs; [
    #  thunderbird
    ];
  };
  programs.xwayland.enable = true;

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "mike";

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # for devenv caching
  nix.settings.trusted-users = [ "root" "mike" ];

  # List services that you want to enable:
  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.X11Forwarding = lib.mkForce true;
    settings.PermitRootLogin = lib.mkForce "yes";
  };
  users.users.root.openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local'' ];
  users.users.mike.openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local'' ];

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 24800 ]; # Barrier
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
