{ pkgs, home-manager, ... }: {
  imports = [
    #./yabai.nix
    #./sketchybar.nix
    ./flutter.nix
    # ./aerospace.nix
  ];

  # here go the darwin preferences and config items
  users.users.mike = {
        home = "/Users/mike";
        shell = pkgs.zsh;
        };
  programs.zsh.enable = true;
  programs.zsh.initContent = ''
    #make sure brew is on the path for M1 
    if [[ $(uname -m) == 'arm64' ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    '';
  environment = {
    shells = with pkgs; [ bash zsh ];
    systemPackages = with pkgs; [ 
      coreutils
      # xquartz
      trezor-agent
    ];
    #systemPath = [ "/opt/homebrew/bin" ];
    pathsToLink = [ "/Applications" ];
    variables.LANG = "en_US.UTF-8";
  };
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;
  security.pam.services.sudo_local.touchIdAuth = true;
  fonts.packages = [ pkgs.nerd-fonts.meslo-lg ];
  
  nix.enable = true;
  system.defaults = {
    finder.AppleShowAllExtensions = true;
    finder._FXShowPosixPathInTitle = true;
    dock.autohide = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
    loginwindow.GuestEnabled = false;
    NSGlobalDomain.AppleICUForce24HourTime = true;
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    # NSGlobalDomain.InitialKeyRepeat = 14;
    NSGlobalDomain.KeyRepeat = 2;
  };
  # backwards compat; don't change
  system.stateVersion = 4;
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    onActivation.autoUpdate = true; 
    onActivation.upgrade = true; 
    global.brewfile = true;
    casks = [ "raycast" ];
    #taps = [ "fujiapple852/trippy" ];
    brews = [ "trippy" ];
  };}
