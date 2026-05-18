
{ pkgs, inputs, ... }:

{
  environment.systemPackages = [
    pkgs.uv
    (pkgs.python313.withPackages (ps: with ps; [ pip wandb packaging ]))
  ];
}
