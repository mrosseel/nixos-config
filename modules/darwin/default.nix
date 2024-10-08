{ pkgs, home-manager, ... }: {
  imports = [
    #./yabai.nix
    #./sketchybar.nix
    ./spacelauncher.nix
    ./flutter.nix
  ];

  # here go the darwin preferences and config items
  users.users.mike = {
        home = "/Users/mike";
        shell = pkgs.zsh;
        };
  #home = {
  #  username = "mike";
  #  homeDirectory = "/Users/mike";
  #};
  programs.zsh.enable = true;
  environment = {
    shells = with pkgs; [ bash zsh ];
    loginShell = pkgs.zsh;
    systemPackages = with pkgs; [ 
      coreutils
      xquartz
      trezor-agent
    ];
    #systemPath = [ "/opt/homebrew/bin" ];
    pathsToLink = [ "/Applications" ];
    variables.LANG = "en_US.UTF-8";
  };
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;
  security.pam.enableSudoTouchIdAuth = true;
  fonts.packages = [ (pkgs.nerdfonts.override { fonts = [ "Meslo" ]; }) ];
  services.nix-daemon.enable = true;
  system.defaults = {
    finder.AppleShowAllExtensions = true;
    finder._FXShowPosixPathInTitle = true;
    dock.autohide = false;
    NSGlobalDomain.AppleShowAllExtensions = true;
    NSGlobalDomain.InitialKeyRepeat = 14;
    NSGlobalDomain.KeyRepeat = 1;
  };
  # backwards compat; don't change
  system.stateVersion = 4;
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    onActivation.autoUpdate = false; 
    global.brewfile = true;
    casks = [ "raycast" "spacelauncher" ];
    #taps = [ "fujiapple852/trippy" ];
    brews = [ "trippy" ];
  };}
