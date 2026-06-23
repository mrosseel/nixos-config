{ pkgs, lib, hostname ? "", ... }:
let
  # Workstations I sit at use C-a; anything I SSH into (servers, the Pi)
  # keeps the default C-b so a single C-a/C-b chord never collides across hops.
  mainMachines = [ "nixtop" "airelon" "nix270" "nixair" ];
  isMain = builtins.elem hostname mainMachines;
  prefixKey = if isMain then "C-a" else "C-b";
in
{
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    newSession = true;
    escapeTime = 0;
    secureSocket = false;
    clock24 = true;
    terminal = "tmux-256color";
    shell = "${pkgs.nushell}/bin/nu";
    historyLimit = 100000;
    keyMode = "vi";
    mouse = true;
    plugins = with pkgs;
      [
        {
          plugin = tmuxPlugins.tmux-thumbs;
          extraConfig = ''
            set -g @thumbs-alphabet dvorak
          '';
        }
        tmuxPlugins.yank
        tmuxPlugins.sensible
        {
          plugin = tmuxPlugins.resurrect;
          extraConfig = ''
            set -g @resurrect-strategy-vim 'session'
            set -g @resurrect-strategy-nvim 'session'
            set -g @resurrect-capture-pane-contents 'on'
          '';
        }
        {
          plugin = tmuxPlugins.continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
            set -g @continuum-boot 'off'
            set -g @continuum-save-interval '10'
          '';
        }
        tmuxPlugins.better-mouse-mode
      ];
    extraConfig = lib.mkAfter ''
      # Prefix: C-a on main machines, C-b on SSH targets (see mainMachines above).
      # Override omarchy's C-Space prefix either way.
      set -g prefix ${prefixKey}
      set -g prefix2 None
      unbind C-Space
      bind ${prefixKey} send-prefix
      ${lib.optionalString isMain "unbind C-b"}

      # Nushell
      set -g default-command "${pkgs.nushell}/bin/nu"
      set -g default-shell "${pkgs.nushell}/bin/nu"

      # Titles
      set-option -g set-titles on
      set-option -g set-titles-string "#S / #W"

      # Vim-style pane nav (Alt+hjkl, prefix+l stays as last-window)
      bind-key M-h select-pane -L
      bind-key M-j select-pane -D
      bind-key M-k select-pane -U
      bind-key M-l select-pane -R

      # Split with | and - (in addition to omarchy's h/v)
      unbind %
      unbind '"'
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # Hand plain-byte keys to apps instead of the csi-u enhanced protocol.
      # Avoids per-character escape sequences corrupting fast paste/dictation.
      set -g extended-keys off

      # Copy mode extras
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind Escape copy-mode

      # Swap windows
      bind -r "<" swap-window -d -t -1
      bind -r ">" swap-window -d -t +1
    '';
  };
}
