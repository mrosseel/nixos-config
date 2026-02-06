{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    # sensibleOnTop = true;
    baseIndex = 1;
    newSession = true;
    # Stop tmux+escape craziness.
    escapeTime = 0;
    # Force tmux to use /tmp for sockets (WSL2 compat)
    secureSocket = false;
    clock24 = true;
    terminal = "tmux-256color";
    shell = "${pkgs.nushell}/bin/nu";
    historyLimit = 100000;
    keyMode = "vi";
    mouse = true;
    plugins = with pkgs;
      [
        #tmux-nvim
        {
          plugin = tmuxPlugins.tmux-thumbs;
          extraConfig = ''
            set -g @thumbs-alphabet dvorak
          '';
        }
        tmuxPlugins.yank
        tmuxPlugins.sensible
        tmuxPlugins.catppuccin
        tmuxPlugins.vim-tmux-navigator
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
        {
          plugin = tmuxPlugins.dracula;
          extraConfig = ''
            set -g @dracula-show-powerline true
            set -g @dracula-plugins "weather"
            set -g @dracula-fixed-location "Ghent, Belgium"
            set -g @dracula-show-fahrenheit false
            set -g @dracula-show-flags true
            set -g @dracula-show-location false
            set -g @dracula-show-left-icon session
            set -g status-position top
          '';
        }
        tmuxPlugins.better-mouse-mode
      ];
    extraConfig = ''
      # Reduce status refresh rate (helps with weather API rate limiting)
      set -g status-interval 300

      # Change splits to match nvim and easier to remember
 
      # act like vim
      setw -g mode-keys vi
      bind-key h select-pane -L
      bind-key j select-pane -D
      bind-key k select-pane -U
      bind-key l select-pane -R     # Open new split at cwd of current split

      unbind %
      unbind '"'
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # Use vim keybindings in copy mode
      set-window-option -g mode-keys vi
      set-option -g set-titles on
      set-option -g set-titles-string "#S / #W"

      # v in copy mode starts making selection
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

      # Escape turns on copy mode
      bind Escape copy-mode

      # Easier reload of config
      bind r source-file ~/.config/tmux/tmux.conf

      # Swap windows left/right
      bind -r "<" swap-window -d -t -1
      bind -r ">" swap-window -d -t +1

      #set-option -g status-position top

      # make Prefix p paste the buffer.
      #unbind p
      #bind p paste-buffer

      # Ensure shells are started properly
      set -g default-command "${pkgs.nushell}/bin/nu"
      set -g default-shell "${pkgs.nushell}/bin/nu"
    '';
  };
}
