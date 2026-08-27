{ pkgs, lib, ... }:

let
  nuPath = lib.getExe pkgs.nushell;
in
{
  # Better terminal, with good rendering.
  programs.kitty = {
    enable = true;
    # Colors come from the omarchy theme (omarchy-nix includes
    # ~/.local/state/omarchy/current/theme/kitty.conf). Setting themeFile here
    # would emit a second include that overrides it.

    # Family follows the omarchy default (JetBrainsMono Nerd Font, mkDefault).
    # Size tracks the omarchy "Text Size" setting: it anchors 12px to 9pt, so
    # 14px is 11pt. `omarchy display text size` sets this by sed-ing
    # ~/.config/kitty/kitty.conf, which is a read-only store symlink here, so
    # the value has to live in nix or every rebuild reverts it.
    font.size = 11;
    keybindings = {
      "kitty_mod+e" = "kitten hints"; # https://sw.kovidgoyal.net/kitty/kittens/hints/
    };
    settings = {
      # https://github.com/kovidgoyal/kitty/issues/371#issuecomment-1095268494
      # mouse_map = "left click ungrabbed no-op";
      # Ctrl+Shift+click to open URL.
      confirm_os_window_close = "0";
      # https://github.com/kovidgoyal/kitty/issues/847
      macos_option_as_alt = "yes";
      shell = "${pkgs.nushell}/bin/nu -l";
      # Disable "potentially unsafe paste" warning
      paste_actions = "quote-urls-at-prompt";
    };
    extraConfig = ''
      cursor_blink_interval 0.5
      cursor_shape underline
      '';
  };

  home.activation = {
    setLoginShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ "$SHELL" != "${nuPath}" ]; then
        echo "Changing login shell to ${nuPath}"
        ${pkgs.util-linux}/bin/chsh -s ${nuPath} $USER
      fi
    '';
  };
}

