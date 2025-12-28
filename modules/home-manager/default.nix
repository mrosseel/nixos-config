{ lib, pkgs, ... }: 

let
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = pkgs.stdenv.isLinux && builtins.pathExists "/etc/nixos";
in {
  # Don't change this when you change package input. Leave it alone.
  home.stateVersion = "23.11";
  imports = [
    ./tmux.nix
    ./git.nix
    ./kitty.nix
    ./astro.nix
    ./neovim.nix
    ./starship.nix
#    ./gc.nix
  ];
  # specify my home-manager configs
  home.packages = with pkgs; [
    ripgrep
    fd
    curl
    xh  # prettier curl
    less
    manix
    mc
    ncdu
    dua  # faster ncdu
    yazi # file manager
    tldr
    fastfetch
    jq
    xclip
    htop-vim
    wormhole-william
    dust # du alternative
    xsel # pbcopy alternative
    killall
    carapace # command options completion
    # lnav # log file navigator
  ];
  home.sessionVariables = {
    PAGER = "less";
    CLICLOLOR = 1;
    EDITOR = "nvim";
  };
  home.sessionPath = [
    "$HOME/.npm-packages/bin"
  ];
  home = {
    username = "mike";
  };
  programs.btop = {
    enable = lib.mkDefault true;
    settings = {
      color_theme = lib.mkDefault "gruvbox-dark-v2";
      vim_keys = lib.mkDefault true;
    };
  };
  #xdg.configFile.nvim = {
  #    source = ./nvim;
  #    recursive = true;
  #  };
  programs.bat.enable = true;
  programs.bat.config.theme = "TwoDark";
  programs.fzf.enable = true;
  programs.fzf.enableZshIntegration = true;
  programs.ssh.matchBlocks = {
    "*" = {
      addKeysToAgent = "yes";
      identityFile = [
        "~/.ssh/id_rsa"
        "~/.ssh/id_ed25519"
      ];
    };
  };

  # Optional: Also enable SSH agent through home-manager
  services.ssh-agent = lib.mkIf (!isDarwin) {
    enable = true;
  };
  programs.eza.enable = true;
  programs.zoxide.enable = true;
  programs.zoxide.enableZshIntegration = true;
  programs.zoxide.enableBashIntegration = true;
  programs.ripgrep.enable = true;
  programs.bash = {
    enable = true;
    shellAliases = {
      cd = "z";
    };
  };
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ls = "eza -a --icons=auto";
      ll = "eza -1 -l -a --icons=auto --group-directories-first ";
      nixswmac = "sudo darwin-rebuild switch --flake ~/nixos-config/.#";
      nixsw = "sudo nixos-rebuild switch --flake ~/nixos-config/.#";
      nixupmac = "pushd ~/nixos-config; nix flake update; nixswmac; popd";
      nixup = "pushd ~/nixos-config; nix flake update; nixsw; popd";
      cd = "z";
      cc = "SHELL=/bin/bash claude";
      # pbcopy="xclip -selection clipboard";
      # pbpaste="xclip -selection clipboard -o";
      neofetch="fastfetch";
    };
    initContent = ''
      #make sure brew is on the path for M1
      if [[ $(uname -m) == 'arm64' ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      # Fix fzf keybindings after zsh-vi-mode loads
      function zvm_after_init() {
        # Re-bind fzf keybindings that zsh-vi-mode overrides
        bindkey '^R' fzf-history-widget
      }
      '';
    plugins = [
      {
          name = "vi-mode";
          src = pkgs.zsh-vi-mode;
          file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
          # ZVM_INIT_MODE=sourcing;
      }
    ];
  };
  home.activation.setLoginShell = lib.mkForce "";
  # direnv loads and unloads shell.nix files when you cd in and out of dirs
  programs.direnv = {
    enable = true;
    enableZshIntegration = true; # see note on other shells below
    nix-direnv.enable = true;
  };
  # programs.alacritty = {
  #   enable = true;
  #   settings.font.normal.family = "MesloLGS Nerd Font Mono";
  #   settings.font.size = 16;
  # };
  home.file.".inputrc".source = ./dotfiles/inputrc;
}
