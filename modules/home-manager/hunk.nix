{ inputs, ... }:

{
  imports = [ inputs.hunk.homeManagerModules.default ];

  programs.hunk = {
    enable = true;
    enableGitIntegration = true; # set hunk as default git pager
    settings = {
      theme = "graphite";
      mode = "split";
      line_numbers = true;
    };
  };
}
