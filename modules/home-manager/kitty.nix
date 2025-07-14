{ pkgs, lib, ... }:

let
  zshPath = lib.getExe pkgs.zsh;
in
{
  # Better terminal, with good rendering.
  programs.kitty = {
    enable = true;
    # Pick "name" from https://github.com/kovidgoyal/kitty-themes/blob/master/themes.json
    themeFile = "Solarized_Dark_Higher_Contrast";
    #theme = "Solarized Dark";
    font = {
      name = "Hack Nerd Font mono";
      size = 16;
    };
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
      shell = "${pkgs.zsh}/bin/zsh";
    };
    extraConfig = ''
      cursor_blink_interval 0.5
      cursor_shape underline
      '';
  };

  home.activation = {
    setLoginShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ "$SHELL" != "${zshPath}" ]; then
        echo "Changing login shell to ${zshPath}"
        ${pkgs.util-linux}/bin/chsh -s ${zshPath} $USER
      fi
    '';
  };
}

