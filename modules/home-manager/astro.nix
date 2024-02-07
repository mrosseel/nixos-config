{ pkgs, ... }:
{
  # Ensure Home Manager is managing the packages for the user environment
  home.packages = with pkgs; [
    stellarium
  ];
}
