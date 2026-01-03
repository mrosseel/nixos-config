
{ pkgs, inputs, ... }:

{
  environment.systemPackages = [
    pkgs.uv
    pkgs.python313
    pkgs.python313Packages.pip
  ];
}
