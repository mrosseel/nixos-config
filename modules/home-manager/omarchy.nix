{ inputs, ... }:

{
  imports = [
    inputs.omarchy-nix.homeManagerModules.default
  ];
}
