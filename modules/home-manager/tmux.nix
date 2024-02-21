{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    shortcut = "a";
    baseIndex = 1;
    newSession = true;
    # Stop tmux+escape craziness.
    escapeTime = 0;
    # Force tmux to use /tmp for sockets (WSL2 compat)
    secureSocket = false;
    clock24 = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "tmux-256color";
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
            set -g @continuum-boot 'on'
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
      #bind r source-file ~/.config/tmux/tmux.conf

      #set-option -g status-position top

      # make Prefix p paste the buffer.
      #unbind p
      #bind p paste-buffer

      # Bind Keys
      # bind-key -T prefix C-g split-window \
      #   "$SHELL --login -i -c 'navi --print | head -c -1 | tmux load-buffer -b tmp - ; tmux paste-buffer -p -t {last} -b tmp -d'"
      # bind-key -T prefix C-l switch -t notes
      # bind-key -T prefix C-d switch -t dotfiles
      # bind-key e send-keys "tmux capture-pane -p -S - | nvim -c 'set buftype=nofile' +" Enter
    '';
  };
}
