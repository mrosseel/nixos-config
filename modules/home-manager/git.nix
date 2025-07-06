{ pkgs, config, ... }:
{
  home.packages = [ 
    pkgs.git-lfs 
    pkgs.tig  # pretty git log
    ];

  programs.git = {
    package = pkgs.gitAndTools.gitFull;
    enable = true;
    userName = "Mike Rosseel";
    userEmail = "mike.rosseel@gmail.com";
    aliases = {
      co = "checkout";
      ci = "commit";
      cia = "commit --amend";
      cam = "commit -a";
      d = "diff";
      s = "status";
      st = "status";
      b = "branch";
      # p = "pull --rebase";
      pu = "push";
      r = "remote -v";
    };
    difftastic.enable = true;
    extraConfig = {
      # init.defaultBranch = "master"; # https://srid.ca/unwoke
      core.editor = "nvim";
      pull.rebase = "false";
      # For supercede
      core.symlinks = true;
    };
    ignores = import ./dotfiles/gitignore_mac.nix; 
  };

  programs.lazygit = {
    enable = true;
    settings = {
      # This looks better with the kitty theme.
      gui.theme = {
        lightTheme = false;
        activeBorderColor = [ "white" "bold" ];
        inactiveBorderColor = [ "white" ];
        selectedLineBgColor = [ "reverse" "white" ];
      };
    };
  };
}
