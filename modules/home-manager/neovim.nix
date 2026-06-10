{ pkgs, lib, config, ... }:
let
  # vi/vim/vimdiff as real binaries. programs.neovim used to provide these via
  # viAlias/vimAlias, but it also generated ~/.config/nvim/init.lua, which — with
  # ~/.config/nvim symlinked to this repo — got written straight into the repo and
  # clobbered our git-tracked config/nvim/init.lua on every switch. Plain neovim
  # plus these wrappers keep the commands working in every shell (incl. nushell)
  # without home-manager generating any config.
  neovim-aliases = pkgs.runCommand "neovim-aliases" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vi"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vim"
    printf '#!/bin/sh\nexec %s/bin/nvim -d "$@"\n' ${pkgs.neovim} > "$out/bin/vimdiff"
    chmod +x "$out/bin/vimdiff"
  '';
in
{
  # omarchy-nix enables programs.neovim, which generates a ~/.config/nvim/init.lua.
  # With ~/.config/nvim symlinked to this repo, that file gets written straight into
  # the repo and clobbers config/nvim/init.lua on every switch. Force it off and
  # install neovim plainly; the real config lives in the git-tracked dir below.
  programs.neovim.enable = lib.mkForce false;

  # Ensure Home Manager is managing the packages for the user environment
  home.packages = with pkgs; [
    neovim
    nodejs
    gcc
    neovim-aliases
  ];

  # The nvim config is a git-tracked, live-editable directory. Symlink it
  # out-of-store (not a read-only /nix/store copy) so files stay writable and
  # `git pull` updates it directly. Declarative on every machine, replacing the
  # old manual ~/.config/nvim symlink. Requires this repo to live at
  # ~/nixos-config for the user.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos-config/config/nvim";
}
