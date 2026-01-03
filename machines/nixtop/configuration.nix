{ config, pkgs, ... }:

{
  imports = [
    ./disko-config.nix
  ];

  # Set the system platform
  nixpkgs.hostPlatform = "x86_64-linux";

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Bootloader - systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Latest kernel for Framework Desktop
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # AMD Ryzen AI 395 iGPU - Allocate 8GB VRAM (8192 MB)
  # Adjust value as needed: 2048 (2GB), 4096 (4GB), 8192 (8GB), 16384 (16GB)
  boot.kernelParams = [ "amdgpu.gttsize=8192" ];

  # zram swap - 5% of 128GB RAM (~6.4GB)
  zramSwap = {
    enable = true;
    memoryPercent = 5;
  };

  # Hostname
  networking.hostName = "nixtop";
  networking.networkmanager.enable = true;

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

  # Enable X11 and display manager (handled by omarchy)
  # services.xserver.enable = true;
  # services.displayManager.gdm.enable = true;

  # Keyboard layout (X11 config handled by omarchy)
  # services.xserver.xkb = {
  #   layout = "us";
  #   variant = "dvorak";
  # };
  console.keyMap = "dvorak";

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
    extraGroups = [ "networkmanager" "wheel" "video" "input" "render" ];
    shell = pkgs.zsh;
  };

  # Auto-login (handled by omarchy seamless_boot)
  # services.displayManager.autoLogin.enable = true;
  # services.displayManager.autoLogin.user = "mike";

  # Workaround for GNOME autologin
  # systemd.services."getty@tty1".enable = false;
  # systemd.services."autovt@tty1".enable = false;

  # Firefox
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # SSH configuration
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.X11Forwarding = true;
    settings.PermitRootLogin = "yes";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local"
  ];

  users.users.mike.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local"
  ];

  # Trusted users for devenv caching
  nix.settings.trusted-users = [ "root" "mike" ];

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

  # Firewall
  networking.firewall.allowedTCPPorts = [ 24800 ]; # Barrier

  # State version
  system.stateVersion = "25.05";
}
