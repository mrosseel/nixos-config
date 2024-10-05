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
  networking.nameservers = [ "8.8.8.8" ];
  environment.etc = {
    "resolv.conf".text = "nameserver 8.8.8.8\n";
  };
  #networking.hostName = "vmi1670642";
  #networking.domain = "contaboserver.net";
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.X11Forwarding = true;
    settings.PermitRootLogin = "yes";
  };
  users.users.root.openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local'' ];
  users.users.mike.openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCh8r6wZSXIWftEm6FvYVU0dk0lLo4yC5iw0gink9VCEyGEgS90D5T6s3CQb42HTssCoUdzRn0lv7fSfU4vPyEa6fAbAIIC0YYChP5y9uvttqo5GIjf/+OrpP79PF90/auKuaHUs41fjEYK7w2h6ZDY8+oQdDWvtGpjkG0PQBOC4GPLEwX95tBOZK3BsxnLXCMIdFrCrOb4RoJY45u1C8MtZZ5Zh4g6wzGz543LcX40kuprhgmqqskR7FkrZUL6Jch1GHQSQsK8O1RCcAivXWMilcrmGAvPUk+cR6oP6PAzt1jRbgEnoYxCjvo5AJHFXxg/Z+eSmx6y/x0mLOGItwi5 mike@Macintosh-2.local'' ];

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
    masterConfig = {
      smtp = {
        args = [ "-o" "smtp_helo_timeout=15" ];
      };
    };
    extraConfig = ''
      inet_protocols = ipv4
    '';
  };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  users.groups.mike = {};
  users.users.mike = {
        home = "/home/mike";
        isNormalUser = true;  # Set to true for a regular user
        group = "mike";
        extraGroups = [ "wheel" ];  # Add the user to additional groups if needed, like 'wheel' for sudo access
        shell = pkgs.zsh;  # Set zsh as the default shell
        ignoreShellProgramCheck = true;
  };
  system.stateVersion = "23.11"; # Did you read the comment?

}
