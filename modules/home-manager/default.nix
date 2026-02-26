{ lib, pkgs, hostname ? "", ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = pkgs.stdenv.isLinux && builtins.pathExists "/etc/nixos";
  rsyncAliases = {
    "airelon" = {
      "2nixtop" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.nox' --exclude='.venv' ~/dev/ mike@nixtop:~/dev/ 2>/dev/null";
    };
    "nixtop" = {
      "2air" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.venv' ~/dev/ mike@airelon.local:~/dev/ 2>/dev/null";
    };
  };
  nushellRsyncAliases = rsyncAliases.${hostname} or {};
  nushellRsyncConfig = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: cmd: "alias ${name} = ${cmd}") nushellRsyncAliases
  );
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
    ./streamdeck.nix
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
    poppler-utils # PDF preview for yazi
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
    mosh
    # lnav # log file navigator
  ] ++ lib.optionals (!isDarwin) [
    nh # nix helper - better UX for nix commands (Linux/NixOS only)
  ];
  home.sessionVariables = {
    PAGER = "less";
    CLICLOLOR = 1;
    EDITOR = "nvim";
  };
  home.sessionPath = [
    "$HOME/.npm-packages/bin"
    "$HOME/.local/bin"
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
  xdg.configFile.nvim = {
    source = ../../config/nvim;
    recursive = true;
  };
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
    "airelon airelon.local" = {
      hostname = "airelon.local";
      setEnv = {
        TERM = "xterm-256color";
      };
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
  programs.zoxide.enableNushellIntegration = false;
  programs.ripgrep.enable = true;
  programs.bash = {
    enable = true;
    shellAliases = {
      cd = "z";
      # Hyprland session management
      hsave = "~/.local/bin/hypr-save-session";
      hrestore = "~/.local/bin/hypr-restore-session";
      hsave-work = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/work-session.json";
      hrestore-work = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/work-session.json";
      hsave-personal = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/personal-session.json";
      hrestore-personal = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/personal-session.json";
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
      clc = "NODE_OPTIONS=--max-old-space-size=8192 SHELL=/bin/bash claude";
      clcd = "NODE_OPTIONS=--max-old-space-size=8192 SHELL=/bin/bash claude --dangerously-skip-permissions";
      # pbcopy="xclip -selection clipboard";
      # pbpaste="xclip -selection clipboard -o";
      neofetch="fastfetch";
      # Hyprland session management
      hsave = "~/.local/bin/hypr-save-session";
      hrestore = "~/.local/bin/hypr-restore-session";
      hsave-work = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/work-session.json";
      hrestore-work = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/work-session.json";
      hsave-personal = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/personal-session.json";
      hrestore-personal = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/personal-session.json";
    } // (rsyncAliases.${hostname} or {});
    initContent = ''
      #make sure brew is on the path for M1
      if [[ $(uname -m) == 'arm64' ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      # Invert terminal colors when SSHed into airelon
      if [[ -n "$SSH_CONNECTION" && "$(hostname)" == "airelon" ]]; then
        printf '\e[?5h'  # Enable reverse video mode
        trap 'printf "\e[?5l"' EXIT  # Restore on exit
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

  # Nushell configuration
  programs.nushell = {
    enable = true;
    settings = {
      show_banner = false;
      edit_mode = "vi";
      cursor_shape = {
        vi_insert = "line";
        vi_normal = "block";
      };
      completions = {
        algorithm = "fuzzy";
      };
      history = {
        file_format = "sqlite";
      };
    };
    shellAliases = {
      ls = "eza -a --icons=auto";
      ll = "eza -1 -l -a --icons=auto --group-directories-first";
      neofetch = "fastfetch";
      nixsw = "sudo nixos-rebuild switch --flake ~/nixos-config/.#";
      nixswmac = "sudo darwin-rebuild switch --flake ~/nixos-config/.#";
      hsave = "~/.local/bin/hypr-save-session";
      hrestore = "~/.local/bin/hypr-restore-session";
      hsave-work = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/work-session.json";
      hrestore-work = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/work-session.json";
      hsave-personal = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/personal-session.json";
      hrestore-personal = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/personal-session.json";
    };
    extraConfig = lib.mkAfter ''
      # zoxide with --cmd cd: replaces builtin cd with zoxide-powered cd
      source ${pkgs.runCommand "zoxide-nushell-cmd-cd" {} ''
        ${pkgs.zoxide}/bin/zoxide init nushell --cmd cd > $out
      ''}

      # Functions that need def instead of alias
      def nixup [] {
        cd ~/nixos-config
        nix flake update
        sudo nixos-rebuild switch --flake ~/nixos-config/.#
      }

      def nixupmac [] {
        cd ~/nixos-config
        nix flake update
        sudo darwin-rebuild switch --flake ~/nixos-config/.#
      }

      def --wrapped clc [...args] {
        with-env { SHELL: "/bin/bash", NODE_OPTIONS: "--max-old-space-size=8192", LD_LIBRARY_PATH: "" } { claude ...$args }
      }

      def --wrapped clcd [...args] {
        with-env { SHELL: "/bin/bash", NODE_OPTIONS: "--max-old-space-size=8192", LD_LIBRARY_PATH: "" } { claude --dangerously-skip-permissions ...$args }
      }

      ${nushellRsyncConfig}
    '';
    environmentVariables = {
      PAGER = "less";
      CLICOLOR = "1";
      EDITOR = "nvim";
    };
    extraEnv = ''
      # Add to PATH
      $env.PATH = ($env.PATH | split row (char esep) | prepend $"($env.HOME)/.npm-packages/bin" | prepend $"($env.HOME)/.local/bin")

      # Homebrew setup for M1 Macs
      if (sys host | get name) == "Darwin" and ((sys host | get arch) == "aarch64") {
        $env.PATH = ($env.PATH | split row (char esep) | prepend "/opt/homebrew/bin")
      }

      # Vi mode indicators (empty - let starship handle it)
      $env.PROMPT_INDICATOR_VI_INSERT = ""
      $env.PROMPT_INDICATOR_VI_NORMAL = ""
    '';
  };

  # Carapace for enhanced completions
  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };

  # Atuin for history search (replaces fzf Ctrl+R)
  programs.atuin = {
    enable = true;
    enableNushellIntegration = true;
    enableZshIntegration = true;
    settings = {
      style = "compact";
      search_mode = "fuzzy";
    };
  };

  # direnv loads and unloads shell.nix files when you cd in and out of dirs
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
    nix-direnv.enable = true;
  };

  # Zellij terminal multiplexer
  programs.zellij = {
    enable = true;
    settings = {
      default_shell = "nu";
      pane_frames = false;
      default_layout = "default";
      default_mode = "normal";
      mouse_mode = true;
      copy_on_select = true;
      scrollback_editor = "nvim";
      themes.tokyo-night = {
        fg = "#c0caf5";
        bg = "#1a1b26";
        black = "#15161e";
        red = "#f7768e";
        green = "#9ece6a";
        yellow = "#e0af68";
        blue = "#7aa2f7";
        magenta = "#bb9af7";
        cyan = "#7dcfff";
        white = "#a9b1d6";
        orange = "#ff9e64";
      };
      theme = "tokyo-night";
    };
  };

  home.file.".inputrc".source = ./dotfiles/inputrc;
}
