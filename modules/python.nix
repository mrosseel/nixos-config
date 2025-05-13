
{ pkgs, inputs, ... }:

{
  environment.systemPackages = [
    pkgs.uv
    pkgs.python313
  ];
}
