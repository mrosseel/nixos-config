{ pkgs, home-manager, ... }: {
  imports = [
    #./yabai.nix
    #./sketchybar.nix
    ./flutter.nix
    ./aerospace.nix
  ];

  # here go the darwin preferences and config items
  users.users.mike = {
        home = "/Users/mike";
        shell = pkgs.zsh;
        };
  system.primaryUser = "mike";
  programs.zsh.enable = true;
  environment = {
    shells = with pkgs; [ bash zsh ];
    systemPackages = with pkgs; [
      coreutils
      # xquartz
      # trezor-agent  # Broken: trezor 0.13.10 requires click<8.2, nixpkgs has 8.2.1
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
    loginwindow.GuestEnabled = false;
    CustomUserPreferences = {
      NSGlobalDomain."com.apple.mouse.linear" = false;
    };
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      ApplePressAndHoldEnabled = false;
      AppleShowAllExtensions = true;
      AppleICUForce24HourTime = true;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticWindowAnimationsEnabled = false;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSNavPanelExpandedStateForSaveMode = true;
      PMPrintingExpandedStateForPrint = true;
    };
    LaunchServices = {
      LSQuarantine = false;
    };
    trackpad = {
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
      Clicking = true;
    };
    finder = {
      AppleShowAllFiles = true;
      CreateDesktop = false;
      FXDefaultSearchScope = "SCcf";
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv";
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
      _FXSortFoldersFirst = true;
    };
    dock = {
      autohide = true;
      expose-animation-duration = 0.15;
      show-recents = false;
      showhidden = true;
      persistent-apps = [];
      tilesize = 30;
      # wvous-bl-corner = 1;
      # wvous-br-corner = 1;
      # wvous-tl-corner = 1;
      # wvous-tr-corner = 1;
    };
    screencapture = {
      location = "/Users/mike/Downloads/temp";
      type = "png";
      disable-shadow = true;
      };

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
