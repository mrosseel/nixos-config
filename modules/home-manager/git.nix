{ pkgs, config, ... }:
let
    userName = "Mike Rosseel";
    userEmail = "mike.rosseel@gmail.com";
in
{
  home.packages = [
    pkgs.git-lfs
    pkgs.tig  # pretty git log
    pkgs.jujutsu # pretty git
    pkgs.delta # better git diffs
    ];

  programs.git = {
    package = pkgs.git;
    enable = true;
    settings = {
      user = {
        name = userName;
        email = userEmail;
      };
      alias = {
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
      # init.defaultBranch = "master"; # https://srid.ca/unwoke
      core = {
        editor = "nvim";
        symlinks = true;
        pager = "delta";
      };
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        line-numbers = true;
        side-by-side = true;
        syntax-theme = "Nord";
      };
      pull.rebase = "false";
    };
    ignores = import ./dotfiles/gitignore_mac.nix;
  };

  # Using delta instead of difftastic for better interactive diffs
  # programs.difftastic = {
  #   enable = true;
  #   git.enable = true;
  # };

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
  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = userName;
        email = userEmail;
      };
      ui = {
        default-command =  ["log" "--reversed"];
        pager = "cat";
      };
    };
  };
}
