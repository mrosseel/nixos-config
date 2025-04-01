{ pkgs, ... }: {
  # Don't change this when you change package input. Leave it alone.
  home.stateVersion = "23.11";
  imports = [
    ./tmux.nix
    ./git.nix
    ./kitty.nix
    ./astro.nix
    ./neovim.nix
#    ./gc.nix
  ];
  # specify my home-manager configs
  home.packages = with pkgs; [
    ripgrep
    fd
    curl
    less
    manix
    mc
    ncdu
    tldr
    fastfetch
    jq
    xclip
    htop-vim
    wormhole-william
    dust # du alternative
    # lnav # log file navigator
  ];
  home.sessionVariables = {
    PAGER = "less";
    CLICLOLOR = 1;
    EDITOR = "neovim";
  };
  home = {
    username = "mike";
  };
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "gruvbox-dark-v2";
      vim_keys = true;
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
  programs.eza.enable = true;
  programs.zoxide.enable = true;
  programs.zoxide.enableZshIntegration = true;
  programs.ripgrep.enable = true;
  programs.bash.enable = true;
  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.zsh.autosuggestion.enable = true;
  programs.zsh.syntaxHighlighting.enable = true;
  programs.zsh.shellAliases = {
    ls = "eza -a --icons=auto";
    ll = "eza -1 -l -a --icons=auto";
    nixswmac = "darwin-rebuild switch --flake ~/nixos-config/.#";
    nixsw = "sudo nixos-rebuild switch --flake ~/nixos-config/.#";
    nixupmac = "pushd ~/nixos-config; nix flake update; nixswmac; popd";
    nixup = "pushd ~/nixos-config; nix flake update; nixsw; popd";
    cd = "z";
    # pbcopy="xclip -selection clipboard";
    # pbpaste="xclip -selection clipboard -o";
    neofetch="fastfetch";
  };
  programs.zsh.initExtra = ''
    #make sure brew is on the path for M1 
    if [[ $(uname -m) == 'arm64' ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    '';
  programs.starship.enable = true;
  programs.starship.enableZshIntegration = true;
  programs.starship.settings = {
    add_newline = false;
    format = "$character";  # A minimal left prompt
    # move the rest of the prompt to the right
    right_format = "$shlvl$shell$username$hostname$nix_shell$git_branch$git_commit$git_state$git_status$directory$jobs$cmd_duration";
    shlvl = {
      disabled = false;
      symbol = "ﰬ";
      style = "bright-red bold";
      threshold = 2;
      # repeat_offset = 2;
    };
    shell = {
      disabled = false;
      format = "$indicator";
      fish_indicator = "";
      bash_indicator = "[BASH](bright-white) ";
      zsh_indicator = "";
    };
    username = {
      style_user = "bright-white bold";
      style_root = "bright-red bold";
    };
    hostname = {
      style = "bright-green bold";
      ssh_only = true;
    };
    nix_shell = {
      symbol = "";
      format = "[$symbol$name]($style) ";
      style = "bright-purple bold";
      heuristic = true;
    };
    git_branch = {
      only_attached = true;
      format = "[$symbol$branch]($style) ";
      style = "bright-yellow bold";
    };
    git_commit = {
      only_detached = true;
      format = "[ﰖ$hash]($style) ";
      style = "bright-yellow bold";
    };
    git_state = {
      style = "bright-purple bold";
    };
    git_status = {
      style = "bright-green bold";
    };
    directory = {
      read_only = " ";
      truncation_length = 0;
    };
    #cmd_duration = {
    #  format = "[$duration]($style) ";
    #  style = "bright-blue";
    #};
    jobs = {
      style = "bright-green bold";
    };
    character = {
      success_symbol = "[\\$](bright-green bold)";
      error_symbol = "[\\$](bright-red bold)";
    };
  };
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
