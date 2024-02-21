{ pkgs, ... }:
{
  # Ensure Home Manager is managing the packages for the user environment
  home.packages = with pkgs; [
    nodejs_21 
  ];
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };
}
