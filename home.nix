{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "mike";
  home.homeDirectory = "/home/mike";
 
  home.packages = [
    pkgs.fortune
    pkgs.vimPlugins.packer-nvim
    pkgs.gcc
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "23.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "Mike";
    userEmail = "mike.rosseel@gmail.com";
  };

  programs.zsh = {
   enable = true;
   enableAutosuggestions = true;
   enableCompletion = true;
   shellAliases = {
     ll = "ls -l";
     switch = "sudo nixos-rebuild switch";
     hswitch = "home-manager switch";
     hconf = "vi ~/nix-config/home.nix";
     conf = "sudo vi /etc/nixos/configuration.nix";
   };
   history = {
     size = 10000;
     path = "${config.xdg.dataHome}/zsh/history";
   };
   oh-my-zsh = {
     enable = true;
     plugins = [ "git" "colored-man-pages" "docker" "docker-compose" "fzf"];
     theme = "agnoster";
   };
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    plugins = with pkgs.vimPlugins; [
      packer-nvim
      vim-nix
      rose-pine
      harpoon
      lsp-zero-nvim
      nvim-cmp
    ];
  };

 programs.tmux = {
    enable = true;
    shortcut = "b";
    # aggressiveResize = true; -- Disabled to be iTerm-friendly
    baseIndex = 1;
    newSession = true;
    # Stop tmux+escape craziness.
    escapeTime = 0;
    # Force tmux to use /tmp for sockets (WSL2 compat)
    secureSocket = false;

    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.resurrect
      tmuxPlugins.continuum
      tmuxPlugins.catppuccin

    ];
 };
}
