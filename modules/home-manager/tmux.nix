{ pkgs, lib, ... }:
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
      # Override omarchy C-Space prefix with C-a
      set -g prefix C-a
      set -g prefix2 None
      unbind C-b
      unbind C-Space
      bind C-a send-prefix

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

      # Copy mode extras
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind Escape copy-mode

      # Swap windows
      bind -r "<" swap-window -d -t -1
      bind -r ">" swap-window -d -t +1
    '';
  };
}
