{ lib, pkgs, hostname ? "", ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = pkgs.stdenv.isLinux && builtins.pathExists "/etc/nixos";
  isHyprland = builtins.elem hostname [ "nixtop" ];
  rsyncAliases = {
    "airelon" = {
      "2nixtop" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.nox' --exclude='.venv' ~/dev/ mike@nixtop:~/dev/ 2>/dev/null";
    };
    "nixtop" = {
      "2air" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.venv' ~/dev/ mike@airelon.local:~/dev/ 2>/dev/null";
      # 3D-printing sync with nix270 (manual rsync, additive — no --delete).
      "sync3d-to-nix270" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.venv' ~/dev/3dprinting/ mike@nix270.local:~/dev/3dprinting/ 2>/dev/null";
      "sync3d-from-nix270" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.venv' mike@nix270.local:~/dev/3dprinting/ ~/dev/3dprinting/ 2>/dev/null";
    };
    "nix270" = {
      # 3D-printing sync with nixtop (manual rsync, additive — no --delete).
      # nix270 only syncs this subdir, not all of ~/dev.
      "sync3d-to-nixtop" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.venv' ~/dev/3dprinting/ mike@nixtop.local:~/dev/3dprinting/ 2>/dev/null";
      "sync3d-from-nixtop" = "rsync -azhW --info=progress2 --exclude='.direnv' --exclude='.venv' mike@nixtop.local:~/dev/3dprinting/ ~/dev/3dprinting/ 2>/dev/null";
    };
  };
  nushellRsyncAliases = rsyncAliases.${hostname} or {};
  nushellRsyncConfig = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: cmd: "alias ${name} = ${cmd}") nushellRsyncAliases
  );
  isNixtop = hostname == "nixtop";
  # On nixtop, build omarchy-nix from the local dev checkout instead of the
  # upstream default in flake.nix. Applied only to the build (nixos-rebuild),
  # never to `nix flake update`: --override-input implies --no-write-lock-file,
  # so the local path stays out of the committed flake.lock.
  omarchyOverride = lib.optionalString isNixtop " --override-input omarchy-nix path:/home/mike/dev/omacom/omarchy-nix";
  hyprSessionAliases = lib.optionalAttrs isHyprland {
    hsave = "~/.local/bin/hypr-save-session";
    hrestore = "~/.local/bin/hypr-restore-session";
    hsave-work = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/work-session.json";
    hrestore-work = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/work-session.json";
    hsave-personal = "~/.local/bin/hypr-save-session -f ~/.local/share/hyprland-sessions/personal-session.json";
    hrestore-personal = "~/.local/bin/hypr-restore-session -f ~/.local/share/hyprland-sessions/personal-session.json";
  };
in {
  # Don't change this when you change package input. Leave it alone.
  home.stateVersion = "23.11";
  imports = [
    ./tmux.nix
    ./herdr.nix
    ./git.nix
    ./kitty.nix
    ./astro.nix
    ./neovim.nix
    ./starship.nix
    ./streamdeck.nix
    ./opencode.nix
    ./hunk.nix
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
    # yazi previewers. These otherwise only happen to be present because
    # omarchy pulls them in; declare them so previews don't break if it stops.
    poppler-utils # PDF
    ffmpegthumbnailer # video thumbnails
    imagemagick # SVG, HEIC and the wider image formats
    p7zip # archive contents
    exiftool # metadata pane
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
  # nvim config is managed directly as a git-tracked directory
  # (not via home-manager, which makes files read-only nix-store symlinks)
  # Symlink is created manually: ~/.config/nvim -> ~/nixos-config/config/nvim
  programs.bat.enable = true;
  programs.bat.config.theme = "TwoDark";
  programs.fzf.enable = true;
  programs.fzf.enableZshIntegration = true;
  # fzf 0.74's `--nushell` output still uses `str downcase` (deprecated in
  # nushell 0.114). Source a sed-patched copy ourselves instead so nushell
  # doesn't warn on every startup. Drop this once nixpkgs bumps fzf.
  programs.fzf.enableNushellIntegration = false;
  # atuin owns Ctrl-R for history search; drop fzf's competing Ctrl-R
  # auto-binding so home-manager doesn't warn about both claiming it.
  # fzf's file/dir widgets (Ctrl-T, Alt-C) stay enabled.
  programs.fzf.historyWidget.command = "";
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
    } // hyprSessionAliases;
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
      nixsw = "sudo nixos-rebuild switch --flake ~/nixos-config/.#${omarchyOverride}";
      nixupmac = "pushd ~/nixos-config; nix flake update; nixswmac; popd";
      nixup = "pushd ~/nixos-config; nix flake update; nixsw; popd";
      cd = "z";
      clc = "NODE_OPTIONS=--max-old-space-size=8192 SHELL=/bin/bash claude";
      clcd = "NODE_OPTIONS=--max-old-space-size=8192 SHELL=/bin/bash claude --dangerously-skip-permissions";
      # pbcopy="xclip -selection clipboard";
      # pbpaste="xclip -selection clipboard -o";
      neofetch="fastfetch";
    } // hyprSessionAliases // (rsyncAliases.${hostname} or {});
    initContent = ''
      # Silence zoxide's "init should be at the end" doctor warning.
      # We can't actually move it past the home-manager-injected
      # syntaxHighlighting source without disabling zoxide's
      # enableZshIntegration and re-adding the eval line manually here,
      # which is fragile across HM updates. The warning is benign — the
      # syntax-highlighting plugin doesn't interfere with zoxide.
      export _ZO_DOCTOR=0

      # Multiplexer servers (herdr, tmux) get re-parented to systemd and keep
      # whatever environment they were first started with. Panes opened later
      # therefore have no Wayland/X11 handles, and anything graphical silently
      # drops to its worst backend: vlc renders through libcaca, yazi previews
      # through chafa. Re-derive the session handles from the runtime dir.
      if [[ -z "$WAYLAND_DISPLAY" && -z "$DISPLAY" ]]; then
        _xdg_rt="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
        for _sock in "$_xdg_rt"/wayland-<->(Nom[1]); do
          export WAYLAND_DISPLAY="''${_sock:t}"
          export XDG_SESSION_TYPE=wayland
        done
        for _hypr in "$_xdg_rt"/hypr/*(N/om[1]); do
          export HYPRLAND_INSTANCE_SIGNATURE="''${_hypr:t}"
        done
        [[ -S /tmp/.X11-unix/X0 ]] && export DISPLAY=:0
        unset _xdg_rt _sock _hypr
      fi

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
      nixsw = "sudo nixos-rebuild switch --flake ~/nixos-config/.#${omarchyOverride}";
      nixswmac = "sudo darwin-rebuild switch --flake ~/nixos-config/.#";
    } // hyprSessionAliases;
    extraConfig = lib.mkAfter ''
      # fzf nushell integration, patched for the `str downcase` deprecation.
      source ${pkgs.runCommand "fzf-nushell-integration.nu" {} ''
        ${pkgs.fzf}/bin/fzf --nushell | ${pkgs.gnused}/bin/sed 's/str downcase/str lowercase/g' > $out
      ''}

      # zoxide with --cmd cd: replaces builtin cd with zoxide-powered cd
      source ${pkgs.runCommand "zoxide-nushell-cmd-cd" {} ''
        ${pkgs.zoxide}/bin/zoxide init nushell --cmd cd > $out
      ''}

      # Functions that need def instead of alias
      def nixup [] {
        cd ~/nixos-config
        nix flake update
        sudo nixos-rebuild switch --flake ~/nixos-config/.#${omarchyOverride}
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

      # nix-darwin exports the nix profile dirs from /etc/zshenv + /etc/bashrc,
      # which nushell never sources -- so on Darwin nushell starts without the
      # home-manager profile on PATH (no zoxide, eza, fzf, ...). NixOS inherits
      # a correct PATH from the session, so this is Darwin-only by design.
      if $nu.os-info.name == "macos" {
        $env.PATH = ($env.PATH | split row (char esep) | prepend [
          $"($env.HOME)/.nix-profile/bin"
          $"/etc/profiles/per-user/($env.USER)/bin"
          "/run/current-system/sw/bin"
          "/nix/var/nix/profiles/default/bin"
        ] | uniq)
      }

      # Homebrew setup for M1 Macs
      if $nu.os-info.name == "macos" and $nu.os-info.arch == "aarch64" {
        $env.PATH = ($env.PATH | split row (char esep) | prepend "/opt/homebrew/bin")
      }

      # Multiplexer servers (herdr, tmux) get re-parented to systemd and keep
      # whatever environment they were first started with. Panes opened later
      # therefore have no Wayland/X11 handles, and anything graphical silently
      # drops to its worst backend: vlc renders through libcaca, yazi previews
      # through chafa. Re-derive the session handles from the runtime dir.
      if (($env.WAYLAND_DISPLAY? | is-empty) and ($env.DISPLAY? | is-empty)) {
        let rt = ($env.XDG_RUNTIME_DIR? | default "/run/user/1000")
        let socks = (glob $"($rt)/wayland-[0-9]*" --no-dir
          | where {|p| not ($p | str ends-with ".lock") } | sort)
        if not ($socks | is-empty) {
          $env.WAYLAND_DISPLAY = ($socks | first | path basename)
          $env.XDG_SESSION_TYPE = "wayland"
        }
        let hypr = (glob $"($rt)/hypr/*" --no-file | sort)
        if not ($hypr | is-empty) {
          $env.HYPRLAND_INSTANCE_SIGNATURE = ($hypr | first | path basename)
        }
        if ("/tmp/.X11-unix/X0" | path exists) { $env.DISPLAY = ":0" }
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
    flags = [ "--disable-up-arrow" ];  # up = plain shell history, ctrl-r = atuin
    settings = {
      style = "compact";
      search_mode = "fuzzy";
      filter_mode = "directory";  # default scope: commands run in current dir
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
  home.file.".local/bin/hypr-save-session" = lib.mkIf isHyprland {
    source = ./scripts/hypr-save-session.sh;
    executable = true;
  };
  home.file.".local/bin/hypr-restore-session" = lib.mkIf isHyprland {
    source = ./scripts/hypr-restore-session.sh;
    executable = true;
  };
}
